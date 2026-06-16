unit Grisp.Evaluator;

interface

uses
  System.SysUtils, System.Generics.Collections, Grisp.Core, Grisp.AST;

// Checked Arithmetic Helpers (exported for use by Engine)
function SafeAdd(A, B: Int64): Int64;
function SafeSub(A, B: Int64): Int64;
function SafeMul(A, B: Int64): Int64;

// Expression evaluation
function EvaluateExpr(AExpr: TExpr; AEnv: TDictionary<string, TValue>; AGraph: TGraph; ACounters: TCounters; AReadTrace: TList<TReadEffect>): TValue;

implementation

function SafeAdd(A, B: Int64): Int64;
begin
  if (B > 0) and (A > Int64.MaxValue - B) then raise Exception.Create('INTEGER_OVERFLOW');
  if (B < 0) and (A < Int64.MinValue - B) then raise Exception.Create('INTEGER_OVERFLOW');
  Result := A + B;
end;

function SafeSub(A, B: Int64): Int64;
begin
  if (B > 0) and (A < Int64.MinValue + B) then raise Exception.Create('INTEGER_OVERFLOW');
  if (B < 0) and (A > Int64.MaxValue + B) then raise Exception.Create('INTEGER_OVERFLOW');
  Result := A - B;
end;

function SafeMul(A, B: Int64): Int64;
begin
  if A = 0 then Exit(0);
  if B = 0 then Exit(0);
  if A = 1 then Exit(B);
  if B = 1 then Exit(A);
  if (A = -1) and (B = Int64.MinValue) then raise Exception.Create('INTEGER_OVERFLOW');
  if (B = -1) and (A = Int64.MinValue) then raise Exception.Create('INTEGER_OVERFLOW');

  if A > 0 then
  begin
    if B > 0 then
    begin
      if A > Int64.MaxValue div B then raise Exception.Create('INTEGER_OVERFLOW');
    end
    else
    begin
      if B < Int64.MinValue div A then raise Exception.Create('INTEGER_OVERFLOW');
    end;
  end
  else
  begin
    if B > 0 then
    begin
      if A < Int64.MinValue div B then raise Exception.Create('INTEGER_OVERFLOW');
    end
    else
    begin
      if A < Int64.MaxValue div B then raise Exception.Create('INTEGER_OVERFLOW');
    end;
  end;
  Result := A * B;
end;

function PowerOf10(APower: Byte): UInt64;
var
  i: Integer;
begin
  Result := 1;
  for i := 1 to APower do
	Result := Result * 10;
end;

function PromoteToFixed(const AVal: TValue; AScale: Byte): TFixedPoint;
var
  Mult: UInt64;
begin
  if AVal.ValType = vtInteger then
  begin
    Mult := PowerOf10(AScale);
    Result := TFixedPoint.Create(SafeMul(AVal.IntValue, Mult), AScale);
  end
  else if AVal.ValType = vtFixedPoint then
  begin
    if AVal.FixValue.Scale = AScale then
      Result := AVal.FixValue
    else if AVal.FixValue.Scale < AScale then
    begin
      Mult := PowerOf10(AScale - AVal.FixValue.Scale);
      Result := TFixedPoint.Create(SafeMul(AVal.FixValue.Value, Mult), AScale);
    end
    else
    begin
      Mult := PowerOf10(AVal.FixValue.Scale - AScale);
      Result := TFixedPoint.Create(AVal.FixValue.Value div Mult, AScale);
    end;
  end
  else
    raise Exception.Create('Cannot promote to FixedPoint: ' + AVal.ToString);
end;

function EvaluateExpr(AExpr: TExpr; AEnv: TDictionary<string, TValue>; AGraph: TGraph; ACounters: TCounters; AReadTrace: TList<TReadEffect>): TValue;
var
  Lit: TExprLiteral;
  V: TExprVar;
  F: TExprField;
  Bin: TExprBinary;
  LenExpr: TExprLen;
  ToFix: TExprToFixed;
  ToInt: TExprToInteger;
  Val1, Val2: TValue;
  Node: TNode;
  Edge: TEdge;
  Id: TIdentifier;
  FVal: TValue;
  Scale1, Scale2: Byte;
  FP1, FP2: TFixedPoint;
  CompResult: Integer;
  ResultSign: Integer;
  AbsV1, AbsV2: UInt64;
  Mult128: UInt64;
  Dividend: TUInt128;
  Quotient: TUInt128;
  Rem: UInt64;
  Mult: UInt64;
begin
  if AExpr is TExprLiteral then
  begin
    Lit := TExprLiteral(AExpr);
    Exit(Lit.Value);
  end;

  if AExpr is TExprVar then
  begin
    V := TExprVar(AExpr);
    if not AEnv.TryGetValue(V.VarName, Val1) then
      raise Exception.Create('Variable not bound: ' + V.VarName);
    Exit(Val1);
  end;

  if AExpr is TExprField then
  begin
    F := TExprField(AExpr);
    if not AEnv.TryGetValue(F.VarName, Val1) then
      raise Exception.Create('Variable not bound: ' + F.VarName);
    if Val1.ValType <> vtIdentifier then
      raise Exception.Create('Field access target must be an Identifier');
    Id := Val1.IdValue;
    if AGraph.FindNode(Id, Node) then
    begin
      AReadTrace.Add(TReadEffect.NodeExistence(Id, ACounters.GetExistenceVersion(Id)));
      if not Node.FindField(F.FieldName, FVal) then
        raise Exception.Create('Field missing: ' + F.FieldName + ' on ' + Id.ToString);
      AReadTrace.Add(TReadEffect.FieldRead(Id, F.FieldName, ACounters.GetFieldVersion(Id, F.FieldName)));
      Exit(FVal);
    end
    else if AGraph.FindEdge(Id, Edge) then
    begin
      AReadTrace.Add(TReadEffect.EdgeExistence(Id, ACounters.GetExistenceVersion(Id)));
      if not Edge.FindField(F.FieldName, FVal) then
        raise Exception.Create('Field missing: ' + F.FieldName + ' on ' + Id.ToString);
      AReadTrace.Add(TReadEffect.FieldRead(Id, F.FieldName, ACounters.GetFieldVersion(Id, F.FieldName)));
      Exit(FVal);
    end
    else
      raise Exception.Create('Element not found in graph: ' + Id.ToString);
  end;

  if AExpr is TExprBinary then
  begin
    Bin := TExprBinary(AExpr);
    Val1 := EvaluateExpr(Bin.Left, AEnv, AGraph, ACounters, AReadTrace);

    if Bin.Op = '&&' then
    begin
      if Val1.ValType <> vtBoolean then raise Exception.Create('&& operator expects boolean');
      if not Val1.BoolValue then Exit(TValue.CreateBoolean(False));
      Val2 := EvaluateExpr(Bin.Right, AEnv, AGraph, ACounters, AReadTrace);
      if Val2.ValType <> vtBoolean then raise Exception.Create('&& operator expects boolean');
      Exit(Val2);
    end;

    if Bin.Op = '||' then
    begin
      if Val1.ValType <> vtBoolean then raise Exception.Create('|| operator expects boolean');
      if Val1.BoolValue then Exit(TValue.CreateBoolean(True));
      Val2 := EvaluateExpr(Bin.Right, AEnv, AGraph, ACounters, AReadTrace);
      if Val2.ValType <> vtBoolean then raise Exception.Create('|| operator expects boolean');
      Exit(Val2);
    end;

    Val2 := EvaluateExpr(Bin.Right, AEnv, AGraph, ACounters, AReadTrace);

    // Mixed promotion for * and /
    if (Val1.ValType = vtInteger) and (Val2.ValType = vtFixedPoint) then
    begin
      if (Bin.Op = '*') or (Bin.Op = '/') then
        Val1 := TValue.CreateFixedPoint(PromoteToFixed(Val1, 0).Value, 0);
	end
    else if (Val1.ValType = vtFixedPoint) and (Val2.ValType = vtInteger) then
    begin
      if (Bin.Op = '*') or (Bin.Op = '/') then
        Val2 := TValue.CreateFixedPoint(PromoteToFixed(Val2, 0).Value, 0);
    end;

    // Integer arithmetic
    if (Val1.ValType = vtInteger) and (Val2.ValType = vtInteger) then
    begin
      if Bin.Op = '+' then Exit(TValue.CreateInteger(SafeAdd(Val1.IntValue, Val2.IntValue)));
      if Bin.Op = '-' then Exit(TValue.CreateInteger(SafeSub(Val1.IntValue, Val2.IntValue)));
      if Bin.Op = '*' then Exit(TValue.CreateInteger(SafeMul(Val1.IntValue, Val2.IntValue)));
      if Bin.Op = '//' then
      begin
        if Val2.IntValue = 0 then raise Exception.Create('DIVISION_BY_ZERO');
        Exit(TValue.CreateInteger(Val1.IntValue div Val2.IntValue));
      end;
      if Bin.Op = '%' then
      begin
        if Val2.IntValue = 0 then raise Exception.Create('DIVISION_BY_ZERO');
        Exit(TValue.CreateInteger(Val1.IntValue mod Val2.IntValue));
      end;
      if Bin.Op = '/' then
        raise Exception.Create('Float division "/" not allowed on integers. Use "//".');

      if Bin.Op = '==' then Exit(TValue.CreateBoolean(Val1.IntValue = Val2.IntValue));
      if Bin.Op = '!=' then Exit(TValue.CreateBoolean(Val1.IntValue <> Val2.IntValue));
      if Bin.Op = '<' then Exit(TValue.CreateBoolean(Val1.IntValue < Val2.IntValue));
      if Bin.Op = '<=' then Exit(TValue.CreateBoolean(Val1.IntValue <= Val2.IntValue));
      if Bin.Op = '>' then Exit(TValue.CreateBoolean(Val1.IntValue > Val2.IntValue));
      if Bin.Op = '>=' then Exit(TValue.CreateBoolean(Val1.IntValue >= Val2.IntValue));
      raise Exception.Create('Invalid operator on integers: ' + Bin.Op);
    end;

    // Fixed-point arithmetic
    if (Val1.ValType = vtFixedPoint) and (Val2.ValType = vtFixedPoint) then
    begin
      Scale1 := Val1.FixValue.Scale;
      Scale2 := Val2.FixValue.Scale;

      if Bin.Op = '+' then
      begin
        if Scale1 <> Scale2 then raise Exception.Create('FixedPoint addition requires identical scale');
        Exit(TValue.CreateFixedPoint(SafeAdd(Val1.FixValue.Value, Val2.FixValue.Value), Scale1));
      end;

      if Bin.Op = '-' then
      begin
        if Scale1 <> Scale2 then raise Exception.Create('FixedPoint subtraction requires identical scale');
        Exit(TValue.CreateFixedPoint(SafeSub(Val1.FixValue.Value, Val2.FixValue.Value), Scale1));
      end;

      if Bin.Op = '*' then
      begin
        if Scale1 + Scale2 > 18 then raise Exception.Create('INTEGER_OVERFLOW');
        Exit(TValue.CreateFixedPoint(SafeMul(Val1.FixValue.Value, Val2.FixValue.Value), Scale1 + Scale2));
      end;

      if Bin.Op = '/' then
      begin
        if Val2.FixValue.Value = 0 then raise Exception.Create('DIVISION_BY_ZERO');
        if ((Val1.FixValue.Value < 0) and (Val2.FixValue.Value > 0)) or
           ((Val1.FixValue.Value > 0) and (Val2.FixValue.Value < 0)) then
          ResultSign := -1
        else
          ResultSign := 1;
        AbsV1 := UInt64(Abs(Val1.FixValue.Value));
        AbsV2 := UInt64(Abs(Val2.FixValue.Value));
        Mult128 := PowerOf10(Scale2);
        Dividend := TUInt128.Mul64x64(AbsV1, Mult128);
        Quotient := TUInt128.Div128by64(Dividend, AbsV2, Rem);
		if Quotient.High <> 0 then raise Exception.Create('INTEGER_OVERFLOW');
        if ResultSign = 1 then
        begin
          if Quotient.Low > UInt64(Int64.MaxValue) then raise Exception.Create('INTEGER_OVERFLOW');
          Exit(TValue.CreateFixedPoint(Int64(Quotient.Low), Scale1));
        end
        else
        begin
          if Quotient.Low > UInt64(Int64.MaxValue) + 1 then raise Exception.Create('INTEGER_OVERFLOW');
          Exit(TValue.CreateFixedPoint(-Int64(Quotient.Low), Scale1));
        end;
      end;

      // Comparisons
      FP1 := Val1.FixValue;
      FP2 := Val2.FixValue;
      if Scale1 <> Scale2 then
      begin
        if Scale1 < Scale2 then
          FP1 := PromoteToFixed(Val1, Scale2)
        else
          FP2 := PromoteToFixed(Val2, Scale1);
      end;
      if Bin.Op = '==' then Exit(TValue.CreateBoolean(FP1.Value = FP2.Value));
      if Bin.Op = '!=' then Exit(TValue.CreateBoolean(FP1.Value <> FP2.Value));
      if Bin.Op = '<' then Exit(TValue.CreateBoolean(FP1.Value < FP2.Value));
      if Bin.Op = '<=' then Exit(TValue.CreateBoolean(FP1.Value <= FP2.Value));
      if Bin.Op = '>' then Exit(TValue.CreateBoolean(FP1.Value > FP2.Value));
      if Bin.Op = '>=' then Exit(TValue.CreateBoolean(FP1.Value >= FP2.Value));
      raise Exception.Create('Invalid operator on fixed-point: ' + Bin.Op);
    end;

    // Boolean comparisons
    if (Val1.ValType = vtBoolean) and (Val2.ValType = vtBoolean) then
    begin
      if Bin.Op = '==' then Exit(TValue.CreateBoolean(Val1.BoolValue = Val2.BoolValue));
      if Bin.Op = '!=' then Exit(TValue.CreateBoolean(Val1.BoolValue <> Val2.BoolValue));
      if Bin.Op = '<' then Exit(TValue.CreateBoolean((not Val1.BoolValue) and Val2.BoolValue));
      if Bin.Op = '<=' then Exit(TValue.CreateBoolean(not (Val1.BoolValue and (not Val2.BoolValue))));
      if Bin.Op = '>' then Exit(TValue.CreateBoolean(Val1.BoolValue and (not Val2.BoolValue)));
      if Bin.Op = '>=' then Exit(TValue.CreateBoolean(not ((not Val1.BoolValue) and Val2.BoolValue)));
      raise Exception.Create('Invalid operator on booleans: ' + Bin.Op);
    end;

    // String comparisons
    if (Val1.ValType = vtString) and (Val2.ValType = vtString) then
    begin
      CompResult := CompareUTF8(Val1.StrValue, Val2.StrValue);
      if Bin.Op = '==' then Exit(TValue.CreateBoolean(CompResult = 0));
      if Bin.Op = '!=' then Exit(TValue.CreateBoolean(CompResult <> 0));
      if Bin.Op = '<' then Exit(TValue.CreateBoolean(CompResult < 0));
      if Bin.Op = '<=' then Exit(TValue.CreateBoolean(CompResult <= 0));
      if Bin.Op = '>' then Exit(TValue.CreateBoolean(CompResult > 0));
      if Bin.Op = '>=' then Exit(TValue.CreateBoolean(CompResult >= 0));
      raise Exception.Create('Invalid operator on strings: ' + Bin.Op);
    end;

    // Identifier comparisons
    if (Val1.ValType = vtIdentifier) and (Val2.ValType = vtIdentifier) then
    begin
      CompResult := CompareIdentifiers(Val1.IdValue, Val2.IdValue);
      if Bin.Op = '==' then Exit(TValue.CreateBoolean(CompResult = 0));
      if Bin.Op = '!=' then Exit(TValue.CreateBoolean(CompResult <> 0));
      if Bin.Op = '<' then Exit(TValue.CreateBoolean(CompResult < 0));
      if Bin.Op = '<=' then Exit(TValue.CreateBoolean(CompResult <= 0));
      if Bin.Op = '>' then Exit(TValue.CreateBoolean(CompResult > 0));
      if Bin.Op = '>=' then Exit(TValue.CreateBoolean(CompResult >= 0));
      raise Exception.Create('Invalid operator on identifiers: ' + Bin.Op);
    end;

    // Mixed integer/fixed-point comparisons
    if ((Val1.ValType = vtInteger) and (Val2.ValType = vtFixedPoint)) or
	   ((Val1.ValType = vtFixedPoint) and (Val2.ValType = vtInteger)) then
    begin
      if Val1.ValType = vtFixedPoint then Scale2 := Val1.FixValue.Scale else Scale2 := Val2.FixValue.Scale;
      FP1 := PromoteToFixed(Val1, Scale2);
      FP2 := PromoteToFixed(Val2, Scale2);
      if Bin.Op = '==' then Exit(TValue.CreateBoolean(FP1.Value = FP2.Value));
      if Bin.Op = '!=' then Exit(TValue.CreateBoolean(FP1.Value <> FP2.Value));
      if Bin.Op = '<' then Exit(TValue.CreateBoolean(FP1.Value < FP2.Value));
      if Bin.Op = '<=' then Exit(TValue.CreateBoolean(FP1.Value <= FP2.Value));
      if Bin.Op = '>' then Exit(TValue.CreateBoolean(FP1.Value > FP2.Value));
      if Bin.Op = '>=' then Exit(TValue.CreateBoolean(FP1.Value >= FP2.Value));
    end;

    raise Exception.Create('Type mismatch or unsupported operator: ' + Bin.Op + ' between ' + Val1.ToString + ' and ' + Val2.ToString);
  end;

  if AExpr is TExprLen then
  begin
    LenExpr := TExprLen(AExpr);
    Val1 := EvaluateExpr(LenExpr.Expr, AEnv, AGraph, ACounters, AReadTrace);
    if Val1.ValType <> vtList then
      raise Exception.Create('len() operator expects a List');
    Exit(TValue.CreateInteger(Length(Val1.ListValue)));
  end;

  if AExpr is TExprToFixed then
  begin
    ToFix := TExprToFixed(AExpr);
    Val1 := EvaluateExpr(ToFix.Expr, AEnv, AGraph, ACounters, AReadTrace);
    if Val1.ValType = vtInteger then
    begin
      Mult := PowerOf10(ToFix.Scale);
      Exit(TValue.CreateFixedPoint(SafeMul(Val1.IntValue, Mult), ToFix.Scale));
    end
    else if Val1.ValType = vtFixedPoint then
    begin
      Scale1 := Val1.FixValue.Scale;
      if Scale1 = ToFix.Scale then
        Exit(Val1)
      else if Scale1 < ToFix.Scale then
      begin
        Mult := PowerOf10(ToFix.Scale - Scale1);
        Exit(TValue.CreateFixedPoint(SafeMul(Val1.FixValue.Value, Mult), ToFix.Scale));
      end
      else
      begin
        Mult := PowerOf10(Scale1 - ToFix.Scale);
        Exit(TValue.CreateFixedPoint(Val1.FixValue.Value div Mult, ToFix.Scale));
      end;
    end
    else
      raise Exception.Create('to_fixed() operator expects Integer or FixedPoint');
  end;

  if AExpr is TExprToInteger then
  begin
    ToInt := TExprToInteger(AExpr);
    Val1 := EvaluateExpr(ToInt.Expr, AEnv, AGraph, ACounters, AReadTrace);
    if Val1.ValType = vtInteger then
      Exit(Val1)
    else if Val1.ValType = vtFixedPoint then
    begin
      Mult := PowerOf10(Val1.FixValue.Scale);
      Exit(TValue.CreateInteger(Val1.FixValue.Value div Mult));
    end
    else
      raise Exception.Create('to_integer() operator expects Integer or FixedPoint');
  end;

  raise Exception.Create('Unsupported AST expression node');
end;

end.
