unit GRISP.Data;

interface

uses
  System.SysUtils, Vcl.Graphics, System.UITypes;

type
  // Delphi 13 Florence kleuren - blauw/futuristisch
  TGRISPColors = record
  public
    const
      BG_DARK       = TColor($1C0B05); // #050B1C
      BG_PANEL      = $331B0E; // #0E1B33
      BG_PANEL2     = $3F2312; // #12233F
      BG_CARD       = $4A2A16; // #162A4A
      BORDER        = $6B3A1E; // #1E3A6B
      BORDER_GLOW   = $FFD400; // #00D4FF cyan
      ACCENT_CYAN   = $FFD400; // #00D4FF BGR!
      ACCENT_BLUE   = $FF7C4F; // #4F7CFF
      TEXT_MAIN     = $FFF4E2; // #E2F4FF
      TEXT_DIM      = $B88B6B; // #6B8BB8
      GREEN_OK      = $88FF44; // #44FF88
      RED_HIGH      = $4444FF; // #FF4444
      AMBER_MED     = $00AAFF; // #FFAA00
      BLUE_LOW      = $FF8855; // #5588FF
  end;

  TPermission = (permRead, permWrite, permExecute);
  TPermissions = set of TPermission;

  TResourceItem = record
    Name: string;
    IsFolder: Boolean;
    Trust: Integer; // 0-100
    Perms: TPermissions;
    Path: string;
  end;

  TSessionItem = record
    Subject: string;
    DayStr: string; // Today, Yesterday, 22 Sep
    TimeStr: string; // 14:32
    MsgCount: Integer;
    IsActive: Boolean;
  end;

  TPlanStep = record
    Title: string;
    Status: Integer; // 0=Pending,1=InProgress,2=Completed
  end;

  TWorkItem = record
    Title: string;
    Priority: Integer; // 0=Low,1=Medium,2=High
  end;

  TChatRole = (crUser, crAssistant, crSystem);

  TChatMessage = record
    Role: TChatRole;
    Text: string;
    TimeStr: string;
    Thinking: string; // collapsable think content
    HasPlan: Boolean;
  end;

implementation

end.
