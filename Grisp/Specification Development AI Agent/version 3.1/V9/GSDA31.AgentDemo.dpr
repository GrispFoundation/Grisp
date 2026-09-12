program GSDA31.AgentDemo;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    System.JSON,
    GSDA31,
    GSDA31.Agent,
    GSDA31.Gateway;

function BuildConfig: TGSDAConfig;
begin
    Result := TGSDAConfig.Create;
    Result.Namespace := 'gsda';
    Result.TargetLanguage := 'Delphi';
    Result.PriorityProfile := 'default';
    Result.TargetAudience := ['engineers'];
    Result.Constraints := ['deterministic', 'traceable'];
    Result.RequestedOutputs := ['specification'];
    Result.MaxRounds := 8;
    Result.MaxMessagesPerRound := 16;
    Result.MaxRepairDepth := 8;
    Result.CriticalCoverageNumerator := 1;
    Result.CriticalCoverageDenominator := 1;
    Result.HMACSecret := TEncoding.UTF8.GetBytes('development-secret');
end;

procedure RunDemo;
var
    LConfig: TGSDAConfig;
    LKernel: TGSDAKernel31;
    LAgent: TGSDASpecAgent31;
    LGateway: TGSDACommandGateway31;
    LTask: TGSDAResearchTask;
    LRunID: string;
    LProfile: TGSDAPeerProfile;
    LFingerprint: string;
    LToken: string;
    LPayload: string;
    LCommand: TJSONObject;
    LResponse: TJSONObject;
    LSpecID: string;
    LInput: TGSDAPeerInput;
    LRound: TGSDARoundResult;
begin
    LConfig := BuildConfig;
    try
        LKernel := TGSDAKernel31.Create(LConfig);
        try
            LProfile := TGSDAPeerProfile.Create;
            LProfile.PeerID := 'peer:alpha';
            LProfile.Provider := 'firefox';
            LProfile.Model := 'development';
            LProfile.ModelVersion := '1';
            LProfile.AdapterID := 'adapter:firefox';
            LProfile.TransportName := 'local';
            LProfile.EndpointFingerprint := 'endpoint:test';
            LProfile.SharedSecret := TEncoding.UTF8.GetBytes('development-secret');
            LProfile.Enabled := True;
            LKernel.RegisterPeer(LProfile);

            LAgent := TGSDASpecAgent31.Create(LKernel);
            try
                LGateway := TGSDACommandGateway31.Create(LAgent);
                try
                    LTask := LAgent.CreateTask(
                        'Develop a deterministic specification for a Firefox automation AI agent.',
                        'Preserve deterministic governance while allowing Firefox-mediated peer reasoning. [CRITICAL]',
                        'specification-development'
                    );

                    LRunID := LAgent.StartRun(LTask.TaskID);
                    Writeln('Task: ', LTask.TaskID);
                    Writeln('Run : ', LRunID);

                    LFingerprint :=
                        LProfile.TransportName + '|' +
                        LProfile.AdapterID + '|' +
                        LProfile.EndpointFingerprint;
                    LToken := GSDABuildHMACToken(
                        LProfile.SharedSecret,
                        LProfile.PeerID,
                        LFingerprint,
                        'round:' + LRunID + ':0'
                    );

                    LPayload :=
                        '{' +
                        '"schema":"gsp/3.1",' +
                        '"content":"Create a deterministic Firefox automation specification.",' +
                        '"content_id":"' +
                        'content:' +
                        GSDA_SHA256Hex('{"content":"Create a deterministic Firefox automation specification.","schema":"gsp/3.1"}') +
                        '"' +
                        '}';

                    LCommand := TJSONObject.Create;
                    try
                        LCommand.AddPair('command', 'peer_message');
                        LCommand.AddPair('run_id', LRunID);
                        LCommand.AddPair('peer_id', LProfile.PeerID);
                        LCommand.AddPair('fingerprint', LFingerprint);
                        LCommand.AddPair('token', LToken);
                        LCommand.AddPair('kind', TJSONNumber.Create(Ord(mkCandidate)));
                        LCommand.AddPair('confidence', TJSONNumber.Create(900));
                        LCommand.AddPair('payload', LPayload);
                        LResponse := LGateway.Execute(LCommand);
                        try
                            Writeln(LResponse.ToJSON);
                        finally
                            LResponse.Free;
                        end;
                    finally
                        LCommand.Free;
                    end;

                    { peer_message is ingress only. Execute the round to
                      deterministically select the candidate and materialize
                      the candidate artifact required by FreezeCandidate. }
                    LInput.PeerID := LProfile.PeerID;
                    LInput.Fingerprint := LFingerprint;
                    LInput.Token := LToken;
                    LInput.Kind := mkCandidate;
                    LInput.Confidence := 900;
                    LInput.Payload := LPayload;

                    LRound := LAgent.ExecuteRound(LRunID, [LInput]);
                    Writeln('Round: ', LRound.RoundIndex);
                    Writeln('Candidate: ', LRound.CandidateArtifactID);
                    Writeln('Winner  : ', LRound.WinningPeerID);

                    LSpecID := LAgent.FreezeCandidate(LRunID);
                    Writeln('Frozen SpecContentID: ', LSpecID);
                finally
                    LGateway.Free;
                end;
            finally
                LAgent.Free;
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
        RunDemo;
    except
        on E: Exception do
        begin
            Writeln(E.ClassName, ': ', E.Message);
            ExitCode := 1;
        end;
    end;
end.
