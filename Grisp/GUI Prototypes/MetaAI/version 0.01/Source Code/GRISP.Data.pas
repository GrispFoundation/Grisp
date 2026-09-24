unit GRISP.Data;

interface

uses
  Vcl.Graphics;

type
  TGRISPColors = record
  public
    const
      BG_DARK     = TColor($1C0B05);
      BG_PANEL    = TColor($331B0E);
      BG_PANEL2   = TColor($3F2312);
      BG_CARD     = TColor($4A2A16);
      BORDER      = TColor($6B3A1E);
      ACCENT_CYAN = TColor($FFD400);
      ACCENT_BLUE = TColor($FF7C4F);
      TEXT_MAIN   = TColor($FFF4E2);
      TEXT_DIM    = TColor($B88B6B);
      GREEN_OK    = TColor($88FF44);
  end;

  TChatRole = (crUser, crAssistant, crSystem);

implementation

end.
