import type { FSWatcher } from "chokidar";
import type { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";
import type { ParsedEvent, SourceType } from "./parsers/index.js";
import { resolveStateDir } from "../config/paths.js";
import { createSubsystemLogger } from "../logging/subsystem.js";
import { requireNodeSqlite } from "../memory/sqlite.js";
import { getParser, parseLines } from "./parsers/index.js";
import {
  ensureObservabilitySchema,
  getTrackedFile,
  insertEventsBatch,
  updateTrackedFile,
} from "./schema.js";
import { readNewLines } from "./tail-reader.js";
import {
  createWatcher,
  matchesPattern,
  resolveWatchedFiles,
  type FileChangeEvent,
  type WatchedPath,
} from "./watcher.js";

const log = createSubsystemLogger("observability/ingestor");

const DEFAULT_DB_FILENAME = "observability.db";
const DEFAULT_BATCH_SIZE = 100;
const INGEST_DEBOUNCE_MS = 500;

/**
 * Default watched paths for log sources.
 */
export function getDefaultWatchedPaths(stateDir?: string): WatchedPath[] {
  const resolvedStateDir = stateDir ?? resolveStateDir();

  return [
    // Session logs: ~/.openclaw/agents/*/sessions/*.jsonl
    {
      pattern: path.join(resolvedStateDir, "agents", "**", "sessions", "*.jsonl"),
      sourceType: "session" as SourceType,
    },
    // Cache trace: ~/.openclaw/logs/cache-trace.jsonl
    {
      pattern: path.join(resolvedStateDir, "logs", "cache-trace.jsonl"),
      sourceType: "cache-trace" as SourceType,
    },
    // System logs: /tmp/openclaw/openclaw-*.log
    {
      pattern: "/tmp/openclaw/openclaw-*.log",
      sourceType: "system-log" as SourceType,
    },
  ];
}

/**
 * Options for the observability ingestor.
 */
export type IngestorOptions = {
  /** Path to the observability database */
  dbPath?: string;
  /** Paths to watch for log files */
  watchedPaths?: WatchedPath[];
  /** Batch size for database inserts */
  batchSize?: number;
  /** State directory override */
  stateDir?: string;
};

/**
 * Observability log ingestor.
 * Watches log files and ingests them into SQLite.
 */
export class ObservabilityIngestor {
  private readonly db: DatabaseSync;
  private readonly dbPath: string;
  private readonly watchedPaths: WatchedPath[];
  private readonly batchSize: number;
  private watcher: FSWatcher | null = null;
  private pendingFiles = new Set<string>();
  private ingestTimer: NodeJS.Timeout | null = null;
  private processing = false;
  private closed = false;

  constructor(options: IngestorOptions = {}) {
    const stateDir = options.stateDir ?? resolveStateDir();
    this.dbPath = options.dbPath ?? path.join(stateDir, DEFAULT_DB_FILENAME);
    this.watchedPaths = options.watchedPaths ?? getDefaultWatchedPaths(stateDir);
    this.batchSize = options.batchSize ?? DEFAULT_BATCH_SIZE;

    // Ensure database directory exists
    const dbDir = path.dirname(this.dbPath);
    if (!fs.existsSync(dbDir)) {
      fs.mkdirSync(dbDir, { recursive: true });
    }

    // Open database
    const { DatabaseSync } = requireNodeSqlite();
    this.db = new DatabaseSync(this.dbPath);
    ensureObservabilitySchema(this.db);

    log.info(`Observability ingestor initialized`, { dbPath: this.dbPath });
  }

  /**
   * Starts watching for file changes and ingesting new data.
   */
  async startWatching(): Promise<void> {
    if (this.closed) {
      throw new Error("Ingestor is closed");
    }
    if (this.watcher) {
      log.warn("Watcher already running");
      return;
    }

    log.info("Starting file watcher", {
      patterns: this.watchedPaths.map((wp) => wp.pattern),
    });

    // Do initial ingestion of existing files
    await this.ingestExisting();

    // Start watching for changes
    this.watcher = createWatcher(this.watchedPaths, (event) => this.onFileChange(event), {
      emitExisting: false,
    });
  }

  /**
   * Stops watching for file changes.
   */
  async stopWatching(): Promise<void> {
    if (this.ingestTimer) {
      clearTimeout(this.ingestTimer);
      this.ingestTimer = null;
    }

    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
      log.info("File watcher stopped");
    }
  }

  /**
   * Ingests all existing files once (no watching).
   */
  async ingestExisting(): Promise<{ files: number; events: number }> {
    if (this.closed) {
      throw new Error("Ingestor is closed");
    }
    const files = await resolveWatchedFiles(this.watchedPaths);
    let totalEvents = 0;

    log.info(`Found ${files.length} files to ingest`);

    for (const file of files) {
      try {
        const count = await this.ingestFile(file.path, file.sourceType);
        totalEvents += count;
      } catch (err) {
        log.error(`Failed to ingest ${file.path}: ${String(err)}`);
      }
    }

    log.info(`Initial ingestion complete`, { files: files.length, events: totalEvents });
    return { files: files.length, events: totalEvents };
  }

  /**
   * Ingests a single file, reading from the last known cursor position.
   */
  async ingestFile(filePath: string, sourceType: SourceType): Promise<number> {
    if (this.closed) {
      return 0;
    }
    const tracked = getTrackedFile(this.db, filePath);
    const cursor = tracked?.byteOffset ?? 0;

    const { lines, newCursor, fileSize, reset } = await readNewLines({
      file: filePath,
      cursor,
    });

    if (lines.length === 0) {
      return 0;
    }

    if (reset) {
      log.info(`File rotation detected for ${filePath}, re-reading from start`);
    }

    const parser = getParser(sourceType);
    const events = parseLines(parser, lines, filePath);

    if (events.length > 0) {
      this.insertEvents(events);
    }

    // Update tracking record
    updateTrackedFile(this.db, {
      path: filePath,
      sourceType,
      byteOffset: newCursor,
      fileSize,
    });

    log.debug(`Ingested ${events.length} events from ${filePath}`, {
      lines: lines.length,
      cursor,
      newCursor,
    });

    return events.length;
  }

  /**
   * Inserts events in batches.
   */
  private insertEvents(events: ParsedEvent[]): void {
    // Convert ParsedEvent to the format expected by insertEventsBatch
    const dbEvents = events.map((e) => ({
      ts: e.ts,
      sourceType: e.sourceType,
      sourceFile: e.sourceFile,
      eventType: e.eventType,
      level: e.level,
      sessionId: e.sessionId,
      agentId: e.agentId,
      runId: e.runId,
      provider: e.provider,
      modelId: e.modelId,
      role: e.role,
      messagePreview: e.messagePreview,
      rawJson: e.rawJson,
    }));

    // Insert in batches
    for (let i = 0; i < dbEvents.length; i += this.batchSize) {
      const batch = dbEvents.slice(i, i + this.batchSize);
      insertEventsBatch(this.db, batch);
    }
  }

  /**
   * Handles file change events from the watcher.
   */
  private onFileChange(event: FileChangeEvent): void {
    if (event.eventType === "unlink") {
      // File deleted, nothing to ingest
      return;
    }

    // Queue the file for ingestion
    this.pendingFiles.add(event.path);
    this.scheduleIngest();
  }

  /**
   * Schedules a debounced ingestion of pending files.
   */
  private scheduleIngest(): void {
    if (this.ingestTimer) {
      return;
    }

    this.ingestTimer = setTimeout(() => {
      this.ingestTimer = null;
      void this.processPendingFiles();
    }, INGEST_DEBOUNCE_MS);
  }

  /**
   * Processes all pending file changes.
   */
  private async processPendingFiles(): Promise<void> {
    if (this.closed || this.processing) {
      return;
    }
    this.processing = true;

    try {
      const files = Array.from(this.pendingFiles);
      this.pendingFiles.clear();

      for (const filePath of files) {
        if (this.closed) {
          break;
        }
        const sourceType = this.getSourceTypeForFile(filePath);
        if (!sourceType) {
          continue;
        }

        try {
          await this.ingestFile(filePath, sourceType);
        } catch (err) {
          log.error(`Failed to ingest ${filePath}: ${String(err)}`);
        }
      }
    } finally {
      this.processing = false;
      // If new files arrived while processing, schedule another run
      if (this.pendingFiles.size > 0 && !this.closed) {
        this.scheduleIngest();
      }
    }
  }

  /**
   * Gets the source type for a file based on watched paths.
   */
  private getSourceTypeForFile(filePath: string): SourceType | null {
    for (const wp of this.watchedPaths) {
      if (matchesPattern(filePath, wp.pattern)) {
        return wp.sourceType;
      }
    }
    return null;
  }

  /**
   * Gets ingestion status.
   */
  status(): {
    dbPath: string;
    watching: boolean;
    trackedFiles: number;
    totalEvents: number;
    eventsByType: Record<string, number>;
  } {
    if (this.closed) {
      throw new Error("Ingestor is closed");
    }
    const trackedFilesRow = this.db
      .prepare("SELECT COUNT(*) as count FROM tracked_files")
      .get() as { count: number };

    const totalEventsRow = this.db.prepare("SELECT COUNT(*) as count FROM events").get() as {
      count: number;
    };

    const eventsByTypeRows = this.db
      .prepare("SELECT source_type, COUNT(*) as count FROM events GROUP BY source_type")
      .all() as Array<{ source_type: string; count: number }>;

    const eventsByType: Record<string, number> = {};
    for (const row of eventsByTypeRows) {
      eventsByType[row.source_type] = row.count;
    }

    return {
      dbPath: this.dbPath,
      watching: this.watcher !== null,
      trackedFiles: trackedFilesRow.count,
      totalEvents: totalEventsRow.count,
      eventsByType,
    };
  }

  /**
   * Closes the ingestor and releases resources.
   */
  async close(): Promise<void> {
    if (this.closed) {
      return;
    }
    this.closed = true;

    await this.stopWatching();
    this.db.close();
    log.info("Observability ingestor closed");
  }
}

/**
 * Creates and returns an observability ingestor instance.
 */
export function createIngestor(options: IngestorOptions = {}): ObservabilityIngestor {
  return new ObservabilityIngestor(options);
}
