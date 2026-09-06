unit GrispCore;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  GrispCapabilities, GrispVfs, GrispGraph;

type
  TGrispTokenKind = (
    gtkEOF,
    gtkIdent,
    gtkString,
    gtkNumber,
    gtkLParen,
    gtkRParen,
    gtkLBrace,
    gtkRBrace,
    gtkLBracket,
    gtkRBracket,
    gtkComma,
    gtkColon,
    gtkSemicolon,
    gtkDot,
    gtkOp,
    gtkKeyword
  );

  TGrispToken = record
    Kind: TGrispTokenKind;
    Text: string;
    Line: Integer;
    Col: Integer;
  end;

  TGrispLexer = class
  private
    FText: string;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    function Peek: Char;
    function NextChar: Char;
    procedure SkipWhitespaceAndComments;
    function ReadIdentOrKeyword: TGrispToken;
    function ReadNumber: TGrispToken;
    function ReadString: TGrispToken;
  public
    constructor Create(const AText: string);
    function NextToken: TGrispToken;
  end;

  TGrispActionKind = (
    gakCreateNode,
    gakCreateEdge,
    gakUpdateField,
    gakDeleteNode,
    gakDeleteEdge,
    gakEmitEvent,
    gakQuery,
    gakFileWrite,
    gakFileRead
  );

  TGrispAction = record
    Kind: TGrispActionKind;
    TargetName: string;
    TargetType: string;
    Arg1: string;
    Arg2: string;
    Params: TArray<string>;
    FieldMap: TDictionary<string, string>;

    class function MakeCreateNode(const AName, AType: string; const AFields: TDictionary<string, string> = nil): TGrispAction; static;
    class function MakeUpdateField(const ATarget, AField, AVal: string): TGrispAction; static;
    class function MakeDeleteNode(const AName: string): TGrispAction; static;
    class function MakeEmitEvent(const AEvent: string; const APayload: TArray<string>): TGrispAction; static;
    class function MakeQuery(const AQuery: string): TGrispAction; static;
    class function MakeFileWrite(const APath, AContent, AMime: string): TGrispAction; static;
  end;

  TGrispRule = record
    RuleId: string;
    Priority: Integer;
    Actions: TArray<TGrispAction>;
  end;

  TGrispParser = class
  private
    FLexer: TGrispLexer;
    FLook: TGrispToken;
    procedure Next;
    procedure ExpectKind(k: TGrispTokenKind);
    function ParseProgram: TArray<TGrispRule>;
    function ParseRule: TGrispRule;
    function ParseActions: TArray<TGrispAction>;
    function ParseActionStmt: TGrispAction;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Parse: TArray<TGrispRule>;
  end;

  TGrispEvent = record
    EventName: string;
    Payload: TArray<string>;
    Tick: Int64;
  end;

  TGrispValidationResult = record
    Accepted: Boolean;
    FailedOps: TArray<string>;
    Diagnostics: string;
    RuleCount: Integer;

    class function MakeAccepted(const ADiag: string; ARuleCount: Integer = 0): TGrispValidationResult; static;
    class function MakeRejected(const ADiag: string; const AFailedOps: TArray<string> = nil): TGrispValidationResult; static;
  end;

  TGrispEngine = class
  private
    FGraph: TGrispGraph;
    FVfs: TGrispVfs;
    FCapabilities: TGrispCapabilitySet;
    FEvents: TList<TGrispEvent>;
    procedure LogEvent(const AName: string; const APayload: TArray<string>);
  public
    constructor Create(AGraph: TGrispGraph; AVfs: TGrispVfs; ACapabilities: TGrispCapabilitySet);
    destructor Destroy; override;

    function ValidatePlan(const Rules: TArray<TGrispRule>; const CapName: string): TGrispValidationResult;
    function ExecuteAction(const Action: TGrispAction; const CapName: string; out Reason: string): Boolean;
    function ExecuteRule(const Rule: TGrispRule; const CapName: string; out Reason: string): Boolean;
    function ExecutePlan(const Rules: TArray<TGrispRule>; const CapName: string; out Reason: string): Boolean;

    function GetEvents: TArray<TGrispEvent>;
    function EventsToJSON: string;

    property Graph: TGrispGraph read FGraph;
    property Vfs: TGrispVfs read FVfs;
    property Capabilities: TGrispCapabilitySet read FCapabilities;
  end;

implementation

{ TGrispLexer }

constructor TGrispLexer.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  FLine := 1;
  FCol := 1;
end;

function TGrispLexer.Peek: Char;
begin
  if FPos > Length(FText) then Exit(#0);
  Result := FText[FPos];
end;

function TGrispLexer.NextChar: Char;
begin
  if FPos > Length(FText) then Exit(#0);
  Result := FText[FPos];
  Inc(FPos);
  if Result = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end
  else
    Inc(FCol);
end;

procedure TGrispLexer.SkipWhitespaceAndComments;
var
  C: Char;
begin
  while True do
  begin
    C := Peek;
    if CharInSet(C, [' ', #9, #10, #13]) then
      NextChar
    else if (C = '/') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '/') then
    begin
      while (Peek <> #0) and (Peek <> #10) do NextChar;
    end
    else if (C = '/') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '*') then
    begin
      NextChar; NextChar;
      while not ((Peek = #0) or ((Peek = '*') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '/'))) do
        NextChar;
      if Peek <> #0 then begin NextChar; NextChar; end;
    end
    else
      Break;
  end;
end;

function TGrispLexer.ReadIdentOrKeyword: TGrispToken;
var
  SB: TStringBuilder;
  C: Char;
  Txt: string;
begin
  SB := TStringBuilder.Create;
  try
    while True do
    begin
      C := Peek;
      if (C = #0) or not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
        Break;
      SB.Append(NextChar);
    end;
    Txt := SB.ToString;
    Result.Kind := gtkIdent;
    Result.Text := Txt;
    Result.Line := FLine;
    Result.Col := FCol;

    if SameText(Txt, 'rules') or SameText(Txt, 'rule') or SameText(Txt, 'match')
      or SameText(Txt, 'actions') or SameText(Txt, 'begin') or SameText(Txt, 'end')
      or SameText(Txt, 'where') or SameText(Txt, 'let') or SameText(Txt, 'with')
      or SameText(Txt, 'priority') or SameText(Txt, 'CreateNode') or SameText(Txt, 'CreateEdge')
      or SameText(Txt, 'UpdateField') or SameText(Txt, 'DeleteNode') or SameText(Txt, 'DeleteEdge')
      or SameText(Txt, 'EmitEvent') or SameText(Txt, 'Query') or SameText(Txt, 'FileWrite')
      or SameText(Txt, 'FileRead') then
      Result.Kind := gtkKeyword;
  finally
    SB.Free;
  end;
end;

function TGrispLexer.ReadNumber: TGrispToken;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    while CharInSet(Peek, ['0'..'9']) do
      SB.Append(NextChar);
    Result.Kind := gtkNumber;
    Result.Text := SB.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    SB.Free;
  end;
end;

function TGrispLexer.ReadString: TGrispToken;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    NextChar; // consume opening "
    while True do
    begin
      C := Peek;
      if C = #0 then Break;
      if C = '"' then
      begin
        NextChar;
        Break;
      end;
      if C = '\' then
      begin
        NextChar;
        case Peek of
          'n': begin SB.Append(#10); NextChar; end;
          'r': begin SB.Append(#13); NextChar; end;
          't': begin SB.Append(#9); NextChar; end;
          '"': begin SB.Append('"'); NextChar; end;
          '\': begin SB.Append('\'); NextChar; end;
        else
          SB.Append(NextChar);
        end;
      end
      else
        SB.Append(NextChar);
    end;
    Result.Kind := gtkString;
    Result.Text := SB.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    SB.Free;
  end;
end;

function TGrispLexer.NextToken: TGrispToken;
var
  C: Char;
begin
  SkipWhitespaceAndComments;
  C := Peek;
  Result.Line := FLine;
  Result.Col := FCol;
  if C = #0 then
  begin
    Result.Kind := gtkEOF;
    Result.Text := '';
    Exit;
  end;

  if CharInSet(C, ['A'..'Z', 'a'..'z', '_']) then
    Exit(ReadIdentOrKeyword);

  if CharInSet(C, ['0'..'9']) then
    Exit(ReadNumber);

  case C of
    '(': begin NextChar; Result.Kind := gtkLParen; Result.Text := '('; end;
    ')': begin NextChar; Result.Kind := gtkRParen; Result.Text := ')'; end;
    '{': begin NextChar; Result.Kind := gtkLBrace; Result.Text := '{'; end;
    '}': begin NextChar; Result.Kind := gtkRBrace; Result.Text := '}'; end;
    '[': begin NextChar; Result.Kind := gtkLBracket; Result.Text := '['; end;
    ']': begin NextChar; Result.Kind := gtkRBracket; Result.Text := ']'; end;
    ',': begin NextChar; Result.Kind := gtkComma; Result.Text := ','; end;
    ':': begin NextChar; Result.Kind := gtkColon; Result.Text := ':'; end;
    ';': begin NextChar; Result.Kind := gtkSemicolon; Result.Text := ';'; end;
    '.': begin NextChar; Result.Kind := gtkDot; Result.Text := '.'; end;
    '"': Exit(ReadString);
  else
    NextChar;
    Result.Kind := gtkOp;
    Result.Text := C;
  end;
end;

{ TGrispAction }

class function TGrispAction.MakeCreateNode(const AName, AType: string;
  const AFields: TDictionary<string, string>): TGrispAction;
var
  Pair: TPair<string, string>;
begin
  Result.Kind := gakCreateNode;
  Result.TargetName := AName;
  Result.TargetType := AType;
  Result.Arg1 := '';
  Result.Arg2 := '';
  SetLength(Result.Params, 0);
  Result.FieldMap := TDictionary<string, string>.Create;
  if Assigned(AFields) then
    for Pair in AFields do
      Result.FieldMap.Add(Pair.Key, Pair.Value);
end;

class function TGrispAction.MakeUpdateField(const ATarget, AField, AVal: string): TGrispAction;
begin
  Result.Kind := gakUpdateField;
  Result.TargetName := ATarget;
  Result.TargetType := '';
  Result.Arg1 := AField;
  Result.Arg2 := AVal;
  SetLength(Result.Params, 0);
  Result.FieldMap := nil;
end;

class function TGrispAction.MakeDeleteNode(const AName: string): TGrispAction;
begin
  Result.Kind := gakDeleteNode;
  Result.TargetName := AName;
  Result.TargetType := '';
  Result.Arg1 := '';
  Result.Arg2 := '';
  SetLength(Result.Params, 0);
  Result.FieldMap := nil;
end;

class function TGrispAction.MakeEmitEvent(const AEvent: string; const APayload: TArray<string>): TGrispAction;
var
  I: Integer;
begin
  Result.Kind := gakEmitEvent;
  Result.TargetName := '';
  Result.TargetType := AEvent;
  Result.Arg1 := '';
  Result.Arg2 := '';
  SetLength(Result.Params, Length(APayload));
  for I := 0 to High(APayload) do
    Result.Params[I] := APayload[I];
  Result.FieldMap := nil;
end;

class function TGrispAction.MakeQuery(const AQuery: string): TGrispAction;
begin
  Result.Kind := gakQuery;
  Result.TargetName := '';
  Result.TargetType := AQuery;
  Result.Arg1 := '';
  Result.Arg2 := '';
  SetLength(Result.Params, 0);
  Result.FieldMap := nil;
end;

class function TGrispAction.MakeFileWrite(const APath, AContent, AMime: string): TGrispAction;
begin
  Result.Kind := gakFileWrite;
  Result.TargetName := APath;
  Result.TargetType := AMime;
  Result.Arg1 := AContent;
  Result.Arg2 := '';
  SetLength(Result.Params, 0);
  Result.FieldMap := nil;
end;

{ TGrispParser }

constructor TGrispParser.Create(const AText: string);
begin
  inherited Create;
  FLexer := TGrispLexer.Create(AText);
  FLook := FLexer.NextToken;
end;

destructor TGrispParser.Destroy;
begin
  FLexer.Free;
  inherited Destroy;
end;

procedure TGrispParser.Next;
begin
  FLook := FLexer.NextToken;
end;

procedure TGrispParser.ExpectKind(k: TGrispTokenKind);
begin
  if FLook.Kind <> k then
    raise Exception.CreateFmt('Parse error at line %d col %d: expected token %d, found %s',
      [FLook.Line, FLook.Col, Ord(k), FLook.Text]);
  Next;
end;

function TGrispParser.Parse: TArray<TGrispRule>;
begin
  Result := ParseProgram;
end;

function TGrispParser.ParseProgram: TArray<TGrispRule>;
var
  Rules: TList<TGrispRule>;
begin
  Rules := TList<TGrispRule>.Create;
  try
    if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'rules') then
    begin
      Next;
      ExpectKind(gtkKeyword); // 'begin'
      while not ((FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'end')) and (FLook.Kind <> gtkEOF) do
      begin
        Rules.Add(ParseRule);
      end;
      ExpectKind(gtkKeyword); // 'end'
    end
    else
      raise Exception.Create('Program must start with rules begin ... end');

    Result := Rules.ToArray;
  finally
    Rules.Free;
  end;
end;

function TGrispParser.ParseRule: TGrispRule;
begin
  Result.RuleId := '';
  Result.Priority := 100;
  SetLength(Result.Actions, 0);

  if not ((FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'rule')) then
    raise Exception.Create('Expected keyword "rule"');
  Next;

  if FLook.Kind <> gtkString then
    raise Exception.Create('Expected rule id string');
  Result.RuleId := FLook.Text;
  Next;

  // Optional priority
  if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'priority') then
  begin
    Next;
    if FLook.Kind = gtkNumber then
    begin
      Result.Priority := StrToIntDef(FLook.Text, 100);
      Next;
    end;
  end;

  // Skip any other optional headers until 'begin'
  while not ((FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'begin')) and (FLook.Kind <> gtkEOF) do
    Next;
  ExpectKind(gtkKeyword); // 'begin'

  // Optional match block
  if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'match') then
  begin
    Next;
    ExpectKind(gtkKeyword); // 'begin'
    while not ((FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'end')) and (FLook.Kind <> gtkEOF) do
      Next;
    ExpectKind(gtkKeyword); // 'end'
  end;

  // Optional where
  if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'where') then
  begin
    Next;
    while (FLook.Kind <> gtkSemicolon) and (FLook.Kind <> gtkEOF) do Next;
    ExpectKind(gtkSemicolon);
  end;

  // Optional let block
  if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'let') then
  begin
    Next;
    ExpectKind(gtkKeyword); // 'begin'
    while not ((FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'end')) and (FLook.Kind <> gtkEOF) do
      Next;
    ExpectKind(gtkKeyword); // 'end'
  end;

  // Actions block
  Result.Actions := ParseActions;

  // End of rule
  if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'end') then
    Next
  else
    raise Exception.Create('Expected "end" for rule block');
end;

function TGrispParser.ParseActions: TArray<TGrispAction>;
var
  Actions: TList<TGrispAction>;
begin
  Actions := TList<TGrispAction>.Create;
  try
    ExpectKind(gtkKeyword); // 'actions'
    ExpectKind(gtkKeyword); // 'begin'
    while not ((FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'end')) and (FLook.Kind <> gtkEOF) do
    begin
      Actions.Add(ParseActionStmt);
    end;
    ExpectKind(gtkKeyword); // 'end'
    Result := Actions.ToArray;
  finally
    Actions.Free;
  end;
end;

function TGrispParser.ParseActionStmt: TGrispAction;
var
  Key, Val: string;
  ParamsList: TList<string>;
begin
  Result.TargetName := '';
  Result.TargetType := '';
  Result.Arg1 := '';
  Result.Arg2 := '';
  SetLength(Result.Params, 0);
  Result.FieldMap := nil;

  if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'CreateNode') then
  begin
    Result.Kind := gakCreateNode;
    Next;
    ExpectKind(gtkLParen);
    Result.TargetName := FLook.Text; Next;
    ExpectKind(gtkComma);
    Result.TargetType := FLook.Text; Next;
    ExpectKind(gtkRParen);

    if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'with') then
    begin
      Next;
      ExpectKind(gtkLBrace);
      Result.FieldMap := TDictionary<string, string>.Create;
      while (FLook.Kind <> gtkRBrace) and (FLook.Kind <> gtkEOF) do
      begin
        Key := FLook.Text; Next;
        ExpectKind(gtkColon);
        Val := FLook.Text; Next;
        Result.FieldMap.AddOrSetValue(Key, Val);
        if FLook.Kind = gtkSemicolon then Next;
      end;
      ExpectKind(gtkRBrace);
    end;
    ExpectKind(gtkSemicolon);
  end
  else if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'UpdateField') then
  begin
    Result.Kind := gakUpdateField;
    Next;
    ExpectKind(gtkLParen);
    Result.TargetName := FLook.Text; Next;
    ExpectKind(gtkComma);
    Result.Arg1 := FLook.Text; Next;
    ExpectKind(gtkComma);
    Result.Arg2 := FLook.Text; Next;
    ExpectKind(gtkRParen);
    ExpectKind(gtkSemicolon);
  end
  else if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'DeleteNode') then
  begin
    Result.Kind := gakDeleteNode;
    Next;
    ExpectKind(gtkLParen);
    Result.TargetName := FLook.Text; Next;
    ExpectKind(gtkRParen);
    ExpectKind(gtkSemicolon);
  end
  else if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'EmitEvent') then
  begin
    Result.Kind := gakEmitEvent;
    Next;
    ExpectKind(gtkLParen);
    Result.TargetType := FLook.Text; Next;
    ExpectKind(gtkComma);
    ExpectKind(gtkLBracket);
    ParamsList := TList<string>.Create;
    try
      while (FLook.Kind <> gtkRBracket) and (FLook.Kind <> gtkEOF) do
      begin
        if (FLook.Kind = gtkString) or (FLook.Kind = gtkNumber) or (FLook.Kind = gtkIdent) then
        begin
          ParamsList.Add(FLook.Text);
          Next;
        end
        else if FLook.Kind = gtkComma then
          Next
        else
          Break;
      end;
      Result.Params := ParamsList.ToArray;
    finally
      ParamsList.Free;
    end;
    ExpectKind(gtkRBracket);
    ExpectKind(gtkRParen);
    ExpectKind(gtkSemicolon);
  end
  else if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'Query') then
  begin
    Result.Kind := gakQuery;
    Next;
    ExpectKind(gtkLParen);
    Result.TargetType := FLook.Text; Next;
    ExpectKind(gtkRParen);
    ExpectKind(gtkSemicolon);
  end
  else if (FLook.Kind = gtkKeyword) and SameText(FLook.Text, 'FileWrite') then
  begin
    Result.Kind := gakFileWrite;
    Next;
    ExpectKind(gtkLParen);
    Result.TargetName := FLook.Text; Next; // path
    ExpectKind(gtkComma);
    Result.Arg1 := FLook.Text; Next; // content
    ExpectKind(gtkComma);
    Result.TargetType := FLook.Text; Next; // mime
    ExpectKind(gtkRParen);
    ExpectKind(gtkSemicolon);
  end
  else
    raise Exception.CreateFmt('Unknown action token: %s at %d:%d', [FLook.Text, FLook.Line, FLook.Col]);
end;

{ TGrispValidationResult }

class function TGrispValidationResult.MakeAccepted(const ADiag: string; ARuleCount: Integer): TGrispValidationResult;
begin
  Result.Accepted := True;
  SetLength(Result.FailedOps, 0);
  Result.Diagnostics := ADiag;
  Result.RuleCount := ARuleCount;
end;

class function TGrispValidationResult.MakeRejected(const ADiag: string; const AFailedOps: TArray<string>): TGrispValidationResult;
var
  I: Integer;
begin
  Result.Accepted := False;
  SetLength(Result.FailedOps, Length(AFailedOps));
  for I := 0 to High(AFailedOps) do
    Result.FailedOps[I] := AFailedOps[I];
  Result.Diagnostics := ADiag;
  Result.RuleCount := 0;
end;

{ TGrispEngine }

constructor TGrispEngine.Create(AGraph: TGrispGraph; AVfs: TGrispVfs; ACapabilities: TGrispCapabilitySet);
begin
  inherited Create;
  FGraph := AGraph;
  FVfs := AVfs;
  FCapabilities := ACapabilities;
  FEvents := TList<TGrispEvent>.Create;
end;

destructor TGrispEngine.Destroy;
begin
  FEvents.Free;
  inherited Destroy;
end;

procedure TGrispEngine.LogEvent(const AName: string; const APayload: TArray<string>);
var
  Ev: TGrispEvent;
  I: Integer;
begin
  Ev.EventName := AName;
  SetLength(Ev.Payload, Length(APayload));
  for I := 0 to High(APayload) do
    Ev.Payload[I] := APayload[I];
  if Assigned(FGraph) then
    Ev.Tick := FGraph.Tick
  else
    Ev.Tick := 0;
  FEvents.Add(Ev);
end;

function TGrispEngine.ValidatePlan(const Rules: TArray<TGrispRule>; const CapName: string): TGrispValidationResult;
var
  Cap: IGrispCapability;
  FailedList: TList<string>;
  R: TGrispRule;
  Act: TGrispAction;
  Reason: string;
  Size: Int64;
begin
  Cap := nil;
  if Assigned(FCapabilities) and (CapName <> '') then
  begin
    if not FCapabilities.Find(CapName, Cap) then
      Exit(TGrispValidationResult.MakeRejected(Format('Required capability "%s" not found in active set', [CapName]),
        ['CAPABILITY_NOT_FOUND']));
  end;

  if Length(Rules) = 0 then
    Exit(TGrispValidationResult.MakeAccepted('No rules to validate', 0));

  FailedList := TList<string>.Create;
  try
    for R in Rules do
    begin
      for Act in R.Actions do
      begin
        case Act.Kind of
          gakCreateNode, gakUpdateField:
            begin
              if Assigned(Cap) and (not Cap.AllowsOp(grWrite)) then
                FailedList.Add(Format('Rule "%s": Operation "%s" not permitted by capability "%s"',
                  [R.RuleId, TGrispCapability.OpToString(grWrite), Cap.Name]));
            end;

          gakDeleteNode, gakDeleteEdge:
            begin
              if Assigned(Cap) and (not Cap.AllowsOp(grDelete)) then
                FailedList.Add(Format('Rule "%s": Operation "%s" not permitted by capability "%s"',
                  [R.RuleId, TGrispCapability.OpToString(grDelete), Cap.Name]));
            end;

          gakFileWrite:
            begin
              if Assigned(Cap) then
              begin
                Size := Length(TEncoding.UTF8.GetBytes(Act.Arg1));
                if not Cap.ValidateWrite(Act.TargetName, Act.TargetType, Size, Reason) then
                  FailedList.Add(Format('Rule "%s": FileWrite("%s") rejected: %s', [R.RuleId, Act.TargetName, Reason]));
              end;
            end;

          gakFileRead:
            begin
              if Assigned(Cap) then
              begin
                if not Cap.AllowsOp(grRead) then
                  FailedList.Add(Format('Rule "%s": FileRead not allowed by capability "%s"', [R.RuleId, Cap.Name]))
                else if not Cap.IsPathAllowed(Act.TargetName) then
                  FailedList.Add(Format('Rule "%s": FileRead("%s") outside capability root "%s"', [R.RuleId, Act.TargetName, Cap.Root]));
              end;
            end;
        end;
      end;
    end;

    if FailedList.Count > 0 then
      Result := TGrispValidationResult.MakeRejected(
        Format('Validation failed with %d error(s): %s', [FailedList.Count, string.Join('; ', FailedList.ToArray)]),
        FailedList.ToArray)
    else
      Result := TGrispValidationResult.MakeAccepted(
        Format('Plan validated successfully with %d rule(s)', [Length(Rules)]),
        Length(Rules));
  finally
    FailedList.Free;
  end;
end;

function TGrispEngine.ExecuteAction(const Action: TGrispAction; const CapName: string; out Reason: string): Boolean;
var
  Cap: IGrispCapability;
  Fields: TDictionary<string, TGrispValue>;
  Pair: TPair<string, string>;
  Node: TGrispNode;
begin
  if Assigned(FCapabilities) and (CapName <> '') then
  begin
    if not FCapabilities.Find(CapName, Cap) then
    begin
      Reason := Format('Required capability "%s" not found in active set', [CapName]);
      Exit(False);
    end;
  end;

  case Action.Kind of
    gakCreateNode:
      begin
        Fields := TDictionary<string, TGrispValue>.Create;
        try
          if Assigned(Action.FieldMap) then
            for Pair in Action.FieldMap do
              Fields.Add(Pair.Key, TGrispValue.MakeString(Pair.Value));

          Node := FGraph.CreateNode(Action.TargetType, Fields);
          LogEvent('create_node', [Node.Id, Action.TargetType]);
        finally
          Fields.Free;
        end;
      end;

    gakUpdateField:
      begin
        FGraph.UpdateNodeField(Action.TargetName, Action.Arg1, TGrispValue.MakeString(Action.Arg2));
        LogEvent('update_field', [Action.TargetName, Action.Arg1, Action.Arg2]);
      end;

    gakDeleteNode:
      begin
        FGraph.DeleteNode(Action.TargetName);
        LogEvent('delete_node', [Action.TargetName]);
      end;

    gakEmitEvent:
      begin
        LogEvent(Action.TargetType, Action.Params);
      end;

    gakQuery:
      begin
        LogEvent('query_response', [Action.TargetType, FGraph.ToCanonicalJSON]);
      end;

    gakFileWrite:
      begin
        if not FVfs.WriteFile(Action.TargetName, Action.Arg1, Action.TargetType, Cap, Reason) then
          Exit(False);
        LogEvent('file_written', [Action.TargetName, Action.TargetType]);
      end;
  end;

  Reason := '';
  Result := True;
end;

function TGrispEngine.ExecuteRule(const Rule: TGrispRule; const CapName: string; out Reason: string): Boolean;
var
  Act: TGrispAction;
begin
  for Act in Rule.Actions do
  begin
    if not ExecuteAction(Act, CapName, Reason) then
      Exit(False);
  end;
  Result := True;
end;

function TGrispEngine.ExecutePlan(const Rules: TArray<TGrispRule>; const CapName: string; out Reason: string): Boolean;
var
  R: TGrispRule;
begin
  for R in Rules do
  begin
    if not ExecuteRule(R, CapName, Reason) then
      Exit(False);
  end;
  Result := True;
end;

function TGrispEngine.GetEvents: TArray<TGrispEvent>;
begin
  Result := FEvents.ToArray;
end;

function TGrispEngine.EventsToJSON: string;
var
  SB: TStringBuilder;
  I, J: Integer;
  Ev: TGrispEvent;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to FEvents.Count - 1 do
    begin
      if I > 0 then SB.Append(',');
      Ev := FEvents[I];
      SB.Append('{"event":"');
      SB.Append(Ev.EventName);
      SB.Append('","tick":');
      SB.Append(IntToStr(Ev.Tick));
      SB.Append(',"payload":[');
      for J := 0 to High(Ev.Payload) do
      begin
        if J > 0 then SB.Append(',');
        SB.Append('"');
        SB.Append(StringReplace(StringReplace(Ev.Payload[J], '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]));
        SB.Append('"');
      end;
      SB.Append(']}');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
