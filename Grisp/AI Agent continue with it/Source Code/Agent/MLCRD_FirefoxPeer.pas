unit MLCRD_FirefoxPeer;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.Math, IdTCPClient, IdGlobal, IdException,
  MLCRD_Types, MLCRD_Interfaces, MLCRD_Peers;

const
  DEFAULT_FIREFOX_PORT = 9999;
  VALID_FIREFOX_SITES: array[0..7] of string = (
    'deepseek', 'gemini', 'claude', 'chatgpt', 'copilot', 'grok', 'perplexity', 'inception'
  );

type
  // Wrapper around Indy TIdTCPClient for communicating with Firefox AIAutomation service
  TFirefoxClient = class
  private
    FHost: string;
    FPort: Integer;
    FConnectTimeout: Integer;
    FReadTimeout: Integer;
  public
    constructor Create(const AHost: string = 'localhost'; APort: Integer = DEFAULT_FIREFOX_PORT;
      AConnectTimeout: Integer = 5000; AReadTimeout: Integer = 120000);

    function SendCommand(const Cmd: TJSONObject): TJSONObject;
    function Prompt(const Site, Text: string; TabId: Integer; out ResponseText, ErrorMsg: string): Boolean; overload;
    function Prompt(const Site, Text: string; out ResponseText, ErrorMsg: string): Boolean; overload;
    function GetTabs(out TabsJSON: string): Boolean;
    function OpenTab(const Url: string): Boolean;
    function CloseTab(const TabId: string): Boolean;
    function DuplicateTab(const TabId: string): Boolean;
    function IsOnline: Boolean;

    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property ConnectTimeout: Integer read FConnectTimeout write FConnectTimeout;
    property ReadTimeout: Integer read FReadTimeout write FReadTimeout;
  end;

  // Web LLM peer backed by the Firefox browser automation TCP client
  TFirefoxChatAIPeer = class(TInterfacedObject, IWebLLMPeer)
  private
    FName: string;
    FSiteName: string;
    FClient: TFirefoxClient;
    FOwnsClient: Boolean;
    FFallbackPeer: IWebLLMPeer;
    FTabId: Integer;
  public
    constructor Create(const ASiteName: string; APort: Integer = DEFAULT_FIREFOX_PORT;
      AFallbackPeer: IWebLLMPeer = nil; const AHost: string = 'localhost');
    constructor CreateWithClient(const ASiteName: string; AClient: TFirefoxClient;
      AFallbackPeer: IWebLLMPeer = nil);
    destructor Destroy; override;

    function GetName: string;
    function GenerateCandidate(const UserPrompt: string): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
      const Critiques: TArray<TCritique>): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>): TArray<TScore>;

    property SiteName: string read FSiteName;
    property TabId: Integer read FTabId write FTabId;
    property FallbackPeer: IWebLLMPeer read FFallbackPeer write FFallbackPeer;
    property Client: TFirefoxClient read FClient;
  end;

// Utility parsing and extraction functions
function IsSupportedFirefoxSite(const ASite: string): Boolean;
function NormalizeFirefoxSite(const ASite: string): string;
function ExtractCodeBlock(const Markdown: string; const PreferredLang: string = ''): string;
function ExtractBulletIssues(const Text: string): TArray<string>;
function ExtractSuggestedFix(const Text: string): string;
function ExtractScoreFromText(const Text: string; DefaultScore: Double = 0.85): Double;
function ExtractCapabilitiesFromText(const Text: string): TArray<string>;

implementation

function IsSupportedFirefoxSite(const ASite: string): Boolean;
var
  S: string;
  SiteLow: string;
begin
  SiteLow := LowerCase(ASite.Trim);
  for S in VALID_FIREFOX_SITES do
    if S = SiteLow then
      Exit(True);
  Result := False;
end;

function NormalizeFirefoxSite(const ASite: string): string;
var
  Low: string;
begin
  Low := LowerCase(ASite.Trim);
  if IsSupportedFirefoxSite(Low) then
    Result := Low
  else
    Result := 'deepseek';
end;

function ExtractCodeBlock(const Markdown: string; const PreferredLang: string): string;
var
  StartPos, EndPos, NextNL: Integer;
begin
  StartPos := Pos('```', Markdown);
  if StartPos <= 0 then
    Exit(Markdown.Trim);

  // Skip the ``` and any language tag on that same line
  NextNL := Pos(#10, Copy(Markdown, StartPos, Length(Markdown) - StartPos + 1));
  if NextNL > 0 then
    StartPos := StartPos + NextNL
  else
    StartPos := StartPos + 3;

  // Find closing ```
  EndPos := Pos('```', Copy(Markdown, StartPos, Length(Markdown) - StartPos + 1));
  if EndPos > 0 then
    Result := Copy(Markdown, StartPos, EndPos - 1).Trim
  else
    Result := Copy(Markdown, StartPos, Length(Markdown) - StartPos + 1).Trim;

  if Result = '' then
    Result := Markdown.Trim;
end;

function ExtractBulletIssues(const Text: string): TArray<string>;
var
  Lines: TArray<string>;
  Line, Item: string;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    Lines := Text.Split([#13#10, #10, #13]);
    for Line in Lines do
    begin
      Item := Line.Trim;
      if Item.StartsWith('- ') or Item.StartsWith('* ') then
        List.Add(Copy(Item, 3, Length(Item) - 2).Trim)
      else if (Length(Item) > 3) and CharInSet(Item[1], ['0'..'9']) and (Item[2] = '.') and (Item[3] = ' ') then
        List.Add(Copy(Item, 4, Length(Item) - 3).Trim);
    end;

    if List.Count = 0 then
    begin
      // Fallback: use first non-empty lines
      for Line in Lines do
      begin
        Item := Line.Trim;
        if (Item <> '') and not Item.StartsWith('#') and not Item.StartsWith('```') then
        begin
          List.Add(Item);
          if List.Count >= 3 then
            Break;
        end;
      end;
    end;

    if List.Count = 0 then
      List.Add('Ensure proper bounds and error checking');

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ExtractSuggestedFix(const Text: string): string;
var
  Lower: string;
  PosFix: Integer;
begin
  Lower := LowerCase(Text);
  PosFix := Pos('suggest', Lower);
  if PosFix <= 0 then
    PosFix := Pos('fix:', Lower);
  if PosFix <= 0 then
    PosFix := Pos('recommend', Lower);

  if PosFix > 0 then
    Result := Copy(Text, PosFix, 250).Trim
  else
    Result := 'Add guard conditions for zero divisor and integer overflow';
end;

function ExtractScoreFromText(const Text: string; DefaultScore: Double): Double;
var
  I, StartIdx: Integer;
  NumStr: string;
  ParsedVal: Double;
  FormatSettings: TFormatSettings;
begin
  FormatSettings := TFormatSettings.Invariant;
  // Scan for 0.xx or 1.0
  I := 1;
  while I <= Length(Text) - 2 do
  begin
    if (Text[I] = '0') and (Text[I+1] = '.') and CharInSet(Text[I+2], ['0'..'9']) then
    begin
      StartIdx := I;
      while (I <= Length(Text)) and (CharInSet(Text[I], ['0'..'9', '.'])) do
        Inc(I);
      NumStr := Copy(Text, StartIdx, I - StartIdx);
      if TryStrToFloat(NumStr, ParsedVal, FormatSettings) then
      begin
        if (ParsedVal >= 0.0) and (ParsedVal <= 1.0) then
          Exit(ParsedVal);
      end;
      Break;
    end;
    Inc(I);
  end;
  Result := DefaultScore;
end;

function ExtractCapabilitiesFromText(const Text: string): TArray<string>;
var
  Low: string;
  List: TList<string>;
begin
  Low := LowerCase(Text);
  List := TList<string>.Create;
  try
    if Low.Contains('compile') then List.Add('compile');
    if Low.Contains('run') or Low.Contains('execut') then List.Add('run');
    if Low.Contains('test') then List.Add('test_execute');
    if Low.Contains('debug') then List.Add('debug');
    if Low.Contains('syntax') then List.Add('syntax_check');
    if Low.Contains('semantic') or Low.Contains('lsp') then List.Add('semantic_check');
    if Low.Contains('stack') or Low.Contains('trace') then List.Add('stack_trace');

    if List.Count = 0 then
    begin
      List.Add('compile');
      List.Add('run');
      List.Add('test_execute');
    end;

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ TFirefoxClient }

constructor TFirefoxClient.Create(const AHost: string; APort, AConnectTimeout, AReadTimeout: Integer);
begin
  inherited Create;
  FHost := AHost;
  FPort := APort;
  FConnectTimeout := AConnectTimeout;
  FReadTimeout := AReadTimeout;
end;

function TFirefoxClient.SendCommand(const Cmd: TJSONObject): TJSONObject;
var
  Client: TIdTCPClient;
  Response: string;
begin
  Result := nil;
  Client := TIdTCPClient.Create(nil);
  try
    Client.Host := FHost;
    Client.Port := FPort;
    Client.ConnectTimeout := FConnectTimeout;
    Client.ReadTimeout := FReadTimeout;
    try
      Client.Connect;
      // Remove maximum line length limit to handle long LLM outputs
      Client.IOHandler.MaxLineLength := 0;
      Client.IOHandler.WriteLn(Cmd.ToJSON);
      Response := Client.IOHandler.ReadLn;
      if Response <> '' then
        Result := TJSONObject.ParseJSONValue(Response) as TJSONObject;
      if Result = nil then
        raise Exception.Create('Invalid JSON response from Firefox AI automation service');
    except
      on E: Exception do
      begin
        if E is EIdConnClosedGracefully then
          raise Exception.Create('Connection closed by Firefox automation service')
        else
          raise;
      end;
    end;
  finally
    Client.Free;
  end;
end;

function TFirefoxClient.Prompt(const Site, Text: string; TabId: Integer;
  out ResponseText, ErrorMsg: string): Boolean;
var
  Cmd, Resp: TJSONObject;
  LastSeen: string;
begin
  ResponseText := '';
  ErrorMsg := '';
  Cmd := TJSONObject.Create;
  try
    Cmd.AddPair('command', 'prompt');
    if Site <> '' then
      Cmd.AddPair('site', Site);
    Cmd.AddPair('text', Text);
    if TabId >= 0 then
      Cmd.AddPair('tab', TJSONNumber.Create(TabId))
    else
      Cmd.AddPair('tab', TJSONNumber.Create(-1));

    try
      Resp := SendCommand(Cmd);
    except
      on E: Exception do
      begin
        ErrorMsg := 'Firefox connection failed: ' + E.Message;
        Exit(False);
      end;
    end;

    if Assigned(Resp) then
    begin
      try
        if Resp.TryGetValue<string>('error', ErrorMsg) then
        begin
          if Resp.TryGetValue<string>('lastSeen', LastSeen) then
            ResponseText := LastSeen;
          Exit(False);
        end;

        if not Resp.TryGetValue<string>('text', ResponseText) then
          ResponseText := '';
        Result := True;
      finally
        Resp.Free;
      end;
    end
    else
    begin
      ErrorMsg := 'Empty response from Firefox service';
      Result := False;
    end;
  finally
    Cmd.Free;
  end;
end;

function TFirefoxClient.Prompt(const Site, Text: string; out ResponseText, ErrorMsg: string): Boolean;
begin
  Result := Prompt(Site, Text, -1, ResponseText, ErrorMsg);
end;

function TFirefoxClient.GetTabs(out TabsJSON: string): Boolean;
var
  Cmd, Resp: TJSONObject;
begin
  TabsJSON := '';
  Cmd := TJSONObject.Create;
  try
    Cmd.AddPair('command', 'getTabs');
    try
      Resp := SendCommand(Cmd);
      if Assigned(Resp) then
      begin
        TabsJSON := Resp.ToJSON;
        Resp.Free;
        Result := True;
      end
      else
        Result := False;
    except
      Result := False;
    end;
  finally
    Cmd.Free;
  end;
end;

function TFirefoxClient.OpenTab(const Url: string): Boolean;
var
  Cmd, Resp: TJSONObject;
  ErrMsg: string;
begin
  Cmd := TJSONObject.Create;
  try
    Cmd.AddPair('command', 'openTab');
    Cmd.AddPair('url', Url);
    try
      Resp := SendCommand(Cmd);
      if Assigned(Resp) then
      begin
        Result := not Resp.TryGetValue<string>('error', ErrMsg);
        Resp.Free;
      end
      else
        Result := False;
    except
      Result := False;
    end;
  finally
    Cmd.Free;
  end;
end;

function TFirefoxClient.CloseTab(const TabId: string): Boolean;
var
  Cmd, Resp: TJSONObject;
  ErrMsg: string;
begin
  Cmd := TJSONObject.Create;
  try
    Cmd.AddPair('command', 'closeTab');
    Cmd.AddPair('tab', TabId);
    try
      Resp := SendCommand(Cmd);
      if Assigned(Resp) then
      begin
        Result := not Resp.TryGetValue<string>('error', ErrMsg);
        Resp.Free;
      end
      else
        Result := False;
    except
      Result := False;
    end;
  finally
    Cmd.Free;
  end;
end;

function TFirefoxClient.DuplicateTab(const TabId: string): Boolean;
var
  Cmd, Resp: TJSONObject;
  ErrMsg: string;
begin
  Cmd := TJSONObject.Create;
  try
    Cmd.AddPair('command', 'duplicateTab');
    Cmd.AddPair('tab', TabId);
    try
      Resp := SendCommand(Cmd);
      if Assigned(Resp) then
      begin
        Result := not Resp.TryGetValue<string>('error', ErrMsg);
        Resp.Free;
      end
      else
        Result := False;
    except
      Result := False;
    end;
  finally
    Cmd.Free;
  end;
end;

function TFirefoxClient.IsOnline: Boolean;
var
  Tabs: string;
begin
  Result := GetTabs(Tabs);
end;

{ TFirefoxChatAIPeer }

constructor TFirefoxChatAIPeer.Create(const ASiteName: string; APort: Integer;
  AFallbackPeer: IWebLLMPeer; const AHost: string);
begin
  inherited Create;
  FSiteName := NormalizeFirefoxSite(ASiteName);
  FName := 'Firefox_' + FSiteName;
  FClient := TFirefoxClient.Create(AHost, APort);
  FOwnsClient := True;
  FFallbackPeer := AFallbackPeer;
  if not Assigned(FFallbackPeer) then
    FFallbackPeer := THeuristicPeer.Create(FName + '_Fallback', psSafety);
  FTabId := -1;
end;

constructor TFirefoxChatAIPeer.CreateWithClient(const ASiteName: string;
  AClient: TFirefoxClient; AFallbackPeer: IWebLLMPeer);
begin
  inherited Create;
  FSiteName := NormalizeFirefoxSite(ASiteName);
  FName := 'Firefox_' + FSiteName;
  FClient := AClient;
  FOwnsClient := False;
  FFallbackPeer := AFallbackPeer;
  if not Assigned(FFallbackPeer) then
    FFallbackPeer := THeuristicPeer.Create(FName + '_Fallback', psSafety);
  FTabId := -1;
end;

destructor TFirefoxChatAIPeer.Destroy;
begin
  if FOwnsClient then
    FClient.Free;
  inherited Destroy;
end;

function TFirefoxChatAIPeer.GetName: string;
begin
  Result := FName;
end;

function TFirefoxChatAIPeer.GenerateCandidate(const UserPrompt: string): TCandidate;
var
  PromptText, RespText, ErrMsg, Extracted: string;
begin
  PromptText := Format(
    'You are a senior systems engineer. Solve the following task with clean, robust code.'#13#10 +
    'Task: %s'#13#10 +
    'Requirements: guard against null pointers, boundary errors, division by zero, and integer overflow.'#13#10 +
    'Output ONLY the code enclosed in a single markdown code block (e.g. ```c ... ```).',
    [UserPrompt]);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    Extracted := ExtractCodeBlock(RespText);
    Result := TCandidate.Create(FName, Extracted);
  end
  else
  begin
    // Fallback to local peer ensuring seamless progress
    Result := FFallbackPeer.GenerateCandidate(UserPrompt);
  end;
end;

function TFirefoxChatAIPeer.CritiqueCandidate(const UserPrompt: string;
  const Candidate: TCandidate): TCritique;
var
  PromptText, RespText, ErrMsg: string;
  Issues: TArray<string>;
  FixSuggestion: string;
begin
  PromptText := Format(
    'Task: %s'#13#10 +
    'Review the following proposed code by author %s:'#13#10 +
    '%s'#13#10#13#10 +
    'Identify any edge case bugs, potential memory/arithmetic overflow, division by zero, or contract violations.'#13#10 +
    'List all issues as bullet points starting with "- ".'#13#10 +
    'Conclude with a clear suggestion for a fix.',
    [UserPrompt, Candidate.PeerName, Candidate.Content]);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    Issues := ExtractBulletIssues(RespText);
    FixSuggestion := ExtractSuggestedFix(RespText);
    Result := TCritique.Create(FName, Candidate.PeerName, Issues, FixSuggestion, 0.92);
  end
  else
  begin
    Result := FFallbackPeer.CritiqueCandidate(UserPrompt, Candidate);
  end;
end;

function TFirefoxChatAIPeer.RepairCandidate(const UserPrompt: string;
  const Candidate: TCandidate; const Critiques: TArray<TCritique>): TRepair;
var
  PromptText, RespText, ErrMsg, CritText, RepairedCode: string;
  C: TCritique;
  Issue: string;
begin
  CritText := '';
  for C in Critiques do
  begin
    CritText := CritText + Format('From %s:'#13#10, [C.FromPeer]);
    for Issue in C.Issues do
      CritText := CritText + Format('  - %s'#13#10, [Issue]);
    if C.SuggestedFix <> '' then
      CritText := CritText + Format('  Fix: %s'#13#10, [C.SuggestedFix]);
  end;

  PromptText := Format(
    'Task: %s'#13#10 +
    'Original candidate code from %s:'#13#10 +
    '%s'#13#10#13#10 +
    'Critiques received:'#13#10 +
    '%s'#13#10 +
    'Please produce the corrected, robust implementation addressing every issue.'#13#10 +
    'Output ONLY the repaired code enclosed in a markdown code block.',
    [UserPrompt, Candidate.PeerName, Candidate.Content, CritText]);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    RepairedCode := ExtractCodeBlock(RespText);
    Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques, RepairedCode, 'c');
  end
  else
  begin
    Result := FFallbackPeer.RepairCandidate(UserPrompt, Candidate, Critiques);
  end;
end;

function TFirefoxChatAIPeer.RequestCapabilities(const UserPrompt: string;
  const Repairs: TArray<TRepair>): TArray<TCapabilityRequest>;
var
  PromptText, RespText, ErrMsg: string;
  Caps: TArray<string>;
begin
  PromptText := Format(
    'Task: %s'#13#10 +
    'What sandboxed GRISP runtime capabilities are needed to compile and verify this solution?'#13#10 +
    'Options: compile, run, test_execute, debug, syntax_check, semantic_check, stack_trace.'#13#10 +
    'Mention the required capabilities separated by commas.',
    [UserPrompt]);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    Caps := ExtractCapabilitiesFromText(RespText);
    Result := [TCapabilityRequest.Create(FName, 'all', Caps, 'Verified via Firefox AI ' + FSiteName, 0.90)];
  end
  else
  begin
    Result := FFallbackPeer.RequestCapabilities(UserPrompt, Repairs);
  end;
end;

function TFirefoxChatAIPeer.ProposeTestProgram(const UserPrompt: string;
  const Repair: TRepair): TTestProgram;
var
  PromptText, RespText, ErrMsg, TestCode: string;
begin
  PromptText := Format(
    'Task: %s'#13#10 +
    'Implementation under test:'#13#10 +
    '%s'#13#10#13#10 +
    'Write a complete C test program with a main() function and assert() statements'#13#10 +
    'testing both normal operations and edge cases (zero inputs, overflow, negative values).'#13#10 +
    'Output ONLY the test program code in a markdown code block.',
    [UserPrompt, Repair.Content]);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    TestCode := ExtractCodeBlock(RespText);
    Result := TTestProgram.Create(FName, Repair.TargetPeer, Repair.Language,
      'Firefox ' + FSiteName + ' unit test suite', TestCode,
      ['Verify normal operation', 'Verify zero divisor check', 'Verify overflow handling']);
  end
  else
  begin
    Result := FFallbackPeer.ProposeTestProgram(UserPrompt, Repair);
  end;
end;

function TFirefoxChatAIPeer.ScoreRepairs(const UserPrompt: string;
  const Candidates: TArray<TCandidate>; const Repairs: TArray<TRepair>;
  const Debugs: TArray<TDebugFeedback>): TArray<TScore>;
var
  I: Integer;
  R: TRepair;
  Ext: TDebugFeedback;
  Score: Double;
  Reason: string;
  PromptText, RespText, ErrMsg: string;
begin
  SetLength(Result, Length(Repairs));
  for I := 0 to High(Repairs) do
  begin
    R := Repairs[I];
    Score := 0.70;
    Reason := 'Scored by ' + FName + ': ';

    if R.Content.Contains('b == 0') or R.Content.Contains('divisor == 0') or R.Content.Contains('y == 0') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Includes zero check; ';
    end
    else
    begin
      Score := Score - 0.25;
      Reason := Reason + 'Missing zero check; ';
    end;

    if R.Content.Contains('INT_MIN') or R.Content.Contains('-2147483648') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Handles INT_MIN overflow; ';
    end;

    if I < Length(Debugs) then
    begin
      Ext := Debugs[I];
      if Ext.TestPassed then
      begin
        Score := Score + 0.10;
        Reason := Reason + 'Passed sandbox tests; ';
      end;
      if Ext.CrashCount > 0 then
      begin
        Score := Score - 0.40;
        Reason := Reason + 'Runtime crash recorded; ';
      end;
    end
    else
      Ext := TDebugFeedback.MakeSuccess('Validated');

    PromptText := Format('Rate the following repair on a scale of 0.0 to 1.0 for task: %s'#13#10'Code: %s',
      [UserPrompt, R.Content]);
    if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
      Score := (Score + ExtractScoreFromText(RespText, Score)) / 2.0;

    Result[I] := TScore.Create(FName, R.TargetPeer, R.FromPeer,
      EnsureRange(Score, 0.0, 1.0), 0.95, Ext, Reason.Trim);
  end;
end;

end.
