unit unit_Lexer_TGrispLexer_version_001;

interface

uses
  System.SysUtils,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001;

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
    function ReadString: TGrispToken;
    function ReadNumber: TGrispToken;
    function ReadIdentifier: TGrispToken;
    function IsKeyword(const S: string): TGrispTokenKind;

  public
    constructor Create(const ASource: string);
    function NextToken: TGrispToken;
    procedure Reset;

    property Source: string read FSource;
    property Position: Integer read FPos;
    property Line: Integer read FLine;
    property Column: Integer read FCol;
  end;

implementation

constructor TGrispLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  Reset;
end;

procedure TGrispLexer.Reset;
begin
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
    // Skip whitespace
    if CharInSet(FSource[FPos], [' ', #9, #13, #10]) then
    begin
      AdvanceChar;
      Continue;
    end;

    // Skip line comments //
    if (FSource[FPos] = '/') and (PeekChar(1) = '/') then
    begin
      AdvanceChar; AdvanceChar;
      while (FPos <= Length(FSource)) and not CharInSet(FSource[FPos], [#10, #13]) do
        AdvanceChar;
      Continue;
    end;

    // Skip block comments /* */
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

function TGrispLexer.IsKeyword(const S: string): TGrispTokenKind;
begin
  if SameText(S, 'node') then Result := tkKeywordNode
  else if SameText(S, 'array') then Result := tkKeywordArray
  else if SameText(S, 'where') then Result := tkKeywordWhere
  else if SameText(S, 'and') then Result := tkKeywordAnd
  else if SameText(S, 'or') then Result := tkKeywordOr
  else if SameText(S, 'not') then Result := tkKeywordNot
  else if SameText(S, 'mod') then Result := tkKeywordMod
  else if SameText(S, 'phase') then Result := tkKeywordPhase
  else if SameText(S, 'temp') then Result := tkKeywordTemp
  else if SameText(S, 'delete') then Result := tkKeywordDelete
  else if SameText(S, 'remove') then Result := tkKeywordRemove
  else if SameText(S, 'type') then Result := tkKeywordType
  else if SameText(S, 'strategy') then Result := tkKeywordStrategy
  else if SameText(S, 'repeat') then Result := tkKeywordRepeat
  else if SameText(S, 'try') then Result := tkKeywordTry
  else if SameText(S, 'choice') then Result := tkKeywordChoice
  else if SameText(S, 'true') or SameText(S, 'false') then Result := tkBoolean
  else Result := tkIdentifier;
end;

function TGrispLexer.ReadString: TGrispToken;
var
  Line, Col: Integer;
  Quote: Char;
  Esc: Boolean;
  SB: TStringBuilder;
begin
  Line := FLine; Col := FCol;
  Quote := FSource[FPos];
  AdvanceChar;

  SB := TStringBuilder.Create;
  try
    Esc := False;
    while FPos <= Length(FSource) do
    begin
      if Esc then
      begin
        case FSource[FPos] of
          'n': SB.Append(#10);
          'r': SB.Append(#13);
          't': SB.Append(#9);
          else SB.Append(FSource[FPos]);
        end;
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

      SB.Append(FSource[FPos]);
      AdvanceChar;
    end;

    Result.Kind := tkString;
    Result.Lexeme := Quote + SB.ToString + Quote;
    Result.Line := Line;
    Result.Column := Col;
  finally
    SB.Free;
  end;
end;

function TGrispLexer.ReadNumber: TGrispToken;
var
  Start, Line, Col: Integer;
  IsFloat: Boolean;
begin
  Line := FLine; Col := FCol;
  Start := FPos;
  IsFloat := False;

  // Handle optional sign
  if CharInSet(FSource[FPos], ['+', '-']) then
    AdvanceChar;

  // Read integer part
  while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
    AdvanceChar;

  // Read fractional part
  if (FSource[FPos] = '.') and CharInSet(PeekChar(1), ['0'..'9']) then
  begin
    IsFloat := True;
    AdvanceChar;
    while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
      AdvanceChar;
  end;

  // Read exponent
  if CharInSet(FSource[FPos], ['e', 'E']) and CharInSet(PeekChar(1), ['0'..'9', '+', '-']) then
  begin
    IsFloat := True;
    AdvanceChar;
    if CharInSet(FSource[FPos], ['+', '-']) then
      AdvanceChar;
    while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
      AdvanceChar;
  end;

  Result.Kind := tkNumber;
  Result.Lexeme := Copy(FSource, Start, FPos - Start);
  Result.Line := Line;
  Result.Column := Col;
end;

function TGrispLexer.ReadIdentifier: TGrispToken;
var
  Start, Line, Col: Integer;
  S: string;
begin
  Line := FLine; Col := FCol;
  Start := FPos;

  // Read identifier (letters, digits, underscore, dot)
  while (FPos <= Length(FSource)) and
        CharInSet(FSource[FPos], ['a'..'z', 'A'..'Z', '0'..'9', '_', '.']) do
    AdvanceChar;

  S := Copy(FSource, Start, FPos - Start);

  Result.Kind := IsKeyword(S);
  Result.Lexeme := S;
  Result.Line := Line;
  Result.Column := Col;
end;

function TGrispLexer.NextToken: TGrispToken;
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

  // Single character tokens
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

    // Operators with possible arrow
    '-':
      begin
        if PeekChar(1) = '>' then
        begin
          Result.Kind := tkArrow;
          Result.Lexeme := '->';
          AdvanceChar;
          AdvanceChar;
          Exit;
        end
        else if CharInSet(PeekChar(1), ['0'..'9']) then
        begin
          Result := ReadNumber;
          Exit;
        end
        else
        begin
          Result.Kind := tkOperator;
          Result.Lexeme := '-';
          AdvanceChar;
          Exit;
        end;
      end;

    '+':
      begin
        if CharInSet(PeekChar(1), ['0'..'9']) then
        begin
          Result := ReadNumber;
          Exit;
        end
        else
        begin
          Result.Kind := tkOperator;
          Result.Lexeme := '+';
          AdvanceChar;
          Exit;
        end;
      end;

    '*', '/':
      begin
        Result.Kind := tkOperator;
        Result.Lexeme := C;
        AdvanceChar;
        Exit;
      end;

    '<':
      begin
        if PeekChar(1) = '=' then
        begin
		  Result.Kind := tkLessEqual;
          Result.Lexeme := '<=';
          AdvanceChar;
          AdvanceChar;
          Exit;
        end
        else if PeekChar(1) = '>' then
        begin
          Result.Kind := tkNotEqual;
          Result.Lexeme := '<>';
          AdvanceChar;
          AdvanceChar;
          Exit;
        end
        else
        begin
          Result.Kind := tkLess;
          Result.Lexeme := '<';
          AdvanceChar;
          Exit;
        end;
      end;

    '>':
      begin
        if PeekChar(1) = '=' then
        begin
          Result.Kind := tkGreaterEqual;
          Result.Lexeme := '>=';
          AdvanceChar;
          AdvanceChar;
          Exit;
        end
        else
        begin
          Result.Kind := tkGreater;
          Result.Lexeme := '>';
          AdvanceChar;
          Exit;
        end;
      end;

    '''', '"':
      begin
        Result := ReadString;
        Exit;
      end;
  end;

  // Numbers
  if CharInSet(C, ['0'..'9']) then
  begin
    Result := ReadNumber;
    Exit;
  end;

  // Identifiers and keywords
  if CharInSet(C, ['a'..'z', 'A'..'Z', '_']) then
  begin
    Result := ReadIdentifier;
    Exit;
  end;

  raise EGrispLexerError.CreateFmt('Invalid character "%s" at %d:%d', [C, FLine, FCol]);
end;

end.
