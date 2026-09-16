import { DeepSeekAdapter } from "./DeepSeekAdapter.sys.mjs";
import { GeminiAdapter } from "./GeminiAdapter.sys.mjs";
import { ChatGPTAdapter } from "./ChatGPTAdapter.sys.mjs";
import { ClaudeAdapter } from "./ClaudeAdapter.sys.mjs";
import { GrokAdapter } from "./GrokAdapter.sys.mjs";
import { CopilotAdapter } from "./CopilotAdapter.sys.mjs";
import { PerplexityAdapter } from "./PerplexityAdapter.sys.mjs";
import { InceptionAdapter } from "./InceptionAdapter.sys.mjs";

export class ProviderRegistry {
  constructor() {
    this.adapters = new Map();
    for (const adapter of [
      new DeepSeekAdapter(), new GeminiAdapter(), new ChatGPTAdapter(), new ClaudeAdapter(),
      new GrokAdapter(), new CopilotAdapter(), new PerplexityAdapter(), new InceptionAdapter(),
    ]) {
      this.adapters.set(adapter.name, adapter);
    }
  }

  get(name) { return this.adapters.get(String(name || "").toLowerCase()) || null; }

  list() {
    return [...this.adapters.values()].map(a => ({
      provider: a.name,
      url: a.url,
      adapter_version: a.adapter_version,
      selector_strategy_version: a.selector_strategy_version,
      supported_features: [...a.supported_features],
    }));
  }

  // §22.1 canonical CAPABILITIES provider entry.
  capabilityEntries() {
    return [...this.adapters.values()]
      .map(a => ({
        id: a.name,
        version: a.adapter_version,
        state: "AVAILABLE",
        input_strategies: ["provider_native_send", "keyboard_enter"],
        capabilities: {
          streaming: true,
          cancellation: true,
          continuation: true,
          diagnostics: true,
        },
      }))
      .sort((x, y) => {
        const a = new TextEncoder().encode(x.id);
        const b = new TextEncoder().encode(y.id);
        const n = Math.min(a.length, b.length);
        for (let i = 0; i < n; i++) if (a[i] !== b[i]) return a[i] - b[i];
        return a.length - b.length;
      });
  }
}