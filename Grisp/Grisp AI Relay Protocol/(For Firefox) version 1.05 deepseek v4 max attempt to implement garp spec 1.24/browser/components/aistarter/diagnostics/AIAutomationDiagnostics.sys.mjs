export class AIAutomationDiagnostics {
  static providerState(provider, state, details = {}) {
    return {
      provider,
      state,
      timestamp: new Date().toISOString(),
      details,
    };
  }

  static error(provider, stage, code, message, details = {}) {
    return {
      provider,
      stage,
      code,
      message,
      details,
      timestamp: new Date().toISOString(),
    };
  }
}
