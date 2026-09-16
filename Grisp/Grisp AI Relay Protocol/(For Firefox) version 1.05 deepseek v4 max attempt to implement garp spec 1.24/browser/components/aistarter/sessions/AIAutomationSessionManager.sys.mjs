import { AIAutomationSession } from "./AIAutomationSession.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

function uuid() { return crypto.randomUUID(); }

export class AIAutomationSessionManager {
  constructor(service, providerRegistry) {
    this.service = service;
    this.providerRegistry = providerRegistry;
    this.sessions = new Map();
    this.tabIds = new WeakMap();
    this.tabsById = new Map();
  }

  getTopWindow() { return this.service.getTopWindow(); }

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
    if (!win) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "no browser window");
    if (this.tabsById.has(tabSpec)) {
      const tab = this.tabsById.get(tabSpec);
      if (tab && win.gBrowser.tabs.indexOf(tab) >= 0) return tab;
      this.tabsById.delete(tabSpec);
    }
    const text = String(tabSpec ?? "");
    for (const tab of win.gBrowser.tabs) {
      if (tab.label === text || tab.linkedBrowser?.currentURI?.spec === text) return tab;
    }
    throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, `tab not found: ${tabSpec}`);
  }

  listTabs() {
    const win = this.getTopWindow();
    if (!win) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "no browser window");
    const out = [];
    for (const tab of win.gBrowser.tabs) {
      out.push({
        tab_id: this.getStableTabId(tab),
        url: tab.linkedBrowser?.currentURI?.spec || "",
        title: tab.label,
        active: !!tab.selected,
      });
    }
    return out;
  }

  openTab(url) {
    const win = this.getTopWindow();
    if (!win) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "no browser window");
    const tab = win.gBrowser.addTrustedTab(url);
    win.gBrowser.selectedTab = tab;
    return { tab_id: this.getStableTabId(tab), url };
  }

  closeTab(tabSpec) {
    const win = this.getTopWindow();
    const tab = this.resolveTab(tabSpec);
    const tabId = this.getStableTabId(tab);
    for (const session of [...this.sessions.values()]) {
      if (session.tabId === tabId) this.closeSession(session.sessionId);
    }
    win.gBrowser.removeTab(tab);
    this.tabsById.delete(tabId);
    return { success: true };
  }

  selectTab(tabSpec) {
    const win = this.getTopWindow();
    const tab = this.resolveTab(tabSpec);
    win.gBrowser.selectedTab = tab;
    return { tab_id: this.getStableTabId(tab) };
  }

  createSession(providerName, tabSpec) {
    const adapter = this.providerRegistry.get(providerName);
    if (!adapter) throw new GarpError(GarpErrorCode.PROVIDER_UNAVAILABLE, `provider not found: ${providerName}`);
    let tab;
    if (tabSpec) tab = this.resolveTab(tabSpec);
    else {
      const win = this.getTopWindow();
      tab = win.gBrowser.addTrustedTab(adapter.url);
      win.gBrowser.selectedTab = tab;
    }
    const session = new AIAutomationSession({
      sessionId: uuid(),
      provider: adapter.name,
      tabId: this.getStableTabId(tab),
      pageGeneration: 1,
    });
    session.state = "PREPARING";
    session.pageURL = tab.linkedBrowser.currentURI.spec;
    this.sessions.set(session.sessionId, session);
    return session;
  }

  closeSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.state = "CLOSED";
    session.activeRequestId = null;
    this.sessions.delete(sessionId);
  }

  get(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new GarpError(GarpErrorCode.SESSION_NOT_FOUND, `session not found: ${sessionId}`);
    return session;
  }

  getTabForSession(session) { return this.resolveTab(session.tabId); }
}