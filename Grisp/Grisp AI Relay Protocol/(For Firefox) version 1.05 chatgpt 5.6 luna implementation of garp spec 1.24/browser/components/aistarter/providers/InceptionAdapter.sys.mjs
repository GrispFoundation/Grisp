import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
export class InceptionAdapter extends ProviderAdapter {
  constructor() { super("inception", "https://chat.inceptionlabs.ai/"); }
  input(doc) { return this.findBySelectors(doc, ["textarea", '[contenteditable="true"]']); }
  sendButton(doc) { return this.findBySelectors(doc, ['button[aria-label*="Send"]']); }
  responseNodes(doc) { return this.findAllBySelectors(doc, [".prose-chat", ".markdown"]); }
  isStreaming(doc) { return !!doc.querySelector('.loading-indicator, [class*="loading"]'); }
}
