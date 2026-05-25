unit unit_Parser_TGrispStrategyParser_version_001;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001,
  unit_Lexer_TGrispLexer_version_001,
  unit_Graph_TGrispGraph_version_001,
  unit_Strategy_TGrispStrategyKind_version_001,
  unit_Strategy_TGrispStrategy_version_001,
  unit_Parser_TGrispParserBase_version_001;

type
  TGrispStrategyParser = class(TGrispParserBase)
  private
    function ParseStrategy: TGrispStrategy;
  public
    constructor Create(const ASource: string; AGraph: TGrispGraph);
    constructor CreateShared(Parent: TGrispParserBase); override;
    procedure ParseStrategyDecl;
    procedure ParseFile; override;
  end;

implementation

constructor TGrispStrategyParser.Create(const ASource: string; AGraph: TGrispGraph);
begin
  inherited Create(ASource, AGraph);
end;

constructor TGrispStrategyParser.CreateShared(Parent: TGrispParserBase);
begin
  inherited CreateShared(Parent);
end;

function TGrispStrategyParser.ParseStrategy: TGrispStrategy;
begin
  if FCurrent.Kind = tkKeywordRepeat then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskRepeat);
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if FCurrent.Kind = tkKeywordTry then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskTry);
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if FCurrent.Kind = tkKeywordChoice then
  begin
    Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskChoice);
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if (FCurrent.Kind = tkKeywordPhase) or ((FCurrent.Kind = tkIdentifier) and SameText(FCurrent.Lexeme, 'phase')) then
  begin
    if FCurrent.Kind = tkIdentifier then Advance;
    Expect(tkLParen, '"(" expected');
    Result := TGrispStrategy.Create(gskPhase);
    if FCurrent.Kind = tkNumber then
    begin
      Result.Phase := Trunc(StrToFloat(FCurrent.Lexeme));
      Advance;
      // FIX: Consume the comma after the phase number if present
      if FCurrent.Kind = tkComma then
        Advance;
    end;
    while FCurrent.Kind <> tkRParen do
    begin
      Result.Strategies.Add(ParseStrategy);
      if FCurrent.Kind = tkComma then Advance;
    end;
    Expect(tkRParen, '")" expected');
  end
  else if FCurrent.Kind = tkIdentifier then
  begin
    Result := TGrispStrategy.Create(gskRule);
    Result.RuleName := FCurrent.Lexeme;
    Advance;
  end
  else
    raise EGrispParseError.Create('Strategy expected');
end;

procedure TGrispStrategyParser.ParseStrategyDecl;
var
  StrategyName: string;
  Strat: TGrispStrategy;
begin
  Expect(tkKeywordStrategy, '"strategy" expected');
  StrategyName := FCurrent.Lexeme;
  Expect(tkIdentifier, 'name expected');
  Expect(tkEquals, '"=" expected');
  Strat := ParseStrategy;
  // Store strategy on the graph, not in a parser-owned engine
  FGraph.AddStrategy(StrategyName, Strat);
end;

procedure TGrispStrategyParser.ParseFile;
begin
  // This method should not be called when in shared mode
  // The full parser handles the main loop
  raise EGrispParseError.Create('ParseFile should not be called on shared parser - use TGrispFullParser instead');
end;

end.
