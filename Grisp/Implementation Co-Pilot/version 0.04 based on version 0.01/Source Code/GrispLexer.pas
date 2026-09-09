unit GrispLexer;

interface

uses
  SysUtils, Classes;

type
  TTokenKind = (
    tkEOF,
    tkIdent,
    tkString,
    tkNumber,
    tkLParen,
    tkRParen,
    tkLBrace,
    tkRBrace,
    tkLBracket,
    tkRBracket,
    tkComma,
    tkColon,
    tkSemicolon,
    tkDot,
    tkOp,
    tkKeyword
  );

  TToken = record
    Kind: TTokenKind;
    Text: string;
    Line: Integer;
    Col: Integer;
  end;

  TLexer = class
  private
    FText: string;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    function Peek: Char;
    function NextChar: Char;
    procedure SkipWhitespaceAndComments;
    function ReadIdentOrKeyword: TToken;
    function ReadNumber: TToken;
    function ReadString: TToken;
  public
    constructor Create(const AText: string);
    function NextToken: TToken;
  end;

implementation

constructor TLexer.Create(const AText: string);
begin
  FText := AText;
  FPos := 1;
  FLine := 1;
  FCol := 1;
end;

function TLexer.Peek: Char;
begin
  if FPos > Length(FText) then Exit(#0);
  Result := FText[FPos];
end;

function TLexer.NextChar: Char;
begin
  if FPos > Length(FText) then Exit(#0);
  Result := FText[FPos];
  Inc(FPos);
  if Result = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end else
    Inc(FCol);
end;

procedure TLexer.SkipWhitespaceAndComments;
var
  c: Char;
begin
  while True do
  begin
    c := Peek;
    if CharInSet(c, [' ', #9, #10, #13]) then
      NextChar
    else if (c = '/') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '/') then
    begin
      // line comment
      while (Peek <> #0) and (Peek <> #10) do NextChar;
    end
    else if (c = '/') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '*') then
    begin
      // block comment
      NextChar; NextChar;
      while not ((Peek = #0) or ((Peek = '*') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '/'))) do
        NextChar;
      if Peek <> #0 then begin NextChar; NextChar; end;
    end
    else Break;
  end;
end;

function TLexer.ReadIdentOrKeyword: TToken;
var
  sb: TStringBuilder;
  c: Char;
  txt: string;
begin
  sb := TStringBuilder.Create;
  try
    while True do
    begin
      c := Peek;
      if (c = #0) then Break;
      if CharInSet(c, ['A'..'Z','a'..'z','0'..'9','_']) then
        sb.Append(NextChar)
      else Break;
    end;
    txt := sb.ToString;
    Result.Kind := tkIdent;
    Result.Text := txt;
    Result.Line := FLine;
    Result.Col := FCol;

    // simple keyword detection (case-insensitive)
    if SameText(txt, 'rules') or SameText(txt, 'rule') or SameText(txt, 'match')
      or SameText(txt, 'actions') or SameText(txt, 'begin') or SameText(txt, 'end')
      or SameText(txt, 'where') or SameText(txt, 'let') or SameText(txt, 'with')
      or SameText(txt, 'CreateNode') or SameText(txt, 'UpdateField')
      or SameText(txt, 'DeleteNode') or SameText(txt, 'EmitEvent') or SameText(txt, 'Query') then
      Result.Kind := tkKeyword;
  finally
    sb.Free;
  end;
end;

function TLexer.ReadNumber: TToken;
var
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    while CharInSet(Peek, ['0'..'9']) do sb.Append(NextChar);
    Result.Kind := tkNumber;
    Result.Text := sb.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    sb.Free;
  end;
end;

function TLexer.ReadString: TToken;
var
  sb: TStringBuilder;
  c: Char;
begin
  sb := TStringBuilder.Create;
  try
    NextChar; // skip opening "
    while True do
    begin
      c := Peek;
      if c = #0 then Break;
      if c = '"' then begin NextChar; Break; end;
      if c = '\' then
      begin
        NextChar;
        case Peek of
          'n': begin sb.Append(#10); NextChar; end;
          'r': begin sb.Append(#13); NextChar; end;
          't': begin sb.Append(#9); NextChar; end;
          '"': begin sb.Append('"'); NextChar; end;
          '\': begin sb.Append('\'); NextChar; end;
        else
          sb.Append(NextChar);
        end;
      end else
        sb.Append(NextChar);
    end;
    Result.Kind := tkString;
    Result.Text := sb.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    sb.Free;
  end;
end;

function TLexer.NextToken: TToken;
var
  c: Char;
begin
  SkipWhitespaceAndComments;
  c := Peek;
  Result.Line := FLine;
  Result.Col := FCol;
  if c = #0 then
  begin
    Result.Kind := tkEOF; Result.Text := '';
    Exit;
  end;
  if CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit(ReadIdentOrKeyword);
  if CharInSet(c, ['0'..'9']) then Exit(ReadNumber);
  case c of
    '(' : begin NextChar; Result.Kind := tkLParen; Result.Text := '('; end;
    ')' : begin NextChar; Result.Kind := tkRParen; Result.Text := ')'; end;
    '{' : begin NextChar; Result.Kind := tkLBrace; Result.Text := '{'; end;
    '}' : begin NextChar; Result.Kind := tkRBrace; Result.Text := '}'; end;
    '[' : begin NextChar; Result.Kind := tkLBracket; Result.Text := '['; end;
    ']' : begin NextChar; Result.Kind := tkRBracket; Result.Text := ']'; end;
    ',' : begin NextChar; Result.Kind := tkComma; Result.Text := ','; end;
    ':' : begin NextChar; Result.Kind := tkColon; Result.Text := ':'; end;
    ';' : begin NextChar; Result.Kind := tkSemicolon; Result.Text := ';'; end;
    '.' : begin NextChar; Result.Kind := tkDot; Result.Text := '.'; end;
    '"' : Exit(ReadString);
    else
      // operators and unknown single-char tokens
      NextChar;
      Result.Kind := tkOp;
      Result.Text := c;
  end;
end;

end.

