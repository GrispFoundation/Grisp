import { DeepSeekAdapter } from "./DeepSeekAdapter.sys.mjs";
import { GeminiAdapter } from "./GeminiAdapter.sys.mjs";
import { ChatGPTAdapter } from "./ChatGPTAdapter.sys.mjs";
import { ClaudeAdapter } from "./ClaudeAdapter.sys.mjs";
import { GrokAdapter } from "./GrokAdapter.sys.mjs";
import { CopilotAdapter } from "./CopilotAdapter.sys.mjs";
import { PerplexityAdapter } from "./PerplexityAdapter.sys.mjs";
import { InceptionAdapter } from "./InceptionAdapter.sys.mjs";
import { sortedUtf8 } from "../garp/GarpUtil.sys.mjs";

export class ProviderRegistry {
  constructor() {
    this.adapters = new Map();
    for (const adapter of [new ChatGPTAdapter(), new ClaudeAdapter(), new CopilotAdapter(), new DeepSeekAdapter(), new GeminiAdapter(), new GrokAdapter(), new InceptionAdapter(), new PerplexityAdapter()]) this.adapters.set(adapter.name, adapter);
  }

  get(name) { return this.adapters.get(String(name || "").toLowerCase()) || null; }

  list() {
    return sortedUtf8([...this.adapters.values()].map(adapter => adapter.name)).map(name => {
      const adapter = this.adapters.get(name);
      const inputStrategies = sortedUtf8(adapter.inputStrategies(null));
      return {
        id: adapter.name,
        version: adapter.adapter_version,
        state: "AVAILABLE",
        input_strategies: inputStrategies,
        capabilities: {
          streaming: adapter.supported_features.includes("streaming"),
          cancellation: adapter.supported_features.includes("cancel"),
          continuation: adapter.supported_features.includes("continuation"),
          diagnostics: adapter.supported_features.includes("diagnostics"),
        },
      };
    });
  }
}
