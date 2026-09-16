import { AIAutomationSession } from "./AIAutomationSession.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";
import { uuid } from "../garp/GarpUtil.sys.mjs";

function validateTabUrl(url) {
  let parsed;
  try { parsed = new URL(url); } catch (_) { throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Invalid URL"); }
  if (!["http:", "https:"].includes(parsed.protocol)) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Only http:// and https:// URLs are permitted");
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
    const win = this.service.getTopWindow();
    if (!win) throw new GarpError(GarpErrorCode.TAB_UNAVAILABLE, "No browser window available");
    return win;
  }

  getStableTabId(tab) {
    if (!tab) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "Tab is unavailable");
    let id = this.tabIds.get(tab);
    if (!id) { id = uuid(); this.tabIds.set(tab, id); }
    this.tabsById.set(id, tab);
    return id;
  }

  resolveTab(tabId) {
    if (typeof tabId !== "string" || tabId.length < 1) throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, "tab_id is required");
    const win = this.getTopWindow();
    const tab = this.tabsById.get(tabId);
    if (!tab || win.gBrowser.tabs.indexOf(tab) < 0) {
      if (tab) this.tabsById.delete(tabId);
      throw new GarpError(GarpErrorCode.TAB_NOT_FOUND, `Tab not found: ${tabId}`);
    }
    if (tab.linkedBrowser?.isRemoteBrowser === false || tab.linkedBrowser?.browsingContext?.discarded) throw new GarpError(GarpErrorCode.TAB_UNAVAILABLE, `Tab unavailable: ${tabId}`);
    return tab;
  }

  listTabs() {
    const win = this.getTopWindow();
    const tabs = [];
    for (const tab of win.gBrowser.tabs) {
      const tabId = this.getStableTabId(tab);
      tabs.push({ tab_id: tabId, url: tab.linkedBrowser?.currentURI?.spec || "about:blank", title: tab.label || "", active: !!tab.selected });
    }
    return tabs;
  }

  findSessionByTab(tabId) { return [...this.sessions.values()].find(session => session.tabId === tabId) || null; }

  openTab(url) {
    validateTabUrl(url);
    const win = this.getTopWindow();
    const tab = win.gBrowser.addTrustedTab(url);
    win.gBrowser.selectedTab = tab;
    return { tab_id: this.getStableTabId(tab), url };
  }

  closeTab(tabId) {
    const win = this.getTopWindow();
    const tab = this.resolveTab(tabId);
    const stableId = this.getStableTabId(tab);
    for (const session of [...this.sessions.values()]) if (session.tabId === stableId) this.closeSession(session.sessionId);
    win.gBrowser.removeTab(tab);
    this.tabsById.delete(stableId);
    return { success: true };
  }

  selectTab(tabId) {
    const win = this.getTopWindow();
    const tab = this.resolveTab(tabId);
    win.gBrowser.selectedTab = tab;
    return { success: true, tab_id: this.getStableTabId(tab) };
  }

  createSession(providerName, tabId = null) {
    const adapter = this.providerRegistry.get(providerName);
    if (!adapter) throw new GarpError(GarpErrorCode.PROVIDER_UNAVAILABLE, `Provider adapter unavailable: ${providerName}`);
    let tab;
    if (tabId !== null) tab = this.resolveTab(tabId);
    else {
      const win = this.getTopWindow();
      tab = win.gBrowser.addTrustedTab(adapter.url);
      win.gBrowser.selectedTab = tab;
    }
    const session = new AIAutomationSession({ sessionId: uuid(), provider: adapter.name, tabId: this.getStableTabId(tab), pageGeneration: 1n });
    session.state = "PREPARING";
    session.pageURL = tab.linkedBrowser?.currentURI?.spec || "";
    this.sessions.set(session.sessionId, session);
    return session;
  }

  attachSession(sessionId, connection) {
    const session = this.get(sessionId);
    session.assertMutable();
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Session is attached exclusively to another connection");
    session.ownerConnection = connection;
    if (session.state === "CLOSED") throw new GarpError(GarpErrorCode.SESSION_CLOSED, "Session is closed");
    return session;
  }

  detachSession(sessionId, connection) {
    const session = this.get(sessionId);
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
    session.ownerConnection = null;
    return session;
  }

  closeSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return null;
    if (session.state !== "CLOSED") session.state = "CLOSED";
    session.activeRequestId = null;
    session.ownerConnection = null;
    session.actorObject = null;
    session.actorInstance = null;
    return session;
  }

  resetSession(sessionId, connection) {
    const session = this.get(sessionId);
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
    session.assertMutable();
    session.state = "PREPARING";
    session.inputState = "UNKNOWN";
    session.generationState = "IDLE";
    session.lastRequestId = null; session.lastMessageId = null; session.lastMessageText = ""; session.lastMessageCount = 0;
    session.conversationId = null;
    session.incrementPageGeneration(session.pageURL);
    return session;
  }

  get(sessionId) {
    if (typeof sessionId !== "string") throw new GarpError(GarpErrorCode.SESSION_NOT_FOUND, "session_id is required");
    const session = this.sessions.get(sessionId);
    if (!session) throw new GarpError(GarpErrorCode.SESSION_NOT_FOUND, `Session not found: ${sessionId}`);
    if (session.state === "CLOSED") throw new GarpError(GarpErrorCode.SESSION_CLOSED, "Session is closed");
    return session;
  }

  getTabForSession(session) { return this.resolveTab(session.tabId); }
}
