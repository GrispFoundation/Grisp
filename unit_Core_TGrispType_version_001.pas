unit unit_Core_TGrispType_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Core_TGrispValueBase_version_001;  // Changed: use Base unit directly

type
  TGrispTypeKind = (
    gtkNumber,
    gtkString,
    gtkBoolean,
    gtkIdentifier,
    gtkNode,
    gtkArray,
    gtkNil
  );

  TGrispType = class
  public
    Kind: TGrispTypeKind;
    ElementType: TGrispType;
    NodeTypeName: string;
    constructor Create(AKind: TGrispTypeKind);
    destructor Destroy; override;
    function Matches(Value: TGrispValue): Boolean;
    function ToString: string; override;
  end;

implementation

constructor TGrispType.Create(AKind: TGrispTypeKind);
begin
  inherited Create;
  Kind := AKind;
  ElementType := nil;
  NodeTypeName := '';
end;

destructor TGrispType.Destroy;
begin
  ElementType.Free;
  inherited Destroy;
end;

function TGrispType.Matches(Value: TGrispValue): Boolean;
var
  NodeId: Integer;
  NodeName: string;
  E: TGrispValue;
begin
  Result := False;
  if Value = nil then Exit;

  case Kind of
    gtkNumber: Result := Value.Kind = gvkNumber;
    gtkString: Result := Value.Kind = gvkString;
    gtkBoolean: Result := Value.Kind = gvkBoolean;
    gtkIdentifier: Result := Value.Kind = gvkIdentifier;
    gtkNil: Result := Value = nil;
    gtkNode:
      begin
        if Value.Kind <> gvkNode then Exit;
		Value.GetNodeReference(NodeId, NodeName);
        Result := (NodeId >= 0) and ((NodeTypeName = '') or (NodeName = NodeTypeName));
      end;
    gtkArray:
      begin
        if Value.Kind <> gvkArray then Exit;
        if ElementType = nil then
          Result := True
        else
        begin
          Result := True;
          for E in Value.ArrayValue do
            if not ElementType.Matches(E) then
            begin
              Result := False;
              Break;
            end;
        end;
      end;
  end;
end;

function TGrispType.ToString: string;
begin
  case Kind of
    gtkNumber: Result := 'number';
    gtkString: Result := 'string';
    gtkBoolean: Result := 'boolean';
    gtkIdentifier: Result := 'identifier';
    gtkNil: Result := 'nil';
    gtkNode:
      if NodeTypeName <> '' then
        Result := 'node<' + NodeTypeName + '>'
      else
        Result := 'node';
    gtkArray:
      if ElementType <> nil then
        Result := 'array<' + ElementType.ToString + '>'
      else
        Result := 'array';
  end;
end;

end.
