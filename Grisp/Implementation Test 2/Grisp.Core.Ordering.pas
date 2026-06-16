unit Grisp.Core.Ordering;

interface

uses
  System.Generics.Defaults,
  Grisp.Core.Types;

function CanonicalCompareStr(const A, B: UTF8String): Integer;
function CanonicalCompareValue(const A, B: TValue): Integer;
function CanonicalCompareNodeId(const A, B: TNodeId): Integer;
function CanonicalCompareEdgeId(const A, B: TEdgeId): Integer;

function ValueComparer: IComparer<TValue>;
function StringComparer: IComparer<UTF8String>;
function NodeIdComparer: IComparer<TNodeId>;
function EdgeIdComparer: IComparer<TEdgeId>;

implementation

uses System.SysUtils;

function CanonicalCompareStr(const A, B: UTF8String): Integer;
var
  LenA, LenB: Integer;
  MinLen: Integer;
begin
  LenA := Length(A);
  LenB := Length(B);
  MinLen := LenA;
  if LenB < MinLen then MinLen := LenB;
  Result := CompareMem(PByte(A), PByte(B), MinLen);
  if Result = 0 then
    Result := LenA - LenB;
end;

function CanonicalCompareValue(const A, B: TValue): Integer;
var
  i: Integer;
  KeysA, KeysB: TArray<UTF8String>;
begin
  if A.Kind <> B.Kind then
    Exit(Ord(A.Kind) - Ord(B.Kind));

  case A.Kind of
    vkInt:    Result := CompareValue(A.AsInt, B.AsInt);
    vkFixed:  Result := CompareValue(A.AsFixedRaw, B.AsFixedRaw);
    vkBool:   Result := Ord(A.AsBool) - Ord(B.AsBool);
    vkString: Result := CanonicalCompareStr(A.AsString, B.AsString);
    vkIdentifier:
      begin
        Result := CanonicalCompareStr(A.AsIdType, B.AsIdType);
        if Result = 0 then
          Result := CompareValue(A.AsIdSeq, B.AsIdSeq);
      end;
    vkList:
      begin
        Result := Length(A.AsList) - Length(B.AsList);
        if Result = 0 then
          for i := 0 to High(A.AsList) do
          begin
            Result := CanonicalCompareValue(A.AsList[i], B.AsList[i]);
            if Result <> 0 then Break;
          end;
      end;
    vkMap:
      begin
        KeysA := A.AsMap.Keys.ToArray;
        KeysB := B.AsMap.Keys.ToArray;
        TArray.Sort<UTF8String>(KeysA, StringComparer);
        TArray.Sort<UTF8String>(KeysB, StringComparer);
		Result := Length(KeysA) - Length(KeysB);
        if Result = 0 then
          for i := 0 to High(KeysA) do
          begin
            Result := CanonicalCompareStr(KeysA[i], KeysB[i]);
            if Result = 0 then
              Result := CanonicalCompareValue(A.AsMap[KeysA[i]], B.AsMap[KeysB[i]]);
            if Result <> 0 then Break;
          end;
      end;
  else
    Result := 0;
  end;
end;

function CanonicalCompareNodeId(const A, B: TNodeId): Integer;
begin
  Result := CanonicalCompareStr(A.TypeName, B.TypeName);
  if Result = 0 then
    Result := CompareValue(A.Seq, B.Seq);
end;

function CanonicalCompareEdgeId(const A, B: TEdgeId): Integer;
begin
  Result := CanonicalCompareStr(A.TypeName, B.TypeName);
  if Result = 0 then
    Result := CompareValue(A.Seq, B.Seq);
end;

function ValueComparer: IComparer<TValue>;
begin
  Result := TComparer<TValue>.Construct(CanonicalCompareValue);
end;

function StringComparer: IComparer<UTF8String>;
begin
  Result := TComparer<UTF8String>.Construct(CanonicalCompareStr);
end;

function NodeIdComparer: IComparer<TNodeId>;
begin
  Result := TComparer<TNodeId>.Construct(CanonicalCompareNodeId);
end;

function EdgeIdComparer: IComparer<TEdgeId>;
begin
  Result := TComparer<TEdgeId>.Construct(CanonicalCompareEdgeId);
end;

end.
