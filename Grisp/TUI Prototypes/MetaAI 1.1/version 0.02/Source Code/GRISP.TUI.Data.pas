unit GRISP.TUI.Data;

interface

type
  TPermission = (permRead, permWrite, permExecute);
  TPermissions = set of TPermission;

  TResourceItem = record
    Name: string;
    IsFolder: Boolean;
    Level: Integer;
    Perms: TPermissions;
    Trust: Integer;
    constructor Create(const AName: string; ALevel: Integer; AIsFolder: Boolean; APerms: TPermissions; ATrust: Integer);
  end;

  TSessionItem = record
    Subject: string;
    Day: string;
    TimeStr: string;
    MsgCount: Integer;
    IsActive: Boolean;
  end;

  TPlanStep = record
    Title: string;
    Status: Integer;
  end;

  TWorkItem = record
    Title: string;
    Priority: Integer;
  end;

  TChatRole = (crUser, crAssistant);

  TChatMessage = record
    Role: TChatRole;
    Text: string;
    TimeStr: string;
    Thinking: string;
    HasPlan: Boolean;
  end;

  TFocusedPanel = (fpExplorer, fpSessions, fpChat, fpPlan, fpInput);

implementation

constructor TResourceItem.Create(const AName: string; ALevel: Integer; AIsFolder: Boolean; APerms: TPermissions; ATrust: Integer);
begin
  Name := AName;
  Level := ALevel;
  IsFolder := AIsFolder;
  Perms := APerms;
  Trust := ATrust;
end;

end.
