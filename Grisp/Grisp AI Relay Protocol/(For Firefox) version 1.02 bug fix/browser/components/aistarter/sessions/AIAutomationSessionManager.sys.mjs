import { AIAutomationSession } from "./AIAutomationSession.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

function uuid() {
  return crypto.randomUUID();
}

export class AIAutomationSessionManager {
  constructor(service, providerRegistry) {
    this.service = service;
    this.providerRegistry = providerRegistry;
    this.sessions = new Map();
    this.tabIds = new WeakMap();
    this.tabsById = new Map();
  }

  getTopWindow() {
    return this.service.getTopWindow();
  }

  getStableTabId(tab) {
    if (!tab) return null;
    let id = this.tabIds.get(tab);
    if (!id) {
      id = uuid();
      this.tabIds.set(tab, id);
      this.tabsById.set(id, tab);
    }
    return id;
  }

  resolveTab(tabSpec) {
    const win = this.getTopWindow();
    if (!win) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "No browser window found");

    if (this.tabsById.has(tabSpec)) {
      const tab = this.tabsById.get(tabSpec);
      if (tab && win.gBrowser.tabs.indexOf(tab) >= 0) return tab;
      this.tabsById.delete(tabSpec);
    }

    if (typeof tabSpec === "number" || (typeof tabSpec === "string" && /^\d+$/.test(tabSpec))) {
      const index = Number.parseInt(tabSpec, 10);
      const tab = win.gBrowser.tabs[index];
      if (tab) return tab;
    }

    const text = String(tabSpec || "");
    for (const tab of win.gBrowser.tabs) {
      if (tab.label === text || tab.linkedBrowser?.currentURI?.spec === text) return tab;
    }
    for (const tab of win.gBrowser.tabs) {
      if (tab.label?.toLowerCase().includes(text.toLowerCase()) || tab.linkedBrowser?.currentURI?.spec?.toLowerCase().includes(text.toLowerCase())) return tab;
    }
    throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, `Tab not found: ${tabSpec}`);
  }

  listTabs() {
    const win = this.getTopWindow();
    if (!win) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "No browser window found");
    const result = [];
    for (let index = 0; index < win.gBrowser.tabs.length; index++) {
      const tab = win.gBrowser.tabs[index];
      const tabId = this.getStableTabId(tab);
      const session = [...this.sessions.values()].find(item => item.tabId === tabId) || null;
      result.push({
        tab_id: tabId,
        index,
        title: tab.label,
        url: tab.linkedBrowser.currentURI.spec,
        selected: tab.selected,
        ...(session ? { provider: session.provider, session_id: session.sessionId, state: session.state } : {}),
      });
    }
    return result;
  }

  openTab(url) {
    const win = this.getTopWindow();
    if (!win) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "No browser window found");
    const tab = win.gBrowser.addTrustedTab(url);
    win.gBrowser.selectedTab = tab;
    return { tab_id: this.getStableTabId(tab), index: win.gBrowser.tabs.indexOf(tab), url };
  }

  closeTab(tabSpec) {
    const win = this.getTopWindow();
    const tab = this.resolveTab(tabSpec);
    const tabId = this.getStableTabId(tab);
    const sessions = [...this.sessions.values()].filter(item => item.tabId === tabId);
    for (const session of sessions) this.closeSession(session.sessionId);
    win.gBrowser.removeTab(tab);
    this.tabsById.delete(tabId);
    return { success: true, tab_id: tabId };
  }

  selectTab(tabSpec) {
    const win = this.getTopWindow();
    const tab = this.resolveTab(tabSpec);
    win.gBrowser.selectedTab = tab;
    return { success: true, tab_id: this.getStableTabId(tab), index: win.gBrowser.tabs.indexOf(tab) };
  }

  createSession(providerName, tabSpec = null) {
    const adapter = this.providerRegistry.get(providerName);
    if (!adapter) throw new GarpError(GarpErrorCode.PROVIDER_NOT_FOUND, `Provider not found: ${providerName}`);

    let tab;
    if (tabSpec !== null && tabSpec !== undefined) {
      tab = this.resolveTab(tabSpec);
    } else {
      const win = this.getTopWindow();
      tab = win.gBrowser.addTrustedTab(adapter.url);
      win.gBrowser.selectedTab = tab;
    }

    const session = new AIAutomationSession({
      sessionId: uuid(),
      provider: providerName,
      tabId: this.getStableTabId(tab),
      pageGeneration: 1,
    });
    session.state = "PREPARING";
    session.pageURL = tab.linkedBrowser.currentURI.spec;
    this.sessions.set(session.sessionId, session);
    return session;
  }

  attachSession(sessionId, tabSpec) {
    const session = this.get(sessionId);
    const tab = this.resolveTab(tabSpec);
    session.tabId = this.getStableTabId(tab);
    session.state = "PREPARING";
    session.markPageGeneration(session.pageGeneration + 1, tab.linkedBrowser.currentURI.spec);
    return session;
  }

  detachSession(sessionId) {
    const session = this.get(sessionId);
    session.state = "NEW";
    session.activeRequestId = null;
    return session;
  }

  closeSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.state = "CLOSED";
    session.activeRequestId = null;
    this.sessions.delete(sessionId);
  }

  resetSession(sessionId) {
    const session = this.get(sessionId);
    session.assertIdle();
    session.generationState = "IDLE";
    session.lastRequestId = null;
    session.lastMessageId = null;
    session.lastMessageText = "";
    session.lastMessageCount = 0;
    session.conversationId = null;
    session.state = "PREPARING";
    session.markPageGeneration(session.pageGeneration + 1);
    return session;
  }

  get(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new GarpError(GarpErrorCode.SESSION_NOT_FOUND, `Session not found: ${sessionId}`);
    return session;
  }

  getTabForSession(session) {
    return this.resolveTab(session.tabId);
  }
}
