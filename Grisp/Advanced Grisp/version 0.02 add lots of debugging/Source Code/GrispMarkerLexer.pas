unit GrispMarkerLexer;

interface

uses
  SysUtils, Classes;

type
  TTokenKind = (tkEOF, tkMarkerBegin, tkMarkerEnd, tkIdent, tkString, tkNumber, tkContent);

  TToken = record
    Kind: TTokenKind;
    Text: string;
    Line: Integer;
    Col: Integer;
  end;

  TMarkerLexer = class
  private
    FText: string;
    FPos: Integer;
    FLine: Integer;
    FCol: Integer;
    function Peek: WideChar;
    function NextChar: WideChar;
    procedure SkipWhitespaceAndComments;
    function ReadIdent: TToken;
    function ReadString: TToken;
    function ReadNumber: TToken;
    function ReadContent: TToken;
    procedure Debug(const Msg: string);
  public
    constructor Create(const AText: string);
    function NextToken: TToken;
  end;

implementation

const
  MARKER_BEGIN = '⟦BEGIN ';
  MARKER_END   = '⟦END ';
  MARKER_CLOSE = '⟧';

constructor TMarkerLexer.Create(const AText: string);
begin
  FText := AText;
  FPos := 1;
  FLine := 1;
  FCol := 1;
end;

procedure TMarkerLexer.Debug(const Msg: string);
begin
  {$IFDEF DEBUG}
  Writeln(ErrOutput, '[Lexer] ', Msg);
  {$ENDIF}
end;

function TMarkerLexer.Peek: WideChar;
begin
  if FPos > Length(FText) then Exit(#0);
  Result := FText[FPos];
end;

function TMarkerLexer.NextChar: WideChar;
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

procedure TMarkerLexer.SkipWhitespaceAndComments;
var
  c: WideChar;
begin
  while True do
  begin
    c := Peek;
    if c = #0 then Break;
    if CharInSet(c, [' ', #9, #10, #13]) then
      NextChar
    else if (c = '/') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '/') then
    begin
      while (Peek <> #0) and (Peek <> #10) do NextChar;
    end
    else if (c = '/') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '*') then
    begin
      NextChar; NextChar;
      while not ((Peek = #0) or ((Peek = '*') and (FPos <= Length(FText)-1) and (FText[FPos+1] = '/'))) do
        NextChar;
      if Peek <> #0 then begin NextChar; NextChar; end;
    end
    else Break;
  end;
end;

function TMarkerLexer.ReadIdent: TToken;
var
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    while CharInSet(Peek, ['A'..'Z','a'..'z','0'..'9','_','-']) do
      sb.Append(NextChar);
    Result.Kind := tkIdent;
    Result.Text := sb.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    sb.Free;
  end;
end;

function TMarkerLexer.ReadString: TToken;
var
  sb: TStringBuilder;
  c: WideChar;
begin
  sb := TStringBuilder.Create;
  try
    NextChar; // skip opening "
    while Peek <> '"' do
    begin
      c := Peek;
      if c = #0 then Break;
      if c = '\' then
      begin
        NextChar;
        case Peek of
          'n': sb.Append(#10);
          'r': sb.Append(#13);
          't': sb.Append(#9);
          '"': sb.Append('"');
          '\': sb.Append('\');
        else
          sb.Append(NextChar);
        end;
      end
      else
        sb.Append(NextChar);
    end;
    NextChar; // skip closing "
    Result.Kind := tkString;
    Result.Text := sb.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    sb.Free;
  end;
end;

function TMarkerLexer.ReadNumber: TToken;
var
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    while CharInSet(Peek, ['0'..'9','.']) do
      sb.Append(NextChar);
    Result.Kind := tkNumber;
    Result.Text := sb.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    sb.Free;
  end;
end;

function TMarkerLexer.ReadContent: TToken;
var
  sb: TStringBuilder;
  c: WideChar;
begin
  sb := TStringBuilder.Create;
  try
    while True do
    begin
      c := Peek;
      if c = #0 then Break;
      if c = '⟦' then Break;
      sb.Append(NextChar);
    end;
    Result.Kind := tkContent;
    Result.Text := sb.ToString;
    Result.Line := FLine;
    Result.Col := FCol;
  finally
    sb.Free;
  end;
end;

function TMarkerLexer.NextToken: TToken;
var
  c: WideChar;
  sb: TStringBuilder;
  tokenText: string;
  markerType: string;
begin
  SkipWhitespaceAndComments;
  c := Peek;
  Result.Line := FLine;
  Result.Col := FCol;
  if c = #0 then
  begin
    Result.Kind := tkEOF;
    Result.Text := '';
    Exit;
  end;

  // Detect marker: starts with '⟦'
  if c = '⟦' then
  begin
    Debug('Marker detected');
    sb := TStringBuilder.Create;
    try
      // Read until we see a space (the marker type)
      while (Peek <> #0) and (Peek <> ' ') do
        sb.Append(NextChar);
      // Now sb = "⟦BEGIN" or "⟦END"
      markerType := sb.ToString;
      // Skip the space
      if Peek = ' ' then NextChar;
      // Read the block name (identifier) until ⟧
      while (Peek <> #0) and (Peek <> '⟧') do
        sb.Append(NextChar);
      // Skip the closing ⟧
      if Peek = '⟧' then NextChar;
      tokenText := sb.ToString;
      Result.Text := tokenText;
      // Determine marker kind using the markerType variable
      if markerType = '⟦BEGIN' then
      begin
        Result.Kind := tkMarkerBegin;
        Debug('BEGIN marker: ' + tokenText);
      end
      else if markerType = '⟦END' then
      begin
        Result.Kind := tkMarkerEnd;
        Debug('END marker: ' + tokenText);
      end
      else
      begin
        Result.Kind := tkContent;
        Debug('Unknown marker type: ' + markerType);
      end;
    finally
      sb.Free;
    end;
    Exit;
  end;

  // Otherwise read as content
  Result := ReadContent;
end;

end.
