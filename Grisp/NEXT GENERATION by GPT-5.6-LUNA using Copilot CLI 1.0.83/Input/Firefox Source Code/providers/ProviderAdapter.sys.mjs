export class ProviderAdapter {
  constructor(provider, version = "1.0") {
    this.provider = provider;
    this.adapterVersion = version;
  }

  discoverInput() { throw new Error("DOM_UNSUPPORTED"); }
  inspectReadyState() { throw new Error("DOM_UNSUPPORTED"); }
  submitPrompt() { throw new Error("DOM_UNSUPPORTED"); }
  inspectGeneration() { throw new Error("DOM_UNSUPPORTED"); }
  detectContinuation() { return null; }
  detectAuthentication() { return "UNKNOWN"; }
  detectRateLimit() { return false; }
  detectError() { return null; }
}
