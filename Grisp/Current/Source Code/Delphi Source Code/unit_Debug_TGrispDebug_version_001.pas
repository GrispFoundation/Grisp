unit unit_Debug_TGrispDebug_version_001;

interface

uses
  System.SysUtils,
  System.TypInfo,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001,
  unit_Core_TGrispValueBase_version_001,
  unit_Graph_TGrispEdge_TGrispNode_version_001;

type
  TGrispDebug = class
  private
    class var FEnabled: Boolean;
    class var FIndentLevel: Integer;
    class procedure WriteIndent;
  public
    class procedure Enable;
    class procedure Disable;
    class function IsEnabled: Boolean;
    class procedure Log(const Msg: string);
    class procedure LogEnter(const MethodName: string);
    class procedure LogExit(const MethodName: string);
    class procedure LogToken(const Prefix: string; const Token: TGrispToken);
    class procedure LogValue(const Prefix: string; const Value: TGrispValue);
    class procedure LogNode(const Prefix: string; const Node: TGrispNode);
  end;

implementation

class procedure TGrispDebug.Enable;
begin
  FEnabled := True;
end;

class procedure TGrispDebug.Disable;
begin
  FEnabled := False;
end;

class function TGrispDebug.IsEnabled: Boolean;
begin
  Result := FEnabled;
end;

class procedure TGrispDebug.WriteIndent;
var
  i: Integer;
begin
  for i := 1 to FIndentLevel do
    Write('  ');
end;

class procedure TGrispDebug.Log(const Msg: string);
begin
  if not FEnabled then Exit;
  WriteIndent;
  Writeln(Msg);
end;

class procedure TGrispDebug.LogEnter(const MethodName: string);
begin
  if not FEnabled then Exit;
  WriteIndent;
  Writeln('-> Enter: ', MethodName);
  Inc(FIndentLevel);
end;

class procedure TGrispDebug.LogExit(const MethodName: string);
begin
  if not FEnabled then Exit;
  Dec(FIndentLevel);
  WriteIndent;
  Writeln('<- Exit: ', MethodName);
end;

class procedure TGrispDebug.LogToken(const Prefix: string; const Token: TGrispToken);
begin
  if not FEnabled then Exit;
  WriteIndent;
  Writeln(Format('%s Token: Kind=%s, Lexeme="%s", Line=%d, Col=%d',
    [Prefix, GetEnumName(TypeInfo(TGrispTokenKind), Ord(Token.Kind)),
     Token.Lexeme, Token.Line, Token.Column]));
end;

class procedure TGrispDebug.LogValue(const Prefix: string; const Value: TGrispValue);
begin
  if not FEnabled or (Value = nil) then Exit;
  WriteIndent;
  Writeln(Format('%s Value: Kind=%s, Value=%s',
    [Prefix, GetEnumName(TypeInfo(TGrispValueKind), Ord(Value.Kind)), Value.ToString]));
end;

class procedure TGrispDebug.LogNode(const Prefix: string; const Node: TGrispNode);
begin
  if not FEnabled or (Node = nil) then Exit;
  WriteIndent;
  Writeln(Format('%s Node: Id=%d, Name="%s", Type="%s"',
    [Prefix, Node.Id, Node.Name, Node.NodeType]));
end;

initialization
  TGrispDebug.FEnabled := False;
  TGrispDebug.FIndentLevel := 0;
end.
