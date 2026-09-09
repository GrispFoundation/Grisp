unit GrispParser;

interface

uses
  SysUtils, Classes, GrispLexer;

type
  TExpr = record
    // minimal expression representation (literal or ident or dotted)
    Kind: string; // 'ident','string','number','dot'
    Text: string;
    Left: Pointer; // reserved for extension
    Right: Pointer;
  end;

  TActionKind = (akCreateNode, akUpdateField, akDeleteNode, akEmitEvent, akQuery);

  TAction = record
    Kind: TActionKind;
    AName: string;
    AType: string;
    Params: TStringList; // deterministic order; ownership: caller is responsible to free lists when appropriate
  end;

  TRule = record
    RuleId: string;
    Actions: array of TAction;
  end;

  TRuleArray = array of TRule;
  TActionArray = array of TAction;

  TParser = class
  private
    FLexer: TLexer;
    FLook: TToken;
    procedure Next;
    procedure ExpectKind(k: TTokenKind);
    function ParseProgram: TRuleArray;
    function ParseRule: TRule;
    procedure ParseMatch; // skip for minimal impl
    procedure ParseWhere; // skip for minimal impl
    function ParseActions: TActionArray;
    function ParseActionStmt: TAction;
    procedure AppendRule(var Arr: TRuleArray; const R: TRule);
    procedure AppendAction(var Arr: TActionArray; const A: TAction);
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Parse: TRuleArray;
  end;

implementation

{ TParser helpers }

procedure TParser.AppendRule(var Arr: TRuleArray; const R: TRule);
var
  n: Integer;
begin
  n := Length(Arr);
  SetLength(Arr, n + 1);
  Arr[n] := R;
end;

procedure TParser.AppendAction(var Arr: TActionArray; const A: TAction);
var
  n: Integer;
begin
  n := Length(Arr);
  SetLength(Arr, n + 1);
  Arr[n] := A;
end;

constructor TParser.Create(const AText: string);
begin
  FLexer := TLexer.Create(AText);
  FLook := FLexer.NextToken;
end;

destructor TParser.Destroy;
begin
  FLexer.Free;
  inherited Destroy;
end;

procedure TParser.Next;
begin
  FLook := FLexer.NextToken;
end;

procedure TParser.ExpectKind(k: TTokenKind);
begin
  if FLook.Kind <> k then
    raise Exception.CreateFmt('Parse error at line %d col %d: expected %d got %d',
      [FLook.Line, FLook.Col, Ord(k), Ord(FLook.Kind)]);
  Next;
end;

function TParser.Parse: TRuleArray;
begin
  Result := ParseProgram;
end;

function TParser.ParseProgram: TRuleArray;
var
  rules: TRuleArray;
  r: TRule;
begin
  SetLength(rules, 0);
  // expect rules begin
  if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'rules')) then
  begin
    Next;
    ExpectKind(tkKeyword); // begin
    while not ((FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'end'))) do
    begin
      r := ParseRule;
      AppendRule(rules, r);
    end;
    ExpectKind(tkKeyword); // end
  end
  else
    raise Exception.Create('Program must start with rules begin ... end');
  Result := rules;
end;

function TParser.ParseRule: TRule;
var
  r: TRule;
  actions: TActionArray;
  i: Integer;
begin
  // initialize
  r.RuleId := '';
  SetLength(r.Actions, 0);

  // rule STRING [priority ...] begin ... end
  if not ((FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'rule'))) then
    raise Exception.Create('Expected rule');
  Next;
  if FLook.Kind <> tkString then
    raise Exception.Create('Expected rule id string');
  r.RuleId := FLook.Text;
  Next;
  // skip optional attributes until 'begin'
  while not ((FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'begin'))) do
    Next;
  ExpectKind(tkKeyword); // begin
  // parse match (skip content)
  if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'match')) then
    ParseMatch;
  // optional where
  if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'where')) then
    ParseWhere;
  // optional let (skip)
  if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'let')) then
  begin
    Next; ExpectKind(tkKeyword); // begin
    while not ((FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'end'))) do Next;
    ExpectKind(tkKeyword); // end
  end;
  // actions
  actions := ParseActions;
  // assign actions to rule
  SetLength(r.Actions, Length(actions));
  for i := 0 to Length(actions) - 1 do
    r.Actions[i] := actions[i];
  // expect end
  if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'end')) then
    Next
  else
    raise Exception.Create('Expected end of rule');
  Result := r;
end;

procedure TParser.ParseMatch;
begin
  // consume 'match' 'begin' ... 'end' deterministically
  ExpectKind(tkKeyword); // match
  ExpectKind(tkKeyword); // begin
  while not ((FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'end'))) do
    Next;
  ExpectKind(tkKeyword); // end
end;

procedure TParser.ParseWhere;
begin
  // consume 'where' EXPR ';' (minimal)
  ExpectKind(tkKeyword); // where
  // skip tokens until semicolon
  while not (FLook.Kind = tkSemicolon) do Next;
  ExpectKind(tkSemicolon);
end;

function TParser.ParseActions: TActionArray;
var
  list: TActionArray;
  a: TAction;
begin
  SetLength(list, 0);
  ExpectKind(tkKeyword); // actions
  ExpectKind(tkKeyword); // begin
  while not ((FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'end'))) do
  begin
    a := ParseActionStmt;
    AppendAction(list, a);
  end;
  ExpectKind(tkKeyword); // end
  Result := list;
end;

function TParser.ParseActionStmt: TAction;
var
  act: TAction;
  params: TStringList;
  // local helpers
  procedure InitAct;
  begin
    act.Kind := akCreateNode;
    act.AName := '';
    act.AType := '';
    params := TStringList.Create;
    act.Params := params;
  end;
begin
  InitAct;
  try
    if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'CreateNode')) then
    begin
      Next; ExpectKind(tkLParen);
      if FLook.Kind <> tkIdent then raise Exception.Create('Expected ident');
      act.AName := FLook.Text; Next;
      ExpectKind(tkComma);
      if FLook.Kind <> tkIdent then raise Exception.Create('Expected type name');
      act.AType := FLook.Text; Next;
      ExpectKind(tkRParen);
      // optional with { ... } - skip parsing map for minimal impl
      if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'with')) then
      begin
        Next; ExpectKind(tkLBrace);
        while not (FLook.Kind = tkRBrace) do Next;
        ExpectKind(tkRBrace);
      end;
      ExpectKind(tkSemicolon);
      act.Kind := akCreateNode;
    end
    else if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'UpdateField')) then
    begin
      Next; ExpectKind(tkLParen);
      if FLook.Kind <> tkIdent then raise Exception.Create('Expected target ident');
      act.AName := FLook.Text; Next;
      ExpectKind(tkComma);
      if FLook.Kind <> tkIdent then raise Exception.Create('Expected field ident');
      params.Add(FLook.Text); Next;
      ExpectKind(tkComma);
      // skip expression until ')'
      while not (FLook.Kind = tkRParen) do Next;
      ExpectKind(tkRParen);
      ExpectKind(tkSemicolon);
      act.Kind := akUpdateField;
      act.Params := params;
    end
    else if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'DeleteNode')) then
    begin
      Next; ExpectKind(tkLParen);
      if FLook.Kind <> tkIdent then raise Exception.Create('Expected ident');
      act.AName := FLook.Text; Next;
      ExpectKind(tkRParen);
      ExpectKind(tkSemicolon);
      act.Kind := akDeleteNode;
    end
    else if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'EmitEvent')) then
    begin
      Next; ExpectKind(tkLParen);
      if FLook.Kind <> tkString then raise Exception.Create('Expected string event type');
      act.AType := FLook.Text; Next;
      ExpectKind(tkComma);
      // parse list expr into params
      ExpectKind(tkLBracket);
      while not (FLook.Kind = tkRBracket) do
      begin
        if FLook.Kind = tkString then
        begin
          params.Add(FLook.Text);
          Next;
        end
        else if FLook.Kind = tkNumber then
        begin
          params.Add(FLook.Text);
          Next;
        end
        else if FLook.Kind = tkComma then
          Next
        else
          raise Exception.CreateFmt('Unexpected token in EmitEvent payload at %d:%d', [FLook.Line, FLook.Col]);
      end;
      ExpectKind(tkRBracket);
      ExpectKind(tkRParen);
      ExpectKind(tkSemicolon);
      act.Kind := akEmitEvent;
      act.Params := params;
    end
    else if (FLook.Kind = tkKeyword) and (SameText(FLook.Text, 'Query')) then
    begin
      Next; ExpectKind(tkLParen);
      if FLook.Kind <> tkString then raise Exception.Create('Expected query string');
      act.AType := FLook.Text; Next;
      ExpectKind(tkRParen);
      ExpectKind(tkSemicolon);
      act.Kind := akQuery;
    end
    else
      raise Exception.CreateFmt('Unknown action at line %d col %d', [FLook.Line, FLook.Col]);
    Result := act;
  except
    // free params if an exception occurred before returning the action
    if Assigned(params) then
      params.Free;
    raise;
  end;
end;

end.

