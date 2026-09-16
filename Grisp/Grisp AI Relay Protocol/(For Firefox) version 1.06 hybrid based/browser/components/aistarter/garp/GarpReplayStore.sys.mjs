import { IOUtils } from "resource://gre/modules/IOUtils.sys.mjs";
import { PathUtils } from "resource://gre/modules/PathUtils.sys.mjs";
import { GarpError,GarpErrorCode } from "./GarpErrors.sys.mjs";
const RETENTION_MS=24*60*60*1000;
export class GarpReplayStore{
  constructor(){this.path=PathUtils.join(PathUtils.profileDir,"garp-auth-replay.json");this.markerPath=PathUtils.join(PathUtils.profileDir,"garp-auth-replay.initialized");this.entries=new Map();this.loaded=false;this.replayStateAvailable=true;this.writePromise=Promise.resolve();}
  async load(){if(this.loaded)return;try{const exists=await IOUtils.exists(this.path),marker=await IOUtils.exists(this.markerPath);if(!exists&&marker){this.replayStateAvailable=false;return;}if(exists){const text=await IOUtils.readUTF8(this.path),p=JSON.parse(text);if(!p||p.version!==1||!Array.isArray(p.entries))throw new Error("invalid replay state");for(const e of p.entries){if(typeof e.key!=="string"||!Number.isFinite(e.expiresAt))throw new Error("invalid replay entry");if(e.expiresAt>Date.now())this.entries.set(e.key,e.expiresAt);}}await IOUtils.writeUTF8(this.markerPath,"GARP/1.24 replay state initialized\n",{tmpPath:`${this.markerPath}.tmp`,backupFile:`${this.markerPath}.bak`});await this.persist();this.loaded=true;}catch(error){this.replayStateAvailable=false;Cu.reportError(`GARP replay store unavailable: ${error}`);}}
  has(key){this.pruneExpired();return this.entries.has(key);}
  async remember(key){if(!this.replayStateAvailable)throw new GarpError(GarpErrorCode.AUTH_REPLAY,"Authentication replay state is unavailable; secret must be rotated");this.pruneExpired();this.entries.set(key,Date.now()+RETENTION_MS);try{await this.persist();}catch(error){this.replayStateAvailable=false;throw new GarpError(GarpErrorCode.AUTH_REPLAY,"Replay state could not be durably persisted; secret must be rotated");}}
  pruneExpired(){const now=Date.now();for(const [k,t] of this.entries)if(t<=now)this.entries.delete(k);}
  async persist(){if(!this.replayStateAvailable)return;const data=JSON.stringify({version:1,entries:[...this.entries].map(([key,expiresAt])=>({key,expiresAt}))});this.writePromise=this.writePromise.then(()=>IOUtils.writeUTF8(this.path,data,{tmpPath:`${this.path}.tmp`,backupFile:`${this.path}.bak`}));return this.writePromise;}
}
