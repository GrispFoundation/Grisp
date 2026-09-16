export class AIAutomationDiagnostics {
    static providerState(provider, state, details = {}, actorInstance = crypto.randomUUID()) {
        return {
            provider,
            state,
            timestamp: new Date().toISOString(),
            details,
            actor_instance: actorInstance,
        };
    }
    static error(provider, stage, code, message, details = {}, actorInstance = crypto.randomUUID()) {
        return {
            provider,
            stage,
            code,
            message,
            details,
            timestamp: new Date().toISOString(),
            actor_instance: actorInstance,
        };
    }
}

