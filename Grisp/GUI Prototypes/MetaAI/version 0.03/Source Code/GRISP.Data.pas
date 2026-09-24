unit GRISP.Data;

interface

uses Vcl.Graphics;

type
  TGRISPColors = record
  public
    const
      BG_DARK   = TColor($1C0B05);
      BG_PANEL  = TColor($331B0E);
      BG_PANEL2 = TColor($3F2312);
      BG_CARD   = TColor($4A2A16);
      BORDER    = TColor($6B3A1E);
      ACCENT_CYAN = TColor($FFD400);
      ACCENT_BLUE = TColor($FF7C4F);
      TEXT_MAIN = TColor($FFF4E2);
      TEXT_DIM  = TColor($B88B6B);
      GREEN_OK  = TColor($88FF00);
      RED_HIGH  = TColor($4444FF);
      AMBER_MED = TColor($00AAFF);
  end;

  TRWXHelper = class
  public
    class function PrioColor(const Prio: string): TColor;
    class function StatusColor(const Status: string): TColor;
  end;

implementation

class function TRWXHelper.PrioColor(const Prio: string): TColor;
begin
  if Prio = 'High' then Result := TGRISPColors.RED_HIGH
  else if Prio = 'Medium' then Result := TGRISPColors.AMBER_MED
  else Result := TGRISPColors.ACCENT_BLUE;
end;

class function TRWXHelper.StatusColor(const Status: string): TColor;
begin
  if Status = 'Completed' then Result := TGRISPColors.GREEN_OK
  else if Status = 'In progress' then Result := TGRISPColors.AMBER_MED
  else Result := TGRISPColors.TEXT_DIM;
end;

end.
