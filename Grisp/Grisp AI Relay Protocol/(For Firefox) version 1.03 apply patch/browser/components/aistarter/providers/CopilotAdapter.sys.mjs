import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
export class CopilotAdapter extends ProviderAdapter {
  constructor() { super("copilot", "https://copilot.microsoft.com/"); }
  input(doc) { return this.findBySelectors(doc, [
    'textarea#userInput', 'textarea[placeholder*="Message"]', 'textarea[placeholder*="Ask"]',
    'textarea[placeholder*="Copilot"]', '[data-testid="composer-input"] textarea',
    '[data-testid="chat-input"] textarea', '.cib-text-input', '#searchbox',
    'textarea[aria-label*="Ask"]', '[aria-label*="Copilot"] textarea',
    'div[contenteditable="true"][role="textbox"]', 'textarea'
  ]); }
  sendButton(doc) { return this.findBySelectors(doc, [
    'button[aria-label*="Submit"]', 'button[aria-label*="Send"]',
    'button[data-testid*="send"]', 'button[type="submit"]'
  ]); }
  responseNodes(doc) { return this.findAllBySelectors(doc, [
    'cib-message-group[source="bot"] cib-message .content', '.cib-message-content',
    '[data-testid="ai-response"]', '[data-testid*="response"] .content',
    '.response-message', '.bot-message', '.ac-container', '.message-bubble',
    '[class*="assistant"][class*="message"]', '[class*="bot"][class*="message"]',
    '.response-text', '.answer-text', '[class*="ResponseText"]', '[class*="responseText"]'
  ]); }
  isStreaming(doc) { return this.findAllBySelectors(doc, [
    '.loading-dots', '.typing-indicator', '[data-testid="stop-button"]',
    'button[aria-label*="Stop"]', '.cib-stop-responding-button'
  ]).length > 0; }
  async inject(input, prompt) {
    await super.inject(input, prompt);
    for (let attempt = 0; attempt < 8; attempt++) {
      await new Promise(resolve => input.ownerDocument.defaultView.setTimeout(resolve, 300));
      const button = this.sendButton(input.ownerDocument);
      if (button) {
        button.click();
        return { submit_method: "button_click" };
      }
    }
    return { submit_method: "not_available" };
  }
}
