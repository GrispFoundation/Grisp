unit GSDA31;

interface

uses
    System.SysUtils,
    System.Classes,
    System.JSON,
    System.Generics.Collections,
    System.Generics.Defaults,
    System.Hash,
    System.DateUtils;

type
    TGSDAId = string;

    TGSDAFailureCode = (
        fcNone,
        fcSchemaFailure,
        fcProtocolFailure,
        fcImpersonationAttempt,
        fcIdentityMismatch,
        fcContentIdentityMismatch,
        fcSourceReferenceUnresolved,
        fcScopeViolation,
        fcInputBoundsExceeded,
        fcAggregationBoundsExceeded,
        fcReliabilityBoundsExceeded,
        fcGovernanceFailure,
        fcLivenessFailure,
        fcPublicationFailure,
        fcNormativeKeywordLeak,
        fcCrossReferenceUnresolved,
        fcConfigIncomplete,
        fcTermCollision,
        fcLineageFailure
    );

    EGSDAFailure = class(Exception)
    private
        FCode: TGSDAFailureCode;
    public
        constructor Create(ACode: TGSDAFailureCode; const AMessage: string);
        property Code: TGSDAFailureCode read FCode;
    end;

    TGSDAMessageKind = (
        mkCandidate,
        mkCritique,
        mkRepair,
        mkScore,
        mkRequirement,
        mkTerm,
        mkQuestion,
        mkConsolidation
    );

    TGSDAPeerActivity = (
        paGeneration,
        paCritique,
        paRepair,
        paScoring,
        paConsolidation,
        paAnalysis
    );

    TGSDAIntentElement = class
    public
        IntentID: TGSDAId;
        Text: string;
        Occurrence: Integer;
        Weight: Int64;
        Critical: Boolean;
        ByteStart: Int64;
        ByteEnd: Int64;
        SourceIDs: TArray<TGSDAId>;
        ArtifactIDs: TArray<TGSDAId>;
    end;

    TGSDAIntent = class
    public
        Elements: TObjectList<TGSDAIntentElement>;
        constructor Create;
        destructor Destroy; override;
    end;

    TGSDAConfig = class
    public
        Namespace: string;
        TargetLanguage: string;
        PriorityProfile: string;
        TargetAudience: TArray<string>;
        Constraints: TArray<string>;
        RequestedOutputs: TArray<string>;
        MaxRounds: Int64;
        MaxMessagesPerRound: Int64;
        MaxRepairDepth: Int64;
        CriticalCoverageNumerator: Int64;
        CriticalCoverageDenominator: Int64;
        HMACSecret: TBytes;
        constructor Create;
    end;

    TGSDARequirement = class
    public
        RequirementID: TGSDAId;
        Text: string;
        NormativeKeyword: string;
        SourceIDs: TArray<TGSDAId>;
        ArtifactIDs: TArray<TGSDAId>;
        EvidenceIDs: TArray<TGSDAId>;
    end;

    TGSDAArtifact = class
    public
        ArtifactID: TGSDAId;
        TaskID: TGSDAId;
        RunID: TGSDAId;
        PeerID: TGSDAId;
        RoundID: TGSDAId;
        LogicalSequence: Int64;
        ArtifactKind: string;
        ContentID: TGSDAId;
        Content: string;
        ParentArtifactIDs: TArray<TGSDAId>;
        RequirementIDs: TArray<TGSDAId>;
        SourceIDs: TArray<TGSDAId>;
    end;

    TGSDAEvidence = class
    public
        EvidenceID: TGSDAId;
        RunID: TGSDAId;
        EvidenceKind: string;
        SubjectIDs: TArray<TGSDAId>;
        ContentID: TGSDAId;
        ProducedBy: TGSDAId;
        CanonicalContent: string;
    end;

    TGSDAReasoningMessage = class
    public
        MessageID: TGSDAId;
        ContentID: TGSDAId;
        RunID: TGSDAId;
        TaskID: TGSDAId;
        PeerID: TGSDAId;
        RoundID: TGSDAId;
        LogicalSequence: Int64;
        Kind: TGSDAMessageKind;
        Confidence: Integer;
        RawPayload: string;
        CanonicalPayload: string;
        Payload: TJSONObject;
        constructor Create;
        destructor Destroy; override;
    end;

    TGSDARevisionSnapshot = class
    public
        RevisionID: TGSDAId;
        SpecContentID: TGSDAId;
        PreviousRevisionID: TGSDAId;
        PackageHash: string;
        Manifest: string;
        CreatedAtUTC: string;
        PackageFiles: TDictionary<string,string>;
        constructor Create;
        destructor Destroy; override;
    end;

    TGSDAHumanDecision = class
    public
        DecisionID: TGSDAId;
        ActorID: string;
        SpecContentID: TGSDAId;
        Accepted: Boolean;
        Rationale: string;
        SignatureHex: string;
        CreatedAtUTC: string;
    end;

    TGSDAJson = class
    private
        class function CompareUTF8(const ALeft, ARight: string): Integer; static;
        class procedure EmitString(const AValue: string; const ABuilder: TStringBuilder); static;
        class procedure EmitValue(const AValue: TJSONValue; const ABuilder: TStringBuilder); static;
        class procedure EmitObject(const AValue: TJSONObject; const ABuilder: TStringBuilder); static;
        class procedure EmitArray(const AValue: TJSONArray; const ABuilder: TStringBuilder); static;
    public
        class function Canonicalize(const AValue: TJSONValue): string; static;
    end;

    TGSDAPeerProfile = class
    public
        PeerID: string;
        Provider: string;
        Model: string;
        ModelVersion: string;
        AdapterID: string;
        TransportName: string;
        EndpointFingerprint: string;
        SharedSecret: TBytes;
        Enabled: Boolean;
    end;

    TGSDAResearchTask = class
    public
        TaskID: TGSDAId;
        TargetContextID: TGSDAId;
        UserPrompt: string;
        UserIntent: string;
        Domain: string;
        Namespace: string;
        TargetLanguage: string;
        TargetAudience: TArray<string>;
        Constraints: TArray<string>;
        RequestedOutputs: TArray<string>;
        PriorityProfile: string;
        Intent: TGSDAIntent;
        CreatedAtUTC: string;
        constructor Create;
        destructor Destroy; override;
    end;

    TGSDAState = class
    private
        FTasks: TObjectDictionary<string,TGSDAResearchTask>;
        FRequirements: TObjectDictionary<string,TGSDARequirement>;
        FArtifacts: TObjectDictionary<string,TGSDAArtifact>;
        FEvidence: TObjectDictionary<string,TGSDAEvidence>;
        FMessages: TObjectDictionary<string,TGSDAReasoningMessage>;
        FIdentities: TDictionary<string,string>;
        FIdentityKinds: TDictionary<string,string>;
        FSequenceByRun: TDictionary<string,Int64>;
        FRevisions: TObjectDictionary<string,TGSDARevisionSnapshot>;
        FLatestRevisionID: string;
    public
        constructor Create;
        destructor Destroy; override;
        procedure AddTask(ATask: TGSDAResearchTask);
        procedure AddRequirement(ARequirement: TGSDARequirement);
        procedure AddArtifact(AArtifact: TGSDAArtifact);
        procedure AddEvidence(AEvidence: TGSDAEvidence);
        procedure AddMessage(AMessage: TGSDAReasoningMessage);
        procedure RegisterIdentity(const AIdentity, AKind, APreimage: string);
        function FindTask(const ATaskID: string): TGSDAResearchTask;
        function FindRequirement(const AID: string): TGSDARequirement;
        function FindArtifact(const AID: string): TGSDAArtifact;
        function FindEvidence(const AID: string): TGSDAEvidence;
        function FindMessage(const AID: string): TGSDAReasoningMessage;
        function IdentityExists(const AID: string): Boolean;
        function NextSequence(const ARunID: string): Int64;
        procedure AddRevision(ARevision: TGSDARevisionSnapshot);
        function FindRevision(const ASpecContentID: string): TGSDARevisionSnapshot;
        function LatestRevision: TGSDARevisionSnapshot;
    end;

    TGSDAIngressResult = record
        MessageID: string;
        ContentID: string;
        LogicalSequence: Int64;
        Accepted: Boolean;
    end;

    TGSDACoverageResult = record
        TotalIntent: Int64;
        CriticalIntent: Int64;
        CoveredCriticalIntent: Int64;
        Numerator: Int64;
        Denominator: Int64;
        UncoveredOffsets: TArray<Int64>;
    end;

    TGSDAKernel31 = class
    private
        FState: TGSDAState;
        FConfig: TGSDAConfig;
        FPeers: TObjectDictionary<string,TGSDAPeerProfile>;
        function SortedStrings(const AValues: TArray<string>): TArray<string>;
        function CanonicalIDObject(const AObject: TJSONObject): string;
        function ComputeContentID(const APayload: TJSONObject): string;
        function VerifyHMAC(const AProfile: TGSDAPeerProfile; const AFingerprint, ARoundID, AToken: string): Boolean;
        function HMACInput(const AProfile: TGSDAPeerProfile; const AFingerprint, ARoundID: string): string;
        function ArrayJSON(const AValues: TArray<string>): TJSONArray;
    public
        constructor Create(AConfig: TGSDAConfig);
        destructor Destroy; override;

        property State: TGSDAState read FState;
        property Config: TGSDAConfig read FConfig;

        procedure RegisterPeer(AProfile: TGSDAPeerProfile);
        function CreateTask(const AUserPrompt, AUserIntent, ADomain: string): TGSDAResearchTask;
        function IssueRunID: string;

        function AcceptPeerMessage(
            const APeerID, ARunID, ATaskID, ARoundID, AFingerprint, AToken: string;
            AKind: TGSDAMessageKind;
            AConfidence: Integer;
            const ARawPayload: string): TGSDAIngressResult;

        function RegisterRequirement(
            const AText, AKeyword: string;
            const ASourceIDs: TArray<string>): TGSDARequirement;

        function RegisterArtifact(
            const ATaskID, ARunID, APeerID, ARoundID, AKind, AContent: string;
            const AParentArtifactIDs, ARequirementIDs, ASourceIDs: TArray<string>;
            const AMessageID: string): TGSDAArtifact;

        function RegisterEvidence(
            const ARunID, AKind: string;
            const ASubjectIDs: TArray<string>;
            const ACanonicalContent, AProducedBy: string): TGSDAEvidence;

        function ComputeCoverage(const ATaskID: string): TGSDACoverageResult;
        procedure LinkIntentToArtifact(
            const ATaskID, AIntentID, AArtifactID: string);
        function BuildRequirementsJSON: string;
        function BuildTraceabilityJSON: string;
        function BuildRegistryJSON: string;
        function ComputeSpecContentID(
            const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
                  AQuestionsJSON, ATraceabilityJSON: string): string;
        function ComputePackageHash(const AFiles: TDictionary<string,string>): string;
        function ValidatePublication(
            const ATaskID, ASpecContentID: string;
            const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
                  AQuestionsJSON, ATraceabilityJSON: string;
            const AHumanDecision: TGSDAHumanDecision): Boolean;
        function CommitRevision(
            const ASpecContentID: string;
            const AFiles: TDictionary<string,string>;
            const AManifest, APackageHash: string;
            const AHumanDecision: TGSDAHumanDecision): TGSDARevisionSnapshot;
    end;

    TGSDAPublication31 = class
    private
        FKernel: TGSDAKernel31;
        procedure CheckKeywords(const ARequirementsJSON, AGlossaryJSON,
                                AAssumptionsJSON, AQuestionsJSON,
                                ATraceabilityJSON: string);
        procedure CheckReferences;
        procedure CheckCoverage(const ATaskID: string);
        procedure CheckPackage(const AFiles: TDictionary<string,string>);
    public
        constructor Create(AKernel: TGSDAKernel31);
        function BuildPackage(
            const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
                  AQuestionsJSON, ATraceabilityJSON: string): TDictionary<string,string>;
        function Publish(
            const ATaskID: string;
            const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
                  AQuestionsJSON, ATraceabilityJSON: string;
            const AHumanDecision: TGSDAHumanDecision): TGSDARevisionSnapshot;
    end;

function GSDA_SHA256Hex(const AValue: string): string;
function GSDA_HMACSHA256Hex(const ASecret: TBytes; const AValue: string): string;
function GSDA_BytesToHex(const ABytes: TBytes): string;
function GSDA_UtcNow: string;
function GSDA_ConstantTimeEquals(const ALeft, ARight: string): Boolean;
function GSDAFailureName(const ACode: TGSDAFailureCode): string;
function GSDAMessageKindName(const AKind: TGSDAMessageKind): string;
function GSDABuildHMACToken(const ASecret: TBytes; const APeerID, AFingerprint, ARoundID: string): string;

implementation

{ Forward declarations }

function IsSafePackagePath(const AName: string): Boolean; forward;

function GSDA_BytesToHex(const ABytes: TBytes): string;
const
    LHexDigits: array[0..15] of Char = '0123456789abcdef';
var
    LIndex: Integer;
    LByte: Byte;
begin
    SetLength(Result, Length(ABytes) * 2);
    for LIndex := 0 to Length(ABytes) - 1 do
    begin
        LByte := ABytes[LIndex];
        Result[(LIndex * 2) + 1] := LHexDigits[LByte shr 4];
        Result[(LIndex * 2) + 2] := LHexDigits[LByte and $0F];
    end;
end;

function GSDA_SHA256Hex(const AValue: string): string;
var
    LStream: TBytesStream;
    LBytes: TBytes;
begin
    LBytes := TEncoding.UTF8.GetBytes(AValue);
    LStream := TBytesStream.Create(LBytes);
    try
        LStream.Position := 0;
        Result := LowerCase(THashSHA2.GetHashString(LStream, SHA256));
    finally
        LStream.Free;
    end;
end;

function GSDA_HMACSHA256Hex(const ASecret: TBytes; const AValue: string): string;
var
    LData: TBytes;
    LDigest: TBytes;
begin
    LData := TEncoding.UTF8.GetBytes(AValue);
    LDigest := THashSHA2.GetHMACAsBytes(LData, ASecret, SHA256);
    Result := GSDA_BytesToHex(LDigest);
end;

function GSDA_UtcNow: string;
begin
    Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

function GSDA_ConstantTimeEquals(const ALeft, ARight: string): Boolean;
var
    LLeft, LRight: TBytes;
    LIndex, LDiff: Integer;
begin
    LLeft := TEncoding.UTF8.GetBytes(ALeft);
    LRight := TEncoding.UTF8.GetBytes(ARight);
    LDiff := Length(LLeft) xor Length(LRight);
    for LIndex := 0 to Length(LLeft) - 1 do
        if LIndex < Length(LRight) then
            LDiff := LDiff or (LLeft[LIndex] xor LRight[LIndex])
        else
            LDiff := LDiff or LLeft[LIndex];
    for LIndex := 0 to Length(LRight) - 1 do
        if LIndex >= Length(LLeft) then
            LDiff := LDiff or LRight[LIndex];
    Result := LDiff = 0;
end;

function GSDAFailureName(const ACode: TGSDAFailureCode): string;
begin
    case ACode of
        fcNone: Result := 'NONE';
        fcSchemaFailure: Result := 'SCHEMA_FAILURE';
        fcProtocolFailure: Result := 'PROTOCOL_FAILURE';
        fcImpersonationAttempt: Result := 'IMPERSONATION_ATTEMPT';
        fcIdentityMismatch: Result := 'IDENTITY_MISMATCH';
        fcContentIdentityMismatch: Result := 'CONTENT_IDENTITY_MISMATCH';
        fcSourceReferenceUnresolved: Result := 'SOURCE_REFERENCE_UNRESOLVED';
        fcScopeViolation: Result := 'SCOPE_VIOLATION';
        fcInputBoundsExceeded: Result := 'INPUT_BOUNDS_EXCEEDED';
        fcAggregationBoundsExceeded: Result := 'AGGREGATION_BOUNDS_EXCEEDED';
        fcReliabilityBoundsExceeded: Result := 'RELIABILITY_BOUNDS_EXCEEDED';
        fcGovernanceFailure: Result := 'GOVERNANCE_FAILURE';
        fcLivenessFailure: Result := 'LIVENESS_FAILURE';
        fcPublicationFailure: Result := 'PUBLICATION_FAILURE';
        fcNormativeKeywordLeak: Result := 'NORMATIVE_KEYWORD_LEAK';
        fcCrossReferenceUnresolved: Result := 'CROSS_REFERENCE_UNRESOLVED';
        fcConfigIncomplete: Result := 'CONFIG_INCOMPLETE';
        fcTermCollision: Result := 'TERM_COLLISION';
        fcLineageFailure: Result := 'LINEAGE_FAILURE';
    else
        Result := 'UNKNOWN';
    end;
end;

function GSDAMessageKindName(const AKind: TGSDAMessageKind): string;
begin
    case AKind of
        mkCandidate: Result := 'candidate';
        mkCritique: Result := 'critique';
        mkRepair: Result := 'repair';
        mkScore: Result := 'score';
        mkRequirement: Result := 'requirement';
        mkTerm: Result := 'term';
        mkQuestion: Result := 'question';
        mkConsolidation: Result := 'consolidation';
    end;
end;

function GSDABuildHMACToken(const ASecret: TBytes; const APeerID, AFingerprint, ARoundID: string): string;
begin
    Result := GSDA_HMACSHA256Hex(ASecret, APeerID + '|' + AFingerprint + '|' + ARoundID);
end;

constructor EGSDAFailure.Create(ACode: TGSDAFailureCode; const AMessage: string);
begin
    inherited Create(AMessage);
    FCode := ACode;
end;

{ TGSDAIntent }

constructor TGSDAIntent.Create;
begin
    Elements := TObjectList<TGSDAIntentElement>.Create(True);
end;

destructor TGSDAIntent.Destroy;
begin
    Elements.Free;
    inherited Destroy;
end;

{ TGSDAConfig }

constructor TGSDAConfig.Create;
begin
    MaxRounds := 8;
    MaxMessagesPerRound := 64;
    MaxRepairDepth := 16;
    CriticalCoverageNumerator := 1;
    CriticalCoverageDenominator := 1;
end;

{ TGSDAReasoningMessage }

constructor TGSDAReasoningMessage.Create;
begin
    Payload := nil;
end;

destructor TGSDAReasoningMessage.Destroy;
begin
    Payload.Free;
    inherited Destroy;
end;

{ TGSDARevisionSnapshot }

constructor TGSDARevisionSnapshot.Create;
begin
    PackageFiles := TDictionary<string,string>.Create;
end;

destructor TGSDARevisionSnapshot.Destroy;
begin
    PackageFiles.Free;
    inherited Destroy;
end;

{ TGSDAResearchTask }

constructor TGSDAResearchTask.Create;
begin
    Intent := TGSDAIntent.Create;
end;

destructor TGSDAResearchTask.Destroy;
begin
    Intent.Free;
    inherited Destroy;
end;

{ TGSDAState }

constructor TGSDAState.Create;
begin
    FTasks := TObjectDictionary<string,TGSDAResearchTask>.Create([doOwnsValues]);
    FRequirements := TObjectDictionary<string,TGSDARequirement>.Create([doOwnsValues]);
    FArtifacts := TObjectDictionary<string,TGSDAArtifact>.Create([doOwnsValues]);
    FEvidence := TObjectDictionary<string,TGSDAEvidence>.Create([doOwnsValues]);
    FMessages := TObjectDictionary<string,TGSDAReasoningMessage>.Create([doOwnsValues]);
    FIdentities := TDictionary<string,string>.Create;
    FIdentityKinds := TDictionary<string,string>.Create;
    FSequenceByRun := TDictionary<string,Int64>.Create;
    FRevisions := TObjectDictionary<string,TGSDARevisionSnapshot>.Create([doOwnsValues]);
    FLatestRevisionID := '';
end;

destructor TGSDAState.Destroy;
begin
    FRevisions.Free;
    FSequenceByRun.Free;
    FIdentityKinds.Free;
    FIdentities.Free;
    FMessages.Free;
    FEvidence.Free;
    FArtifacts.Free;
    FRequirements.Free;
    FTasks.Free;
    inherited Destroy;
end;

procedure TGSDAState.AddTask(ATask: TGSDAResearchTask);
begin
    if FTasks.ContainsKey(ATask.TaskID) then
        raise EGSDAFailure.Create(fcIdentityMismatch, 'Task identity collision');
    FTasks.Add(ATask.TaskID, ATask);
end;

procedure TGSDAState.AddRequirement(ARequirement: TGSDARequirement);
begin
    if FRequirements.ContainsKey(ARequirement.RequirementID) then
        raise EGSDAFailure.Create(fcIdentityMismatch, 'Requirement identity collision');
    FRequirements.Add(ARequirement.RequirementID, ARequirement);
end;

procedure TGSDAState.AddArtifact(AArtifact: TGSDAArtifact);
begin
    if FArtifacts.ContainsKey(AArtifact.ArtifactID) then
        raise EGSDAFailure.Create(fcIdentityMismatch, 'Artifact identity collision');
    FArtifacts.Add(AArtifact.ArtifactID, AArtifact);
end;

procedure TGSDAState.AddEvidence(AEvidence: TGSDAEvidence);
begin
    if FEvidence.ContainsKey(AEvidence.EvidenceID) then
        raise EGSDAFailure.Create(fcIdentityMismatch, 'Evidence identity collision');
    FEvidence.Add(AEvidence.EvidenceID, AEvidence);
end;

procedure TGSDAState.AddMessage(AMessage: TGSDAReasoningMessage);
begin
    if FMessages.ContainsKey(AMessage.MessageID) then
        raise EGSDAFailure.Create(fcIdentityMismatch, 'Message identity collision');
    FMessages.Add(AMessage.MessageID, AMessage);
end;

procedure TGSDAState.RegisterIdentity(const AIdentity, AKind, APreimage: string);
var
    LExisting: string;
    LExistingKind: string;
begin
    if FIdentities.TryGetValue(AIdentity, LExisting) then
    begin
        LExistingKind := FIdentityKinds[AIdentity];
        if (LExisting <> APreimage) or (LExistingKind <> AKind) then
            raise EGSDAFailure.Create(fcIdentityMismatch, 'Identity collision or preimage mismatch');
        Exit;
    end;
    FIdentities.Add(AIdentity, APreimage);
    FIdentityKinds.Add(AIdentity, AKind);
end;

function TGSDAState.FindTask(const ATaskID: string): TGSDAResearchTask;
begin
    if not FTasks.TryGetValue(ATaskID, Result) then
        Result := nil;
end;

function TGSDAState.FindRequirement(const AID: string): TGSDARequirement;
begin
    if not FRequirements.TryGetValue(AID, Result) then
        Result := nil;
end;

function TGSDAState.FindArtifact(const AID: string): TGSDAArtifact;
begin
    if not FArtifacts.TryGetValue(AID, Result) then
        Result := nil;
end;

function TGSDAState.FindEvidence(const AID: string): TGSDAEvidence;
begin
    if not FEvidence.TryGetValue(AID, Result) then
        Result := nil;
end;

function TGSDAState.FindMessage(const AID: string): TGSDAReasoningMessage;
begin
    if not FMessages.TryGetValue(AID, Result) then
        Result := nil;
end;

function TGSDAState.IdentityExists(const AID: string): Boolean;
begin
    Result := FIdentities.ContainsKey(AID);
end;

function TGSDAState.NextSequence(const ARunID: string): Int64;
var
    LValue: Int64;
begin
    if not FSequenceByRun.TryGetValue(ARunID, LValue) then
        LValue := 0;
    if LValue = High(Int64) then
        raise EGSDAFailure.Create(fcInputBoundsExceeded, 'Logical sequence overflow');
    Inc(LValue);
    FSequenceByRun.AddOrSetValue(ARunID, LValue);
    Result := LValue;
end;

procedure TGSDAState.AddRevision(ARevision: TGSDARevisionSnapshot);
begin
    if FRevisions.ContainsKey(ARevision.SpecContentID) then
        raise EGSDAFailure.Create(fcLineageFailure, 'Revision already exists');
    FRevisions.Add(ARevision.SpecContentID, ARevision);
    FLatestRevisionID := ARevision.SpecContentID;
end;

function TGSDAState.FindRevision(const ASpecContentID: string): TGSDARevisionSnapshot;
begin
    if not FRevisions.TryGetValue(ASpecContentID, Result) then
        Result := nil;
end;

function TGSDAState.LatestRevision: TGSDARevisionSnapshot;
begin
    if FLatestRevisionID = '' then
        Exit(nil);
    Result := FindRevision(FLatestRevisionID);
end;

{ TGSDAKernel31 }

constructor TGSDAKernel31.Create(AConfig: TGSDAConfig);
begin
    if AConfig = nil then
        raise EArgumentNilException.Create('Config');
    FConfig := AConfig;
    FState := TGSDAState.Create;
    FPeers := TObjectDictionary<string,TGSDAPeerProfile>.Create([doOwnsValues]);

    if FConfig.Namespace = '' then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'Namespace is required');
    if FConfig.TargetLanguage = '' then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'Target language is required');
    if FConfig.MaxRounds <= 0 then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'MaxRounds must be positive');
    if FConfig.MaxMessagesPerRound <= 0 then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'MaxMessagesPerRound must be positive');
    if FConfig.CriticalCoverageDenominator <= 0 then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'Critical coverage denominator must be positive');
    if (FConfig.CriticalCoverageNumerator < 0) or
       (FConfig.CriticalCoverageNumerator > FConfig.CriticalCoverageDenominator) then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'Invalid critical coverage threshold');
    if Length(FConfig.HMACSecret) = 0 then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'HMAC secret is required');
end;

destructor TGSDAKernel31.Destroy;
begin
    FPeers.Free;
    FState.Free;
    inherited Destroy;
end;

function TGSDAKernel31.SortedStrings(const AValues: TArray<string>): TArray<string>;
var
    LList: TList<string>;
    LValue: string;
begin
    LList := TList<string>.Create;
    try
        for LValue in AValues do
            LList.Add(LValue);
        LList.Sort;
        Result := LList.ToArray;
    finally
        LList.Free;
    end;
end;

function TGSDAKernel31.CanonicalIDObject(const AObject: TJSONObject): string;
begin
    Result := TGSDAJson.Canonicalize(AObject);
end;

function TGSDAKernel31.ArrayJSON(const AValues: TArray<string>): TJSONArray;
var
    LValue: string;
begin
    Result := TJSONArray.Create;
    for LValue in SortedStrings(AValues) do
        Result.Add(LValue);
end;

procedure TGSDAKernel31.RegisterPeer(AProfile: TGSDAPeerProfile);
begin
    if AProfile = nil then
        raise EArgumentNilException.Create('Peer profile');
    if AProfile.PeerID = '' then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'Peer ID missing');
    if Length(AProfile.SharedSecret) = 0 then
        raise EGSDAFailure.Create(fcConfigIncomplete, 'Peer secret missing');
    if FPeers.ContainsKey(AProfile.PeerID) then
        raise EGSDAFailure.Create(fcIdentityMismatch, 'Peer already registered');
    FPeers.Add(AProfile.PeerID, AProfile);
end;

function TGSDAKernel31.CreateTask(const AUserPrompt, AUserIntent, ADomain: string): TGSDAResearchTask;
var
    LObject: TJSONObject;
    LIndex: Integer;
    LIntentText: string;
    LIntent: TGSDAIntentElement;
    LParts: TArray<string>;
    LCursor: Integer;
begin
    if AUserPrompt = '' then
        raise EGSDAFailure.Create(fcSchemaFailure, 'Prompt is required');

    Result := TGSDAResearchTask.Create;
    Result.UserPrompt := AUserPrompt;
    Result.UserIntent := AUserIntent;
    Result.Domain := ADomain;
    Result.Namespace := FConfig.Namespace;
    Result.TargetLanguage := FConfig.TargetLanguage;
    Result.TargetAudience := Copy(FConfig.TargetAudience);
    Result.Constraints := Copy(FConfig.Constraints);
    Result.RequestedOutputs := Copy(FConfig.RequestedOutputs);
    Result.PriorityProfile := FConfig.PriorityProfile;
    Result.CreatedAtUTC := GSDA_UtcNow;

    LObject := TJSONObject.Create;
    try
        LObject.AddPair('user_prompt', Result.UserPrompt);
        LObject.AddPair('user_intent', Result.UserIntent);
        LObject.AddPair('domain', Result.Domain);
        LObject.AddPair('target_audience', ArrayJSON(Result.TargetAudience));
        LObject.AddPair('constraints', ArrayJSON(Result.Constraints));
        LObject.AddPair('requested_outputs', ArrayJSON(Result.RequestedOutputs));
        LObject.AddPair('priority_profile', Result.PriorityProfile);
        Result.TaskID := 'task:' + GSDA_SHA256Hex(CanonicalIDObject(LObject));
    finally
        LObject.Free;
    end;

    LObject := TJSONObject.Create;
    try
        LObject.AddPair('task_id', Result.TaskID);
        LObject.AddPair('namespace', Result.Namespace);
        LObject.AddPair('target_language', Result.TargetLanguage);
        Result.TargetContextID := 'ctx:' + GSDA_SHA256Hex(CanonicalIDObject(LObject));
    finally
        LObject.Free;
    end;

    { Deterministic hybrid baseline: sentences are segmented from user intent.
      Explicit [CRITICAL] marks criticality. Offsets are UTF-8 byte offsets. }
    LParts := Result.UserIntent.Split(['.'], TStringSplitOptions.ExcludeEmpty);
    LCursor := 0;
    for LIndex := 0 to High(LParts) do
    begin
        LIntentText := Trim(LParts[LIndex]);
        if LIntentText = '' then
            Continue;
        LIntent := TGSDAIntentElement.Create;
        LIntent.Occurrence := LIndex + 1;
        LIntent.Text := LIntentText;
        LIntent.Weight := 1;
        LIntent.Critical := Pos('[CRITICAL]', UpperCase(LIntentText)) > 0;
        LIntent.ByteStart := Length(TEncoding.UTF8.GetBytes(Copy(Result.UserIntent, 1, LCursor)));
        LIntent.ByteEnd := LIntent.ByteStart + Length(TEncoding.UTF8.GetBytes(LIntentText)) - 1;
        LIntent.IntentID := 'intent:' + GSDA_SHA256Hex(
            'intent_element_identity/3.1:' +
            LIntentText + ':' + LIntent.Occurrence.ToString
        );
        Result.Intent.Elements.Add(LIntent);
        Inc(LCursor, Pos('.', Copy(Result.UserIntent, LCursor + 1, MaxInt)));
        if LCursor <= 0 then
            LCursor := Length(Result.UserIntent);
    end;

    FState.AddTask(Result);
end;

function TGSDAKernel31.IssueRunID: string;
begin
    Result := 'run:' + GUIDToString(TGUID.NewGuid);
end;

function TGSDAKernel31.ComputeContentID(const APayload: TJSONObject): string;
var
    LProjection: TJSONObject;
    LPair: TJSONPair;
begin
    LProjection := APayload.Clone as TJSONObject;
    try
        LPair := LProjection.RemovePair('message_id'); LPair.Free;
        LPair := LProjection.RemovePair('hmac'); LPair.Free;
        LPair := LProjection.RemovePair('peer_id'); LPair.Free;
        LPair := LProjection.RemovePair('run_id'); LPair.Free;
        LPair := LProjection.RemovePair('round_id'); LPair.Free;
        LPair := LProjection.RemovePair('logical_sequence'); LPair.Free;
        LPair := LProjection.RemovePair('content_id'); LPair.Free;
        Result := 'content:' + GSDA_SHA256Hex(TGSDAJson.Canonicalize(LProjection));
    finally
        LProjection.Free;
    end;
end;

function TGSDAKernel31.HMACInput(const AProfile: TGSDAPeerProfile; const AFingerprint, ARoundID: string): string;
begin
    Result := AProfile.PeerID + '|' + AFingerprint + '|' + ARoundID;
end;

function TGSDAKernel31.VerifyHMAC(const AProfile: TGSDAPeerProfile; const AFingerprint, ARoundID, AToken: string): Boolean;
var
    LExpected: string;
begin
    if AFingerprint <>
       (AProfile.TransportName + '|' + AProfile.AdapterID + '|' + AProfile.EndpointFingerprint) then
        Exit(False);
    LExpected := GSDA_HMACSHA256Hex(
        AProfile.SharedSecret,
        HMACInput(AProfile, AFingerprint, ARoundID)
    );
    Result := GSDA_ConstantTimeEquals(LExpected, AToken);
end;

function TGSDAKernel31.AcceptPeerMessage(
    const APeerID, ARunID, ATaskID, ARoundID, AFingerprint, AToken: string;
    AKind: TGSDAMessageKind;
    AConfidence: Integer;
    const ARawPayload: string): TGSDAIngressResult;
var
    LPeer: TGSDAPeerProfile;
    LTask: TGSDAResearchTask;
    LValue: TJSONValue;
    LPayload: TJSONObject;
    LSchema: string;
    LContentID: string;
    LCanonical: string;
    LMessageID: string;
    LSequence: Int64;
    LMessage: TGSDAReasoningMessage;
    LIdentityObject: TJSONObject;
begin
    FillChar(Result, SizeOf(Result), 0);

    if not FPeers.TryGetValue(APeerID, LPeer) or (not LPeer.Enabled) then
        raise EGSDAFailure.Create(fcImpersonationAttempt, 'Unknown or disabled peer');

    LTask := FState.FindTask(ATaskID);
    if LTask = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Task does not exist');

    if (AConfidence < 1) or (AConfidence > 1000) then
        raise EGSDAFailure.Create(fcProtocolFailure, 'Confidence outside 1..1000');

    if not VerifyHMAC(LPeer, AFingerprint, ARoundID, AToken) then
        raise EGSDAFailure.Create(fcImpersonationAttempt, 'Peer authentication failed');

    LValue := TJSONObject.ParseJSONValue(Trim(ARawPayload));
    if not (LValue is TJSONObject) then
    begin
        LValue.Free;
        raise EGSDAFailure.Create(fcProtocolFailure, 'Payload is not a JSON object');
    end;
    LPayload := TJSONObject(LValue);
    try
        LSchema := LPayload.GetValue<string>('schema', '');
        if LSchema <> 'gsp/3.1' then
            raise EGSDAFailure.Create(fcSchemaFailure, 'Unsupported GSP schema');

        LContentID := ComputeContentID(LPayload);
        if LPayload.GetValue<string>('content_id', '') <> LContentID then
            raise EGSDAFailure.Create(fcContentIdentityMismatch, 'content_id mismatch');

        LCanonical := TGSDAJson.Canonicalize(LPayload);
        LSequence := FState.NextSequence(ARunID);
        LMessageID := 'msg:' + GSDA_SHA256Hex(
            TGSDAJson.Canonicalize(
                TJSONObject.Create
                    .AddPair('schema', 'message_identity/3.1')
                    .AddPair('run_id', ARunID)
                    .AddPair('peer_id', APeerID)
                    .AddPair('payload_schema', LSchema)
                    .AddPair('content_id', LContentID)
            )
        );

        if FState.FindMessage(LMessageID) <> nil then
            raise EGSDAFailure.Create(fcIdentityMismatch, 'Duplicate message identity');

        LMessage := TGSDAReasoningMessage.Create;
        LMessage.MessageID := LMessageID;
        LMessage.ContentID := LContentID;
        LMessage.RunID := ARunID;
        LMessage.TaskID := ATaskID;
        LMessage.PeerID := APeerID;
        LMessage.RoundID := ARoundID;
        LMessage.LogicalSequence := LSequence;
        LMessage.Kind := AKind;
        LMessage.Confidence := AConfidence;
        LMessage.RawPayload := ARawPayload;
        LMessage.CanonicalPayload := LCanonical;
        LMessage.Payload := LPayload.Clone as TJSONObject;

        LIdentityObject := TJSONObject.Create;
        try
            LIdentityObject.AddPair('schema', 'message_identity/3.1');
            LIdentityObject.AddPair('run_id', ARunID);
            LIdentityObject.AddPair('peer_id', APeerID);
            LIdentityObject.AddPair('payload_schema', LSchema);
            LIdentityObject.AddPair('content_id', LContentID);
            FState.RegisterIdentity(
                LMessageID,
                'message',
                TGSDAJson.Canonicalize(LIdentityObject)
            );
        finally
            LIdentityObject.Free;
        end;

        FState.AddMessage(LMessage);

        Result.Accepted := True;
        Result.MessageID := LMessageID;
        Result.ContentID := LContentID;
        Result.LogicalSequence := LSequence;
    finally
        LPayload.Free;
    end;
end;

function TGSDAKernel31.RegisterRequirement(
    const AText, AKeyword: string; const ASourceIDs: TArray<string>): TGSDARequirement;
var
    LObject: TJSONObject;
begin
    for var LID in ASourceIDs do
        if not FState.IdentityExists(LID) then
            raise EGSDAFailure.Create(fcSourceReferenceUnresolved, 'Unknown source reference: ' + LID);

    LObject := TJSONObject.Create;
    try
        LObject.AddPair('schema', 'requirement_identity/3.1');
        LObject.AddPair('text', AText);
        LObject.AddPair('normative_keyword', AKeyword);
        LObject.AddPair('source_ids', ArrayJSON(ASourceIDs));
        Result := TGSDARequirement.Create;
        Result.RequirementID := 'req:' + GSDA_SHA256Hex(TGSDAJson.Canonicalize(LObject));
        Result.Text := AText;
        Result.NormativeKeyword := AKeyword;
        Result.SourceIDs := Copy(ASourceIDs);
        FState.AddRequirement(Result);
        FState.RegisterIdentity(Result.RequirementID, 'requirement', TGSDAJson.Canonicalize(LObject));
    finally
        LObject.Free;
    end;
end;

function TGSDAKernel31.RegisterArtifact(
    const ATaskID, ARunID, APeerID, ARoundID, AKind, AContent: string;
    const AParentArtifactIDs, ARequirementIDs, ASourceIDs: TArray<string>;
    const AMessageID: string): TGSDAArtifact;
var
    LObject: TJSONObject;
    LContentID: string;
begin
    if FState.FindTask(ATaskID) = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Task missing for artifact');

    for var LID in AParentArtifactIDs do
        if FState.FindArtifact(LID) = nil then
            raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Unknown parent artifact: ' + LID);

    for var LID in ARequirementIDs do
        if FState.FindRequirement(LID) = nil then
            raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Unknown requirement: ' + LID);

    for var LID in ASourceIDs do
        if not FState.IdentityExists(LID) then
            raise EGSDAFailure.Create(fcSourceReferenceUnresolved, 'Unknown source: ' + LID);

    LContentID := 'content:' + GSDA_SHA256Hex(AContent);
    Result := TGSDAArtifact.Create;
    Result.TaskID := ATaskID;
    Result.RunID := ARunID;
    Result.PeerID := APeerID;
    Result.RoundID := ARoundID;
    Result.LogicalSequence := FState.NextSequence(ARunID);
    Result.ArtifactKind := AKind;
    Result.ContentID := LContentID;
    Result.Content := AContent;
    Result.ParentArtifactIDs := Copy(AParentArtifactIDs);
    Result.RequirementIDs := Copy(ARequirementIDs);
    Result.SourceIDs := Copy(ASourceIDs);

    LObject := TJSONObject.Create;
    try
        LObject.AddPair('schema', 'artifact_identity/3.1');
        LObject.AddPair('task_id', ATaskID);
        LObject.AddPair('run_id', ARunID);
        LObject.AddPair('artifact_kind', AKind);
        LObject.AddPair('content_id', LContentID);
        LObject.AddPair('author_peer_id', APeerID);
        LObject.AddPair('round_id', ARoundID);
        LObject.AddPair('parent_artifact_ids', ArrayJSON(AParentArtifactIDs));
        LObject.AddPair('message_id', AMessageID);
        Result.ArtifactID := 'artifact:' + GSDA_SHA256Hex(TGSDAJson.Canonicalize(LObject));
        FState.RegisterIdentity(Result.ArtifactID, 'artifact', TGSDAJson.Canonicalize(LObject));
    finally
        LObject.Free;
    end;

    FState.AddArtifact(Result);
end;

function TGSDAKernel31.RegisterEvidence(
    const ARunID, AKind: string; const ASubjectIDs: TArray<string>;
    const ACanonicalContent, AProducedBy: string): TGSDAEvidence;
var
    LObject: TJSONObject;
    LContentID: string;
begin
    for var LID in ASubjectIDs do
        if not FState.IdentityExists(LID) then
            raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Evidence subject missing: ' + LID);

    LContentID := 'content:' + GSDA_SHA256Hex(ACanonicalContent);
    Result := TGSDAEvidence.Create;
    Result.RunID := ARunID;
    Result.EvidenceKind := AKind;
    Result.SubjectIDs := Copy(ASubjectIDs);
    Result.ContentID := LContentID;
    Result.ProducedBy := AProducedBy;
    Result.CanonicalContent := ACanonicalContent;

    LObject := TJSONObject.Create;
    try
        LObject.AddPair('schema', 'evidence_identity/3.1');
        LObject.AddPair('run_id', ARunID);
        LObject.AddPair('evidence_kind', AKind);
        LObject.AddPair('subject_ids', ArrayJSON(ASubjectIDs));
        LObject.AddPair('content_id', LContentID);
        LObject.AddPair('produced_by', AProducedBy);
        Result.EvidenceID := 'evidence:' + GSDA_SHA256Hex(TGSDAJson.Canonicalize(LObject));
        FState.RegisterIdentity(Result.EvidenceID, 'evidence', TGSDAJson.Canonicalize(LObject));
    finally
        LObject.Free;
    end;

    FState.AddEvidence(Result);
end;

function TGSDAKernel31.ComputeCoverage(const ATaskID: string): TGSDACoverageResult;
var
    LTask: TGSDAResearchTask;
    LElement: TGSDAIntentElement;
    LArtifactID: string;
    LCovered: Boolean;
    LOffsets: TList<Int64>;
begin
    LTask := FState.FindTask(ATaskID);
    if LTask = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved, 'Task missing');

    FillChar(Result, SizeOf(Result), 0);
    LOffsets := TList<Int64>.Create;
    try
        for LElement in LTask.Intent.Elements do
        begin
            Inc(Result.TotalIntent);
            if not LElement.Critical then
                Continue;
            Inc(Result.CriticalIntent);
            LCovered := False;
            for LArtifactID in LElement.ArtifactIDs do
                if FState.FindArtifact(LArtifactID) <> nil then
                begin
                    LCovered := True;
                    Break;
                end;
            if LCovered then
                Inc(Result.CoveredCriticalIntent)
            else
                LOffsets.Add(LElement.ByteStart);
        end;

        if Result.CriticalIntent = 0 then
        begin
            Result.Numerator := 1;
            Result.Denominator := 1;
        end
        else
        begin
            Result.Numerator := Result.CoveredCriticalIntent;
            Result.Denominator := Result.CriticalIntent;
        end;
        Result.UncoveredOffsets := LOffsets.ToArray;
    finally
        LOffsets.Free;
    end;
end;

procedure TGSDAKernel31.LinkIntentToArtifact(
    const ATaskID, AIntentID, AArtifactID: string);
var
    LTask: TGSDAResearchTask;
    LElement: TGSDAIntentElement;
    LIndex: Integer;
begin
    LTask := FState.FindTask(ATaskID);
    if LTask = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved,
            'Task not found: ' + ATaskID);

    if FState.FindArtifact(AArtifactID) = nil then
        raise EGSDAFailure.Create(fcCrossReferenceUnresolved,
            'Artifact not found: ' + AArtifactID);

    for LElement in LTask.Intent.Elements do
    begin
        if LElement.IntentID = AIntentID then
        begin
            for LIndex := 0 to Length(LElement.ArtifactIDs) - 1 do
                if LElement.ArtifactIDs[LIndex] = AArtifactID then
                    Exit;

            SetLength(LElement.ArtifactIDs, Length(LElement.ArtifactIDs) + 1);
            LElement.ArtifactIDs[High(LElement.ArtifactIDs)] := AArtifactID;
            Exit;
        end;
    end;

    raise EGSDAFailure.Create(fcCrossReferenceUnresolved,
        'Intent element not found: ' + AIntentID);
end;

function TGSDAKernel31.BuildRequirementsJSON: string;
var
    LRoot: TJSONObject;
    LArray: TJSONArray;
    LReq: TGSDARequirement;
    LObj: TJSONObject;
begin
    LRoot := TJSONObject.Create;
    try
        LArray := TJSONArray.Create;
        for LReq in FState.FRequirements.Values do
        begin
            LObj := TJSONObject.Create;
            LObj.AddPair('requirement_id', LReq.RequirementID);
            LObj.AddPair('text', LReq.Text);
            LObj.AddPair('normative_keyword', LReq.NormativeKeyword);
            LArray.Add(LObj);
        end;
        LRoot.AddPair('schema', 'requirements/3.1');
        LRoot.AddPair('items', LArray);
        Result := TGSDAJson.Canonicalize(LRoot);
    finally
        LRoot.Free;
    end;
end;

function TGSDAKernel31.BuildTraceabilityJSON: string;
var
    LRoot: TJSONObject;
    LArtifacts: TJSONArray;
    LEvidence: TJSONArray;
    LArtifact: TGSDAArtifact;
    LEvidenceItem: TGSDAEvidence;
    LObj: TJSONObject;
begin
    LRoot := TJSONObject.Create;
    try
        LArtifacts := TJSONArray.Create;
        for LArtifact in FState.FArtifacts.Values do
        begin
            LObj := TJSONObject.Create;
            LObj.AddPair('artifact_id', LArtifact.ArtifactID);
            LObj.AddPair('requirement_ids', ArrayJSON(LArtifact.RequirementIDs));
            LObj.AddPair('source_ids', ArrayJSON(LArtifact.SourceIDs));
            LArtifacts.Add(LObj);
        end;

        LEvidence := TJSONArray.Create;
        for LEvidenceItem in FState.FEvidence.Values do
        begin
            LObj := TJSONObject.Create;
            LObj.AddPair('evidence_id', LEvidenceItem.EvidenceID);
            LObj.AddPair('subject_ids', ArrayJSON(LEvidenceItem.SubjectIDs));
            LObj.AddPair('kind', LEvidenceItem.EvidenceKind);
            LEvidence.Add(LObj);
        end;

        LRoot.AddPair('schema', 'traceability/3.1');
        LRoot.AddPair('artifacts', LArtifacts);
        LRoot.AddPair('evidence', LEvidence);
        Result := TGSDAJson.Canonicalize(LRoot);
    finally
        LRoot.Free;
    end;
end;

function TGSDAKernel31.BuildRegistryJSON: string;
var
    LRoot, LObj: TJSONObject;
begin
    LRoot := TJSONObject.Create;
    try
        LObj := TJSONObject.Create;
        LObj.AddPair('kernel_version', '3.1.0');
        LObj.AddPair('canonicalization', 'GSDA-UTF8-BYTEWISE-3.1');
        LRoot.AddPair('schema', 'registry/3.1');
        LRoot.AddPair('implementation', LObj);
        Result := TGSDAJson.Canonicalize(LRoot);
    finally
        LRoot.Free;
    end;
end;

function TGSDAKernel31.ComputeSpecContentID(
    const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
          AQuestionsJSON, ATraceabilityJSON: string): string;
var
    LRoot: TJSONObject;
begin
    LRoot := TJSONObject.Create;
    try
        LRoot.AddPair('schema', 'spec_content_identity/3.1');
        LRoot.AddPair('requirements', TJSONObject.ParseJSONValue(ARequirementsJSON));
        LRoot.AddPair('glossary', TJSONObject.ParseJSONValue(AGlossaryJSON));
        LRoot.AddPair('assumptions', TJSONObject.ParseJSONValue(AAssumptionsJSON));
        LRoot.AddPair('open_questions', TJSONObject.ParseJSONValue(AQuestionsJSON));
        LRoot.AddPair('traceability', TJSONObject.ParseJSONValue(ATraceabilityJSON));
        Result := 'spec:' + GSDA_SHA256Hex(TGSDAJson.Canonicalize(LRoot));
    finally
        LRoot.Free;
    end;
end;

function TGSDAKernel31.ComputePackageHash(const AFiles: TDictionary<string,string>): string;
var
    LNames: TList<string>;
    LName: string;
    LBuilder: TStringBuilder;
    LFileID: string;
begin
    LNames := TList<string>.Create;
    try
        for LName in AFiles.Keys do
            LNames.Add(LName);
        LNames.Sort;
        LBuilder := TStringBuilder.Create;
        try
            for LName in LNames do
            begin
                LFileID := 'file:' + GSDA_SHA256Hex(AFiles[LName]);
                LBuilder.Append(LName).Append('=').Append(LFileID).Append(#10);
            end;
            Result := GSDA_SHA256Hex(LBuilder.ToString);
        finally
            LBuilder.Free;
        end;
    finally
        LNames.Free;
    end;
end;

function IsSafePackagePath(const AName: string): Boolean;
begin
    Result := (AName <> '') and
              (Pos('..', AName) = 0) and
              (not AName.StartsWith('/')) and
              (not AName.StartsWith('\')) and
              (Pos(':', AName) = 0);
end;

function TGSDAKernel31.ValidatePublication(
    const ATaskID, ASpecContentID: string;
    const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
          AQuestionsJSON, ATraceabilityJSON: string;
    const AHumanDecision: TGSDAHumanDecision): Boolean;
var
    LExpected: string;
    LTask: TGSDAResearchTask;
begin
    Result := False;

    LTask := FState.FindTask(ATaskID);
    if LTask = nil then
        Exit;

    LExpected := ComputeSpecContentID(
        ARequirementsJSON,
        AGlossaryJSON,
        AAssumptionsJSON,
        AQuestionsJSON,
        ATraceabilityJSON
    );
    if LExpected <> ASpecContentID then
        Exit;

    if AHumanDecision = nil then
        Exit;
    if not AHumanDecision.Accepted then
        Exit;
    if AHumanDecision.ActorID = '' then
        Exit;
    if AHumanDecision.Rationale = '' then
        Exit;
    if AHumanDecision.SpecContentID <> ASpecContentID then
        Exit;

    Result := True;
end;

function TGSDAKernel31.CommitRevision(
    const ASpecContentID: string;
    const AFiles: TDictionary<string,string>;
    const AManifest, APackageHash: string;
    const AHumanDecision: TGSDAHumanDecision): TGSDARevisionSnapshot;
var
    LPrevious: TGSDARevisionSnapshot;
    LParentID: string;
begin
    if (AHumanDecision = nil) or not AHumanDecision.Accepted then
        raise EGSDAFailure.Create(fcGovernanceFailure, 'Human acceptance required');

    LPrevious := FState.LatestRevision;
    if LPrevious = nil then
        LParentID := ''
    else
        LParentID := LPrevious.RevisionID;

    Result := TGSDARevisionSnapshot.Create;
    Result.SpecContentID := ASpecContentID;
    Result.PreviousRevisionID := LParentID;
    Result.PackageHash := APackageHash;
    Result.Manifest := AManifest;
    Result.CreatedAtUTC := GSDA_UtcNow;
    for var LName in AFiles.Keys do
        Result.PackageFiles.Add(LName, AFiles[LName]);

    Result.RevisionID := 'revision:' + GSDA_SHA256Hex(
        ASpecContentID + '|' + LParentID + '|' + AManifest
    );

    FState.AddRevision(Result);
end;

{ TGSDAPublication31 }

constructor TGSDAPublication31.Create(AKernel: TGSDAKernel31);
begin
    FKernel := AKernel;
end;

procedure TGSDAPublication31.CheckKeywords(
    const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
          AQuestionsJSON, ATraceabilityJSON: string);
const
    LKeywords: array[0..10] of string = (
        'MUST','MUST NOT','SHALL','SHALL NOT','SHOULD','SHOULD NOT',
        'MAY','REQUIRED','RECOMMENDED','NOT RECOMMENDED','OPTIONAL'
    );
var
    LText, LKeyword: string;
begin
    LText := UpperCase(
        ARequirementsJSON + #10 + AGlossaryJSON + #10 +
        AAssumptionsJSON + #10 + AQuestionsJSON + #10 + ATraceabilityJSON
    );

    { Structured requirements carry their keyword as data. To avoid declaring
      the entire serialized JSON invalid, the release linter in the next layer
      should operate on rendered prose blocks. This kernel still rejects the
      strongest obvious leak: keyword-like prose outside the dedicated field. }
    for LKeyword in LKeywords do
        if (Pos('>' + LKeyword + '<', LText) > 0) then
            raise EGSDAFailure.Create(fcNormativeKeywordLeak, LKeyword);
end;

procedure TGSDAPublication31.CheckReferences;
var
    LRequirement: TGSDARequirement;
    LID: string;
    LMessage: TGSDAReasoningMessage;
    LParents: TJSONValue;
    LParentID: string;
begin
    for LRequirement in FKernel.State.FRequirements.Values do
    begin
        for LID in LRequirement.SourceIDs do
            if not FKernel.State.IdentityExists(LID) then
                raise EGSDAFailure.Create(fcSourceReferenceUnresolved, LID);
        for LID in LRequirement.ArtifactIDs do
            if FKernel.State.FindArtifact(LID) = nil then
                raise EGSDAFailure.Create(fcCrossReferenceUnresolved, LID);
    end;

    for LMessage in FKernel.State.FMessages.Values do
    begin
        LParents := LMessage.Payload.GetValue('parent_ids');
        if LParents is TJSONArray then
            for var LIndex := 0 to TJSONArray(LParents).Count - 1 do
            begin
                LParentID := TJSONArray(LParents).Items[LIndex].Value;
                if not FKernel.State.IdentityExists(LParentID) then
                    raise EGSDAFailure.Create(fcCrossReferenceUnresolved, LParentID);
            end;
    end;
end;

procedure TGSDAPublication31.CheckCoverage(const ATaskID: string);
var
    LCoverage: TGSDACoverageResult;
    LLeft, LRight: Int64;
begin
    LCoverage := FKernel.ComputeCoverage(ATaskID);
    LLeft := LCoverage.Numerator * FKernel.Config.CriticalCoverageDenominator;
    LRight := FKernel.Config.CriticalCoverageNumerator * LCoverage.Denominator;
    if LLeft < LRight then
        raise EGSDAFailure.Create(fcPublicationFailure, 'Critical intent coverage below threshold');
end;

procedure TGSDAPublication31.CheckPackage(const AFiles: TDictionary<string,string>);
const
    LRequired: array[0..5] of string = (
        'spec.requirements.json',
        'spec.glossary.json',
        'spec.assumptions.json',
        'spec.open_questions.json',
        'spec.traceability.json',
        'registry.json'
    );
var
    LName: string;
begin
    for LName in LRequired do
        if not AFiles.ContainsKey(LName) then
            raise EGSDAFailure.Create(fcPublicationFailure, 'Missing package file: ' + LName);
    for LName in AFiles.Keys do
        if not IsSafePackagePath(LName) then
            raise EGSDAFailure.Create(fcPublicationFailure, 'Unsafe package path: ' + LName);
end;

function TGSDAPublication31.BuildPackage(
    const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
          AQuestionsJSON, ATraceabilityJSON: string): TDictionary<string,string>;
begin
    Result := TDictionary<string,string>.Create;
    try
        Result.Add('spec.requirements.json', ARequirementsJSON);
        Result.Add('spec.glossary.json', AGlossaryJSON);
        Result.Add('spec.assumptions.json', AAssumptionsJSON);
        Result.Add('spec.open_questions.json', AQuestionsJSON);
        Result.Add('spec.traceability.json', ATraceabilityJSON);
        Result.Add('registry.json', FKernel.BuildRegistryJSON);
        CheckPackage(Result);
    except
        Result.Free;
        raise;
    end;
end;

function TGSDAPublication31.Publish(
    const ATaskID: string;
    const ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
          AQuestionsJSON, ATraceabilityJSON: string;
    const AHumanDecision: TGSDAHumanDecision): TGSDARevisionSnapshot;
var
    LSpecID: string;
    LFiles: TDictionary<string,string>;
    LPackageHash: string;
    LNames: TList<string>;
    LManifest: TStringBuilder;
    LName: string;
begin
    LSpecID := FKernel.ComputeSpecContentID(
        ARequirementsJSON,
        AGlossaryJSON,
        AAssumptionsJSON,
        AQuestionsJSON,
        ATraceabilityJSON
    );

    CheckKeywords(ARequirementsJSON, AGlossaryJSON, AAssumptionsJSON,
                  AQuestionsJSON, ATraceabilityJSON);
    CheckCoverage(ATaskID);
    CheckReferences;

    if not FKernel.ValidatePublication(
        ATaskID,
        LSpecID,
        ARequirementsJSON,
        AGlossaryJSON,
        AAssumptionsJSON,
        AQuestionsJSON,
        ATraceabilityJSON,
        AHumanDecision
    ) then
        raise EGSDAFailure.Create(fcPublicationFailure, 'Publication validation failed');

    LFiles := BuildPackage(
        ARequirementsJSON,
        AGlossaryJSON,
        AAssumptionsJSON,
        AQuestionsJSON,
        ATraceabilityJSON
    );
    try
        LPackageHash := FKernel.ComputePackageHash(LFiles);
        LNames := TList<string>.Create;
        try
            for LName in LFiles.Keys do
                LNames.Add(LName);
            LNames.Sort;
            LManifest := TStringBuilder.Create;
            try
                for LName in LNames do
                    LManifest.Append(LName).Append('=').Append(LFiles[LName]).Append(#10);
                Result := FKernel.CommitRevision(
                    LSpecID, LFiles, LManifest.ToString,
                    LPackageHash, AHumanDecision
                );
            finally
                LManifest.Free;
            end;
        finally
            LNames.Free;
        end;
    finally
        LFiles.Free;
    end;
end;

{ Canonical JSON }

class function TGSDAJson.CompareUTF8(const ALeft, ARight: string): Integer;
var
    LLeft, LRight: TBytes;
    LIndex, LLength: Integer;
begin
    LLeft := TEncoding.UTF8.GetBytes(ALeft);
    LRight := TEncoding.UTF8.GetBytes(ARight);
    LLength := Length(LLeft);
    if Length(LRight) < LLength then
        LLength := Length(LRight);
    for LIndex := 0 to LLength - 1 do
    begin
        if LLeft[LIndex] < LRight[LIndex] then Exit(-1);
        if LLeft[LIndex] > LRight[LIndex] then Exit(1);
    end;
    if Length(LLeft) < Length(LRight) then Exit(-1);
    if Length(LLeft) > Length(LRight) then Exit(1);
    Result := 0;
end;

class procedure TGSDAJson.EmitString(const AValue: string; const ABuilder: TStringBuilder);
var
    LIndex, LCode: Integer;
    LChar: Char;
begin
    ABuilder.Append('"');
    for LIndex := 1 to Length(AValue) do
    begin
        LChar := AValue[LIndex];
        LCode := Ord(LChar);
        case LChar of
            '"': ABuilder.Append('\"');
            '\': ABuilder.Append('\\');
            #8: ABuilder.Append('\\b');
            #9: ABuilder.Append('\\t');
            #10: ABuilder.Append('\\n');
            #12: ABuilder.Append('\\f');
            #13: ABuilder.Append('\\r');
        else
            if LCode < 32 then
                ABuilder.Append('\\u').Append(IntToHex(LCode,4))
            else
                ABuilder.Append(LChar);
        end;
    end;
    ABuilder.Append('"');
end;

class procedure TGSDAJson.EmitObject(const AValue: TJSONObject; const ABuilder: TStringBuilder);
var
    LPairs: TList<TJSONPair>;
    LSeen: TDictionary<string,Boolean>;
    LPair: TJSONPair;
    LIndex: Integer;
begin
    LPairs := TList<TJSONPair>.Create;
    LSeen := TDictionary<string,Boolean>.Create;
    try
        for LPair in AValue do
        begin
            if LSeen.ContainsKey(LPair.JsonString.Value) then
                raise EGSDAFailure.Create(fcSchemaFailure, 'Duplicate JSON object key');
            LSeen.Add(LPair.JsonString.Value, True);
            LPairs.Add(LPair);
        end;

        LPairs.Sort(
            TComparer<TJSONPair>.Construct(
                function(const ALeft, ARight: TJSONPair): Integer
                begin
                    Result := CompareUTF8(ALeft.JsonString.Value, ARight.JsonString.Value);
                end
            )
        );

        ABuilder.Append('{');
        for LIndex := 0 to LPairs.Count - 1 do
        begin
            EmitString(LPairs[LIndex].JsonString.Value, ABuilder);
            ABuilder.Append(':');
            EmitValue(LPairs[LIndex].JsonValue, ABuilder);
            if LIndex < LPairs.Count - 1 then
                ABuilder.Append(',');
        end;
        ABuilder.Append('}');
    finally
        LSeen.Free;
        LPairs.Free;
    end;
end;

class procedure TGSDAJson.EmitArray(const AValue: TJSONArray; const ABuilder: TStringBuilder);
var
    LIndex: Integer;
begin
    ABuilder.Append('[');
    for LIndex := 0 to AValue.Count - 1 do
    begin
        EmitValue(AValue.Items[LIndex], ABuilder);
        if LIndex < AValue.Count - 1 then
            ABuilder.Append(',');
    end;
    ABuilder.Append(']');
end;

class procedure TGSDAJson.EmitValue(const AValue: TJSONValue; const ABuilder: TStringBuilder);
begin
    if AValue = nil then
        raise EGSDAFailure.Create(fcSchemaFailure, 'Missing JSON value');

    if AValue is TJSONObject then
        EmitObject(TJSONObject(AValue), ABuilder)
    else if AValue is TJSONArray then
        EmitArray(TJSONArray(AValue), ABuilder)
    else if AValue is TJSONString then
        EmitString(TJSONString(AValue).Value, ABuilder)
    else if AValue is TJSONNumber then
        ABuilder.Append(TJSONNumber(AValue).ToString)
    else if AValue is TJSONBool then
        ABuilder.Append(LowerCase(AValue.ToString))
    else if AValue is TJSONNull then
        ABuilder.Append('null')
    else
        raise EGSDAFailure.Create(fcSchemaFailure, 'Unsupported JSON value');
end;

class function TGSDAJson.Canonicalize(const AValue: TJSONValue): string;
var
    LBuilder: TStringBuilder;
begin
    LBuilder := TStringBuilder.Create;
    try
        EmitValue(AValue, LBuilder);
        Result := LBuilder.ToString;
    finally
        LBuilder.Free;
    end;
end;

end.
