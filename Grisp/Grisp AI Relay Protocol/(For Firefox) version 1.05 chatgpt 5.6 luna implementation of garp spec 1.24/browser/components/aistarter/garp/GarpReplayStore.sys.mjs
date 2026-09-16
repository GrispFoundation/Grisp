import { IOUtils } from "resource://gre/modules/IOUtils.sys.mjs";
import { PathUtils } from "resource://gre/modules/PathUtils.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";
import { monotonicNow, sha256, textEncoder } from "./GarpUtil.sys.mjs";

const RETENTION_MS = 24 * 60 * 60 * 1000;

async function digestHex(text) {
  const bytes = await sha256(textEncoder.encode(text));
  return [...bytes].map(b => b.toString(16).padStart(2, "0")).join("");
}

export class GarpReplayStore {
  constructor() {
    this.path = PathUtils.join(PathUtils.profileDir, "garp-auth-replay.json");
    this.markerPath = PathUtils.join(PathUtils.profileDir, "garp-auth-replay.initialized");
    this.entries = new Map();
    this.loaded = false;
    this.replayStateAvailable = true;
    this.writePromise = Promise.resolve();
  }

  async load() {
    if (this.loaded) return;
    try {
      const exists = await IOUtils.exists(this.path);
      const markerExists = await IOUtils.exists(this.markerPath);
      if (!exists && markerExists) {
        this.replayStateAvailable = false;
        return;
      }
      if (exists) {
        const text = await IOUtils.readUTF8(this.path);
        const parsed = JSON.parse(text);
        if (!parsed || parsed.version !== 1 || !Array.isArray(parsed.entries)) throw new Error("invalid replay state");
        for (const entry of parsed.entries) {
          if (typeof entry.key !== "string" || !Number.isFinite(entry.expiresAt)) throw new Error("invalid replay entry");
          if (entry.expiresAt > Date.now()) this.entries.set(entry.key, entry.expiresAt);
        }
      }
      await IOUtils.writeUTF8(this.markerPath, "GARP/1.24 replay state initialized\n", { tmpPath: `${this.markerPath}.tmp`, backupFile: `${this.markerPath}.bak` });
      await this.persist();
      this.loaded = true;
    } catch (error) {
      this.replayStateAvailable = false;
      Cu.reportError(`GARP/1.24 replay store unavailable: ${error}`);
    }
  }

  async keyFromTranscriptCore(transcriptCore) {
    const digest = await sha256(transcriptCore);
    return [...digest].map(b => b.toString(16).padStart(2, "0")).join("");
  }

  has(key) {
    this.pruneExpired();
    return this.entries.has(key);
  }

  async remember(key) {
    if (!this.replayStateAvailable) throw new GarpError(GarpErrorCode.AUTH_REPLAY, "Authentication replay state is unavailable; configured secret is disabled");
    this.pruneExpired();
    this.entries.set(key, Date.now() + RETENTION_MS);
    try {
      await this.persist();
    } catch (error) {
      this.replayStateAvailable = false;
      throw new GarpError(GarpErrorCode.AUTH_REPLAY, "Authentication replay state could not be durably persisted; configured secret is disabled");
    }
  }

  pruneExpired() {
    const now = Date.now();
    for (const [key, expiresAt] of this.entries) if (expiresAt <= now) this.entries.delete(key);
  }

  async persist() {
    if (!this.replayStateAvailable) return;
    const data = JSON.stringify({ version: 1, entries: [...this.entries].map(([key, expiresAt]) => ({ key, expiresAt })) });
    this.writePromise = this.writePromise.then(() => IOUtils.writeUTF8(this.path, data, { tmpPath: `${this.path}.tmp`, backupFile: `${this.path}.bak` }));
    return this.writePromise;
  }
}
