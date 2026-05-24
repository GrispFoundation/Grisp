unit unit_GrispLexer_version_001;

interface

uses
  System.SysUtils,
  unit_GrispTokens_version_001;

type
  EGrispLexerError = class(Exception);

  TGrispLexer = class
  private
    FSource: string;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    procedure AdvanceChar;
    function PeekChar(Offset: Integer = 0): Char;
    procedure SkipWhitespaceAndComments;
    function ReadString: TToken;
    function ReadNumber: TToken;
    function ReadIdentifier: TToken;
  public
    constructor Create(const ASource: string);
    function NextToken: TToken;
  end;

implementation

constructor TGrispLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FPos := 1;
  FLine := 1;
  FCol := 1;
end;

procedure TGrispLexer.AdvanceChar;
begin
  if FPos <= Length(FSource) then
  begin
    if FSource[FPos] = #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else if FSource[FPos] <> #13 then
      Inc(FCol);
    Inc(FPos);
  end;
end;

function TGrispLexer.PeekChar(Offset: Integer): Char;
begin
  if FPos + Offset <= Length(FSource) then
    Result := FSource[FPos + Offset]
  else
    Result := #0;
end;

procedure TGrispLexer.SkipWhitespaceAndComments;
begin
  while FPos <= Length(FSource) do
  begin
    if CharInSet(FSource[FPos], [' ', #9, #13, #10]) then
    begin
      AdvanceChar;
      Continue;
    end;
    // // line comment
    if (FSource[FPos] = '/') and (PeekChar(1) = '/') then
	begin
      AdvanceChar; AdvanceChar;
      while (FPos <= Length(FSource)) and not CharInSet(FSource[FPos], [#10,#13]) do
        AdvanceChar;
      Continue;
    end;
    // /* block comment */
    if (FSource[FPos] = '/') and (PeekChar(1) = '*') then
    begin
      AdvanceChar; AdvanceChar;
      while FPos <= Length(FSource) do
      begin
        if (FSource[FPos] = '*') and (PeekChar(1) = '/') then
        begin
          AdvanceChar; AdvanceChar;
          Break;
        end
        else
          AdvanceChar;
      end;
      Continue;
    end;
    Break;
  end;
end;

function TGrispLexer.ReadString: TToken;
var
  Line, Col: Integer;
  Quote: Char;
  Esc: Boolean;
  SB: string;
begin
  Line := FLine; Col := FCol;
  Quote := FSource[FPos];
  AdvanceChar;
  SB := '';
  Esc := False;
  while FPos <= Length(FSource) do
  begin
    if Esc then
    begin
      SB := SB + FSource[FPos];
      Esc := False;
      AdvanceChar;
      Continue;
    end;
    if FSource[FPos] = '\' then
    begin
      Esc := True;
      AdvanceChar;
      Continue;
    end;
    if FSource[FPos] = Quote then
    begin
      AdvanceChar;
      Break;
    end;
    SB := SB + FSource[FPos];
    AdvanceChar;
  end;
  Result.Kind := tkString;
  Result.Lexeme := Quote + SB + Quote;
  Result.Line := Line;
  Result.Column := Col;
end;

function TGrispLexer.ReadNumber: TToken;
var
  Start, Line, Col: Integer;
begin
  Line := FLine; Col := FCol;
  Start := FPos;
  if CharInSet(FSource[FPos], ['+','-']) then
    AdvanceChar;
  while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
    AdvanceChar;
  if (FSource[FPos] = '.') and CharInSet(PeekChar(1), ['0'..'9']) then
  begin
    AdvanceChar;
    while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
      AdvanceChar;
  end;
  Result.Kind := tkNumber;
  Result.Lexeme := Copy(FSource, Start, FPos - Start);
  Result.Line := Line;
  Result.Column := Col;
end;

function TGrispLexer.ReadIdentifier: TToken;
var
  Start, Line, Col: Integer;
  S: string;
begin
  Line := FLine; Col := FCol;
  Start := FPos;
  AdvanceChar;
  while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['a'..'z','A'..'Z','0'..'9','_','.']) do
    AdvanceChar;
  S := Copy(FSource, Start, FPos - Start);
  Result.Lexeme := S;
  Result.Line := Line;
  Result.Column := Col;

  if SameText(S,'node') then Result.Kind := tkKeywordNode
  else if SameText(S,'array') then Result.Kind := tkKeywordArray
  else if SameText(S,'where') then Result.Kind := tkKeywordWhere
  else if SameText(S,'and') then Result.Kind := tkKeywordAnd
  else if SameText(S,'or') then Result.Kind := tkKeywordOr
  else if SameText(S,'not') then Result.Kind := tkKeywordNot
  else if SameText(S,'mod') then Result.Kind := tkKeywordMod
  else if SameText(S,'true') or SameText(S,'false') then Result.Kind := tkBoolean
  else Result.Kind := tkIdentifier;
end;

function TGrispLexer.NextToken: TToken;
var
  C: Char;
begin
  SkipWhitespaceAndComments;
  Result.Line := FLine;
  Result.Column := FCol;
  if FPos > Length(FSource) then
  begin
    Result.Kind := tkEOF;
    Result.Lexeme := '';
    Exit;
  end;

  C := FSource[FPos];
  case C of
    '{': begin Result.Kind := tkLBrace; Result.Lexeme := '{'; AdvanceChar; Exit; end;
	'}': begin Result.Kind := tkRBrace; Result.Lexeme := '}'; AdvanceChar; Exit; end;
    '[': begin Result.Kind := tkLBracket; Result.Lexeme := '['; AdvanceChar; Exit; end;
    ']': begin Result.Kind := tkRBracket; Result.Lexeme := ']'; AdvanceChar; Exit; end;
    '(': begin Result.Kind := tkLParen; Result.Lexeme := '('; AdvanceChar; Exit; end;
    ')': begin Result.Kind := tkRParen; Result.Lexeme := ')'; AdvanceChar; Exit; end;
    ':': begin Result.Kind := tkColon; Result.Lexeme := ':'; AdvanceChar; Exit; end;
    '=': begin Result.Kind := tkEquals; Result.Lexeme := '='; AdvanceChar; Exit; end;
    ',': begin Result.Kind := tkComma; Result.Lexeme := ','; AdvanceChar; Exit; end;
    ';': begin Result.Kind := tkSemicolon; Result.Lexeme := ';'; AdvanceChar; Exit; end;
    '+','-','*':
      begin
        Result.Kind := tkOperator;
        Result.Lexeme := C;
        AdvanceChar;
        Exit;
      end;
    '/':
      begin
        // '/' alone is operator, '//' and '/*' were stripped in SkipWhitespaceAndComments
        Result.Kind := tkOperator;
        Result.Lexeme := '/';
        AdvanceChar;
        Exit;
      end;
    '<':
      begin
        if PeekChar(1) = '=' then
        begin Result.Kind := tkLessEqual; Result.Lexeme := '<='; AdvanceChar; AdvanceChar; Exit; end
        else if PeekChar(1) = '>' then
        begin Result.Kind := tkNotEqual; Result.Lexeme := '<>'; AdvanceChar; AdvanceChar; Exit; end
        else
        begin Result.Kind := tkLess; Result.Lexeme := '<'; AdvanceChar; Exit; end;
      end;
    '>':
      begin
        if PeekChar(1) = '=' then
        begin Result.Kind := tkGreaterEqual; Result.Lexeme := '>='; AdvanceChar; AdvanceChar; Exit; end
        else
        begin Result.Kind := tkGreater; Result.Lexeme := '>'; AdvanceChar; Exit; end;
      end;
    '''','"':
      begin Result := ReadString; Exit; end;
  end;

  if CharInSet(C, ['0'..'9']) then
  begin
    Result := ReadNumber;
    Exit;
  end;

  if CharInSet(C, ['a'..'z','A'..'Z','_']) then
  begin
    Result := ReadIdentifier;
    Exit;
  end;

  // allow leading + / - for numbers
  if CharInSet(C, ['+','-']) and CharInSet(PeekChar(1), ['0'..'9']) then
  begin
    Result := ReadNumber;
    Exit;
  end;

  raise EGrispLexerError.CreateFmt('Invalid character "%s" at %d:%d', [C, FLine, FCol]);
end;

end.
