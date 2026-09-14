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
  list() { return [...this.adapters.values()].map(adapter => ({
    provider: adapter.name,
    url: adapter.url,
    adapter_version: adapter.adapter_version,
    selector_strategy_version: adapter.selector_strategy_version,
    supported_features: [...adapter.supported_features],
  })); }
}
