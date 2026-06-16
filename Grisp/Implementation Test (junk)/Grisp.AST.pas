unit Grisp.AST;

interface

uses
  System.SysUtils, System.Generics.Collections, Grisp.Core;

type
  TExpr = class
  public
    destructor Destroy; override;
  end;

  TExprLiteral = class(TExpr)
  public
    Value: TValue;
    constructor Create(const AValue: TValue);
  end;

  TExprVar = class(TExpr)
  public
    VarName: string;
    constructor Create(const AVarName: string);
  end;

  TExprField = class(TExpr)
  public
    VarName: string;
    FieldName: string;
    constructor Create(const AVarName, AFieldName: string);
  end;

  TExprBinary = class(TExpr)
  public
    Op: string;
    Left: TExpr;
    Right: TExpr;
    constructor Create(const AOp: string; ALeft, ARight: TExpr);
    destructor Destroy; override;
  end;

  TExprLen = class(TExpr)
  public
    Expr: TExpr;
    constructor Create(AExpr: TExpr);
    destructor Destroy; override;
  end;

  TExprToFixed = class(TExpr)
  public
    Expr: TExpr;
    Scale: Byte;
    constructor Create(AExpr: TExpr; AScale: Byte);
    destructor Destroy; override;
  end;

  TExprToInteger = class(TExpr)
  public
    Expr: TExpr;
    constructor Create(AExpr: TExpr);
    destructor Destroy; override;
  end;

  TPatternType = (ptNode, ptEdge);

  TPattern = class
  public
    PatternType: TPatternType;
    VarName: string;
    TypeName: string;
    SrcVar: string;
	TgtVar: string;
    constructor CreateNode(const AVarName, ATypeName: string);
    constructor CreateEdge(const AVarName, ATypeName, ASrcVar, ATgtVar: string);
  end;

  TLetBinding = class
  public
    VarName: string;
    Expr: TExpr;
    constructor Create(const AVarName: string; AExpr: TExpr);
    destructor Destroy; override;
  end;

  TAction = class
  public
    destructor Destroy; override;
  end;

  TFieldExprEntry = record
    Name: string;
    Expr: TExpr;
  end;

  TActionCreateNode = class(TAction)
  public
    VarName: string;
    TypeName: string;
    Fields: TArray<TFieldExprEntry>;
    constructor Create(const AVarName, ATypeName: string; const AFields: TArray<TFieldExprEntry>);
    destructor Destroy; override;
  end;

  TActionCreateEdge = class(TAction)
  public
    VarName: string;
    TypeName: string;
    SrcExpr: TExpr;
    TgtExpr: TExpr;
    Fields: TArray<TFieldExprEntry>;
    constructor Create(const AVarName, ATypeName: string; ASrcExpr, ATgtExpr: TExpr; const AFields: TArray<TFieldExprEntry>);
    destructor Destroy; override;
  end;

  TActionUpdateField = class(TAction)
  public
    TargetExpr: TExpr;
    FieldName: string;
    Expr: TExpr;
    constructor Create(ATargetExpr: TExpr; const AFieldName: string; AExpr: TExpr);
    destructor Destroy; override;
  end;

  TActionDeleteEdge = class(TAction)
  public
    Expr: TExpr;
    constructor Create(AExpr: TExpr);
    destructor Destroy; override;
  end;

  TActionDeleteNode = class(TAction)
  public
    VarName: string;
    constructor Create(const AVarName: string);
  end;

  TActionEmitEvent = class(TAction)
  public
    EventType: string;
    Payloads: TArray<TExpr>;
    constructor Create(const AEventType: string; const APayloads: TArray<TExpr>);
    destructor Destroy; override;
  end;

  TRule = class
  public
    RuleId: string;
    BasePriority: Int64;
    PriorityScale: Int64;
    FairnessScale: Int64;
    Patterns: TObjectList<TPattern>;
    Constraints: TObjectList<TExpr>;
    LetBindings: TObjectList<TLetBinding>;
    Actions: TObjectList<TAction>;
    constructor Create(const ARuleId: string; ABasePri, APriScale, AFairScale: Int64);
    destructor Destroy; override;
  end;

implementation

{ TExpr }

destructor TExpr.Destroy;
begin
  inherited;
end;

{ TExprLiteral }

constructor TExprLiteral.Create(const AValue: TValue);
begin
  Value := AValue;
end;

{ TExprVar }

constructor TExprVar.Create(const AVarName: string);
begin
  VarName := AVarName;
end;

{ TExprField }

constructor TExprField.Create(const AVarName, AFieldName: string);
begin
  VarName := AVarName;
  FieldName := AFieldName;
end;

{ TExprBinary }

constructor TExprBinary.Create(const AOp: string; ALeft, ARight: TExpr);
begin
  Op := AOp;
  Left := ALeft;
  Right := ARight;
end;

destructor TExprBinary.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited;
end;

{ TExprLen }

constructor TExprLen.Create(AExpr: TExpr);
begin
  Expr := AExpr;
end;

destructor TExprLen.Destroy;
begin
  Expr.Free;
  inherited;
end;

{ TExprToFixed }

constructor TExprToFixed.Create(AExpr: TExpr; AScale: Byte);
begin
  Expr := AExpr;
  Scale := AScale;
end;

destructor TExprToFixed.Destroy;
begin
  Expr.Free;
  inherited;
end;

{ TExprToInteger }

constructor TExprToInteger.Create(AExpr: TExpr);
begin
  Expr := AExpr;
end;

destructor TExprToInteger.Destroy;
begin
  Expr.Free;
  inherited;
end;

{ TPattern }

constructor TPattern.CreateNode(const AVarName, ATypeName: string);
begin
  PatternType := ptNode;
  VarName := AVarName;
  TypeName := ATypeName;
end;

constructor TPattern.CreateEdge(const AVarName, ATypeName, ASrcVar, ATgtVar: string);
begin
  PatternType := ptEdge;
  VarName := AVarName;
  TypeName := ATypeName;
  SrcVar := ASrcVar;
  TgtVar := ATgtVar;
end;

{ TLetBinding }

constructor TLetBinding.Create(const AVarName: string; AExpr: TExpr);
begin
  VarName := AVarName;
  Expr := AExpr;
end;

destructor TLetBinding.Destroy;
begin
  Expr.Free;
  inherited;
end;

{ TAction }

destructor TAction.Destroy;
begin
  inherited;
end;

{ TActionCreateNode }

constructor TActionCreateNode.Create(const AVarName, ATypeName: string; const AFields: TArray<TFieldExprEntry>);
begin
  VarName := AVarName;
  TypeName := ATypeName;
  Fields := AFields;
end;

destructor TActionCreateNode.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Fields) do
    Fields[i].Expr.Free;
  inherited;
end;

{ TActionCreateEdge }

constructor TActionCreateEdge.Create(const AVarName, ATypeName: string; ASrcExpr, ATgtExpr: TExpr; const AFields: TArray<TFieldExprEntry>);
begin
  VarName := AVarName;
  TypeName := ATypeName;
  SrcExpr := ASrcExpr;
  TgtExpr := ATgtExpr;
  Fields := AFields;
end;

destructor TActionCreateEdge.Destroy;
var
  i: Integer;
begin
  SrcExpr.Free;
  TgtExpr.Free;
  for i := 0 to High(Fields) do
    Fields[i].Expr.Free;
  inherited;
end;

{ TActionUpdateField }

constructor TActionUpdateField.Create(ATargetExpr: TExpr; const AFieldName: string; AExpr: TExpr);
begin
  TargetExpr := ATargetExpr;
  FieldName := AFieldName;
  Expr := AExpr;
end;

destructor TActionUpdateField.Destroy;
begin
  TargetExpr.Free;
  Expr.Free;
  inherited;
end;

{ TActionDeleteEdge }

constructor TActionDeleteEdge.Create(AExpr: TExpr);
begin
  Expr := AExpr;
end;

destructor TActionDeleteEdge.Destroy;
begin
  Expr.Free;
  inherited;
end;

{ TActionDeleteNode }

constructor TActionDeleteNode.Create(const AVarName: string);
begin
  VarName := AVarName;
end;

{ TActionEmitEvent }

constructor TActionEmitEvent.Create(const AEventType: string; const APayloads: TArray<TExpr>);
begin
  EventType := AEventType;
  Payloads := APayloads;
end;

destructor TActionEmitEvent.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Payloads) do
    Payloads[i].Free;
  inherited;
end;

{ TRule }

constructor TRule.Create(const ARuleId: string; ABasePri, APriScale, AFairScale: Int64);
begin
  RuleId := ARuleId;
  BasePriority := ABasePri;
  PriorityScale := APriScale;
  FairnessScale := AFairScale;
  Patterns := TObjectList<TPattern>.Create(True);
  Constraints := TObjectList<TExpr>.Create(True);
  LetBindings := TObjectList<TLetBinding>.Create(True);
  Actions := TObjectList<TAction>.Create(True);
end;

destructor TRule.Destroy;
begin
  Patterns.Free;
  Constraints.Free;
  LetBindings.Free;
  Actions.Free;
  inherited;
end;

end.
