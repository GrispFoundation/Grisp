unit GSDA31.Gateway;

interface

uses
    System.SysUtils,
    System.JSON,
    System.Generics.Collections,
    GSDA31,
    GSDA31.Agent;

type
    TGSDACommandGateway31 = class
    private
        FAgent: TGSDASpecAgent31;
        function RequireString(const AObject: TJSONObject; const AName: string): string;
        function MessageKindFromInt(AValue: Integer): TGSDAMessageKind;
    public
        constructor Create(AAgent: TGSDASpecAgent31);
        function Execute(const ACommand: TJSONObject): TJSONObject;
    end;

implementation

constructor TGSDACommandGateway31.Create(AAgent: TGSDASpecAgent31);
begin
    if AAgent = nil then
        raise EArgumentNilException.Create('Agent');
    FAgent := AAgent;
end;

function TGSDACommandGateway31.RequireString(
    const AObject: TJSONObject; const AName: string): string;
begin
    Result := AObject.GetValue<string>(AName, '');
    if Result = '' then
        raise EGSDAFailure.Create(fcSchemaFailure, 'Missing command field: ' + AName);
end;

function TGSDACommandGateway31.MessageKindFromInt(
    AValue: Integer): TGSDAMessageKind;
begin
    if (AValue < Ord(Low(TGSDAMessageKind))) or
       (AValue > Ord(High(TGSDAMessageKind))) then
        raise EGSDAFailure.Create(fcProtocolFailure, 'Invalid message kind');
    Result := TGSDAMessageKind(AValue);
end;

function TGSDACommandGateway31.Execute(
    const ACommand: TJSONObject): TJSONObject;
var
    LType: string;
    LTask: TGSDAResearchTask;
    LRunID: string;
    LResult: TGSDAIngressResult;
    LInput: TGSDAPeerInput;
    LRound: TGSDARoundResult;
    LSpecID: string;
    LRevision: TGSDARevisionSnapshot;
    LHuman: TGSDAHumanDecision;
begin
    if ACommand = nil then
        raise EArgumentNilException.Create('Command');

    LType := RequireString(ACommand, 'command');
    Result := TJSONObject.Create;
    Result.AddPair('schema', 'gsda_gateway_response/3.1');
    Result.AddPair('command', LType);

    try
        if LType = 'create_task' then
        begin
            LTask := FAgent.CreateTask(
                RequireString(ACommand, 'user_prompt'),
                ACommand.GetValue<string>('user_intent', ''),
                ACommand.GetValue<string>('domain', 'specification')
            );
            Result.AddPair('task_id', LTask.TaskID);
            Result.AddPair('target_context_id', LTask.TargetContextID);
        end
        else if LType = 'start_run' then
        begin
            LRunID := FAgent.StartRun(RequireString(ACommand, 'task_id'));
            Result.AddPair('run_id', LRunID);
        end
        else if LType = 'peer_message' then
        begin
            LInput.PeerID := RequireString(ACommand, 'peer_id');
            LInput.Fingerprint := RequireString(ACommand, 'fingerprint');
            LInput.Token := RequireString(ACommand, 'token');
            LInput.Kind := MessageKindFromInt(ACommand.GetValue<Integer>('kind', -1));
            LInput.Confidence := ACommand.GetValue<Integer>('confidence', 0);
            LInput.Payload := RequireString(ACommand, 'payload');

            LResult := FAgent.SubmitPeerMessage(
                RequireString(ACommand, 'run_id'),
                LInput
            );
            Result.AddPair('accepted', BoolToStr(LResult.Accepted, True));
            Result.AddPair('message_id', LResult.MessageID);
            Result.AddPair('content_id', LResult.ContentID);
            Result.AddPair('logical_sequence', TJSONNumber.Create(LResult.LogicalSequence));
        end
        else if LType = 'execute_round' then
        begin
            raise EGSDAFailure.Create(
                fcProtocolFailure,
                'execute_round requires the typed Agent API; use peer_message repeatedly'
            );
        end
        else if LType = 'freeze_candidate' then
        begin
            LSpecID := FAgent.FreezeCandidate(RequireString(ACommand, 'run_id'));
            Result.AddPair('spec_content_id', LSpecID);
        end
        else if LType = 'publish' then
        begin
            if not (ACommand.GetValue('human_decision') is TJSONObject) then
                raise EGSDAFailure.Create(
                    fcGovernanceFailure,
                    'human_decision object is required'
                );

            LHuman := TGSDAHumanDecision.Create;
            LHuman.ActorID := RequireString(ACommand.GetValue('human_decision') as TJSONObject, 'actor_id');
            LHuman.SpecContentID := RequireString(ACommand.GetValue('human_decision') as TJSONObject, 'spec_content_id');
            LHuman.Accepted := ACommand.GetValue('human_decision').GetValue<Boolean>('accepted', False);
            LHuman.Rationale := RequireString(ACommand.GetValue('human_decision') as TJSONObject, 'rationale');
            LHuman.SignatureHex := RequireString(ACommand.GetValue('human_decision') as TJSONObject, 'signature_hex');
            LHuman.CreatedAtUTC := ACommand.GetValue('human_decision').GetValue<string>('created_at_utc', '');

            LRevision := FAgent.Publish(
                RequireString(ACommand, 'run_id'),
                LHuman
            );
            Result.AddPair('revision_id', LRevision.RevisionID);
            Result.AddPair('spec_content_id', LRevision.SpecContentID);
            Result.AddPair('package_hash', LRevision.PackageHash);
            LHuman.Free;
            LHuman := nil;
        end
        else if LType = 'state' then
            Result.AddPair('state',
                FAgent.StateToJson(RequireString(ACommand, 'run_id')))
        else
            raise EGSDAFailure.Create(fcProtocolFailure, 'Unknown gateway command: ' + LType);
    except
        on E: EGSDAFailure do
        begin
            Result.AddPair('accepted', 'false');
            Result.AddPair('error_code', GSDAFailureName(E.Code));
            Result.AddPair('error_message', E.Message);
        end;
    end;
end;

end.
