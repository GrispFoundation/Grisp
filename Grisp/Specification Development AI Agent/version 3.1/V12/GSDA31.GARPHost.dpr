program GSDA31.GARPHost;

{$APPTYPE CONSOLE}

uses
    System.SysUtils,
    GSDA31,
    GSDA31.Agent,
    GSDA31.GARP;

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

procedure RunServer;
var
    LConfig: TGSDAConfig;
    LKernel: TGSDAKernel31;
    LAgent: TGSDASpecAgent31;
    LProfile: TGSDAPeerProfile;
    LServer: TGSDA31GARPServer;
    LLine: string;
begin
    LConfig := BuildConfig;
    try
        LKernel := TGSDAKernel31.Create(LConfig);
        try
            LProfile := TGSDAPeerProfile.Create;
            LProfile.PeerID := 'peer:alpha';
            LProfile.Provider := 'firefox';
            LProfile.Model := 'external-ui';
            LProfile.ModelVersion := '1';
            LProfile.AdapterID := 'adapter:firefox';
            LProfile.TransportName := 'local';
            LProfile.EndpointFingerprint := 'endpoint:firefox';
            LProfile.SharedSecret := TEncoding.UTF8.GetBytes('development-secret');
            LProfile.Enabled := True;
            LKernel.RegisterPeer(LProfile);

            LAgent := TGSDASpecAgent31.Create(LKernel);
            try
                LServer := TGSDA31GARPServer.Create(LAgent, 9911);
                try
                    LServer.Start;
                    Writeln('GSDA/3.1 GARP server listening on 127.0.0.1:', LServer.Port);
                    Writeln('Registered peer: ', LProfile.PeerID);
                    Writeln('Press ENTER to stop.');
                    Readln(LLine);
                    LServer.Stop;
                finally
                    LServer.Free;
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
        RunServer;
    except
        on E: Exception do
        begin
            Writeln(E.ClassName, ': ', E.Message);
            ExitCode := 1;
        end;
    end;
end.
