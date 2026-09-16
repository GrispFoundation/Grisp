import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
export class CopilotAdapter extends ProviderAdapter {
  constructor() { super("copilot", "https://copilot.microsoft.com/"); }
  input(doc) { return this.findBySelectors(doc, ['textarea#userInput', 'textarea[placeholder*="Message"]', 'textarea[placeholder*="Ask"]', '[data-testid="composer-input"] textarea', '[data-testid="chat-input"] textarea', '.cib-text-input', 'textarea[aria-label*="Ask"]', '[aria-label*="Copilot"] textarea', 'div[contenteditable="true"][role="textbox"]', 'textarea']); }
  sendButton(doc) { return this.findBySelectors(doc, ['button[aria-label*="Submit"]', 'button[aria-label*="Send"]', 'button[data-testid*="send"]', 'button[type="submit"]']); }
  responseNodes(doc) { return this.findAllBySelectors(doc, ['cib-message-group[source="bot"] cib-message .content', '.cib-message-content', '[data-testid="ai-response"]', '.response-message', '.bot-message', '.response-text', '.answer-text']); }
  isStreaming(doc) { return this.findAllBySelectors(doc, ['.loading-dots', '.typing-indicator', '[data-testid="stop-button"]', 'button[aria-label*="Stop"]', '.cib-stop-responding-button']).length > 0; }
}
