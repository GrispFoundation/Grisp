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
end;

destructor TDocument.Destroy;
begin
  FRoot.Free;
  inherited;
end;

function TDocument.Parse(const AText: string): Boolean;
var
  Lexer: TMarkerLexer;
  Tok: TToken;
  Current: TBlock;
  Stack: TStack<TBlock>;
begin
  Result := False;
  Lexer := TMarkerLexer.Create(AText);
  Stack := TStack<TBlock>.Create;
  try
    Current := FRoot;
    while True do
    begin
      Tok := Lexer.NextToken;
      if Tok.Kind = tkEOF then Break;
      case Tok.Kind of
        tkMarkerBegin:
          begin
            var BlockName := Trim(Copy(Tok.Text, 8, Length(Tok.Text)-8-1));
            var NewBlock := TBlock.Create(BlockName, '');
            Current.Children.Add(NewBlock);
            Stack.Push(Current);
            Current := NewBlock;
          end;
        tkMarkerEnd:
          begin
            if Stack.Count > 0 then
              Current := Stack.Pop;
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
    Result := True;
  finally
    Lexer.Free;
    Stack.Free;
  end;
end;

end.