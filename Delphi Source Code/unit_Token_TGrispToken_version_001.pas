unit unit_Token_TGrispToken_version_001;

interface

uses
  System.SysUtils,
  System.TypInfo,
  unit_Token_TGrispTokenKind_version_001;

type
  TGrispToken = record
    Kind: TGrispTokenKind;
    Lexeme: string;
    Line: Integer;
    Column: Integer;

    function IsKeyword: Boolean;
    function IsOperator: Boolean;
    function IsLiteral: Boolean;
    function ToString: string;
  end;

implementation

function TGrispToken.IsKeyword: Boolean;
begin
  Result := Kind in [
    tkKeywordNode,
    tkKeywordArray,
    tkKeywordWhere,
    tkKeywordAnd,
    tkKeywordOr,
    tkKeywordNot,
    tkKeywordMod,
    tkKeywordPhase,
    tkKeywordTemp,
    tkKeywordDelete,
    tkKeywordRemove,
    tkKeywordType,
    tkKeywordStrategy,
    tkKeywordRepeat,
    tkKeywordTry,
    tkKeywordChoice
  ];
end;

function TGrispToken.IsOperator: Boolean;
begin
  Result := Kind in [
    tkOperator,
    tkLess,
    tkGreater,
    tkLessEqual,
    tkGreaterEqual,
    tkNotEqual,
    tkEquals,
    tkArrow
  ];
end;

function TGrispToken.IsLiteral: Boolean;
begin
  Result := Kind in [
    tkNumber,
    tkString,
    tkBoolean,
    tkIdentifier
  ];
end;

function TGrispToken.ToString: string;
begin
  Result := Format('Token(%s, "%s", %d:%d)',
    [GetEnumName(TypeInfo(TGrispTokenKind), Ord(Kind)),
     Lexeme, Line, Column]);
end;

end.
