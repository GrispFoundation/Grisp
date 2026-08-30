unit TestGrispCore;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  GrispCapabilities, GrispVfs, GrispGraph, GrispCore;

type
  TTestGrispCoreRunner = class
  private
    FPassed: Integer;
    FFailed: Integer;
    procedure AssertTrue(Condition: Boolean; const Msg: string);
    procedure AssertEquals(const Expected, Actual, Msg: string);
  public
    constructor Create;
    procedure RunAllTests;

    procedure TestPathNormalization;
    procedure TestCapabilityEnforcement;
    procedure TestVfsFileOperations;
    procedure TestGraphTransitions;
    procedure TestParserAndExecution;

    property Passed: Integer read FPassed;
    property Failed: Integer read FFailed;
  end;

implementation

constructor TTestGrispCoreRunner.Create;
begin
  inherited Create;
  FPassed := 0;
  FFailed := 0;
end;

procedure TTestGrispCoreRunner.AssertTrue(Condition: Boolean; const Msg: string);
begin
  if Condition then
  begin
    Inc(FPassed);
    Writeln('  [PASS] ' + Msg);
  end
  else
  begin
    Inc(FFailed);
    Writeln('  [FAIL] ' + Msg);
  end;
end;

procedure TTestGrispCoreRunner.AssertEquals(const Expected, Actual, Msg: string);
begin
  if Expected = Actual then
  begin
    Inc(FPassed);
    Writeln('  [PASS] ' + Msg);
  end
  else
  begin
    Inc(FFailed);
    Writeln(Format('  [FAIL] %s - Expected: "%s", Actual: "%s"', [Msg, Expected, Actual]));
  end;
end;

procedure TTestGrispCoreRunner.TestPathNormalization;
begin
  Writeln('--- TestPathNormalization ---');
  AssertEquals('/workspace/test.txt', TGrispVfs.NormalizePath('/workspace/test.txt'), 'Standard POSIX path');
  AssertEquals('/workspace/test.txt', TGrispVfs.NormalizePath('C:\workspace\test.txt'), 'Strip Windows drive C:');
  AssertEquals('/workspace/test.txt', TGrispVfs.NormalizePath('G:\workspace\test.txt'), 'Strip Windows drive G:');
  AssertEquals('/workspace/test.txt', TGrispVfs.NormalizePath('/workspace/sub/../test.txt'), 'Resolve parent ..');
  AssertEquals('/secret.txt', TGrispVfs.NormalizePath('/workspace/../../secret.txt'), 'Prevent escape past root /');
  AssertEquals('/workspace/file.c', TGrispVfs.NormalizePath('workspace//file.c'), 'Double slashes collapsed');
  AssertEquals('/workspace/file.c', TGrispVfs.NormalizePath('./workspace/./file.c'), 'Current dir . removed');
end;

procedure TTestGrispCoreRunner.TestCapabilityEnforcement;
var
  Cap: IGrispCapability;
  Reason: string;
begin
  Writeln('--- TestCapabilityEnforcement ---');
  Cap := TGrispCapability.Create('write-workspace', '/workspace', [grRead, grWrite, grList], ['text/plain', 'text/x-c'], 1024);

  AssertTrue(Cap.AllowsOp(grRead), 'Cap allows read');
  AssertTrue(Cap.AllowsOp(grWrite), 'Cap allows write');
  AssertTrue(not Cap.AllowsOp(grDelete), 'Cap denies delete');

  AssertTrue(Cap.IsPathAllowed('/workspace/test.txt'), 'Path inside /workspace allowed');
  AssertTrue(not Cap.IsPathAllowed('/sandbox/test.txt'), 'Path in /sandbox denied');
  AssertTrue(not Cap.IsPathAllowed('/etc/passwd'), 'Path in /etc denied');

  AssertTrue(Cap.ValidateWrite('/workspace/code.c', 'text/x-c', 500, Reason), 'Write within limits allowed');
  AssertTrue(not Cap.ValidateWrite('/workspace/code.c', 'application/x-executable', 500, Reason), 'Binary MIME denied');
  AssertTrue(not Cap.ValidateWrite('/workspace/code.c', 'text/x-c', 5000, Reason), 'Size exceeding 1024 bytes denied');
end;

procedure TTestGrispCoreRunner.TestVfsFileOperations;
var
  Vfs: TGrispVfs;
  Cap: IGrispCapability;
  Content, Reason: string;
  Files: TArray<string>;
begin
  Writeln('--- TestVfsFileOperations ---');
  Vfs := TGrispVfs.Create('', False); // in-memory
  try
    Cap := TGrispCapability.Create('workspace-cap', '/workspace', [grRead, grWrite, grList, grDelete], ['text/plain'], 10000);

    AssertTrue(Vfs.WriteFile('/workspace/hello.txt', 'Hello GRISP', 'text/plain', Cap, Reason), 'VFS write file');
    AssertTrue(Vfs.FileExists('/workspace/hello.txt'), 'VFS file exists');

    AssertTrue(Vfs.ReadFile('/workspace/hello.txt', Cap, Content, Reason), 'VFS read file');
    AssertEquals('Hello GRISP', Content, 'VFS read content matches');

    AssertTrue(Vfs.ListFiles('/workspace', Cap, Files, Reason), 'VFS list files');
    AssertTrue(Length(Files) = 1, 'VFS list count matches');

    AssertTrue(Vfs.DeleteFile('/workspace/hello.txt', Cap, Reason), 'VFS delete file');
    AssertTrue(not Vfs.FileExists('/workspace/hello.txt'), 'VFS file removed');
  finally
    Vfs.Free;
  end;
end;

procedure TTestGrispCoreRunner.TestGraphTransitions;
var
  Graph: TGrispGraph;
  Node1, Node2: TGrispNode;
  Edge: TGrispEdge;
  Fields: TDictionary<string, TGrispValue>;
begin
  Writeln('--- TestGraphTransitions ---');
  Graph := TGrispGraph.Create;
  try
    Fields := TDictionary<string, TGrispValue>.Create;
    try
      Fields.Add('name', TGrispValue.MakeString('Alice'));
      Fields.Add('age', TGrispValue.MakeInt(30));
      Node1 := Graph.CreateNode('Person', Fields);
    finally
      Fields.Free;
    end;

    AssertTrue(Node1.Id = 'Person:1', 'Node 1 ID allocated as Person:1');
    AssertTrue(Graph.NodeCount = 1, 'Graph node count is 1');

    Node2 := Graph.CreateNode('Person');
    AssertTrue(Node2.Id = 'Person:2', 'Node 2 ID allocated as Person:2');

    Edge := Graph.CreateEdge('Knows', Node1.Id, Node2.Id);
    AssertTrue(Edge.Id = 'Knows:1', 'Edge ID allocated as Knows:1');
    AssertTrue(Graph.EdgeCount = 1, 'Graph edge count is 1');

    Graph.UpdateNodeField(Node1.Id, 'age', TGrispValue.MakeInt(31));
    AssertTrue(Node1.ElementVersion = 2, 'Node element version incremented on update');

    Graph.DeleteNode(Node1.Id);
    AssertTrue(Graph.NodeCount = 1, 'Graph node count after delete is 1');
    AssertTrue(Graph.EdgeCount = 0, 'Incident edges automatically deleted');
  finally
    Graph.Free;
  end;
end;

procedure TTestGrispCoreRunner.TestParserAndExecution;
var
  Parser: TGrispParser;
  Rules: TArray<TGrispRule>;
  Graph: TGrispGraph;
  Vfs: TGrispVfs;
  CapSet: TGrispCapabilitySet;
  Cap: IGrispCapability;
  Engine: TGrispEngine;
  Reason: string;
  CodeText: string;
begin
  Writeln('--- TestParserAndExecution ---');
  CodeText :=
    'rules begin'#13#10 +
    '  rule "init-user" priority 100 begin'#13#10 +
    '    match begin'#13#10 +
    '      Person: PersonType;'#13#10 +
    '    end'#13#10 +
    '    actions begin'#13#10 +
    '      CreateNode(u, UserType) with { name: "Bob"; role: "Admin"; };'#13#10 +
    '      EmitEvent("user_created", ["Bob", "Admin"]);'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    'end';

  Parser := TGrispParser.Create(CodeText);
  try
    Rules := Parser.Parse;
    AssertTrue(Length(Rules) = 1, 'Parsed 1 rule');
    AssertEquals('init-user', Rules[0].RuleId, 'Rule ID matches');
    AssertTrue(Length(Rules[0].Actions) = 2, 'Parsed 2 actions');
  finally
    Parser.Free;
  end;

  Graph := TGrispGraph.Create;
  Vfs := TGrispVfs.Create('', False);
  CapSet := TGrispCapabilitySet.Create;
  try
    Cap := TGrispCapability.Create('admin-cap', '/workspace', [grRead, grWrite, grList], ['text/plain'], 10000);
    CapSet.Add(Cap);

    Engine := TGrispEngine.Create(Graph, Vfs, CapSet);
    try
      AssertTrue(Engine.ExecutePlan(Rules, 'admin-cap', Reason), 'Engine executes parsed rule');
      AssertTrue(Graph.NodeCount = 1, 'Graph contains created node UserType:1');
      AssertTrue(Length(Engine.GetEvents) = 2, 'Emitted 2 events');
    finally
      Engine.Free;
    end;
  finally
    CapSet.Free;
    Vfs.Free;
    Graph.Free;
  end;
end;

procedure TTestGrispCoreRunner.RunAllTests;
begin
  Writeln('========================================');
  Writeln('   RUNNING GRISP CORE & VFS TESTS       ');
  Writeln('========================================');
  TestPathNormalization;
  TestCapabilityEnforcement;
  TestVfsFileOperations;
  TestGraphTransitions;
  TestParserAndExecution;
  Writeln('----------------------------------------');
  Writeln(Format('Core Tests Completed: %d Passed, %d Failed', [FPassed, FFailed]));
  Writeln('========================================');
end;

end.
