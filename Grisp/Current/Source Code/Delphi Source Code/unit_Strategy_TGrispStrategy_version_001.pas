unit unit_Strategy_TGrispStrategy_version_001;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  unit_Strategy_TGrispStrategyKind_version_001;

type
  TGrispStrategy = class
  public
    Kind: TGrispStrategyKind;
    RuleName: string;
    Phase: Integer;
    Strategies: TList<TGrispStrategy>;
    constructor Create(AKind: TGrispStrategyKind);
    destructor Destroy; override;
    function Clone: TGrispStrategy;
  end;

implementation

constructor TGrispStrategy.Create(AKind: TGrispStrategyKind);
begin
  inherited Create;
  Kind := AKind;
  Strategies := TList<TGrispStrategy>.Create;
  Phase := 0;
end;

destructor TGrispStrategy.Destroy;
begin
  Strategies.Free;
  inherited Destroy;
end;

function TGrispStrategy.Clone: TGrispStrategy;
var
  SubStrategy: TGrispStrategy;
begin
  Result := TGrispStrategy.Create(Kind);
  Result.RuleName := RuleName;
  Result.Phase := Phase;
  for SubStrategy in Strategies do
    Result.Strategies.Add(SubStrategy.Clone);
end;

end.
