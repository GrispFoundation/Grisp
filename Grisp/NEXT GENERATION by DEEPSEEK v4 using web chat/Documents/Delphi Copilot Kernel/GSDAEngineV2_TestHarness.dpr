program GSDAEngineV2_TestHarness;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  GSDAEngineV2;

var
  Engine: TGSDAEngineV2;
  ResultObj: TGSDAEngineResultV2;

  Prompts: TArray<string>;

  RawMsgs: array of array of TArray<string>;
  PeerIDs: array of array of TArray<string>;
  MsgTypes: array of array of TArray<Integer>;
  Confidences: array of array of TArray<Integer>;

begin
  try
    Engine := TGSDAEngineV2.Create;

    // 1. Define tasks
    SetLength(Prompts, 1);
    Prompts[0] := 'Explain GSDA system behavior';

    // 2. Define rounds for the single task
    SetLength(RawMsgs, 1);
    SetLength(PeerIDs, 1);
    SetLength(MsgTypes, 1);
    SetLength(Confidences, 1);

    // Task 0 has 2 rounds
    SetLength(RawMsgs[0], 2);
    SetLength(PeerIDs[0], 2);
    SetLength(MsgTypes[0], 2);
    SetLength(Confidences[0], 2);

    // Round 0 messages
    RawMsgs[0][0] := [
      '{"schema":"gsp/1.0","content":"candidate A"}',
      '{"schema":"gsp/1.0","critique":"needs improvement"}'
    ];
    PeerIDs[0][0] := ['t1:peerA', 't2:peerB'];
    MsgTypes[0][0] := [0, 1]; // candidate, critique
    Confidences[0][0] := [900, 850];

    // Round 1 messages
    RawMsgs[0][1] := [
      '{"schema":"gsp/1.0","content":"candidate A improved"}',
      '{"schema":"gsp/1.0","repair":"fixed issue"}'
    ];
    PeerIDs[0][1] := ['t1:peerA', 't1:peerC'];
    MsgTypes[0][1] := [0, 2]; // candidate, repair
    Confidences[0][1] := [920, 880];

    // 3. Execute full GSDA system
    ResultObj := Engine.ExecuteSystem(
      Prompts,
      RawMsgs,
      PeerIDs,
      MsgTypes,
      Confidences
    );

    // 4. Print final system JSON
    Writeln('=== FINAL SYSTEM OUTPUT ===');
    Writeln(ResultObj.SystemJson.ToJSON);

  except
    on E: Exception do
      Writeln('ERROR: ', E.Message);
  end;

  Readln;
end.
