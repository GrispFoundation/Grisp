unit unit_Core_TGrispExpressionEvaluator_version_001;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  unit_Core_TGrispValueBase_version_001,  // Changed: use Base unit directly
  unit_Core_TGrispExpression_version_001;

type
  TGrispExpressionEvaluator = class
  private
    class function EvaluateLiteral(Expression: TGrispExpression): TGrispValue; static;
    class function EvaluateVariable(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function EvaluateUnary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function EvaluateBinary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function EvaluateCall(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue; static;
    class function RequireNumber(Value: TGrispValue; const Context: string): Double; static;
    class function RequireBoolean(Value: TGrispValue; const Context: string): Boolean; static;
    class procedure EnsureArgumentCount(Expression: TGrispExpression; Expected: Integer); static;
  public
    class function Evaluate(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
  end;

implementation

class function TGrispExpressionEvaluator.Evaluate(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
begin
  if Expression = nil then Exit(nil);
  case Expression.Kind of
    gekLiteral: Result := EvaluateLiteral(Expression);
    gekVariable: Result := EvaluateVariable(Expression, Bindings);
    gekUnary: Result := EvaluateUnary(Expression, Bindings);
    gekBinary: Result := EvaluateBinary(Expression, Bindings);
    gekCall: Result := EvaluateCall(Expression, Bindings);
  else
    Result := nil;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateLiteral(Expression: TGrispExpression): TGrispValue;
begin
  if Assigned(Expression.Value) then
    Result := TGrispValue(Expression.Value).Clone
  else
    Result := nil;
end;

class function TGrispExpressionEvaluator.EvaluateVariable(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var BoundValue: TGrispValue;
begin
  if not Assigned(Bindings) then
    raise Exception.Create('No variable bindings supplied');
  if Bindings.TryGetValue(Expression.Name, BoundValue) then
    Result := BoundValue.Clone
  else
    raise Exception.CreateFmt('Unbound variable "%s"', [Expression.Name]);
end;

class function TGrispExpressionEvaluator.EvaluateUnary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var Operand: TGrispValue;
begin
  Operand := Evaluate(Expression.Left, Bindings);
  try
    if SameText(Expression.OperatorSymbol, 'not') then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := not RequireBoolean(Operand, 'not');
      Exit;
    end;
    if Expression.OperatorSymbol = '-' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := -RequireNumber(Operand, 'unary -');
      Exit;
    end;
    raise Exception.CreateFmt('Unknown unary operator "%s"', [Expression.OperatorSymbol]);
  finally
    Operand.Free;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateBinary(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var LeftValue, RightValue: TGrispValue; RightNumber: Double; LeftBool, RightBool: Boolean;
begin
  LeftValue := Evaluate(Expression.Left, Bindings);
  RightValue := Evaluate(Expression.Right, Bindings);
  try
    if Expression.OperatorSymbol = '+' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '+') + RequireNumber(RightValue, '+');
      Exit;
    end;
    if Expression.OperatorSymbol = '-' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '-') - RequireNumber(RightValue, '-');
      Exit;
    end;
    if Expression.OperatorSymbol = '*' then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '*') * RequireNumber(RightValue, '*');
      Exit;
    end;
    if Expression.OperatorSymbol = '/' then
    begin
      RightNumber := RequireNumber(RightValue, '/');
	  if RightNumber = 0 then raise Exception.Create('Division by zero');
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := RequireNumber(LeftValue, '/') / RightNumber;
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'mod') then
    begin
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := Trunc(RequireNumber(LeftValue, 'mod')) mod Trunc(RequireNumber(RightValue, 'mod'));
      Exit;
    end;
    if Expression.OperatorSymbol = '=' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '=') = RequireNumber(RightValue, '=');
      Exit;
    end;
    if Expression.OperatorSymbol = '<>' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<>') <> RequireNumber(RightValue, '<>');
      Exit;
    end;
    if Expression.OperatorSymbol = '<' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<') < RequireNumber(RightValue, '<');
      Exit;
    end;
    if Expression.OperatorSymbol = '>' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '>') > RequireNumber(RightValue, '>');
      Exit;
    end;
    if Expression.OperatorSymbol = '<=' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '<=') <= RequireNumber(RightValue, '<=');
      Exit;
    end;
    if Expression.OperatorSymbol = '>=' then
    begin
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := RequireNumber(LeftValue, '>=') >= RequireNumber(RightValue, '>=');
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'and') then
    begin
      LeftBool := RequireBoolean(LeftValue, 'and');
      RightBool := RequireBoolean(RightValue, 'and');
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := LeftBool and RightBool;
      Exit;
    end;
    if SameText(Expression.OperatorSymbol, 'or') then
    begin
      LeftBool := RequireBoolean(LeftValue, 'or');
      RightBool := RequireBoolean(RightValue, 'or');
      Result := TGrispValue.Create(gvkBoolean);
      Result.BoolValue := LeftBool or RightBool;
      Exit;
    end;
    raise Exception.CreateFmt('Unknown binary operator "%s"', [Expression.OperatorSymbol]);
  finally
    LeftValue.Free;
	RightValue.Free;
  end;
end;

class function TGrispExpressionEvaluator.EvaluateCall(Expression: TGrispExpression; Bindings: TDictionary<string, TGrispValue>): TGrispValue;
var Arg0, Arg1, Arg2: TGrispValue; N0, N1, N2: Double;
begin
  if SameText(Expression.Name, 'min') then
  begin
    EnsureArgumentCount(Expression, 2);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    try
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := Min(RequireNumber(Arg0, 'min'), RequireNumber(Arg1, 'min'));
    finally Arg0.Free; Arg1.Free; end;
    Exit;
  end;
  if SameText(Expression.Name, 'max') then
  begin
    EnsureArgumentCount(Expression, 2);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    try
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := Max(RequireNumber(Arg0, 'max'), RequireNumber(Arg1, 'max'));
    finally Arg0.Free; Arg1.Free; end;
    Exit;
  end;
  if SameText(Expression.Name, 'mid') then
  begin
    EnsureArgumentCount(Expression, 3);
    Arg0 := Evaluate(Expression.Arguments[0], Bindings);
    Arg1 := Evaluate(Expression.Arguments[1], Bindings);
    Arg2 := Evaluate(Expression.Arguments[2], Bindings);
    try
      N0 := RequireNumber(Arg0, 'mid'); N1 := RequireNumber(Arg1, 'mid'); N2 := RequireNumber(Arg2, 'mid');
      Result := TGrispValue.Create(gvkNumber);
      Result.NumberValue := N0 + N1 + N2 - Min(Min(N0, N1), N2) - Max(Max(N0, N1), N2);
    finally Arg0.Free; Arg1.Free; Arg2.Free; end;
    Exit;
  end;
  raise Exception.CreateFmt('Unknown function "%s"', [Expression.Name]);
end;

class function TGrispExpressionEvaluator.RequireNumber(Value: TGrispValue; const Context: string): Double;
begin
  if not Assigned(Value) or (Value.Kind <> gvkNumber) then
    raise Exception.CreateFmt('Operator "%s" requires number operands', [Context]);
  Result := Value.NumberValue;
end;

class function TGrispExpressionEvaluator.RequireBoolean(Value: TGrispValue; const Context: string): Boolean;
begin
  if not Assigned(Value) or (Value.Kind <> gvkBoolean) then
    raise Exception.CreateFmt('Operator "%s" requires boolean operands', [Context]);
  Result := Value.BoolValue;
end;

class procedure TGrispExpressionEvaluator.EnsureArgumentCount(Expression: TGrispExpression; Expected: Integer);
begin
  if Expression.Arguments.Count <> Expected then
    raise Exception.CreateFmt('Function "%s" expects %d arguments, got %d',
      [Expression.Name, Expected, Expression.Arguments.Count]);
end;

end.
