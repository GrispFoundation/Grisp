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
    tkLBrace,    // {
    tkRBrace,    // }
    tkLBracket,  // [
    tkRBracket,  // ]
    tkLess,      // <
    tkGreater,   // >
    tkColon,     // :
    tkEquals,    // =
    tkComma      // ,
  );

  TToken = record
    Kind: TTokenKind;
    Lexeme: string;
    Line: Integer;
    Column: Integer;
  end;

implementation

end.
