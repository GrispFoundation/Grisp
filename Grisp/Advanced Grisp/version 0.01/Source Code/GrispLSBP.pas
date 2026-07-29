unit GrispLSBP;

interface

uses
  SysUtils, Classes, Generics.Collections;

type
  TLSBPDocumentType = (dtBundle, dtPatch);

  TLSBPBundle = class
  private
    FDocumentType: TLSBPDocumentType;
    FMetadata: TDictionary<string, string>;
    FFiles: TDictionary<string, string>; // path -> content
    FDirectories: TStringList;
    FDeletes: TStringList;
    FDiffs: TDictionary<string, string>;
    function BuildHeader(const BundleType: string; const IncludeHash: Boolean): string;
    function BuildPayload: string;
    function ComputeHash: string;
  public
    constructor Create(AType: TLSBPDocumentType);
    destructor Destroy; override;
    procedure AddFile(const Path, Content: string; const Encoding: string = 'utf8');
    procedure AddDirectory(const Path: string);
    procedure AddDelete(const Path: string);
    procedure AddDiff(const Path, DiffText: string);
    function GenerateBundle(const ErrorHandling: string = 'abort'): string;
  end;

implementation

uses
  System.Hash;

{ TLSBPBundle }

constructor TLSBPBundle.Create(AType: TLSBPDocumentType);
begin
  FDocumentType := AType;
  FMetadata := TDictionary<string, string>.Create;
  FFiles := TDictionary<string, string>.Create;
  FDirectories := TStringList.Create;
  FDeletes := TStringList.Create;
  FDiffs := TDictionary<string, string>.Create;
  FMetadata.Add('LSBPVersion', '0.38');
  FMetadata.Add('BundleToolVersion', '0.38');
  FMetadata.Add('Profile', 'generic');
end;

destructor TLSBPBundle.Destroy;
begin
  FMetadata.Free;
  FFiles.Free;
  FDirectories.Free;
  FDeletes.Free;
  FDiffs.Free;
  inherited;
end;

procedure TLSBPBundle.AddFile(const Path, Content: string; const Encoding: string = 'utf8');
begin
  FFiles.Add(Path, Content);
end;

procedure TLSBPBundle.AddDirectory(const Path: string);
begin
  FDirectories.Add(Path);
end;

procedure TLSBPBundle.AddDelete(const Path: string);
begin
  FDeletes.Add(Path);
end;

procedure TLSBPBundle.AddDiff(const Path, DiffText: string);
begin
  FDiffs.Add(Path, DiffText);
end;

function TLSBPBundle.BuildHeader(const BundleType: string; const IncludeHash: Boolean): string;
var
  sb: TStringBuilder;
  pair: TPair<string, string>;
begin
  sb := TStringBuilder.Create;
  try
    sb.AppendLine('⟦BEGIN BUNDLE HEADER⟧');
    for pair in FMetadata do
      sb.AppendLine('⟦BEGIN ' + pair.Key + '⟧' + pair.Value + '⟦END ' + pair.Key + '⟧');
    sb.AppendLine('⟦BEGIN BundleType⟧' + BundleType + '⟦END BundleType⟧');
    if IncludeHash then
    begin
      sb.AppendLine('⟦BEGIN SHA256⟧PLACEHOLDER⟦END SHA256⟧');
      sb.AppendLine('⟦BEGIN BundleID⟧PLACEHOLDER⟦END BundleID⟧');
    end;
    sb.AppendLine('⟦END BUNDLE HEADER⟧');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

function TLSBPBundle.BuildPayload: string;
var
  sb: TStringBuilder;
  s: string;
  Paths: TStringList;
begin
  sb := TStringBuilder.Create;
  try
    sb.AppendLine('⟦BEGIN BUNDLE PAYLOAD⟧');
    // Deletes (descending path order)
    FDeletes.Sort;
    for s in FDeletes do
      sb.AppendLine('⟦BEGIN DELETE⟧⟦BEGIN Path⟧' + s + '⟦END Path⟧⟦END DELETE⟧');
    // Directories
    FDirectories.Sort;
    for s in FDirectories do
      sb.AppendLine('⟦BEGIN DIRECTORY⟧⟦BEGIN Path⟧' + s + '⟦END Path⟧⟦END DIRECTORY⟧');
    // Files (sorted)
    Paths := TStringList.Create;
    try
      // Iterate over keys manually to avoid AddStrings issue
      for s in FFiles.Keys do
        Paths.Add(s);
      Paths.Sort;
      for s in Paths do
      begin
        var Content := FFiles[s];
        sb.AppendLine('⟦BEGIN FILE⟧');
        sb.AppendLine('⟦BEGIN Path⟧' + s + '⟦END Path⟧');
        sb.AppendLine('⟦BEGIN Encoding⟧utf8⟦END Encoding⟧');
        sb.AppendLine('⟦BEGIN CONTENT⟧');
        sb.AppendLine(Content);
        sb.AppendLine('⟦END CONTENT⟧');
        sb.AppendLine('⟦END FILE⟧');
      end;
    finally
      Paths.Free;
    end;
    // Diffs
    for s in FDiffs.Keys do
    begin
      sb.AppendLine('⟦BEGIN DIFF⟧');
      sb.AppendLine('⟦BEGIN Path⟧' + s + '⟦END Path⟧');
      sb.AppendLine('⟦BEGIN CONTENT⟧');
      sb.AppendLine(FDiffs[s]);
      sb.AppendLine('⟦END CONTENT⟧');
      sb.AppendLine('⟦END DIFF⟧');
    end;
    sb.AppendLine('⟦END BUNDLE PAYLOAD⟧');
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

function TLSBPBundle.ComputeHash: string;
begin
  Result := 'dummy_hash';
end;

function TLSBPBundle.GenerateBundle(const ErrorHandling: string): string;
var
  Header, Payload, Body: string;
  BundleTypeStr: string;
  Hash: string;
begin
  if FDocumentType = dtBundle then
    BundleTypeStr := 'Full'
  else
    BundleTypeStr := 'Patch';
  Header := BuildHeader(BundleTypeStr, True);
  Payload := BuildPayload;
  Body := '⟦BEGIN ' + BundleTypeStr + '⟧' + sLineBreak + Header + Payload + '⟦END ' + BundleTypeStr + '⟧';
  Hash := ComputeHash;
  Body := StringReplace(Body, 'PLACEHOLDER', Hash, [rfReplaceAll]);
  Result := Body;
end;

end.
