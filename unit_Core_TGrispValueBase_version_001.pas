unit unit_Core_TGrispValueBase_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TGrispValueKind = (
    gvkNumber,
    gvkString,
    gvkBoolean,
    gvkIdentifier,
    gvkArray,
    gvkNode,
    gvkExpression
  );

  TGrispValue = class
  private
    FNodeId: Integer;      // Store node ID instead of direct reference
    FNodeName: string;     // Store node name instead of direct reference
  public
    Kind: TGrispValueKind;
    NumberValue: Double;
    StringValue: string;
    BoolValue: Boolean;
    IdentifierValue: string;
    ArrayValue: TObjectList<TGrispValue>;
    ExpressionValue: TObject;  // Will be TGrispExpression

    // Node reference stored as ID/Name to avoid circular dependency
    procedure SetNodeReference(AId: Integer; const AName: string);
    procedure GetNodeReference(out AId: Integer; out AName: string);

    constructor Create(AKind: TGrispValueKind);
    destructor Destroy; override;
    function Clone: TGrispValue;
    function ToString: string; override;
  end;

implementation

constructor TGrispValue.Create(AKind: TGrispValueKind);
begin
  inherited Create;
  Kind := AKind;
  if Kind = gvkArray then
    ArrayValue := TObjectList<TGrispValue>.Create(True);
  FNodeId := -1;
  FNodeName := '';
end;

destructor TGrispValue.Destroy;
begin
  ArrayValue.Free;
  ExpressionValue.Free;
  inherited Destroy;
end;

procedure TGrispValue.SetNodeReference(AId: Integer; const AName: string);
begin
  FNodeId := AId;
  FNodeName := AName;
end;

procedure TGrispValue.GetNodeReference(out AId: Integer; out AName: string);
begin
  AId := FNodeId;
  AName := FNodeName;
end;

function TGrispValue.Clone: TGrispValue;
var E: TGrispValue;
begin
  Result := TGrispValue.Create(Kind);
  Result.NumberValue := NumberValue;
  Result.StringValue := StringValue;
  Result.BoolValue := BoolValue;
  Result.IdentifierValue := IdentifierValue;
  Result.FNodeId := FNodeId;
  Result.FNodeName := FNodeName;
  if Kind = gvkArray then
    for E in ArrayValue do
      Result.ArrayValue.Add(E.Clone);
  if (Kind = gvkExpression) and (ExpressionValue <> nil) then
    Result.ExpressionValue := ExpressionValue;
end;

function TGrispValue.ToString: string;
begin
  case Kind of
    gvkNumber: Result := FloatToStr(NumberValue);
    gvkString: Result := '"' + StringValue + '"';
    gvkBoolean: Result := BoolToStr(BoolValue, True);
    gvkIdentifier: Result := IdentifierValue;
    gvkArray: Result := '[...]';
    gvkNode:
      if FNodeId >= 0 then
        Result := Format('node(%d:%s)', [FNodeId, FNodeName])
      else
        Result := 'node(nil)';
    gvkExpression: Result := '<expr>';
  else
    Result := 'nil';
  end;
end;

end.
