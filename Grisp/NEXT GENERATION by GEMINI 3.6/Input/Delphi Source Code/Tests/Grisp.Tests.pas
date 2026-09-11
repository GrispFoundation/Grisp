unit Grisp.Tests;

interface

uses
  System.SysUtils, System.Classes,
  Grisp.Types, Grisp.Canonical, Grisp.Parser, 
  Grisp.MockCompiler, Grisp.MockTestRunner, Grisp.StateMachine, Grisp.GARP;

type
  /// <summary>
  /// Standalone test runner for verifying GRISP v1.0 fail-closed invariant guarantees.
  /// </summary>
  TGrispTests = class
  private
    class procedure Assert(ACondition: Boolean; const ATestName, AMessage: string); static;
    class procedure TestCanonicalHashing; static;
    class procedure TestParserSingleBlock; static;
    class procedure TestParserAmbiguousBlocks; static;
    class procedure TestMockCompilerFailure; static;
    class procedure TestFullStateMachinePipeline; static;
    class procedure TestGarpBinaryFraming; static;
  public
    class procedure RunAllTests; static;
  end;

implementation

class procedure TGrispTests.Assert(ACondition: Boolean; const ATestName, AMessage: string);
begin
  if not ACondition then
    raise Exception.CreateFmt('[TEST FAILURE] %s: %s', [ATestName, AMessage]);
  Writeln(Format('[PASS] %s', [ATestName]));
end;

class procedure TGrispTests.TestCanonicalHashing;
var
  InputText: string;
  Bytes: TBytes;
  Hash1, Hash2: string;
begin
  InputText := 'unit TestUnit; interface implementation end.';
  Bytes := TGrispCanonical.ToUTF8Bytes(InputText);
  
  Hash1 := TGrispCanonical.ComputeSHA256(Bytes);
  Hash2 := TGrispCanonical.ComputeSHA256(InputText);

  Assert(SameText(Hash1, Hash2), 'CanonicalHashing', 'Byte hash and text hash mismatch');
  Assert(Length(Hash1) = 64, 'CanonicalHashing', 'SHA-256 string length must be 64 characters');
end;

class procedure TGrispTests.TestParserSingleBlock;
var
  Payload: string;
  SessionID, TabID: TGuid;
  Candidate: TGrispCandidate;
  Success: Boolean;
begin
  CreateGUID(SessionID);
  CreateGUID(TabID);
  Payload := 'Here is code:' + #10 + '```pascal' + #10 + 'WriteLn("Hello");' + #10 + '```';

  Success := TGrispParser.ParseResponse(Payload, SessionID, TabID, Candidate);

  Assert(Success, 'ParserSingleBlock', 'Valid single block parsing failed');
  Assert(Candidate.State = csParsed, 'ParserSingleBlock', 'Candidate state must be csParsed');
  Assert(Length(Candidate.Manifest.RawBytes) > 0, 'ParserSingleBlock', 'Manifest payload empty');
end;

class procedure TGrispTests.TestParserAmbiguousBlocks;
var
  Payload: string;
  SessionID, TabID: TGuid;
  Candidate: TGrispCandidate;
  Success: Boolean;
begin
  CreateGUID(SessionID);
  CreateGUID(TabID);
  // Two blocks present -> Ambiguous -> Must fail closed
  Payload := 'Block 1:' + #10 + '```pascal' + #10 + 'x := 1;' + #10 + '```' + #10 +
             'Block 2:' + #10 + '```pascal' + #10 + 'y := 2;' + #10 + '```';

  Success := TGrispParser.ParseResponse(Payload, SessionID, TabID, Candidate);

  Assert(not Success, 'ParserAmbiguousBlocks', 'Parser allowed ambiguous multiple code blocks');
  Assert(Candidate.State = csRejected, 'ParserAmbiguousBlocks', 'State must be csRejected');
  Assert(Candidate.LastError = errParseAmbiguous, 'ParserAmbiguousBlocks', 'Error code must be errParseAmbiguous');
end;

class procedure TGrispTests.TestMockCompilerFailure;
var
  Compiler: TGrispMockCompiler;
  Candidate: TGrispCandidate;
  Code: string;
begin
  Compiler := TGrispMockCompiler.Create;
  try
    Code := '```pascal' + #10 + 'unit BadCode; [SYNTAX_ERROR]' + #10 + '```';
    TGrispParser.ParseResponse(Code, TGUID.Empty, TGUID.Empty, Candidate);

    Assert(not Compiler.Compile(Candidate), 'MockCompilerFailure', 'Compiler should reject code containing [SYNTAX_ERROR]');
    Assert(Candidate.State = csRejected, 'MockCompilerFailure', 'Candidate must be rejected after compile failure');
    Assert(Length(Candidate.EvidenceLog) = 1, 'MockCompilerFailure', 'Evidence log must record compile attempt');
    Assert(not Candidate.EvidenceLog[0].Success, 'MockCompilerFailure', 'Log entry must mark failure');
  finally
    Compiler.Free;
  end;
end;

class procedure TGrispTests.TestFullStateMachinePipeline;
var
  StateMachine: TGrispStateMachine;
  Candidate: TGrispCandidate;
  SessionID, TabID: TGuid;
  Payload: string;
  Success: Boolean;
begin
  CreateGUID(SessionID);
  CreateGUID(TabID);
  StateMachine := TGrispStateMachine.Create;
  try
    Payload := 'Valid output:' + #10 + '```pascal' + #10 + 'unit Valid;' + #10 + '```';

    Success := StateMachine.ProcessResponse(Payload, SessionID, TabID, Candidate);
    Assert(Success, 'StateMachinePipeline', 'ProcessResponse failed on valid candidate');
    Assert(Candidate.State = csVerified, 'StateMachinePipeline', 'Candidate must reach csVerified state');

    Success := StateMachine.AcceptCandidate(Candidate);
    Assert(Success, 'StateMachinePipeline', 'AcceptCandidate failed on verified candidate');
    Assert(Candidate.State = csAccepted, 'StateMachinePipeline', 'Final state must be csAccepted');
    Assert(Length(Candidate.EvidenceLog) >= 3, 'StateMachinePipeline', 'Full pipeline evidence trace missing');
  finally
    StateMachine.Free;
  end;
end;

class procedure TGrispTests.TestGarpBinaryFraming;
var
  SourceData, FramedData: TBytes;
  Stream: TMemoryStream;
  Packet: TGarpPacket;
  Success: Boolean;
begin
  SourceData := TGrispCanonical.ToUTF8Bytes('GARP binary test payload');
  FramedData := TGarpTransport.FramePayload(SourceData);

  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(FramedData[0], Length(FramedData));
    Stream.Position := 0;

    Success := TGarpTransport.TryUnframePacket(Stream, Packet);

    Assert(Success, 'GarpBinaryFraming', 'Unframing GARP packet failed');
    Assert(Packet.PayloadLength = UInt32(Length(SourceData)), 'GarpBinaryFraming', 'Unframed length mismatch');
    Assert(TGrispCanonical.ComputeSHA256(Packet.Payload) = TGrispCanonical.ComputeSHA256(SourceData),
      'GarpBinaryFraming', 'Payload bytes corrupted during framing cycle');
  finally
    Stream.Free;
  end;
end;

class procedure TGrispTests.RunAllTests;
begin
  Writeln('=== Running GRISP v1.0 Test Suite ===');
  TestCanonicalHashing;
  TestParserSingleBlock;
  TestParserAmbiguousBlocks;
  TestMockCompilerFailure;
  TestFullStateMachinePipeline;
  TestGarpBinaryFraming;
  Writeln('=== All Tests Passed Successfully ===');
end;

end.