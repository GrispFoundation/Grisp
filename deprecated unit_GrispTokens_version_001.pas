unit unit_GrispTokens_version_001;

interface

type
  TTokenKind = (
    tkEOF,
    tkIdentifier,
    tkNumber,
    tkString,
    tkBoolean,
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
    tkKeywordChoice,
    tkLBrace,
    tkRBrace,
    tkLBracket,
    tkRBracket,
    tkLParen,
    tkRParen,
    tkLess,
    tkGreater,
    tkLessEqual,
    tkGreaterEqual,
    tkNotEqual,
    tkColon,
    tkEquals,
    tkComma,
    tkSemicolon,
    tkOperator,
    tkArrow
  );

  TToken = record
    Kind: TTokenKind;
    Lexeme: string;
    Line: Integer;
    Column: Integer;
  end;

implementation

end.
