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
        for (const a of [new ChatGPTAdapter(), new ClaudeAdapter(), new CopilotAdapter(), new DeepSeekAdapter(), new GeminiAdapter(), new GrokAdapter(), new InceptionAdapter(), new PerplexityAdapter()])
            this.adapters.set(a.name, a);
    }

    get(name) {
        return this.adapters.get(String(name || "").toLowerCase()) || null;
    }

    list() {
        return sortedUtf8([...this.adapters.keys()]).map(n => this.adapters.get(n));
    }

    getCapabilityEntries() {
        return sortedUtf8([...this.adapters.keys()]).map(n => { const a = this.adapters.get(n); return { id: a.name, version: a.adapter_version, state: "AVAILABLE", input_strategies: sortedUtf8(a.inputStrategies(null)), capabilities: { streaming: a.supported_features.includes("streaming"), cancellation: a.supported_features.includes("cancel"), continuation: a.supported_features.includes("continuation"), diagnostics: a.supported_features.includes("diagnostics") } }; });
    }
}
