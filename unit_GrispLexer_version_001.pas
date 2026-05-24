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
    else
    begin
      if FSource[FPos] <> #13 then
      begin
        Inc(FCol);
      end;
    end;
    Inc(FPos);
  end;
end;

function TGrispLexer.PeekChar(Offset: Integer): Char;
begin
  if FPos + Offset <= Length(FSource) then
  begin
    Result := FSource[FPos + Offset];
  end
  else
  begin
    Result := #0;
  end;
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
    if FSource[FPos] = '/' then
    begin
      if PeekChar(1) = '/' then
      begin
        AdvanceChar;
        AdvanceChar;
        while (FPos <= Length(FSource)) and not CharInSet(FSource[FPos], [#10, #13]) do
        begin
		  AdvanceChar;
        end;
        Continue;
      end;
      if PeekChar(1) = '*' then
      begin
        AdvanceChar;
        while FPos <= Length(FSource) do
        begin
          if (FSource[FPos] = '*') and (PeekChar(1) = '/') then
          begin
            AdvanceChar;
            AdvanceChar;
            Break;
          end
          else
          begin
            AdvanceChar;
          end;
        end;
        Continue;
      end;
    end;
    Break;
  end;
end;

function TGrispLexer.ReadString: TToken;
var
  Line: Integer;
  Col: Integer;
  Quote: Char;
  Esc: Boolean;
  SB: string;
begin
  Line := FLine;
  Col := FCol;
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
  Start: Integer;
  Line: Integer;
  Col: Integer;
begin
  Line := FLine;
  Col := FCol;
  Start := FPos;
  if CharInSet(FSource[FPos], ['+', '-']) then
  begin
    AdvanceChar;
  end;
  while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
  begin
    AdvanceChar;
  end;
  if (FSource[FPos] = '.') and CharInSet(PeekChar(1), ['0'..'9']) then
  begin
    AdvanceChar;
    while (FPos <= Length(FSource)) and CharInSet(FSource[FPos], ['0'..'9']) do
    begin
      AdvanceChar;
    end;
  end;
  Result.Kind := tkNumber;
  Result.Lexeme := Copy(FSource, Start, FPos - Start);
  Result.Line := Line;
  Result.Column := Col;
end;

function TGrispLexer.ReadIdentifier: TToken;
var
  Start: Integer;
  Line: Integer;
  Col: Integer;
  S: string;
begin
  Line := FLine;
  Col := FCol;
  Start := FPos;
  AdvanceChar;
  while FPos <= Length(FSource) do
  begin
    if CharInSet(FSource[FPos], ['a'..'z', 'A'..'Z', '0'..'9', '_', '.']) then
    begin
      AdvanceChar;
    end
    else
    begin
      Break;
    end;
  end;
  S := Copy(FSource, Start, FPos - Start);
  Result.Lexeme := S;
  Result.Line := Line;
  Result.Column := Col;
  if SameText(S, 'node') then
  begin
    Result.Kind := tkKeywordNode;
  end
  else
  begin
    if SameText(S, 'array') then
    begin
      Result.Kind := tkKeywordArray;
    end
    else
    begin
      if SameText(S, 'where') then
      begin
        Result.Kind := tkKeywordWhere;
      end
      else
      begin
        if SameText(S, 'and') then
        begin
          Result.Kind := tkKeywordAnd;
        end
        else
        begin
          if SameText(S, 'or') then
          begin
            Result.Kind := tkKeywordOr;
          end
          else
          begin
            if SameText(S, 'not') then
            begin
              Result.Kind := tkKeywordNot;
            end
            else
            begin
              if SameText(S, 'mod') then
              begin
                Result.Kind := tkKeywordMod;
              end
              else
              begin
                if SameText(S, 'true') or SameText(S, 'false') then
                begin
                  Result.Kind := tkBoolean;
                end
                else
                begin
                  Result.Kind := tkIdentifier;
                end;
              end;
            end;
          end;
        end;
      end;
    end;
  end;
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
    '{':
      begin
        Result.Kind := tkLBrace;
        Result.Lexeme := '{';
        AdvanceChar;
        Exit;
      end;
    '}':
      begin
        Result.Kind := tkRBrace;
        Result.Lexeme := '}';
        AdvanceChar;
        Exit;
      end;
    '[':
      begin
        Result.Kind := tkLBracket;
        Result.Lexeme := '[';
        AdvanceChar;
        Exit;
      end;
    ']':
      begin
        Result.Kind := tkRBracket;
        Result.Lexeme := ']';
        AdvanceChar;
        Exit;
      end;
    '(':
      begin
        Result.Kind := tkLParen;
        Result.Lexeme := '(';
        AdvanceChar;
        Exit;
      end;
    ')':
      begin
        Result.Kind := tkRParen;
        Result.Lexeme := ')';
        AdvanceChar;
        Exit;
      end;
    ':':
      begin
        Result.Kind := tkColon;
        Result.Lexeme := ':';
        AdvanceChar;
        Exit;
      end;
    '=':
      begin
        Result.Kind := tkEquals;
        Result.Lexeme := '=';
        AdvanceChar;
        Exit;
      end;
    ',':
      begin
        Result.Kind := tkComma;
        Result.Lexeme := ',';
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
        else
        begin
          if PeekChar(1) = '>' then
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
  if CharInSet(C, ['0'..'9', '+', '-']) then
  begin
    Result := ReadNumber;
    Exit;
  end;
  if CharInSet(C, ['a'..'z', 'A'..'Z', '_']) then
  begin
    Result := ReadIdentifier;
    Exit;
  end;
  raise EGrispLexerError.CreateFmt('Invalid character "%s" at %d:%d', [C, FLine, FCol]);
end;

end.
