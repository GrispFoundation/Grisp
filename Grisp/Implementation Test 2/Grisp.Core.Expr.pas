unit Grisp.Core.Expr;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Math,
  Grisp.Core.Types,
  Grisp.Core.Graph;

type
  TBinOp = (boAdd, boSub, boMul, boDiv, boIntDiv, boMod,
            boLt, boLe, boGt, boGe, boEq, boNe, boAnd, boOr);

  TExprKind = (ekLiteral, ekVar, ekFieldAccess, ekBinOp, ekLen, ekToFixed, ekToInteger);

  TExpr = record
    Kind: TExprKind;
    case Byte of
      0: (Literal: TValue);
      1: (VarName: UTF8String);
      2: (FieldAccessTarget: TExpr; FieldName: UTF8String);
      3: (BinOpLeft, BinOpRight: TExpr; Op: TBinOp);
      4: (LenOperand: TExpr);
      5: (ToFixedOperand: TExpr; Scale: Byte);
      6: (ToIntegerOperand: TExpr);
  end;

  TEnv = TDictionary<UTF8String, TValue>;

function EvalExpr(const Expr: TExpr; const Env: TEnv; const G: TGraph): TValue;
function ApplyBinaryOp(Op: TBinOp; const L, R: TValue): TValue;

implementation

// Helper for checked arithmetic
function CheckedAdd(A, B: Int64): Int64;
begin
  if (B > 0) and (A > High(Int64) - B) then
    raise Exception.Create('INTEGER_OVERFLOW');
  if (B < 0) and (A < Low(Int64) - B) then
    raise Exception.Create('INTEGER_OVERFLOW');
  Result := A + B;
end;

function CheckedSub(A, B: Int64): Int64;
begin
  Result := CheckedAdd(A, -B);
end;

function CheckedMul(A, B: Int64): Int64;
var
  Hi: Int64;
begin
  Hi := 0;
  if Math.CheckMul(A, B, Hi, Result) then
    raise Exception.Create('INTEGER_OVERFLOW');
end;

// Fixed-point helpers
function FixedToFloat(const V: TValue): Double;
begin
  Result := V.AsFixedRaw / Power(10, V.FixedScale);
end;

function FloatToFixed(V: Double; Scale: Byte): TValue;
begin
  Result.Kind := vkFixed;
  Result.AsFixedRaw := Round(V * Power(10, Scale));
  Result.FixedScale := Scale;
end;

function PromoteToFixed(const V: TValue; Scale: Byte): TValue;
begin
  if V.Kind = vkInt then
    Result := FloatToFixed(V.AsInt, Scale)
  else if V.Kind = vkFixed then
    Result := FloatToFixed(FixedToFloat(V), Scale)
  else
    raise Exception.Create('INVALID_IR');
end;

function EvalExpr(const Expr: TExpr; const Env: TEnv; const G: TGraph): TValue;
var
  TargetVal, FieldVal: TValue;
  NodeId: TNodeId;
  Node: TNode;
begin
  case Expr.Kind of
    ekLiteral:
      Exit(Expr.Literal);
    ekVar:
      begin
        if not Env.TryGetValue(Expr.VarName, Result) then
          raise Exception.Create('INVALID_IR');
      end;
    ekFieldAccess:
      begin
        TargetVal := EvalExpr(Expr.FieldAccessTarget, Env, G);
        if TargetVal.Kind <> vkIdentifier then
          raise Exception.Create('INVALID_IR');
        NodeId.TypeName := TargetVal.AsIdType;
        NodeId.Seq := TargetVal.AsIdSeq;
        if not G.Nodes.TryGetValue(NodeId, Node) then
          raise Exception.Create('MISSING_NODE');
        if not Node.Fields.TryGetValue(Expr.FieldName, FieldVal) then
          raise Exception.Create('MISSING_FIELD');
        Result := FieldVal;
      end;
    ekBinOp:
      begin
        var L := EvalExpr(Expr.BinOpLeft, Env, G);
        var R := EvalExpr(Expr.BinOpRight, Env, G);
        Result := ApplyBinaryOp(Expr.Op, L, R);
      end;
    ekLen:
      begin
        var ListVal := EvalExpr(Expr.LenOperand, Env, G);
        if ListVal.Kind <> vkList then
          raise Exception.Create('INVALID_IR');
        Result.Kind := vkInt;
        Result.AsInt := Length(ListVal.AsList);
      end;
    ekToFixed:
      begin
        var V := EvalExpr(Expr.ToFixedOperand, Env, G);
        Result := PromoteToFixed(V, Expr.Scale);
      end;
    ekToInteger:
      begin
        var V := EvalExpr(Expr.ToIntegerOperand, Env, G);
        if V.Kind = vkInt then
          Result := V
        else if V.Kind = vkFixed then
        begin
          Result.Kind := vkInt;
          Result.AsInt := Trunc(FixedToFloat(V));
        end
        else
          raise Exception.Create('INVALID_IR');
      end;
  else
    raise Exception.Create('INVALID_IR');
  end;
end;

function ApplyBinaryOp(Op: TBinOp; const L, R: TValue): TValue;
var
  LInt, RInt: Int64;
  LFloat, RFloat: Double;
  LFixedRaw, RFixedRaw, ResRaw: Int64;
  Scale: Byte;
begin
  // Short-circuit for Boolean operators
  if (Op = boAnd) or (Op = boOr) then
  begin
    if (L.Kind <> vkBool) or (R.Kind <> vkBool) then
      raise Exception.Create('INVALID_IR');
    Result.Kind := vkBool;
    if Op = boAnd then
      Result.AsBool := L.AsBool and R.AsBool
    else
      Result.AsBool := L.AsBool or R.AsBool;
    Exit;
  end;

  // Arithmetic and comparison – handle integer and fixed-point promotion
  if (L.Kind = vkInt) and (R.Kind = vkInt) then
  begin
    LInt := L.AsInt;
    RInt := R.AsInt;
    case Op of
      boAdd: begin Result.Kind := vkInt; Result.AsInt := CheckedAdd(LInt, RInt); end;
      boSub: begin Result.Kind := vkInt; Result.AsInt := CheckedSub(LInt, RInt); end;
      boMul: begin Result.Kind := vkInt; Result.AsInt := CheckedMul(LInt, RInt); end;
      boDiv: if RInt = 0 then raise Exception.Create('DIVISION_BY_ZERO')
             else begin Result.Kind := vkFixed; // Fixed division per spec
                  Scale := 0; // result is fixed with scale 0? Actually spec says use big-integer, keep as fixed.
                  Result.Kind := vkFixed;
                  Result.AsFixedRaw := LInt div RInt; // truncates toward zero
                  Result.FixedScale := 0;
             end;
      boIntDiv: if RInt = 0 then raise Exception.Create('DIVISION_BY_ZERO')
                else begin Result.Kind := vkInt; Result.AsInt := LInt div RInt; end;
      boMod: if RInt = 0 then raise Exception.Create('DIVISION_BY_ZERO')
             else begin Result.Kind := vkInt; Result.AsInt := LInt mod RInt; end;
      boLt: begin Result.Kind := vkBool; Result.AsBool := LInt < RInt; end;
      boLe: begin Result.Kind := vkBool; Result.AsBool := LInt <= RInt; end;
      boGt: begin Result.Kind := vkBool; Result.AsBool := LInt > RInt; end;
      boGe: begin Result.Kind := vkBool; Result.AsBool := LInt >= RInt; end;
      boEq: begin Result.Kind := vkBool; Result.AsBool := LInt = RInt; end;
      boNe: begin Result.Kind := vkBool; Result.AsBool := LInt <> RInt; end;
    else
      raise Exception.Create('INVALID_IR');
    end;
  end
  else if (L.Kind in [vkInt, vkFixed]) and (R.Kind in [vkInt, vkFixed]) then
  begin
    // Promote both to fixed-point with max scale
    if L.Kind = vkInt then
      LFloat := L.AsInt
    else
      LFloat := FixedToFloat(L);
    if R.Kind = vkInt then
      RFloat := R.AsInt
    else
      RFloat := FixedToFloat(R);
    case Op of
      boAdd: begin Result := FloatToFixed(LFloat + RFloat, Max(L.FixedScale, R.FixedScale)); end;
      boSub: begin Result := FloatToFixed(LFloat - RFloat, Max(L.FixedScale, R.FixedScale)); end;
      boMul: begin Result := FloatToFixed(LFloat * RFloat, Max(L.FixedScale, R.FixedScale)); end;
      boDiv: if RFloat = 0 then raise Exception.Create('DIVISION_BY_ZERO')
             else begin Result := FloatToFixed(LFloat / RFloat, Max(L.FixedScale, R.FixedScale)); end;
      boLt: begin Result.Kind := vkBool; Result.AsBool := LFloat < RFloat; end;
      boLe: begin Result.Kind := vkBool; Result.AsBool := LFloat <= RFloat; end;
      boGt: begin Result.Kind := vkBool; Result.AsBool := LFloat > RFloat; end;
      boGe: begin Result.Kind := vkBool; Result.AsBool := LFloat >= RFloat; end;
      boEq: begin Result.Kind := vkBool; Result.AsBool := LFloat = RFloat; end;
      boNe: begin Result.Kind := vkBool; Result.AsBool := LFloat <> RFloat; end;
    else
      raise Exception.Create('INVALID_IR');
    end;
  end
  else
    raise Exception.Create('INVALID_IR');
end;

end.
