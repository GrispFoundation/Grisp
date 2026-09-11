unit Grisp.GARP;

interface

uses
  System.SysUtils, System.Classes, Grisp.Types, Grisp.Canonical;

type
  /// <summary>
  /// GARP/1.0 4-byte length-framed binary packet structure.
  /// Header format: [Payload Length: UInt32 (Network Byte Order / Big-Endian)]
  /// </summary>
  TGarpPacket = record
    PayloadLength: UInt32;
    Payload: TBytes;
  end;

  /// <summary>
  /// GARP Protocol framing helper providing fail-closed binary serialization
  /// and stream framing to prevent payload truncation or index shift errors.
  /// </summary>
  TGarpTransport = class
  public
    /// <summary>
    /// Wraps raw payload bytes into a length-framed GARP packet stream.
    /// </summary>
    class function FramePayload(const APayload: TBytes): TBytes; static;

    /// <summary>
    /// Unframes stream data into a complete GARP packet.
    /// Returns False if stream contains insufficient data or length header exceeds maximum allowed frame.
    /// </summary>
    class function TryUnframePacket(
      AStream: TStream;
      out APacket: TGarpPacket;
      AMaxPayloadSize: UInt32 = 10485760 // 10 MB Default Cap
    ): Boolean; static;

    /// <summary>
    /// Serializes candidate manifest data into GARP binary packet format.
    /// </summary>
    class function SerializeManifest(const AManifest: TGrispManifest): TBytes; static;
  end;

implementation

class function TGarpTransport.FramePayload(const APayload: TBytes): TBytes;
var
  Len: UInt32;
begin
  Len := UInt32(Length(APayload));

  SetLength(Result, 4 + Len);

  // Pack 4-byte length prefix in Network Byte Order (Big-Endian)
  Result[0] := Byte((Len shr 24) and $FF);
  Result[1] := Byte((Len shr 16) and $FF);
  Result[2] := Byte((Len shr 8) and $FF);
  Result[3] := Byte(Len and $FF);

  if Len > 0 then
    Move(APayload[0], Result[4], Len);
end;

class function TGarpTransport.TryUnframePacket(
  AStream: TStream;
  out APacket: TGarpPacket;
  AMaxPayloadSize: UInt32
): Boolean;
var
  Header: array[0..3] of Byte;
  OriginalPos: Int64;
begin
  APacket.PayloadLength := 0;
  APacket.Payload := nil;

  if (AStream = nil) or (AStream.Size - AStream.Position < 4) then
    Exit(False);

  OriginalPos := AStream.Position;

  // Read 4-byte length prefix
  AStream.ReadBuffer(Header, 4);

  // Unpack Big-Endian length header to native UInt32 host order
  APacket.PayloadLength := (UInt32(Header[0]) shl 24) or
                           (UInt32(Header[1]) shl 16) or
                           (UInt32(Header[2]) shl 8) or
                           UInt32(Header[3]);

  // Fail-closed security gate: Guard against integer overflow / memory exhaustion attacks
  if (APacket.PayloadLength > AMaxPayloadSize) then
  begin
    AStream.Position := OriginalPos;
    Exit(False);
  end;

  // Check if complete frame body is available in stream
  if UInt32(AStream.Size - AStream.Position) < APacket.PayloadLength then
  begin
    AStream.Position := OriginalPos; // Rewind to start of header until full frame arrives
    Exit(False);
  end;

  // Read full payload body
  SetLength(APacket.Payload, APacket.PayloadLength);
  if APacket.PayloadLength > 0 then
    AStream.ReadBuffer(APacket.Payload[0], APacket.PayloadLength);

  Result := True;
end;

class function TGarpTransport.SerializeManifest(const AManifest: TGrispManifest): TBytes;
var
  MemStream: TMemoryStream;
  Writer: TBinaryWriter;
  SessionBytes, TabBytes: TBytes;
  SourcePathBytes, HashBytes: TBytes;
begin
  MemStream := TMemoryStream.Create;
  try
    Writer := TBinaryWriter.Create(MemStream);
    try
      SessionBytes := AManifest.SessionID.ToByteArray;
      TabBytes := AManifest.TabID.ToByteArray;
      SourcePathBytes := TGrispCanonical.ToUTF8Bytes(AManifest.SourcePath);
      HashBytes := TGrispCanonical.ToUTF8Bytes(AManifest.ContentHash);

      // Binary payload structure: GUIDs + Length-prefixed string metadata + Raw UTF8 Code Bytes
      Writer.Write(SessionBytes, 0, 16);
      Writer.Write(TabBytes, 0, 16);

      Writer.Write(Int32(Length(SourcePathBytes)));
      if Length(SourcePathBytes) > 0 then
        Writer.Write(SourcePathBytes, 0, Length(SourcePathBytes));

      Writer.Write(Int32(Length(HashBytes)));
      if Length(HashBytes) > 0 then
        Writer.Write(HashBytes, 0, Length(HashBytes));

      Writer.Write(Int32(Length(AManifest.RawBytes)));
      if Length(AManifest.RawBytes) > 0 then
        Writer.Write(AManifest.RawBytes, 0, Length(AManifest.RawBytes));

      SetLength(Result, MemStream.Size);
      Move(MemStream.Memory^, Result[0], MemStream.Size);
    finally
      Writer.Free;
    end;
  finally
    MemStream.Free;
  end;
end;

end.
