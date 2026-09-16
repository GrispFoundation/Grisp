export class AIAutomationParent extends JSWindowActorParent {
  constructor() {
    super();
    this.actorInstance = crypto.randomUUID();
  }

  receiveMessage(_message) {}
}
