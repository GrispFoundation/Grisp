unit unit_Token_TGrispTokenHelper_version_001;

interface

uses
  System.SysUtils,                              // Added for SameText
  unit_Token_TGrispTokenKind_version_001,
  unit_Token_TGrispToken_version_001;

type
  TGrispTokenHelper = record
  private
    FToken: TGrispToken;
  public
    constructor Create(const AToken: TGrispToken);

    function IsEOF: Boolean;
    function IsIdentifier: Boolean;
    function IsNumber: Boolean;
    function IsString: Boolean;
    function IsBoolean: Boolean;
    function IsKeyword(const Keyword: string): Boolean;
    function IsKeywordNode: Boolean;
    function IsKeywordArray: Boolean;
    function IsKeywordWhere: Boolean;
    function IsKeywordAnd: Boolean;
    function IsKeywordOr: Boolean;
    function IsKeywordNot: Boolean;
    function IsKeywordMod: Boolean;
    function IsKeywordPhase: Boolean;
    function IsKeywordTemp: Boolean;
    function IsKeywordDelete: Boolean;
    function IsKeywordRemove: Boolean;
    function IsKeywordType: Boolean;
    function IsKeywordStrategy: Boolean;
    function IsKeywordRepeat: Boolean;
    function IsKeywordTry: Boolean;
    function IsKeywordChoice: Boolean;
    function IsLBrace: Boolean;
    function IsRBrace: Boolean;
    function IsLBracket: Boolean;
    function IsRBracket: Boolean;
    function IsLParen: Boolean;
    function IsRParen: Boolean;
    function IsColon: Boolean;
    function IsEquals: Boolean;
    function IsComma: Boolean;
    function IsSemicolon: Boolean;
    function IsArrow: Boolean;

    property Token: TGrispToken read FToken;
  end;

implementation

constructor TGrispTokenHelper.Create(const AToken: TGrispToken);
begin
  FToken := AToken;
end;

function TGrispTokenHelper.IsEOF: Boolean;
begin
  Result := FToken.Kind = tkEOF;
end;

function TGrispTokenHelper.IsIdentifier: Boolean;
begin
  Result := FToken.Kind = tkIdentifier;
end;

function TGrispTokenHelper.IsNumber: Boolean;
begin
  Result := FToken.Kind = tkNumber;
end;

function TGrispTokenHelper.IsString: Boolean;
begin
  Result := FToken.Kind = tkString;
end;

function TGrispTokenHelper.IsBoolean: Boolean;
begin
  Result := FToken.Kind = tkBoolean;
end;

function TGrispTokenHelper.IsKeyword(const Keyword: string): Boolean;
begin
  Result := FToken.IsKeyword and SameText(FToken.Lexeme, Keyword);
end;

function TGrispTokenHelper.IsKeywordNode: Boolean;
begin
  Result := FToken.Kind = tkKeywordNode;
end;

function TGrispTokenHelper.IsKeywordArray: Boolean;
begin
  Result := FToken.Kind = tkKeywordArray;
end;

function TGrispTokenHelper.IsKeywordWhere: Boolean;
begin
  Result := FToken.Kind = tkKeywordWhere;
end;

function TGrispTokenHelper.IsKeywordAnd: Boolean;
begin
  Result := FToken.Kind = tkKeywordAnd;
end;

function TGrispTokenHelper.IsKeywordOr: Boolean;
begin
  Result := FToken.Kind = tkKeywordOr;
end;

function TGrispTokenHelper.IsKeywordNot: Boolean;
begin
  Result := FToken.Kind = tkKeywordNot;
end;

function TGrispTokenHelper.IsKeywordMod: Boolean;
begin
  Result := FToken.Kind = tkKeywordMod;
end;

function TGrispTokenHelper.IsKeywordPhase: Boolean;
begin
  Result := FToken.Kind = tkKeywordPhase;
end;

function TGrispTokenHelper.IsKeywordTemp: Boolean;
begin
  Result := FToken.Kind = tkKeywordTemp;
end;

function TGrispTokenHelper.IsKeywordDelete: Boolean;
begin
  Result := FToken.Kind = tkKeywordDelete;
end;

function TGrispTokenHelper.IsKeywordRemove: Boolean;
begin
  Result := FToken.Kind = tkKeywordRemove;
end;

function TGrispTokenHelper.IsKeywordType: Boolean;
begin
  Result := FToken.Kind = tkKeywordType;
end;

function TGrispTokenHelper.IsKeywordStrategy: Boolean;
begin
  Result := FToken.Kind = tkKeywordStrategy;
end;

function TGrispTokenHelper.IsKeywordRepeat: Boolean;
begin
  Result := FToken.Kind = tkKeywordRepeat;
end;

function TGrispTokenHelper.IsKeywordTry: Boolean;
begin
  Result := FToken.Kind = tkKeywordTry;
end;

function TGrispTokenHelper.IsKeywordChoice: Boolean;
begin
  Result := FToken.Kind = tkKeywordChoice;
end;

function TGrispTokenHelper.IsLBrace: Boolean;
begin
  Result := FToken.Kind = tkLBrace;
end;

function TGrispTokenHelper.IsRBrace: Boolean;
begin
  Result := FToken.Kind = tkRBrace;
end;

function TGrispTokenHelper.IsLBracket: Boolean;
begin
  Result := FToken.Kind = tkLBracket;
end;

function TGrispTokenHelper.IsRBracket: Boolean;
begin
  Result := FToken.Kind = tkRBracket;
end;

function TGrispTokenHelper.IsLParen: Boolean;
begin
  Result := FToken.Kind = tkLParen;
end;

function TGrispTokenHelper.IsRParen: Boolean;
begin
  Result := FToken.Kind = tkRParen;
end;

function TGrispTokenHelper.IsColon: Boolean;
begin
  Result := FToken.Kind = tkColon;
end;

function TGrispTokenHelper.IsEquals: Boolean;
begin
  Result := FToken.Kind = tkEquals;
end;

function TGrispTokenHelper.IsComma: Boolean;
begin
  Result := FToken.Kind = tkComma;
end;

function TGrispTokenHelper.IsSemicolon: Boolean;
begin
  Result := FToken.Kind = tkSemicolon;
end;

function TGrispTokenHelper.IsArrow: Boolean;
begin
  Result := FToken.Kind = tkArrow;
end;

end.
