program GrispCLI;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  GrispExecutor in '..\..\Source Code\GrispExecutor.pas',
  GrispLexer in '..\..\Source Code\GrispLexer.pas',
  GrispParser in '..\..\Source Code\GrispParser.pas';

procedure PrintInvalidIR(const Msg: string);
begin
  // Deterministic JSON error output
  Writeln('{"error":"INVALID_IR","message":"', StringReplace(Msg, '"', '\"', [rfReplaceAll]), '"}');
end;

function ReadAllInput: string;
var
  sl: TStringList;
  s: string;
begin
  sl := TStringList.Create;
  try
    if ParamCount >= 1 then
    begin
      if not FileExists(ParamStr(1)) then
      begin
        Writeln('ERROR: input file not found: ', ParamStr(1));
        Halt(1);
      end;
      sl.LoadFromFile(ParamStr(1));
      s := sl.Text;
      Writeln('DEBUG: reading input from file: ', ParamStr(1));
    end
    else
    begin
      // fallback: read stdin (works with redirect or interactive + EOF)
      sl.Clear;
      Writeln('DEBUG: reading input from stdin (send EOF when done)');
      while not EOF do
      begin
        ReadLn(s);
        sl.Add(s);
      end;
      s := sl.Text;
    end;

    // Remove Unicode BOM (UTF-8/UTF-16) if present
    if (Length(s) > 0) and (s[1] = #$FEFF) then
      Delete(s, 1, 1);

    // Defensive: remove UTF-8 BOM bytes if present
    if (Length(s) >= 3) and (Ord(s[1]) = $EF) and (Ord(s[2]) = $BB) and (Ord(s[3]) = $BF) then
      Delete(s, 1, 3);

    // Trim leading ASCII whitespace/newlines so parser sees 'rules' at pos 1
    while (Length(s) > 0) and (s[1] <= ' ') do Delete(s, 1, 1);

    Result := s;
  finally
    sl.Free;
  end;
end;

var
  inputText: string;
  parser: TParser;
  rules: TRuleArray;
  executor: TExecutor;
  i, j: Integer;
  actionsList: TStringList;
  actionsArr: TArray<string>;
  a: TAction;
  sb: TStringBuilder;
  pi: Integer;
begin
  try
    // Read input (file param preferred, else stdin)
    inputText := ReadAllInput;

    // Parse
    parser := TParser.Create(inputText);
    try
      try
        rules := parser.Parse;
      except
        on E: Exception do
        begin
          PrintInvalidIR(E.Message);
          Halt(2);
        end;
      end;
    finally
      parser.Free;
    end;

    // Minimal serialization of actions into deterministic strings for executor
    actionsList := TStringList.Create;
    try
      for i := 0 to Length(rules) - 1 do
      begin
        for j := 0 to Length(rules[i].Actions) - 1 do
        begin
          a := rules[i].Actions[j];
          case a.Kind of
            akCreateNode:
              actionsList.Add('CreateNode|' + a.AName + '|' + a.AType);
            akUpdateField:
              begin
                if (a.Params <> nil) and (a.Params.Count > 0) then
                  actionsList.Add('UpdateField|' + a.AName + '|' + a.Params[0] + '|' + '<<expr>>')
                else
                  actionsList.Add('UpdateField|' + a.AName + '|' + '' + '|' + '<<expr>>');
              end;
            akDeleteNode:
              actionsList.Add('DeleteNode|' + a.AName);
            akEmitEvent:
              begin
                // include payload items if present
                if (a.Params <> nil) and (a.Params.Count > 0) then
                begin
                  // build "EmitEvent|eventName|item1|item2|..."
                  sb := TStringBuilder.Create;
                  try
                    sb.Append('EmitEvent|');
                    sb.Append(a.AType);
                    for pi := 0 to a.Params.Count - 1 do
                    begin
                      sb.Append('|');
                      sb.Append(a.Params[pi]);
                    end;
                    actionsList.Add(sb.ToString);
                  finally
                    sb.Free;
                  end;
                end
                else
                  actionsList.Add('EmitEvent|' + a.AType);
              end;
            akQuery:
              actionsList.Add('EmitEvent|query_response|' + a.AType);
          end;
        end;
      end;

      // Convert TStringList to dynamic array of string for ExecuteRules
      SetLength(actionsArr, actionsList.Count);
      for i := 0 to actionsList.Count - 1 do
        actionsArr[i] := actionsList[i];

      // Execute
      executor := TExecutor.Create;
      try
        executor.ExecuteRules(actionsArr);
      finally
        executor.Free;
      end;

    finally
      actionsList.Free;
    end;

  except
    on E: Exception do
    begin
      PrintInvalidIR(E.Message);
      Halt(3);
    end;
  end;
end.

