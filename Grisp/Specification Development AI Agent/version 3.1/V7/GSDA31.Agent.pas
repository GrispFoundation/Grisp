unit GSDA31.Agent;

interface

uses
    System.SysUtils,
    System.JSON,
    System.Generics.Collections,
    GSDA31;

type
    TGSDARunStatus = (
        rsCreated,
        rsGenerating,
        rsAnalyzing,
        rsConsolidating,
        rsFrozen,
        rsPublicationBlocked,
        rsPublished,
        rsFailed
    );

    TGSDARunContext = class
    public
        RunID: string;
        TaskID: string;
        RoundIndex: Int64;
        Status: TGSDARunStatus;
        CandidateArtifactIDs: TList<string>;
        LastCandidateArtifactID: string;
        constructor Create;
        destructor Destroy; override;
    end;

    TGSDAPeerInput = record
        PeerID: string;
        Fingerprint: string;
        Token: string;
        Kind: TGSDAMessageKind;
        Confidence: Integer;
        Payload: string;
    end;

    TGSDARoundResult = record
        RoundIndex: Int64;
        AcceptedMessages: Integer;
        CandidateArtifactID: string;
        WinningPeerID: string;
        WinningScoreNumerator: Int64;
        WinningScoreDenominator: Int64;
        Converged: Boolean;
    end;

    TGSDASpecAgent31 = class
    private
        FKernel: TGSDAKernel31;
        FPublication: TGSDAPublication31;
        FRuns: TObjectDictionary<string,TGSDARunContext>;
        function GetRun(const ARunID: string): TGSDARunContext;
        function NextRoundID(const ARunID: string; ARoundIndex: Int64): string;
        function BuildCandidateContent(const APayload: TJSONObject): string;
        function ComputeCandidateScore(
            const AMessage: TGSDAReasoningMessage
        ): TPair<Int64,Int64>;
        function SelectBestCandidate(
            const AMessageIDs: TArray<string>
        ): string;
        function BuildEmptySpecJson(const ASchema, AItemName: string): string;
    public
        constructor Create(AKernel: TGSDAKernel31);
        destructor Destroy; override;

        function CreateTask(
            const AUserPrompt, AUserIntent, ADomain: string
        ): TGSDAResearchTask;

        function StartRun(const ATaskID: string): string;

        function SubmitPeerMessage(
            const ARunID: string;
            const AInput: TGSDAPeerInput
        ): TGSDAIngressResult;

        function ExecuteRound(
            const ARunID: string;
            const AInputs: TArray<TGSDAPeerInput>
        ): TGSDARoundResult;

        function FreezeCandidate(const ARunID: string): string;

        function Publish(
            const ARunID: string;
            const AHumanDecision: TGSDAHumanDecision
        ): TGSDARevisionSnapshot;

        function StateToJson(const ARunID: string): TJSONObject;

        property Kernel: TGSDAKernel31 read FKernel;
    end;

implementation

constructor TGSDARunContext.Create;
begin
    CandidateArtifactIDs := TList<string>.Create;
    Status := rsCreated;
    RoundIndex := -1;
end;

destructor TGSDARunContext.Destroy;
begin
    CandidateArtifactIDs.Free;
    inherited Destroy;
end;

constructor TGSDASpecAgent31.Create(AKernel: TGSDAKernel31);
begin
    if AKernel = nil then
        raise EArgumentNilException.Create('Kernel');

    FKernel := AKernel;
    FPublication := TGSDAPublication31.Create(AKernel);
    FRuns := TObjectDictionary<string,TGSDARunContext>.Create([doOwnsValues]);
end;

destructor TGSDASpecAgent31.Destroy;
begin
    FRuns.Free;
    FPublication.Free;
    inherited Destroy;
end;

function TGSDASpecAgent31.GetRun(const ARunID: string): TGSDARunContext;
begin
    if not FRuns.TryGetValue(ARunID, Result) then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Run not found: ' + ARunID);
end;

function TGSDASpecAgent31.NextRoundID(const ARunID: string; ARoundIndex: Int64): string;
begin
    Result := 'round:' + ARunID + ':' + IntToStr(ARoundIndex);
end;

function TGSDASpecAgent31.CreateTask(
    const AUserPrompt, AUserIntent, ADomain: string): TGSDAResearchTask;
begin
    Result := FKernel.CreateTask(AUserPrompt, AUserIntent, ADomain);
end;

function TGSDASpecAgent31.StartRun(const ATaskID: string): string;
var
    LTask: TGSDAResearchTask;
    LContext: TGSDARunContext;
begin
    LTask := FKernel.State.FindTask(ATaskID);
    if LTask = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Task not found: ' + ATaskID);

    Result := FKernel.IssueRunID;
    LContext := TGSDARunContext.Create;
    LContext.RunID := Result;
    LContext.TaskID := ATaskID;
    FRuns.Add(Result, LContext);
end;

function TGSDASpecAgent31.SubmitPeerMessage(
    const ARunID: string;
    const AInput: TGSDAPeerInput): TGSDAIngressResult;
var
    LRun: TGSDARunContext;
    LRoundID: string;
    LTask: TGSDAResearchTask;
begin
    LRun := GetRun(ARunID);
    LTask := FKernel.State.FindTask(LRun.TaskID);
    if LTask = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Task missing for run');

    if LRun.RoundIndex < 0 then
        LRun.RoundIndex := 0;

    if LRun.Status in [rsFrozen, rsPublished] then
        raise EGSDAFailure.Create(fcProtocolFailure, 'Run no longer accepts peer messages');

    LRoundID := NextRoundID(ARunID, LRun.RoundIndex);
    LRun.Status := rsGenerating;

    Result := FKernel.AcceptPeerMessage(
        AInput.PeerID,
        ARunID,
        LRun.TaskID,
        LRoundID,
        AInput.Fingerprint,
        AInput.Token,
        AInput.Kind,
        AInput.Confidence,
        AInput.Payload
    );
end;

function TGSDASpecAgent31.ComputeCandidateScore(
    const AMessage: TGSDAReasoningMessage): TPair<Int64,Int64>;
var
    LPeerReliabilityNumerator: Int64;
    LPeerReliabilityDenominator: Int64;
begin
    { Exact baseline scorer for the agent layer:
      confidence is integer 1..1000; peer reliability is kept as the
      deterministic integer pair encoded by the first reliability outcome
      records in the full implementation. Until that subsystem is present,
      use the neutral exact prior 1/2. No floating point is used. }
    LPeerReliabilityNumerator := 1;
    LPeerReliabilityDenominator := 2;

    Result.Key := Int64(AMessage.Confidence) * LPeerReliabilityNumerator;
    Result.Value := LPeerReliabilityDenominator;
end;

function CompareRationals(
    const ANumeratorA, ADenominatorA,
          ANumeratorB, ADenominatorB: Int64): Integer;
var
    LLeft: Int64;
    LRight: Int64;
begin
    LLeft := ANumeratorA * ADenominatorB;
    LRight := ANumeratorB * ADenominatorA;

    if LLeft < LRight then
        Result := -1
    else if LLeft > LRight then
        Result := 1
    else
        Result := 0;
end;

function TGSDASpecAgent31.SelectBestCandidate(
    const AMessageIDs: TArray<string>): string;
var
    LBestID: string;
    LBestMessage: TGSDAReasoningMessage;
    LBestScore: TPair<Int64,Int64>;
    LMessageID: string;
    LMessage: TGSDAReasoningMessage;
    LScore: TPair<Int64,Int64>;
    LComparison: Integer;
begin
    Result := '';
    LBestID := '';
    LBestMessage := nil;

    for LMessageID in AMessageIDs do
    begin
        LMessage := FKernel.State.FindMessage(LMessageID);
        if LMessage = nil then
            Continue;
        if LMessage.Kind <> mkCandidate then
            Continue;

        LScore := ComputeCandidateScore(LMessage);
        if LBestID = '' then
        begin
            LBestID := LMessageID;
            LBestMessage := LMessage;
            LBestScore := LScore;
            Continue;
        end;

        LComparison := CompareRationals(
            LScore.Key, LScore.Value,
            LBestScore.Key, LBestScore.Value
        );

        if (LComparison > 0) or
           ((LComparison = 0) and
            (CompareStr(LMessage.MessageID, LBestMessage.MessageID) < 0)) then
        begin
            LBestID := LMessageID;
            LBestMessage := LMessage;
            LBestScore := LScore;
        end;
    end;

    Result := LBestID;
end;

function TGSDASpecAgent31.BuildCandidateContent(
    const APayload: TJSONObject): string;
begin
    Result := TGSDAJson.Canonicalize(APayload);
end;

function TGSDASpecAgent31.ExecuteRound(
    const ARunID: string;
    const AInputs: TArray<TGSDAPeerInput>): TGSDARoundResult;
var
    LRun: TGSDARunContext;
    LResults: TList<TGSDAIngressResult>;
    LInput: TGSDAPeerInput;
    LIngress: TGSDAIngressResult;
    LMessageIDs: TArray<string>;
    LCandidateMessageID: string;
    LMessage: TGSDAReasoningMessage;
    LArtifact: TGSDAArtifact;
    LTask: TGSDAResearchTask;
    LPreviousCandidate: string;
    LScore: TPair<Int64,Int64>;
    LRoundID: string;
    LIndex: Integer;
begin
    LRun := GetRun(ARunID);
    Inc(LRun.RoundIndex);
    LRoundID := NextRoundID(ARunID, LRun.RoundIndex);
    LRun.Status := rsGenerating;

    LResults := TList<TGSDAIngressResult>.Create;
    try
        if Length(AInputs) > FKernel.Config.MaxMessagesPerRound then
            raise EGSDAFailure.Create(fcInputBoundsExceeded, 'Too many peer messages');

        for LInput in AInputs do
        begin
            LIngress := FKernel.AcceptPeerMessage(
                LInput.PeerID,
                ARunID,
                LRun.TaskID,
                LRoundID,
                LInput.Fingerprint,
                LInput.Token,
                LInput.Kind,
                LInput.Confidence,
                LInput.Payload
            );
            if not LIngress.Accepted then
                raise EGSDAFailure.Create(fcProtocolFailure, 'Peer message was not accepted');
            LResults.Add(LIngress);
        end;

        SetLength(LMessageIDs, LResults.Count);
        for LIndex := 0 to LResults.Count - 1 do
            LMessageIDs[LIndex] := LResults[LIndex].MessageID;

        LCandidateMessageID := SelectBestCandidate(LMessageIDs);
        if LCandidateMessageID = '' then
            raise EGSDAFailure.Create(fcProtocolFailure, 'Round contains no valid candidate');

        LMessage := FKernel.State.FindMessage(LCandidateMessageID);
        LTask := FKernel.State.FindTask(LRun.TaskID);
        if (LMessage = nil) or (LTask = nil) then
            raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Candidate/task missing');

        LScore := ComputeCandidateScore(LMessage);
        LArtifact := FKernel.RegisterArtifact(
            LRun.TaskID,
            ARunID,
            LMessage.PeerID,
            LRoundID,
            'candidate',
            BuildCandidateContent(LMessage.Payload),
            [],
            [],
            [LMessage.MessageID],
            LMessage.MessageID
        );

        if LTask.Intent.Elements.Count = 0 then
            raise EGSDAFailure.Create(fcPublicationFailure, 'Task contains no intent element');
        FKernel.LinkIntentToArtifact(
            LTask.TaskID,
            LTask.Intent.Elements[0].IntentID,
            LArtifact.ArtifactID
        );
        LRun.CandidateArtifactIDs.Add(LArtifact.ArtifactID);
        LPreviousCandidate := LRun.LastCandidateArtifactID;
        LRun.LastCandidateArtifactID := LArtifact.ArtifactID;
        LRun.Status := rsConsolidating;

        Result.RoundIndex := LRun.RoundIndex;
        Result.AcceptedMessages := LResults.Count;
        Result.CandidateArtifactID := LArtifact.ArtifactID;
        Result.WinningPeerID := LMessage.PeerID;
        Result.WinningScoreNumerator := LScore.Key;
        Result.WinningScoreDenominator := LScore.Value;
        Result.Converged :=
            (LPreviousCandidate <> '') and
            (LPreviousCandidate = LArtifact.ArtifactID);
    finally
        LResults.Free;
    end;
end;

function TGSDASpecAgent31.BuildEmptySpecJson(
    const ASchema, AItemName: string): string;
begin
    Result :=
        '{"schema":"' + ASchema + '","' + AItemName + '":[]}';
end;

function TGSDASpecAgent31.FreezeCandidate(const ARunID: string): string;
var
    LRun: TGSDARunContext;
    LTask: TGSDAResearchTask;
    LRequirements: string;
    LGlossary: string;
    LAssumptions: string;
    LQuestions: string;
    LTraceability: string;
begin
    LRun := GetRun(ARunID);
    LTask := FKernel.State.FindTask(LRun.TaskID);
    if LTask = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Task missing');

    if LRun.LastCandidateArtifactID = '' then
        raise EGSDAFailure.Create(fcPublicationFailure, 'No candidate to freeze');

    LRequirements := FKernel.BuildRequirementsJSON;
    LGlossary := BuildEmptySpecJson('glossary/3.1', 'terms');
    LAssumptions := BuildEmptySpecJson('assumptions/3.1', 'items');
    LQuestions := BuildEmptySpecJson('open_questions/3.1', 'items');

    LTraceability := FKernel.BuildTraceabilityJSON;

    Result := FKernel.ComputeSpecContentID(
        LRequirements,
        LGlossary,
        LAssumptions,
        LQuestions,
        LTraceability
    );

    LRun.Status := rsFrozen;
end;

function TGSDASpecAgent31.Publish(
    const ARunID: string;
    const AHumanDecision: TGSDAHumanDecision): TGSDARevisionSnapshot;
var
    LRun: TGSDARunContext;
    LRequirements: string;
    LGlossary: string;
    LAssumptions: string;
    LQuestions: string;
    LTraceability: string;
    LSpecContentID: string;
    LDecision: TGSDAHumanDecision;
begin
    LRun := GetRun(ARunID);
    if LRun.LastCandidateArtifactID = '' then
        raise EGSDAFailure.Create(fcPublicationFailure, 'Cannot publish without candidate');

    LRequirements := FKernel.BuildRequirementsJSON;
    LGlossary := BuildEmptySpecJson('glossary/3.1', 'terms');
    LAssumptions := BuildEmptySpecJson('assumptions/3.1', 'items');
    LQuestions := BuildEmptySpecJson('open_questions/3.1', 'items');
    LTraceability := FKernel.BuildTraceabilityJSON;

    LSpecContentID := FKernel.ComputeSpecContentID(
        LRequirements,
        LGlossary,
        LAssumptions,
        LQuestions,
        LTraceability
    );

    if AHumanDecision = nil then
        raise EGSDAFailure.Create(
            fcGovernanceFailure,
            'Explicit human decision is required for publication'
        );

    LDecision := AHumanDecision;

    if LDecision.SpecContentID <> LSpecContentID then
        raise EGSDAFailure.Create(fcGovernanceFailure, 'Human decision targets different SpecContentID');

    try
        Result := FPublication.Publish(
            LRun.TaskID,
            LRequirements,
            LGlossary,
            LAssumptions,
            LQuestions,
            LTraceability,
            LDecision
        );
        LRun.Status := rsPublished;
    except
        on E: EGSDAFailure do
        begin
            LRun.Status := rsPublicationBlocked;
            raise;
        end;
    end;
end;

function TGSDASpecAgent31.StateToJson(const ARunID: string): TJSONObject;
var
    LRun: TGSDARunContext;
    LObject: TJSONObject;
    LArray: TJSONArray;
    LArtifactID: string;
begin
    LRun := GetRun(ARunID);
    Result := TJSONObject.Create;
    Result.AddPair('run_id', LRun.RunID);
    Result.AddPair('task_id', LRun.TaskID);
    Result.AddPair('round_index', TJSONNumber.Create(LRun.RoundIndex));
    Result.AddPair('status', Ord(LRun.Status).ToString);
    Result.AddPair('last_candidate_artifact_id', LRun.LastCandidateArtifactID);

    LArray := TJSONArray.Create;
    for LArtifactID in LRun.CandidateArtifactIDs do
        LArray.Add(LArtifactID);
    Result.AddPair('candidate_artifact_ids', LArray);
end;

end.
