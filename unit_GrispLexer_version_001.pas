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
  public
    constructor Create(const ASource: string);
    function NextToken: TToken;
  end;

implementation

{ TGrispLexer }

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
    else if FSource[FPos] = #13 then
    begin
      if (FPos + 1 <= Length(FSource)) and (FSource[FPos + 1] = #10) then
      begin
        // Handled by LF (#10)
      end
      else
      begin
        Inc(FLine);
        FCol := 1;
      end;
    end
    else
    begin
      Inc(FCol);
    end;
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
var
  C: Char;
begin
  while FPos <= Length(FSource) do
  begin
    C := FSource[FPos];
    if (C = ' ') or (C = #9) or (C = #13) or (C = #10) then
    begin
      AdvanceChar;
    end
    else if (C = '/') and (PeekChar(1) = '/') then
    begin
      AdvanceChar; // '/'
      AdvanceChar; // '/'
      while (FPos <= Length(FSource)) and (FSource[FPos] <> #13) and (FSource[FPos] <> #10) do
      begin
        AdvanceChar;
      end;
    end
    else if (C = '/') and (PeekChar(1) = '*') then
    begin
      AdvanceChar; // '/'
      AdvanceChar; // '*'
      while FPos <= Length(FSource) do
      begin
        if (FSource[FPos] = '*') and (PeekChar(1) = '/') then
        begin
          AdvanceChar; // '*'
          AdvanceChar; // '/'
          Break;
        end
        else
        begin
          AdvanceChar;
        end;
      end;
    end
    else
    begin
      Break;
    end;
  end;
end;

function TGrispLexer.NextToken: TToken;
var
  C, NextC, StartQuote: Char;
  LexemeStart: Integer;
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

  // 1. Single character symbols
  case C of
    '{': begin Result.Kind := tkLBrace; Result.Lexeme := '{'; AdvanceChar; Exit; end;
    '}': begin Result.Kind := tkRBrace; Result.Lexeme := '}'; AdvanceChar; Exit; end;
    '[': begin Result.Kind := tkLBracket; Result.Lexeme := '['; AdvanceChar; Exit; end;
    ']': begin Result.Kind := tkRBracket; Result.Lexeme := ']'; AdvanceChar; Exit; end;
    '<': begin Result.Kind := tkLess; Result.Lexeme := '<'; AdvanceChar; Exit; end;
    '>': begin Result.Kind := tkGreater; Result.Lexeme := '>'; AdvanceChar; Exit; end;
    ':': begin Result.Kind := tkColon; Result.Lexeme := ':'; AdvanceChar; Exit; end;
    '=': begin Result.Kind := tkEquals; Result.Lexeme := '='; AdvanceChar; Exit; end;
    ',': begin Result.Kind := tkComma; Result.Lexeme := ','; AdvanceChar; Exit; end;
  end;

  // 2. String literal
  if (C = '''') or (C = '"') then
  begin
    StartQuote := C;
    Result.Kind := tkString;
    LexemeStart := FPos;
    AdvanceChar; // Skip opening quote
    while (FPos <= Length(FSource)) and (FSource[FPos] <> StartQuote) do
    begin
      AdvanceChar;
    end;
    if FPos <= Length(FSource) then
      AdvanceChar; // Skip closing quote
    
    Result.Lexeme := Copy(FSource, LexemeStart, FPos - LexemeStart);
    Exit;
  end;

  // 3. Number literal (handles positive/negative numbers)
  if ((C >= '0') and (C <= '9')) or
     (((C = '-') or (C = '+')) and (PeekChar(1) >= '0') and (PeekChar(1) <= '9')) then
  begin
    Result.Kind := tkNumber;
    LexemeStart := FPos;
    AdvanceChar; // Skip sign or first digit
    
    while (FPos <= Length(FSource)) and (FSource[FPos] >= '0') and (FSource[FPos] <= '9') do
    begin
      AdvanceChar;
    end;
    
    // Optional decimal part
    if (FSource[FPos] = '.') and (PeekChar(1) >= '0') and (PeekChar(1) <= '9') then
    begin
      AdvanceChar; // Skip '.'
      while (FPos <= Length(FSource)) and (FSource[FPos] >= '0') and (FSource[FPos] <= '9') do
      begin
        AdvanceChar;
      end;
    end;
    
    Result.Lexeme := Copy(FSource, LexemeStart, FPos - LexemeStart);
    Exit;
  end;

  // 4. Identifier / Keyword
  if ((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or (C = '_') then
  begin
    Result.Kind := tkIdentifier;
    LexemeStart := FPos;
    AdvanceChar;
    while FPos <= Length(FSource) do
    begin
      NextC := FSource[FPos];
      if ((NextC >= 'a') and (NextC <= 'z')) or
         ((NextC >= 'A') and (NextC <= 'Z')) or
         ((NextC >= '0') and (NextC <= '9')) or
         (NextC = '_') or
         (NextC = '.') then
      begin
        AdvanceChar;
      end
      else
      begin
        Break;
      end;
    end;
    Result.Lexeme := Copy(FSource, LexemeStart, FPos - LexemeStart);
    
    // Check for keywords
    if SameText(Result.Lexeme, 'node') then
      Result.Kind := tkKeywordNode
    else if SameText(Result.Lexeme, 'array') then
      Result.Kind := tkKeywordArray
    else if SameText(Result.Lexeme, 'true') or SameText(Result.Lexeme, 'false') then
      Result.Kind := tkBoolean;
    Exit;
  end;

  raise EGrispLexerError.CreateFmt('Invalid character "%s" at line %d, column %d', [C, FLine, FCol]);
end;

end.
