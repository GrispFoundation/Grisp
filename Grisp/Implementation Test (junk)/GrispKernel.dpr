program GrispKernel;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Grisp.Core in 'Grisp.Core.pas',
  Grisp.JSON in 'Grisp.JSON.pas',
  Grisp.AST in 'Grisp.AST.pas',
  Grisp.Evaluator in 'Grisp.Evaluator.pas',
  Grisp.Parser in 'Grisp.Parser.pas',
  Grisp.Engine in 'Grisp.Engine.pas';

function ReadStdin: string;
var
  Line: string;
begin
  Result := '';
  while not Eof do
  begin
    Readln(Line);
    Result := Result + Line + #10;
  end;
end;

procedure WriteOutput(const APath, AContent: string);
var
  SWriter: TStreamWriter;
begin
  if (APath = '') or (APath = '-') then
    Write(AContent)
  else
  begin
    SWriter := TStreamWriter.Create(APath, False, TEncoding.UTF8);
    try
      SWriter.Write(AContent);
    finally
      SWriter.Free;
    end;
  end;
end;

function FormatErrJSON(const ACode, AMsg: string; ATick: Int64): string;
begin
  Result := '{"code":"' + ACode + '","context":{"location":0,"message":"' + AMsg + '"},"state":null,"tick":' + IntToStr(ATick) + '}';
end;

var
  InputPath, OutputPath: string;
  InputJSON, OutputJSON: string;
  Rules: TObjectList<TRule>;
  State: TState;
  MaxTicks: Int64;
  TypeHash: string;
  Engine: TEngine;
  ResultVal: TValue;
begin
  try
    InputPath := '';
    OutputPath := '';
    if ParamCount >= 1 then
      InputPath := ParamStr(1);
    if ParamCount >= 2 then
      OutputPath := ParamStr(2);

    if InputPath = '' then
    begin
      Writeln(ErrOutput, 'Usage: GrispKernel <input_file_or_-> [<output_file_or_->]');
	  Halt(1);
    end;

    if InputPath = '-' then
      InputJSON := ReadStdin
    else
    begin
      if not FileExists(InputPath) then
      begin
        Writeln(ErrOutput, 'Input file not found: ' + InputPath);
        Halt(1);
      end;
      InputJSON := TFile.ReadAllText(InputPath, TEncoding.UTF8);
    end;

    Rules := nil;
    State := nil;
    try
      ParseInput(InputJSON, Rules, State, MaxTicks, TypeHash);
    except
      on E: Exception do
      begin
        OutputJSON := FormatErrJSON('INVALID_IR', E.Message, 0);
        WriteOutput(OutputPath, OutputJSON);
        Halt(0);
      end;
    end;

    try
      Engine := TEngine.Create(Rules, State, MaxTicks, TypeHash);
      try
        ResultVal := Engine.ExecuteSimulation;
        OutputJSON := SerializeJSON(ResultVal);
        WriteOutput(OutputPath, OutputJSON);
      finally
        Engine.Free;
      end;
    except
      on E: Exception do
      begin
        OutputJSON := FormatErrJSON('RESOURCE_LIMIT_EXCEEDED', E.Message, 0);
        WriteOutput(OutputPath, OutputJSON);
      end;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Fatal CLI error: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
