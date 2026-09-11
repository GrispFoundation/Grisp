export class GarpSessionManager {
  #sessions = new Map();
  #requests = new Map();

  createSession(provider, tabId) {
    const sessionId = crypto.randomUUID();
    this.#sessions.set(sessionId, {
      sessionId, provider, tabId, state: "READY", pageGeneration: 0,
      activeRequestId: null
    });
    return this.#sessions.get(sessionId);
  }

  getSession(sessionId) {
    const session = this.#sessions.get(sessionId);
    if (!session) throw new Error("SESSION_NOT_FOUND");
    return session;
  }

  acceptPrompt(sessionId, requestId) {
    const session = this.getSession(sessionId);
    const existing = this.#requests.get(requestId);
    if (existing) return existing;
    if (session.activeRequestId) throw new Error("SESSION_BUSY");
    const request = { requestId, sessionId, sequence: 0, state: "ACCEPTED" };
    session.activeRequestId = requestId;
    session.state = "BUSY";
    this.#requests.set(requestId, request);
    return request;
  }

  completePrompt(requestId, state = "COMPLETE") {
    const request = this.#requests.get(requestId);
    if (!request) throw new Error("REQUEST_NOT_FOUND");
    const session = this.getSession(request.sessionId);
    request.state = state;
    session.state = "READY";
    session.activeRequestId = null;
    return request;
  }

  nextSequence(requestId) {
    const request = this.#requests.get(requestId);
    if (!request) throw new Error("REQUEST_NOT_FOUND");
    return ++request.sequence;
  }

  status(requestId) {
    const request = this.#requests.get(requestId);
    if (!request) throw new Error("REQUEST_NOT_FOUND");
    return { ...request };
  }
}
