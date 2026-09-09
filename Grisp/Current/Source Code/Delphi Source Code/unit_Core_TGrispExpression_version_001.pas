unit unit_Core_TGrispExpression_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Core_TGrispValueBase_version_001;  // Changed: use Base unit

type
  TGrispExpressionKind = (
    gekLiteral,
    gekVariable,
    gekUnary,
    gekBinary,
    gekCall
  );

  TGrispExpression = class
  public
    Kind: TGrispExpressionKind;
    Value: TObject; // TGrispValue
    Name: string;
    OperatorSymbol: string;
    Left: TGrispExpression;
    Right: TGrispExpression;
    Arguments: TObjectList<TGrispExpression>;
    constructor Create(AKind: TGrispExpressionKind);
    destructor Destroy; override;
    function Clone: TGrispExpression;
  end;

implementation

constructor TGrispExpression.Create(AKind: TGrispExpressionKind);
begin
  inherited Create;
  Kind := AKind;
  Arguments := TObjectList<TGrispExpression>.Create(True);
end;

destructor TGrispExpression.Destroy;
begin
  Arguments.Free;
  Left.Free;
  Right.Free;
  Value.Free;
  inherited Destroy;
end;

function TGrispExpression.Clone: TGrispExpression;
var Arg: TGrispExpression;
begin
  Result := TGrispExpression.Create(Kind);
  Result.Name := Name;
  Result.OperatorSymbol := OperatorSymbol;
  if Assigned(Value) then
    Result.Value := TGrispValue(Value).Clone;
  if Assigned(Left) then
    Result.Left := Left.Clone;
  if Assigned(Right) then
    Result.Right := Right.Clone;
  for Arg in Arguments do
    Result.Arguments.Add(Arg.Clone);
end;

end.
