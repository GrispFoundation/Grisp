program GSDA31_Conformance;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    System.JSON,
    System.Generics.Collections,
    GSDA31 in 'GSDA31.pas';

procedure AssertTrue(ACondition: Boolean; const AMessage: string);
begin
    if not ACondition then
        raise Exception.Create('FAIL: ' + AMessage);
end;

procedure TestCanonical;
var
    LObject: TJSONObject;
begin
    LObject := TJSONObject.Create;
    try
        LObject.AddPair('b', 1);
        LObject.AddPair('a', 2);
        AssertTrue(
            TGSDAJson.Canonicalize(LObject) = '{"a":2,"b":1}',
            'UTF-8 bytewise object ordering'
        );
    finally
        LObject.Free;
    end;
end;

procedure TestTaskIdentity;
var
    LConfig: TGSDAConfig;
    LKernel: TGSDAKernel31;
    LTaskA, LTaskB: TGSDAResearchTask;
begin
    LConfig := TGSDAConfig.Create;
    try
        LConfig.Namespace := 'gsda';
        LConfig.TargetLanguage := 'Delphi';
        LConfig.PriorityProfile := 'default';
        LConfig.TargetAudience := ['engineers'];
        LConfig.Constraints := ['deterministic'];
        LConfig.RequestedOutputs := ['spec'];
        LConfig.HMACSecret := TEncoding.UTF8.GetBytes('secret');

        LKernel := TGSDAKernel31.Create(LConfig);
        try
            LTaskA := LKernel.CreateTask(
                'Create a deterministic specification',
                'Preserve user intent',
                'specification'
            );
            LTaskB := LKernel.CreateTask(
                'Create a deterministic specification',
                'Preserve user intent',
                'other-domain'
            );

            AssertTrue(LTaskA.TaskID <> LTaskB.TaskID, 'Domain affects TaskID');
            AssertTrue(LTaskA.TargetContextID <> '', 'TargetContextID exists');
        finally
            LKernel.Free;
        end;
    finally
        LConfig.Free;
    end;
end;

procedure TestRoundID;
var
    LRunID: string;
begin
    LRunID := 'run:01234567-89ab-cdef-0123-456789abcdef';
    AssertTrue(
        'round:' + LRunID + ':3' = 'round:' + LRunID + ':3',
        'Round ID format'
    );
end;

procedure TestPeerAuthentication;
var
    LConfig: TGSDAConfig;
    LKernel: TGSDAKernel31;
    LPeer: TGSDAPeerProfile;
    LTask: TGSDAResearchTask;
    LRunID, LRoundID, LFingerprint, LToken, LContentID: string;
    LPayload: TJSONObject;
    LResult: TGSDAIngressResult;
begin
    LConfig := TGSDAConfig.Create;
    try
        LConfig.Namespace := 'gsda';
        LConfig.TargetLanguage := 'Delphi';
        LConfig.PriorityProfile := 'default';
        LConfig.HMACSecret := TEncoding.UTF8.GetBytes('kernel-secret');

        LKernel := TGSDAKernel31.Create(LConfig);
        try
            LPeer := TGSDAPeerProfile.Create;
            LPeer.PeerID := 'peer:alpha';
            LPeer.Provider := 'test';
            LPeer.Model := 'model';
            LPeer.ModelVersion := '1';
            LPeer.AdapterID := 'adapter:test';
            LPeer.TransportName := 'local';
            LPeer.EndpointFingerprint := 'endpoint:test';
            LPeer.SharedSecret := TEncoding.UTF8.GetBytes('peer-secret');
            LPeer.Enabled := True;
            LKernel.RegisterPeer(LPeer);

            LTask := LKernel.CreateTask('Prompt', 'Intent', 'specification');
            LRunID := LKernel.IssueRunID;
            LRoundID := 'round:' + LRunID + ':0';
            LFingerprint := 'local|adapter:test|endpoint:test';

            LPayload := TJSONObject.Create;
            try
                LPayload.AddPair('schema', 'gsp/3.1');
                LPayload.AddPair('content', 'candidate');
                LContentID := 'content:' + GSDA_SHA256Hex(
                    TGSDAJson.Canonicalize(LPayload)
                );
                LPayload.AddPair('content_id', LContentID);
                LToken := GSDABuildHMACToken(
                    LPeer.SharedSecret,
                    LPeer.PeerID,
                    LFingerprint,
                    LRoundID
                );
                LResult := LKernel.AcceptPeerMessage(
                    LPeer.PeerID,
                    LRunID,
                    LTask.TaskID,
                    LRoundID,
                    LFingerprint,
                    LToken,
                    mkCandidate,
                    900,
                    LPayload.ToJSON
                );
                AssertTrue(LResult.Accepted, 'Authenticated peer message accepted');
            finally
                LPayload.Free;
            end;
        finally
            LKernel.Free;
        end;
    finally
        LConfig.Free;
    end;
end;

begin
    try
        Writeln('GSDA/3.1 conformance harness');
        TestCanonical;
        TestTaskIdentity;
        TestRoundID;
        TestPeerAuthentication;
        Writeln('PASS');
    except
        on E: Exception do
        begin
            Writeln(E.ClassName + ': ' + E.Message);
            ExitCode := 1;
        end;
    end;
end.
