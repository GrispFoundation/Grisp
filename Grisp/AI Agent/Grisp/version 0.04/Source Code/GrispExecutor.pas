unit GrispExecutor;

interface

uses
  SysUtils, Classes;

type
  TEvent = record
    Name: string;
    Payload: TStringList;
  end;

  TExecutor = class
  private
    procedure EmitEvent(const AName: string; APayload: TStringList);
    procedure CreateNode(const AName, AType: string);
    procedure UpdateField(const AName, AField: string; const AValue: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ExecuteRules(const Rules: TArray<string>); // minimal: accept serialized actions
    procedure PrintEvents;
  end;

implementation

{ TExecutor }

constructor TExecutor.Create;
begin
  inherited Create;
  // geen opslag van events meer; we streamen direct
end;

destructor TExecutor.Destroy;
begin
  inherited Destroy;
end;

function EscapeJSON(const S: string): string;
begin
  // eenvoudige JSON string escape (quotes and backslashes)
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  // control chars could be expanded if needed
end;

procedure TExecutor.EmitEvent(const AName: string; APayload: TStringList);
var
  i: Integer;
  s: string;
begin
  // Print deterministic canonical JSON for the event
  Write('{"event": "');
  Write(EscapeJSON(AName));
  Write('", "payload": [');
  if (APayload <> nil) and (APayload.Count > 0) then
  begin
    WriteLn;
    s := EscapeJSON(APayload[0]);
    Write('  "');
    Write(s);
    Write('"');
    for i := 1 to APayload.Count - 1 do
    begin
      WriteLn(',');
      s := EscapeJSON(APayload[i]);
      Write('  "');
      Write(s);
      Write('"');
    end;
    WriteLn;
    Write(']}');
    WriteLn;
  end
  else
  begin
    Write(']}');
    WriteLn;
  end;
end;

procedure TExecutor.CreateNode(const AName, AType: string);
var
  payload: TStringList;
begin
  payload := TStringList.Create;
  try
    payload.Add(AName);
    payload.Add(AType);
    EmitEvent('create_node', payload);
  finally
    payload.Free;
  end;
end;

procedure TExecutor.UpdateField(const AName, AField: string; const AValue: string);
var
  payload: TStringList;
begin
  payload := TStringList.Create;
  try
    payload.Add(AName);
    payload.Add(AField);
    payload.Add(AValue);
    EmitEvent('update_field', payload);
  finally
    payload.Free;
  end;
end;

procedure TExecutor.ExecuteRules(const Rules: TArray<string>);
var
  i, j: Integer;
  ruleLine: string;
  parts: TStringList;
  cmd: string;
  payload: TStringList;
begin
  // Each Rules entry is expected as "Action|param1|param2|..."
  for i := 0 to Length(Rules) - 1 do
  begin
    ruleLine := Rules[i];
    parts := TStringList.Create;
    try
      parts.StrictDelimiter := True;
      parts.Delimiter := '|';
      parts.DelimitedText := ruleLine;

      if parts.Count = 0 then
        Continue;

      cmd := parts[0];

      if SameText(cmd, 'CreateNode') then
      begin
        if parts.Count >= 3 then
          CreateNode(parts[1], parts[2]);
      end
      else if SameText(cmd, 'UpdateField') then
      begin
        if parts.Count >= 4 then
          UpdateField(parts[1], parts[2], parts[3]);
      end
      else if SameText(cmd, 'EmitEvent') then
      begin
        // parts[1] = event name, parts[2..] = payload items (if any)
        payload := TStringList.Create;
        try
          if parts.Count >= 3 then
          begin
            for j := 2 to parts.Count - 1 do
              payload.Add(parts[j]);
          end;
          EmitEvent(parts[1], payload);
        finally
          payload.Free;
        end;
      end
      else if SameText(cmd, 'DeleteNode') then
      begin
        // Minimal behavior: emit delete event
        payload := TStringList.Create;
        try
          if parts.Count >= 2 then
            payload.Add(parts[1]);
          EmitEvent('delete_node', payload);
        finally
          payload.Free;
        end;
      end
      else
      begin
        // Unknown command: ignore or optionally emit an error event
        // EmitEvent('unknown_command', TStringList.Create); // optional
      end;

    finally
      parts.Free;
    end;
  end;
end;

procedure TExecutor.PrintEvents;
begin
  // events are printed as they are emitted; nothing to do here
end;

end.

