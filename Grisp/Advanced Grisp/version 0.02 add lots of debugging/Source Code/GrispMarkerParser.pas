{$DEFINE DEBUG}
unit GrispMarkerParser;

interface

uses
  SysUtils, Classes, Generics.Collections, GrispMarkerLexer;

type
  TBlock = class
  public
    Name: string;
    Content: string;
    Children: TList<TBlock>;
    constructor Create(const AName, AContent: string);
    destructor Destroy; override;
    function FindChild(const AName: string): TBlock;
    function GetContent(const AName: string): string;
  end;

  TDocument = class
  private
    FRoot: TBlock;
    FDebugLog: TStringList;
    procedure Debug(const Msg: string);
  public
    constructor Create;
    destructor Destroy; override;
    function Parse(const AText: string): Boolean;
    property Root: TBlock read FRoot;
  end;

implementation

{ TBlock }

constructor TBlock.Create(const AName, AContent: string);
begin
  Name := AName;
  Content := AContent;
  Children := TList<TBlock>.Create;
end;

destructor TBlock.Destroy;
var
  b: TBlock;
begin
  for b in Children do b.Free;
  Children.Free;
  inherited;
end;

function TBlock.FindChild(const AName: string): TBlock;
var
  b: TBlock;
begin
  for b in Children do
    if SameText(b.Name, AName) then Exit(b);
  Result := nil;
end;

function TBlock.GetContent(const AName: string): string;
var
  b: TBlock;
begin
  b := FindChild(AName);
  if Assigned(b) then Result := b.Content
  else Result := '';
end;

{ TDocument }

constructor TDocument.Create;
begin
  FRoot := TBlock.Create('ROOT', '');
  FDebugLog := TStringList.Create;
  FDebugLog.Add('=== MarkerParser started ===');
end;

destructor TDocument.Destroy;
begin
  FRoot.Free;
  FDebugLog.Free;
  inherited;
end;

procedure TDocument.Debug(const Msg: string);
begin
  {$IFDEF DEBUG}
  FDebugLog.Add(Msg);
  Writeln(ErrOutput, '[MarkerParser] ', Msg);
  {$ENDIF}
end;

function TDocument.Parse(const AText: string): Boolean;
var
  Lexer: TMarkerLexer;
  Tok: TToken;
  Current: TBlock;
  Stack: TStack<TBlock>;
  tokenCount: Integer;
  BlockName: string;
begin
  Debug('Parse: starting parse, text length = ' + IntToStr(Length(AText)));
  Lexer := TMarkerLexer.Create(AText);
  Stack := TStack<TBlock>.Create;
  try
    Current := FRoot;
    tokenCount := 0;
    while True do
    begin
      Tok := Lexer.NextToken;
      if Tok.Kind = tkEOF then Break;
      Inc(tokenCount);
      if (tokenCount mod 20 = 0) or (Tok.Kind in [tkMarkerBegin, tkMarkerEnd]) then
        Debug(Format('Token #%d: kind=%d, text="%s", line=%d, col=%d',
          [tokenCount, Ord(Tok.Kind), Tok.Text, Tok.Line, Tok.Col]));
      case Tok.Kind of
        tkMarkerBegin:
          begin
            // Tok.Text is like "⟦BEGINPROGRAM" or "⟦BEGINMETADATA"
            // Extract block name by removing the "⟦BEGIN" prefix (6 characters)
            BlockName := Copy(Tok.Text, 7, MaxInt);
            BlockName := Trim(BlockName);
            Debug('BEGIN: ' + BlockName);
            var NewBlock := TBlock.Create(BlockName, '');
            Current.Children.Add(NewBlock);
            Stack.Push(Current);
            Current := NewBlock;
          end;
        tkMarkerEnd:
          begin
            // Tok.Text is like "⟦ENDPROGRAM" or "⟦ENDMETADATA"
            // Extract block name by removing the "⟦END" prefix (4 characters)
            BlockName := Copy(Tok.Text, 5, MaxInt);
            BlockName := Trim(BlockName);
            Debug('END: ' + BlockName);
            if Stack.Count > 0 then
              Current := Stack.Pop
            else
              Debug('Warning: END without matching BEGIN');
          end;
        tkContent:
          begin
            if Assigned(Current) then
              Current.Content := Current.Content + Tok.Text;
          end;
      else
        if Assigned(Current) then
          Current.Content := Current.Content + Tok.Text;
      end;
    end;
    Debug('Parse: completed, ' + IntToStr(tokenCount) + ' tokens processed');
    Debug('Parse: root has ' + IntToStr(FRoot.Children.Count) + ' children');
    for var i := 0 to FRoot.Children.Count - 1 do
      Debug('  root child[' + IntToStr(i) + '] = ' + FRoot.Children[i].Name);
    FDebugLog.SaveToFile('parser_debug.log');
    Result := True;
  finally
    Lexer.Free;
    Stack.Free;
  end;
end;

end.
