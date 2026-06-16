unit Grisp.Core.Counters;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  Grisp.Core.Types,
  Grisp.Core.Ordering;

type
  TNodeFieldKey = record
    Node: TNodeId;
    Field: UTF8String;
  end;

  TNodeFieldKeyComparer = class(TEqualityComparer<TNodeFieldKey>)
    function Equals(const Left, Right: TNodeFieldKey): Boolean; override;
    function GetHashCode(const Value: TNodeFieldKey): Integer; override;
  end;

  TCounters = record
    TickCounter: Int64;
    NodeSeq: TDictionary<UTF8String, Int64>;
    // For minimal test, only these two version maps:
    ExistenceVersionNode: TDictionary<TNodeId, Int64>;
    FieldVersionNode: TDictionary<TNodeFieldKey, Int64>;
  end;

function CheckedInc(var V: Int64): Boolean;
procedure RaiseCounterOverflow;

implementation

function CheckedInc(var V: Int64): Boolean;
begin
  if V = High(Int64) then
    Exit(False);
  Inc(V);
  Result := True;
end;

procedure RaiseCounterOverflow;
begin
  raise Exception.Create('COUNTER_OVERFLOW');
end;

{ TNodeFieldKeyComparer }

function TNodeFieldKeyComparer.Equals(const Left, Right: TNodeFieldKey): Boolean;
begin
  Result := (CanonicalCompareNodeId(Left.Node, Right.Node) = 0) and
            (CanonicalCompareStr(Left.Field, Right.Field) = 0);
end;

function TNodeFieldKeyComparer.GetHashCode(const Value: TNodeFieldKey): Integer;
begin
  Result := BobJenkinsHash(@Value, SizeOf(Value), 0);
end;

end.
