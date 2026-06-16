unit Grisp.JSON;

interface

uses
  System.SysUtils, System.Character, System.Generics.Collections, System.Generics.Defaults, Grisp.Core;

function ParseJSON(const AJSON: string): TValue;
function SerializeJSON(const AVal: TValue): string;

function IdentToValue(const AId: TIdentifier): TValue;
function ValueToIdent(const AVal: TValue): TIdentifier;

implementation

type
  TJSONParser = record
  private
    FInput: string;
    FPos: Integer;
    FLen: Integer;
    procedure SkipWhitespace;
    function Match(const Expected: string): Boolean;
    function ReadChar: Char;
    function PeekChar: Char;
    function ParseValue: TValue;
    function ParseString: string;
    function ParseNumber: Int64;
    function ParseList: TValue;
    function ParseMap: TValue;
    procedure Error(const Msg: string);
  public
    class function Parse(const AJSON: string): TValue; static;
  end;

function IdentToValue(const AId: TIdentifier): TValue;
begin
  Result := TValue.CreateIdentifier(AId.TypeName, AId.SequenceNumber);
end;

function ValueToIdent(const AVal: TValue): TIdentifier;
begin
  if AVal.ValType <> vtIdentifier then
    raise Exception.Create('Expected identifier value, found ' + AVal.ToString);
  Result := AVal.IdValue;
end;

{ TJSONParser }

procedure TJSONParser.SkipWhitespace;
begin
  while (FPos <= FLen) and (FInput[FPos] <= ' ') do
    Inc(FPos);
end;

function TJSONParser.Match(const Expected: string): Boolean;
var
  i: Integer;
begin
  if FPos + Length(Expected) - 1 > FLen then Exit(False);
  for i := 1 to Length(Expected) do
    if FInput[FPos + i - 1] <> Expected[i] then Exit(False);
  Inc(FPos, Length(Expected));
  Result := True;
end;

function TJSONParser.ReadChar: Char;
begin
  if FPos > FLen then Result := #0
  else begin Result := FInput[FPos]; Inc(FPos); end;
end;

function TJSONParser.PeekChar: Char;
begin
  if FPos > FLen then Result := #0
  else Result := FInput[FPos];
end;

procedure TJSONParser.Error(const Msg: string);
begin
  raise Exception.Create(Msg + ' at position ' + IntToStr(FPos));
end;

function TJSONParser.ParseString: string;
var
  C: Char;
  HexCode: string;
  i: Integer;
begin
  if ReadChar <> '"' then Error('Expected string start "');
  Result := '';
  while FPos <= FLen do
  begin
    C := ReadChar;
    if C = '"' then Exit;
    if C = '\' then
    begin
      C := ReadChar;
      case C of
        '"': Result := Result + '"';
        '\': Result := Result + '\';
        '/': Result := Result + '/';
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'u':
          begin
            HexCode := '';
            for i := 1 to 4 do HexCode := HexCode + ReadChar;
            Result := Result + Char(StrToInt('$' + HexCode));
          end;
      else
        Result := Result + C;
      end;
    end
    else
      Result := Result + C;
  end;
  Error('Unterminated string');
end;

function TJSONParser.ParseNumber: Int64;
var
  NumStr: string;
  Sign: Int64;
begin
  NumStr := '';
  Sign := 1;
  if PeekChar = '-' then
  begin
    Sign := -1;
    ReadChar;
  end;
  while (FPos <= FLen) and (FInput[FPos] >= '0') and (FInput[FPos] <= '9') do
    NumStr := NumStr + ReadChar;
  if NumStr = '' then Error('Expected digits');
  Result := Sign * StrToInt64(NumStr);
end;

function TJSONParser.ParseList: TValue;
var
  Elements: TList<TValue>;
begin
  if ReadChar <> '[' then Error('Expected [');
  Elements := TList<TValue>.Create;
  try
    SkipWhitespace;
    if PeekChar = ']' then
    begin
      ReadChar;
      Result := TValue.CreateList(Elements.ToArray);
      Exit;
    end;
    while True do
    begin
      Elements.Add(ParseValue);
      SkipWhitespace;
      if PeekChar = ']' then
      begin
        ReadChar;
        Break;
      end;
      if ReadChar <> ',' then Error('Expected , or ]');
	end;
    Result := TValue.CreateList(Elements.ToArray);
  finally
    Elements.Free;
  end;
end;

function TJSONParser.ParseMap: TValue;
var
  Entries: TList<TPair<string, TValue>>;
  Key: string;
  Val: TValue;
begin
  if ReadChar <> '{' then Error('Expected {');
  Entries := TList<TPair<string, TValue>>.Create;
  try
    SkipWhitespace;
    if PeekChar = '}' then
    begin
      ReadChar;
      Result := TValue.CreateMap(Entries.ToArray);
      Exit;
    end;
    while True do
    begin
      SkipWhitespace;
      Key := ParseString;
      SkipWhitespace;
      if ReadChar <> ':' then Error('Expected :');
      Val := ParseValue;
      Entries.Add(TPair<string, TValue>.Create(Key, Val));
      SkipWhitespace;
      if PeekChar = '}' then
      begin
        ReadChar;
        Break;
      end;
      if ReadChar <> ',' then Error('Expected , or }');
    end;
    Entries.Sort(TComparer<TPair<string, TValue>>.Construct(
      function(const Left, Right: TPair<string, TValue>): Integer
      begin
        Result := CompareUTF8(Left.Key, Right.Key);
      end
    ));
    Result := TValue.CreateMap(Entries.ToArray);
  finally
    Entries.Free;
  end;
end;

function TJSONParser.ParseValue: TValue;
var
  C: Char;
  S: string;
  DotIdx, i: Integer;
  IsFixed, IsIdent: Boolean;
  ScaleVal: Byte;
  FPValue: Int64;
  IdSeq: Int64;
  IdType: string;
begin
  SkipWhitespace;
  C := PeekChar;
  if C = '{' then Exit(ParseMap);
  if C = '[' then Exit(ParseList);
  if C = '"' then
  begin
    S := ParseString;
    IsFixed := False;
    DotIdx := Pos('.', S);
    if (DotIdx > 1) and (DotIdx < Length(S)) then
	begin
      IsFixed := True;
      for i := 1 to Length(S) do
      begin
        if i = DotIdx then Continue;
        if (i = 1) and (S[1] = '-') then Continue;
        if not S[i].IsDigit then
        begin
          IsFixed := False;
          Break;
        end;
      end;
    end;
    if IsFixed then
    begin
      ScaleVal := Length(S) - DotIdx;
      if ScaleVal <= 18 then
      begin
        FPValue := StrToInt64(Copy(S, 1, DotIdx - 1) + Copy(S, DotIdx + 1, ScaleVal));
        Exit(TValue.CreateFixedPoint(FPValue, ScaleVal));
      end;
    end;
    IsIdent := False;
    DotIdx := Pos(':', S);
    if (DotIdx > 1) and (DotIdx < Length(S)) then
    begin
      IsIdent := (S[1].IsLetter or (S[1] = '_'));
      if IsIdent then
      begin
        for i := 2 to DotIdx - 1 do
          if not (S[i].IsLetterOrDigit or (S[i] = '_') or (S[i] = '-')) then
          begin
            IsIdent := False;
            Break;
          end;
      end;
      if IsIdent then
        for i := DotIdx + 1 to Length(S) do
          if not S[i].IsDigit then
          begin
            IsIdent := False;
            Break;
          end;
    end;
    if IsIdent then
    begin
      IdType := Copy(S, 1, DotIdx - 1);
      IdSeq := StrToInt64(Copy(S, DotIdx + 1, Length(S) - DotIdx));
      Exit(TValue.CreateIdentifier(IdType, IdSeq));
    end;
    Exit(TValue.CreateString(S));
  end;
  if (C = '-') or ((C >= '0') and (C <= '9')) then
    Exit(TValue.CreateInteger(ParseNumber));
  if Match('true') then Exit(TValue.CreateBoolean(True));
  if Match('false') then Exit(TValue.CreateBoolean(False));
  if Match('null') then Exit(TValue.CreateNull);
  Error('Unexpected token character: ' + C);
  Result := TValue.CreateNull;
end;

class function TJSONParser.Parse(const AJSON: string): TValue;
var
  Parser: TJSONParser;
begin
  Parser.FInput := AJSON;
  Parser.FPos := 1;
  Parser.FLen := Length(AJSON);
  Result := Parser.ParseValue;
  Parser.SkipWhitespace;
  if Parser.FPos <= Parser.FLen then
    Parser.Error('Extra characters after JSON value');
end;

function ParseJSON(const AJSON: string): TValue;
begin
  Result := TJSONParser.Parse(AJSON);
end;

function EscapeJSONString(const S: string): string;
var
  C: Char;
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #12: Result := Result + '\f';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

function SerializeJSON(const AVal: TValue): string;
var
  S: string;
  i: Integer;
begin
  case AVal.ValType of
    vtNull: Result := 'null';
    vtInteger: Result := IntToStr(AVal.IntValue);
    vtFixedPoint: Result := '"' + AVal.FixValue.ToString + '"';
    vtBoolean: if AVal.BoolValue then Result := 'true' else Result := 'false';
    vtString: Result := '"' + EscapeJSONString(AVal.StrValue) + '"';
    vtIdentifier: Result := '"' + AVal.IdValue.ToString + '"';
    vtList:
      begin
        S := '[';
        for i := 0 to High(AVal.ListValue) do
        begin
          if i > 0 then S := S + ',';
          S := S + SerializeJSON(AVal.ListValue[i]);
        end;
        S := S + ']';
        Result := S;
      end;
    vtMap:
      begin
        S := '{';
        for i := 0 to High(AVal.MapValue) do
        begin
          if i > 0 then S := S + ',';
          S := S + '"' + EscapeJSONString(AVal.MapValue[i].Key) + '":' + SerializeJSON(AVal.MapValue[i].Value);
        end;
        S := S + '}';
        Result := S;
      end;
  else
    Result := 'null';
  end;
end;

end.
