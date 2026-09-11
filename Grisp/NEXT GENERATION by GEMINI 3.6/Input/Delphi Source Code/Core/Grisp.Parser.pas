unit Grisp.Parser;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, Grisp.Types, Grisp.Canonical;

type
  /// <summary>
  /// Fail-closed candidate parser for deterministic payload extraction.
  /// Enforces single-block unambiguous rules for machine verification.
  /// </summary>
  TGrispParser = class
  private
    class function FindNextFence(
      const AText: string; 
      AStartPos: Integer; 
      out AFenceStart, AFenceEnd: Integer; 
      out ALang: string
    ): Boolean; static;
  public
    /// <summary>
    /// Parses raw AI text output into a validated TGrispCandidate.
    /// Returns False and sets csRejected if zero or multiple code blocks exist.
    /// </summary>
    class function ParseResponse(
      const AResponse: string; 
      const ASessionID: TGrispSessionID; 
      const ATabID: TGrispTabID; 
      out ACandidate: TGrispCandidate
    ): Boolean; static;
  end;

implementation

class function TGrispParser.FindNextFence(
  const AText: string; 
  AStartPos: Integer; 
  out AFenceStart, AFenceEnd: Integer; 
  out ALang: string
): Boolean;
var
  OpenPos, FirstNL, ClosePos: Integer;
begin
  Result := False;
  AFenceStart := 0;
  AFenceEnd := 0;
  ALang := '';

  OpenPos := PosEx('```', AText, AStartPos);
  if OpenPos = 0 then
    Exit;

  FirstNL := PosEx(#10, AText, OpenPos + 3);
  if FirstNL = 0 then
    Exit;

  ClosePos := PosEx('```', AText, FirstNL + 1);
  if ClosePos = 0 then
    Exit;

  AFenceStart := OpenPos;
  AFenceEnd := ClosePos + 3;
  ALang := Trim(Copy(AText, OpenPos + 3, FirstNL - (OpenPos + 3)));
  ALang := StringReplace(ALang, #13, '', [rfReplaceAll]);

  Result := True;
end;

class function TGrispParser.ParseResponse(
  const AResponse: string; 
  const ASessionID: TGrispSessionID; 
  const ATabID: TGrispTabID; 
  out ACandidate: TGrispCandidate
): Boolean;
var
  CurrPos, BlockCount, FenceStart, FenceEnd: Integer;
  Lang, ExtractedCode: string;
  SelectedStart, SelectedEnd: Integer;
  Utf8Bytes: TBytes;
begin
  FillChar(ACandidate, SizeOf(ACandidate), 0);
  ACandidate.ID := ASessionID;
  ACandidate.State := csCreated;
  ACandidate.LastError := errNone;

  CurrPos := 1;
  BlockCount := 0;
  SelectedStart := 0;
  SelectedEnd := 0;

  // Scan text for code blocks
  while FindNextFence(AResponse, CurrPos, FenceStart, FenceEnd, Lang) do
  begin
    Inc(BlockCount);
    if BlockCount = 1 then
    begin
      SelectedStart := FenceStart;
      SelectedEnd := FenceEnd;
    end;
    CurrPos := FenceEnd;
  end;

  // Gate 1: No code payload found
  if BlockCount = 0 then
  begin
    ACandidate.State := csRejected;
    ACandidate.LastError := errParseError;
    Exit(False);
  end;

  // Gate 2: Fail-closed on ambiguity (multiple code blocks present)
  if BlockCount > 1 then
  begin
    ACandidate.State := csRejected;
    ACandidate.LastError := errParseAmbiguous;
    Exit(False);
  end;

  // Extract inner code block payload
  CurrPos := PosEx(#10, AResponse, SelectedStart + 3);
  ExtractedCode := Copy(AResponse, CurrPos + 1, (SelectedEnd - 3) - (CurrPos + 1));
  ExtractedCode := Trim(ExtractedCode);

  if ExtractedCode.IsEmpty then
  begin
    ACandidate.State := csRejected;
    ACandidate.LastError := errParseError;
    Exit(False);
  end;

  // Package canonical manifest
  Utf8Bytes := TGrispCanonical.ToUTF8Bytes(ExtractedCode);
  
  ACandidate.Manifest.SessionID := ASessionID;
  ACandidate.Manifest.TabID := ATabID;
  ACandidate.Manifest.SourcePath := '';
  ACandidate.Manifest.RawBytes := Utf8Bytes;
  ACandidate.Manifest.ContentHash := TGrispCanonical.ComputeSHA256(Utf8Bytes);

  ACandidate.State := csParsed;
  Result := True;
end;

end.