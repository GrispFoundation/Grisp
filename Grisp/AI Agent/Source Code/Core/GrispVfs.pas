unit GrispVfs;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  GrispCapabilities;

type
  TGrispVfsEntry = record
    VirtualPath: string;
    MimeType: string;
    Content: string;
    SizeBytes: Int64;
    ModifiedUtc: TDateTime;
    IsDirectory: Boolean;
  end;

  TGrispVfs = class
  private
    FSandboxPhysicalRoot: string;
    FEntries: TDictionary<string, TGrispVfsEntry>;
    FUseDiskBacking: Boolean;

    procedure EnsurePhysicalDir(const PhysicalDir: string);
  public
    constructor Create(const ASandboxPhysicalRoot: string = ''; AUseDiskBacking: Boolean = True);
    destructor Destroy; override;

    class function NormalizePath(const RawPath: string): string; static;
    class function GetMimeFromExtension(const Filename: string): string; static;
    function ResolveSafe(const VirtualPath: string; out RealPath, Reason: string): Boolean;
    function ResolveToPhysical(const VirtualPath: string): string;

    function WriteFile(const VirtualPath, Content, Mime: string; const Cap: IGrispCapability; out Reason: string): Boolean; overload;
    function WriteFile(const VirtualPath, Content, Mime: string): Boolean; overload; // Unchecked / internal

    function ReadFile(const VirtualPath: string; const Cap: IGrispCapability; out Content, Reason: string): Boolean; overload;
    function ReadFile(const VirtualPath: string; out Content: string): Boolean; overload; // Unchecked / internal

    function DeleteFile(const VirtualPath: string; const Cap: IGrispCapability; out Reason: string): Boolean; overload;
    function DeleteFile(const VirtualPath: string): Boolean; overload;

    function ListFiles(const VirtualDir: string; const Cap: IGrispCapability; out Files: TArray<string>; out Reason: string): Boolean; overload;
    function ListFiles(const VirtualDir: string; out Files: TArray<string>): Boolean; overload;

    function FileExists(const VirtualPath: string): Boolean;
    function GetFileSize(const VirtualPath: string): Int64;
    function GetFileMime(const VirtualPath: string): string;
    procedure Clear;

    property SandboxPhysicalRoot: string read FSandboxPhysicalRoot;
    property UseDiskBacking: Boolean read FUseDiskBacking write FUseDiskBacking;
  end;

implementation

{ TGrispVfs }

class function TGrispVfs.NormalizePath(const RawPath: string): string;
var
  S, Token: string;
  Parts, OutParts: TList<string>;
  I: Integer;
begin
  S := RawPath.Trim;

  // 1. Strip drive letters (e.g. "C:", "G:")
  if (Length(S) >= 2) and CharInSet(S[1], ['A'..'Z', 'a'..'z']) and (S[2] = ':') then
    Delete(S, 1, 2);

  // 2. Replace backslashes with slashes
  S := StringReplace(S, '\', '/', [rfReplaceAll]);

  // 3. Remove UNC prefixes or double slashes
  while S.Contains('//') do
    S := StringReplace(S, '//', '/', [rfReplaceAll]);

  // 4. Tokenize by '/'
  Parts := TList<string>.Create;
  OutParts := TList<string>.Create;
  try
    Token := '';
    for I := 1 to Length(S) do
    begin
      if S[I] = '/' then
      begin
        if Token <> '' then
        begin
          Parts.Add(Token);
          Token := '';
        end;
      end
      else
        Token := Token + S[I];
    end;
    if Token <> '' then
      Parts.Add(Token);

    // 5. Canonical stack resolution (resolve '.' and '..')
    for I := 0 to Parts.Count - 1 do
    begin
      Token := Parts[I];
      if Token = '.' then
        Continue
      else if Token = '..' then
      begin
        if OutParts.Count > 0 then
          OutParts.Delete(OutParts.Count - 1);
        // Note: '..' cannot escape root '/'
      end
      else
        OutParts.Add(Token);
    end;

    // 6. Build canonical string
    if OutParts.Count = 0 then
      Result := '/'
    else
    begin
      Result := '';
      for I := 0 to OutParts.Count - 1 do
        Result := Result + '/' + OutParts[I];
    end;
  finally
    Parts.Free;
    OutParts.Free;
  end;
end;

class function TGrispVfs.GetMimeFromExtension(const Filename: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(TPath.GetExtension(Filename));
  if (Ext = '.txt') or (Ext = '.log') or (Ext = '.grisp') then
    Result := 'text/plain'
  else if (Ext = '.c') or (Ext = '.h') then
    Result := 'text/x-c'
  else if (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.pp') then
    Result := 'text/x-pascal'
  else if (Ext = '.py') then
    Result := 'text/x-python'
  else if (Ext = '.json') then
    Result := 'application/json'
  else if (Ext = '.exe') or (Ext = '.dll') or (Ext = '.bin') then
    Result := 'application/octet-stream'
  else
    Result := 'text/plain';
end;

constructor TGrispVfs.Create(const ASandboxPhysicalRoot: string; AUseDiskBacking: Boolean);
begin
  inherited Create;
  FEntries := TDictionary<string, TGrispVfsEntry>.Create;
  FUseDiskBacking := AUseDiskBacking;

  if ASandboxPhysicalRoot <> '' then
    FSandboxPhysicalRoot := TPath.GetFullPath(ASandboxPhysicalRoot)
  else
    FSandboxPhysicalRoot := TPath.Combine(TPath.GetTempPath, 'grisp_sandbox_' + IntToStr(TThread.GetTickCount64));

  if FUseDiskBacking then
    EnsurePhysicalDir(FSandboxPhysicalRoot);
end;

destructor TGrispVfs.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TGrispVfs.EnsurePhysicalDir(const PhysicalDir: string);
begin
  if (PhysicalDir <> '') and not TDirectory.Exists(PhysicalDir) then
    TDirectory.CreateDirectory(PhysicalDir);
end;

function TGrispVfs.ResolveSafe(const VirtualPath: string; out RealPath, Reason: string): Boolean;
var
  Canon: string;
  Relative: string;
  Phys: string;
begin
  Canon := VirtualPath.Trim;
  // Strictly reject drive letter injection
  if Pos(':', Canon) > 0 then
  begin
    Reason := Format('Drive letters are not permitted in virtual path: "%s"', [VirtualPath]);
    Exit(False);
  end;

  // Normalize path
  Canon := NormalizePath(Canon);

  if Canon.StartsWith('/') then
    Relative := Copy(Canon, 2, Length(Canon) - 1)
  else
    Relative := Canon;

  Relative := StringReplace(Relative, '/', PathDelim, [rfReplaceAll]);
  Phys := TPath.GetFullPath(TPath.Combine(FSandboxPhysicalRoot, Relative));

  // Strict physical prefix check to guarantee sandbox containment
  if not Phys.StartsWith(FSandboxPhysicalRoot) then
  begin
    Reason := Format('Path "%s" attempts to escape physical sandbox boundary', [VirtualPath]);
    Exit(False);
  end;

  RealPath := Phys;
  Reason := '';
  Result := True;
end;

function TGrispVfs.ResolveToPhysical(const VirtualPath: string): string;
var
  RealPath, Reason: string;
begin
  if ResolveSafe(VirtualPath, RealPath, Reason) then
    Result := RealPath
  else
    Result := TPath.Combine(FSandboxPhysicalRoot, 'rejected_path');
end;

function TGrispVfs.WriteFile(const VirtualPath, Content, Mime: string; const Cap: IGrispCapability; out Reason: string): Boolean;
var
  Canon: string;
  Size: Int64;
  EffectiveMime: string;
begin
  Canon := NormalizePath(VirtualPath);
  Size := Length(TEncoding.UTF8.GetBytes(Content));

  if Mime <> '' then
    EffectiveMime := Mime
  else
    EffectiveMime := GetMimeFromExtension(Canon);

  if Assigned(Cap) then
  begin
    if not Cap.ValidateWrite(Canon, EffectiveMime, Size, Reason) then
      Exit(False);
  end;

  Result := WriteFile(Canon, Content, EffectiveMime);
  Reason := '';
end;

function TGrispVfs.WriteFile(const VirtualPath, Content, Mime: string): Boolean;
var
  Canon, Phys, PhysDir, Reason: string;
  Entry: TGrispVfsEntry;
  EffectiveMime: string;
begin
  Canon := NormalizePath(VirtualPath);

  if Mime <> '' then
    EffectiveMime := Mime
  else
    EffectiveMime := GetMimeFromExtension(Canon);

  Entry.VirtualPath := Canon;
  Entry.MimeType := EffectiveMime;
  Entry.Content := Content;
  Entry.SizeBytes := Length(TEncoding.UTF8.GetBytes(Content));
  Entry.ModifiedUtc := Now;
  Entry.IsDirectory := False;

  FEntries.AddOrSetValue(Canon, Entry);

  if FUseDiskBacking then
  begin
    if ResolveSafe(Canon, Phys, Reason) then
    begin
      try
        PhysDir := TPath.GetDirectoryName(Phys);
        EnsurePhysicalDir(PhysDir);
        TFile.WriteAllText(Phys, Content, TEncoding.UTF8);
      except
        // In-memory record remains safe
      end;
    end;
  end;

  Result := True;
end;

function TGrispVfs.ReadFile(const VirtualPath: string; const Cap: IGrispCapability; out Content, Reason: string): Boolean;
var
  Canon: string;
begin
  Canon := NormalizePath(VirtualPath);

  if Assigned(Cap) then
  begin
    if not Cap.AllowsOp(grRead) then
    begin
      Reason := Format('Capability "%s" does not allow read operation', [Cap.Name]);
      Exit(False);
    end;

    if not Cap.IsPathAllowed(Canon) then
    begin
      Reason := Format('Path "%s" is outside capability root "%s"', [Canon, Cap.Root]);
      Exit(False);
    end;
  end;

  if not ReadFile(Canon, Content) then
  begin
    Reason := Format('Virtual file "%s" not found', [Canon]);
    Exit(False);
  end;

  Reason := '';
  Result := True;
end;

function TGrispVfs.ReadFile(const VirtualPath: string; out Content: string): Boolean;
var
  Canon, Phys, Reason: string;
  Entry: TGrispVfsEntry;
begin
  Canon := NormalizePath(VirtualPath);

  if FEntries.TryGetValue(Canon, Entry) then
  begin
    Content := Entry.Content;
    Exit(True);
  end;

  if FUseDiskBacking and ResolveSafe(Canon, Phys, Reason) then
  begin
    if TFile.Exists(Phys) then
    begin
      Content := TFile.ReadAllText(Phys, TEncoding.UTF8);
      Entry.VirtualPath := Canon;
      Entry.MimeType := GetMimeFromExtension(Canon);
      Entry.Content := Content;
      Entry.SizeBytes := Length(TEncoding.UTF8.GetBytes(Content));
      Entry.ModifiedUtc := Now;
      Entry.IsDirectory := False;
      FEntries.AddOrSetValue(Canon, Entry);
      Exit(True);
    end;
  end;

  Content := '';
  Result := False;
end;

function TGrispVfs.DeleteFile(const VirtualPath: string; const Cap: IGrispCapability; out Reason: string): Boolean;
var
  Canon: string;
begin
  Canon := NormalizePath(VirtualPath);

  if Assigned(Cap) then
  begin
    if not Cap.AllowsOp(grDelete) then
    begin
      Reason := Format('Capability "%s" does not allow delete operation', [Cap.Name]);
      Exit(False);
    end;

    if not Cap.IsPathAllowed(Canon) then
    begin
      Reason := Format('Path "%s" is outside capability root "%s"', [Canon, Cap.Root]);
      Exit(False);
    end;
  end;

  Result := DeleteFile(Canon);
  Reason := '';
end;

function TGrispVfs.DeleteFile(const VirtualPath: string): Boolean;
var
  Canon, Phys, Reason: string;
begin
  Canon := NormalizePath(VirtualPath);
  FEntries.Remove(Canon);

  if FUseDiskBacking and ResolveSafe(Canon, Phys, Reason) then
  begin
    if TFile.Exists(Phys) then
      TFile.Delete(Phys);
  end;

  Result := True;
end;

function TGrispVfs.ListFiles(const VirtualDir: string; const Cap: IGrispCapability; out Files: TArray<string>; out Reason: string): Boolean;
var
  Canon: string;
begin
  Canon := NormalizePath(VirtualDir);

  if Assigned(Cap) then
  begin
    if not Cap.AllowsOp(grList) then
    begin
      Reason := Format('Capability "%s" does not allow list operation', [Cap.Name]);
      Exit(False);
    end;

    if not Cap.IsPathAllowed(Canon) then
    begin
      Reason := Format('Path "%s" is outside capability root "%s"', [Canon, Cap.Root]);
      Exit(False);
    end;
  end;

  Result := ListFiles(Canon, Files);
  Reason := '';
end;

function TGrispVfs.ListFiles(const VirtualDir: string; out Files: TArray<string>): Boolean;
var
  Canon, Prefix: string;
  K: string;
  List: TList<string>;
begin
  Canon := NormalizePath(VirtualDir);
  if Canon = '/' then
    Prefix := '/'
  else
    Prefix := Canon + '/';

  List := TList<string>.Create;
  try
    for K in FEntries.Keys do
    begin
      if (Canon = '/') or K.StartsWith(Prefix) then
        List.Add(K);
    end;
    List.Sort;
    Files := List.ToArray;
    Result := True;
  finally
    List.Free;
  end;
end;

function TGrispVfs.FileExists(const VirtualPath: string): Boolean;
var
  Canon, Phys, Reason: string;
begin
  Canon := NormalizePath(VirtualPath);
  if FEntries.ContainsKey(Canon) then
    Exit(True);

  if FUseDiskBacking and ResolveSafe(Canon, Phys, Reason) then
    Exit(TFile.Exists(Phys));

  Result := False;
end;

function TGrispVfs.GetFileSize(const VirtualPath: string): Int64;
var
  Canon: string;
  Entry: TGrispVfsEntry;
begin
  Canon := NormalizePath(VirtualPath);
  if FEntries.TryGetValue(Canon, Entry) then
    Exit(Entry.SizeBytes);
  Result := 0;
end;

function TGrispVfs.GetFileMime(const VirtualPath: string): string;
var
  Canon: string;
  Entry: TGrispVfsEntry;
begin
  Canon := NormalizePath(VirtualPath);
  if FEntries.TryGetValue(Canon, Entry) then
    Exit(Entry.MimeType);
  Result := GetMimeFromExtension(Canon);
end;

procedure TGrispVfs.Clear;
begin
  FEntries.Clear;
  if FUseDiskBacking and TDirectory.Exists(FSandboxPhysicalRoot) then
  begin
    try
      TDirectory.Delete(FSandboxPhysicalRoot, True);
      EnsurePhysicalDir(FSandboxPhysicalRoot);
    except
    end;
  end;
end;

end.
