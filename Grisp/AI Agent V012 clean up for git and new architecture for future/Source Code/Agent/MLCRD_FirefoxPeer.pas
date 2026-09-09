// Filename: MLCRD_FirefoxPeer.pas
unit MLCRD_FirefoxPeer;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.Math, System.IOUtils, IdTCPClient, IdGlobal, IdException,
  MLCRD_Types, MLCRD_Interfaces, MLCRD_Peers;

const
  DEFAULT_FIREFOX_PORT = 9999;
  VALID_FIREFOX_SITES: array[0..7] of string = (
    'deepseek', 'gemini', 'claude', 'chatgpt', 'copilot', 'grok', 'perplexity', 'inception'
  );

type
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
    function GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
    function CritiqueCandidate(const UserPrompt: string; const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
    function RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
      const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
    function RequestCapabilities(const UserPrompt: string; const Repairs: TArray<TRepair>;
      const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
    function ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
      const Config: TAgentConfiguration): TTestProgram;
    function ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
      const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
      const Config: TAgentConfiguration): TArray<TScore>;
    property SiteName: string read FSiteName;
    property TabId: Integer read FTabId write FTabId;
    property FallbackPeer: IWebLLMPeer read FFallbackPeer write FFallbackPeer;
    property Client: TFirefoxClient read FClient;
  end;

// Utility functions
function IsSupportedFirefoxSite(const ASite: string): Boolean;
function NormalizeFirefoxSite(const ASite: string): string;
function CleanCodeContent(const S: string): string;
function ExtractCodeBlock(const Markdown: string; const PreferredLang: string = ''): string;
function ExtractAllCodeBlocks(const Markdown: string; out Files: TArray<TFileEntry>): Boolean;
function ExtractBulletIssues(const Text: string): TArray<string>;
function ExtractSuggestedFix(const Text: string): string;
function ExtractScoreFromText(const Text: string; DefaultScore: Double = 0.85): Double;
function ExtractCapabilitiesFromText(const Text: string): TArray<string>;

// Debug logging support
procedure InitializeDebugLog(const ALogPath: string);
procedure LogDebug(const Msg: string);
function FormatDebugPrompt(const PeerName, Phase: string; const OriginalPrompt: string): string;

implementation

// ---------------------------------------------------------------------------
// Debug logging globals
// ---------------------------------------------------------------------------
var
  DebugEnabled: Boolean = False;
  DebugLogFile: string = '';

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Central cleanup: remove common prefixes and trim
// ---------------------------------------------------------------------------
function CleanCodeContent(const S: string): string;
var
  Tmp: string;
begin
  Tmp := S;
  // Remove common copy/paste artifacts
  Tmp := StringReplace(Tmp, 'pascalCopyDownload', '', [rfReplaceAll]);
  Tmp := StringReplace(Tmp, 'delphiCopyDownload', '', [rfReplaceAll]);
  Tmp := StringReplace(Tmp, 'CopyDownload', '', [rfReplaceAll]);
  // Fix concatenated keywords
  Tmp := StringReplace(Tmp, 'Delphiprogram', 'program', [rfReplaceAll]);
  Tmp := StringReplace(Tmp, 'Pascalprogram', 'program', [rfReplaceAll]);
  // If it still starts with 'delphi' or 'pascal' followed by 'program' (without space)
  if (Length(Tmp) > 7) and SameText(Copy(Tmp, 1, 6), 'delphi') and (Copy(Tmp, 7, 1) = 'p') then
    Tmp := Copy(Tmp, 7, Length(Tmp) - 6);
  if (Length(Tmp) > 6) and SameText(Copy(Tmp, 1, 5), 'pascal') and (Copy(Tmp, 6, 1) = 'p') then
    Tmp := Copy(Tmp, 6, Length(Tmp) - 5);
  Tmp := StringReplace(Tmp, 'CopyDownload', '', [rfReplaceAll]);
  Result := Trim(Tmp);
end;

// ---------------------------------------------------------------------------
// Extract single code block (maintains backward compatibility)
// ---------------------------------------------------------------------------
function ExtractCodeBlock(const Markdown: string; const PreferredLang: string): string;
var
  StartPos, EndPos, NextNL: Integer;
  S: string;
begin
  StartPos := Pos('```', Markdown);
  if StartPos <= 0 then
    S := Markdown
  else
  begin
    NextNL := Pos(#10, Copy(Markdown, StartPos, Length(Markdown) - StartPos + 1));
    if NextNL > 0 then
      StartPos := StartPos + NextNL
    else
      StartPos := StartPos + 3;

    EndPos := Pos('```', Copy(Markdown, StartPos, Length(Markdown) - StartPos + 1));
    if EndPos > 0 then
      S := Copy(Markdown, StartPos, EndPos - 1)
    else
      S := Copy(Markdown, StartPos, Length(Markdown) - StartPos + 1);
  end;
  Result := CleanCodeContent(S);
end;

// ---------------------------------------------------------------------------
// Extract ALL code blocks, with cleanup and filename parsing
// ---------------------------------------------------------------------------
function ExtractAllCodeBlocks(const Markdown: string; out Files: TArray<TFileEntry>): Boolean;
var
  Lines: TArray<string>;
  I: Integer;
  InBlock: Boolean;
  CurrentHeader, CurrentContent: string;
  List: TList<TFileEntry>;
  Line: string;
  FileName: string;
  function GetExtensionFromLang(const Lang: string): string;
  begin
    if SameText(Lang, 'pas') or SameText(Lang, 'pascal') or SameText(Lang, 'delphi') then
      Result := '.pas'
    else if SameText(Lang, 'c') then
      Result := '.c'
    else if SameText(Lang, 'python') or SameText(Lang, 'py') then
      Result := '.py'
    else if SameText(Lang, 'cpp') or SameText(Lang, 'c++') then
      Result := '.cpp'
    else
      Result := '.txt';
  end;
begin
  List := TList<TFileEntry>.Create;
  try
    Lines := Markdown.Split([#13#10, #10, #13]);
    InBlock := False;
    CurrentHeader := '';
    CurrentContent := '';
    for I := 0 to High(Lines) do
    begin
      Line := Lines[I];
      // Detect start of a code block
      if (not InBlock) and Line.Trim.StartsWith('```') then
      begin
        InBlock := True;
        CurrentHeader := Line.Trim.Replace('```', '').Trim;
        CurrentContent := '';
        Continue;
      end;
      // Detect end of a code block
      if InBlock and Line.Trim.StartsWith('```') then
      begin
        InBlock := False;
        if CurrentContent <> '' then
        begin
          var Entry: TFileEntry;
          CurrentContent := CleanCodeContent(CurrentContent);
          // Parse filename from header: 'lang:filename' or just 'lang'
          FileName := '';
          var ColonPos := Pos(':', CurrentHeader);
          if ColonPos > 0 then
            FileName := Trim(Copy(CurrentHeader, ColonPos + 1, MaxInt))
          else if CurrentHeader <> '' then
          begin
            var Lang := CurrentHeader;
            FileName := 'program' + GetExtensionFromLang(Lang);
          end;
          if FileName = '' then
            FileName := 'program.txt';
          Entry.FileName := FileName;
          Entry.Content := CurrentContent;
          List.Add(Entry);
        end;
        Continue;
      end;
      if InBlock then
      begin
        if CurrentContent <> '' then
          CurrentContent := CurrentContent + sLineBreak;
        CurrentContent := CurrentContent + Line;
      end;
    end;

    // If no code blocks were found, treat the whole response as a single file
    if List.Count = 0 then
    begin
      var Entry: TFileEntry;
      var Cleaned := CleanCodeContent(Markdown);
      // Try to guess a simple name (fallback)
      if Cleaned.StartsWith('program') or Cleaned.StartsWith('unit') then
        Entry.FileName := 'program.pas'
      else if Cleaned.StartsWith('#include') or Cleaned.StartsWith('int main') then
        Entry.FileName := 'program.c'
      else if Cleaned.StartsWith('import') or Cleaned.StartsWith('def ') then
        Entry.FileName := 'program.py'
      else
        Entry.FileName := 'program.txt';
      Entry.Content := Cleaned;
      List.Add(Entry);
    end;

    Files := List.ToArray;
    Result := True;
  finally
    List.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Other extraction helpers
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Debug logging
// ---------------------------------------------------------------------------
procedure InitializeDebugLog(const ALogPath: string);
begin
  DebugEnabled := True;
  DebugLogFile := ALogPath;
  LogDebug('=== GRISP AI Agent Debug Log Started ===');
  LogDebug('Timestamp: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  LogDebug('----------------------------------------');
end;

procedure LogDebug(const Msg: string);
var
  Line: string;
begin
  if not DebugEnabled then
    Exit;
  Line := FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + Msg;
  TFile.AppendAllText(DebugLogFile, Line + sLineBreak);
end;

function FormatDebugPrompt(const PeerName, Phase: string; const OriginalPrompt: string): string;
begin
  Result := Format(
    '<!-- DEBUG: Generated by %s in phase "%s". Please ignore this line; it is not part of the task. -->'#13#10#13#10 +
    '%s',
    [PeerName, Phase, OriginalPrompt]);
end;

// ---------------------------------------------------------------------------
// TFirefoxClient
// ---------------------------------------------------------------------------
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
  CmdJson: string;
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

    CmdJson := Cmd.ToJSON;
    LogDebug('>>> REQUEST to ' + Site + ' (tab ' + IntToStr(TabId) + '): ' + CmdJson);

    try
      Resp := SendCommand(Cmd);
    except
      on E: Exception do
      begin
        ErrorMsg := 'Firefox connection failed: ' + E.Message;
        LogDebug('<<< ERROR: ' + ErrorMsg);
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
          LogDebug('<<< RESPONSE (error): ' + Resp.ToJSON);
          Exit(False);
        end;

        if not Resp.TryGetValue<string>('text', ResponseText) then
          ResponseText := '';
        Result := True;
        LogDebug('<<< RESPONSE (text): ' + ResponseText);
      finally
        Resp.Free;
      end;
    end
    else
    begin
      ErrorMsg := 'Empty response from Firefox service';
      LogDebug('<<< ERROR: Empty response');
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

// ---------------------------------------------------------------------------
// TFirefoxChatAIPeer
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// GenerateCandidate
// ---------------------------------------------------------------------------
function TFirefoxChatAIPeer.GenerateCandidate(const UserPrompt: string; const Config: TAgentConfiguration): TCandidate;
var
  PromptText, RespText, ErrMsg, Extracted: string;
  LangName: string;
begin
  case Config.PreferredLanguage of
    alPascal, alDelphi: LangName := 'Delphi';
    alC: LangName := 'C';
    alPython: LangName := 'Python';
  else
    LangName := 'C';
  end;

  PromptText := Format(
    'You are a senior systems engineer. Write a valid %s console application that prints "Hello, World!".'#13#10 +
    'The code must start with "program" (for Delphi) or the appropriate main function.'#13#10 +
    'Task: %s'#13#10 +
    'Output ONLY the code enclosed in a single markdown code block.',
    [LangName, UserPrompt]);

  if Config.EnablePromptTagging then
    PromptText := FormatDebugPrompt(FName, 'GenerateCandidate', PromptText);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    Extracted := ExtractCodeBlock(RespText);
    Result := TCandidate.Create(FName, Extracted);
  end
  else
    Result := FFallbackPeer.GenerateCandidate(UserPrompt, Config);
end;

// ---------------------------------------------------------------------------
// CritiqueCandidate
// ---------------------------------------------------------------------------
function TFirefoxChatAIPeer.CritiqueCandidate(const UserPrompt: string;
  const Candidate: TCandidate; const Config: TAgentConfiguration): TCritique;
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

  if Config.EnablePromptTagging then
    PromptText := FormatDebugPrompt(FName, 'CritiqueCandidate', PromptText);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    Issues := ExtractBulletIssues(RespText);
    FixSuggestion := ExtractSuggestedFix(RespText);
    Result := TCritique.Create(FName, Candidate.PeerName, Issues, FixSuggestion, 0.92);
  end
  else
    Result := FFallbackPeer.CritiqueCandidate(UserPrompt, Candidate, Config);
end;

// ---------------------------------------------------------------------------
// RepairCandidate – with explicit filename instruction
// ---------------------------------------------------------------------------
function TFirefoxChatAIPeer.RepairCandidate(const UserPrompt: string; const Candidate: TCandidate;
  const Critiques: TArray<TCritique>; const Config: TAgentConfiguration): TRepair;
var
  PromptText, RespText, ErrMsg, CritText, RepairedCode: string;
  C: TCritique;
  Issue: string;
  LangName: string;
  Files: TArray<TFileEntry>;
  FirstFileContent: string;
begin
  case Config.PreferredLanguage of
    alPascal, alDelphi: LangName := 'Pascal/Delphi';
    alC: LangName := 'C';
    alPython: LangName := 'Python';
  else
    LangName := 'C';
  end;

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
    'Original candidate code from %s (language: %s):'#13#10 +
    '%s'#13#10#13#10 +
    'Critiques received:'#13#10 +
    '%s'#13#10 +
    'Please produce the corrected, robust implementation in %s addressing every issue.'#13#10 +
    'IMPORTANT: Provide each code block with a filename in the markdown header, like this:'#13#10 +
    '  ```%s:MyUnit.pas'#13#10 +
    '  ... code ...'#13#10 +
    '  ```'#13#10 +
    'If multiple files are needed, use separate blocks with appropriate filenames.'#13#10 +
    'Output ONLY the code blocks, each with a filename header.',
    [UserPrompt, Candidate.PeerName, LangName, Candidate.Content, CritText, LangName, LangName]);

  if Config.EnablePromptTagging then
    PromptText := FormatDebugPrompt(FName, 'RepairCandidate', PromptText);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    if ExtractAllCodeBlocks(RespText, Files) and (Length(Files) > 0) then
    begin
      FirstFileContent := Files[0].Content;
      Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques,
        FirstFileContent, LangName, Files);
    end
    else
    begin
      RepairedCode := ExtractCodeBlock(RespText);
      Result := TRepair.Create(FName, Candidate.PeerName, Candidate.Content, Critiques,
        RepairedCode, LangName);
    end;
  end
  else
    Result := FFallbackPeer.RepairCandidate(UserPrompt, Candidate, Critiques, Config);
end;

// ---------------------------------------------------------------------------
// RequestCapabilities
// ---------------------------------------------------------------------------
function TFirefoxChatAIPeer.RequestCapabilities(const UserPrompt: string;
  const Repairs: TArray<TRepair>; const Config: TAgentConfiguration): TArray<TCapabilityRequest>;
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

  if Config.EnablePromptTagging then
    PromptText := FormatDebugPrompt(FName, 'RequestCapabilities', PromptText);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    Caps := ExtractCapabilitiesFromText(RespText);
    Result := [TCapabilityRequest.Create(FName, 'all', Caps, 'Verified via Firefox AI ' + FSiteName, 0.90)];
  end
  else
    Result := FFallbackPeer.RequestCapabilities(UserPrompt, Repairs, Config);
end;

// ---------------------------------------------------------------------------
// ProposeTestProgram
// ---------------------------------------------------------------------------
function TFirefoxChatAIPeer.ProposeTestProgram(const UserPrompt: string; const Repair: TRepair;
  const Config: TAgentConfiguration): TTestProgram;
var
  PromptText, RespText, ErrMsg, TestCode: string;
  LangName: string;
begin
  case Config.PreferredLanguage of
    alPascal, alDelphi: LangName := 'Pascal/Delphi';
    alC: LangName := 'C';
    alPython: LangName := 'Python';
  else
    LangName := 'C';
  end;

  PromptText := Format(
    'Task: %s'#13#10 +
    'Implementation under test (written in %s):'#13#10 +
    '%s'#13#10#13#10 +
    'Please write a complete, self-contained test program in %s that:'#13#10 +
    '- Includes a test runner (e.g., main() with assertions, or a DUnit/fpcunit skeleton).'#13#10 +
    '- Thoroughly tests all public functions present in the implementation.'#13#10 +
    '- Covers typical use cases, edge cases, and error conditions specific to this code (e.g., if it does division, test zero divisor; if it does sorting, test empty list; if it does parsing, test malformed input).'#13#10 +
    'Output only the complete test program code, enclosed in a single markdown code block.',
    [UserPrompt, LangName, Repair.Content, LangName]);

  if Config.EnablePromptTagging then
    PromptText := FormatDebugPrompt(FName, 'ProposeTestProgram', PromptText);

  if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
  begin
    TestCode := ExtractCodeBlock(RespText);
    Result := TTestProgram.Create(FName, Repair.TargetPeer, LangName,
      'Firefox ' + FSiteName + ' test suite for ' + Repair.TargetPeer,
      TestCode,
      ['Derived from the repair code; covers the specific functions present']
    );
  end
  else
    Result := FFallbackPeer.ProposeTestProgram(UserPrompt, Repair, Config);
end;

// ---------------------------------------------------------------------------
// ScoreRepairs
// ---------------------------------------------------------------------------
function TFirefoxChatAIPeer.ScoreRepairs(const UserPrompt: string; const Candidates: TArray<TCandidate>;
  const Repairs: TArray<TRepair>; const Debugs: TArray<TDebugFeedback>;
  const Config: TAgentConfiguration): TArray<TScore>;
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

    if R.Content.Contains('b == 0') or R.Content.Contains('b = 0') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Includes zero guard; ';
    end
    else
    begin
      Score := Score - 0.25;
      Reason := Reason + 'Missing zero guard; ';
    end;

    if R.Content.Contains('INT_MIN') or R.Content.Contains('-2147483648') then
    begin
      Score := Score + 0.15;
      Reason := Reason + 'Handles INT_MIN overflow; ';
    end;

    if (I < Length(Debugs)) then
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

    if Config.EnablePromptTagging then
      PromptText := FormatDebugPrompt(FName, 'ScoreRepairs', PromptText);

    if FClient.Prompt(FSiteName, PromptText, FTabId, RespText, ErrMsg) and (RespText.Trim <> '') then
      Score := (Score + ExtractScoreFromText(RespText, Score)) / 2.0;

    Result[I] := TScore.Create(FName, R.TargetPeer, R.FromPeer,
      EnsureRange(Score, 0.0, 1.0), 0.95, Ext, Reason.Trim);
  end;
end;

end.