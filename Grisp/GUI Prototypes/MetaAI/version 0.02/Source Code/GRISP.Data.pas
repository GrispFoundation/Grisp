unit GRISP.Data;

interface

uses
  Vcl.Graphics, System.SysUtils;

type
  TGRISPColors = record
  public
    const
      BG_DARK     = TColor($1C0B05); // $050B1C swapped to BGR
      BG_PANEL    = TColor($331B0E); // $0E1B33
      BG_PANEL2   = TColor($3F2312); // $12233F
      BG_CARD     = TColor($4A2A16); // $162A4A
      BG_BUBBLE_USER = TColor($6B3A1A); // $1A3A6B
      BG_BUBBLE_AI   = TColor($33200E); // $0E2033
      BORDER      = TColor($6B3A1E);
      ACCENT_CYAN = TColor($FFD400); // $00D4FF
      ACCENT_BLUE = TColor($FF7C4F); // $4F7CFF
      TEXT_MAIN   = TColor($FFF4E2); // $E2F4FF
      TEXT_DIM    = TColor($B88B6B); // $6B8BB8
      GREEN_OK    = TColor($88FF00); // $00FF88
      RED_HIGH    = TColor($4444FF); // $FF4444
      AMBER_MED   = TColor($00AAFF); // $FFAA00
      BLUE_LOW    = TColor($FF7C4F);
      TRUST_CYAN  = TColor($FFD400);
  end;

  TChatRole = (crUser, crAssistant, crSystem);

  TRWXHelper = class
  public
    class function PermColor(Perm: Char; Allowed: Boolean): TColor;
    class function TrustColor(Trust: Integer): TColor;
    class function StatusColor(const Status: string): TColor;
    class function PrioColor(const Prio: string): TColor;
  end;

implementation

class function TRWXHelper.PermColor(Perm: Char; Allowed: Boolean): TColor;
begin
  if not Allowed then Exit(TGRISPColors.TEXT_DIM);
  case Perm of
    'R': Result := TGRISPColors.ACCENT_BLUE;
    'W': Result := TGRISPColors.GREEN_OK;
    'X': Result := TGRISPColors.AMBER_MED;
  else Result := TGRISPColors.TEXT_DIM;
  end;
end;

class function TRWXHelper.TrustColor(Trust: Integer): TColor;
begin
  if Trust >= 80 then Result := TGRISPColors.GREEN_OK
  else if Trust >= 50 then Result := TGRISPColors.AMBER_MED
  else Result := TGRISPColors.RED_HIGH;
end;

class function TRWXHelper.StatusColor(const Status: string): TColor;
begin
  if Status = 'Completed' then Result := TGRISPColors.GREEN_OK
  else if Status = 'In progress' then Result := TGRISPColors.AMBER_MED
  else Result := TGRISPColors.TEXT_DIM;
end;

class function TRWXHelper.PrioColor(const Prio: string): TColor;
begin
  if Prio = 'High' then Result := TGRISPColors.RED_HIGH
  else if Prio = 'Medium' then Result := TGRISPColors.AMBER_MED
  else Result := TGRISPColors.ACCENT_BLUE;
end;

end.
