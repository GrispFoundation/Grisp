// Style: semantic-prefixes v2.0

unit GRISP.TUI.Model;

interface

uses
    System.SysUtils;

type
    TGrispPermission = (gpRead, gpWrite, gpExecute);

    TGrispResource = record
        Name: string;
        Kind: string;
        Trust: Integer;
        ReadAllowed: Boolean;
        WriteAllowed: Boolean;
        ExecuteAllowed: Boolean;
        Depth: Integer;
        IsFolder: Boolean;
        Expanded: Boolean;
    end;

    TGrispSession = record
        Title: string;
        DateTimeText: string;
    end;

    TGrispMessage = record
        Role: string;
        TimeText: string;
        Lines: TArray<string>;
    end;

    TGrispPlanItem = record
        Title: string;
        State: string;
    end;

    TGrispModel = class
    private
        mResources: TArray<TGrispResource>;
        mSessions: TArray<TGrispSession>;
        mMessages: TArray<TGrispMessage>;
        mPlan: TArray<TGrispPlanItem>;
        mSelectedResource: Integer;
        mSelectedSession: Integer;
        mInputText: string;
    public
        constructor Create;
        procedure AddUserMessage(const ParaText: string);
        procedure AddAssistantMessage(const ParaLines: array of string);
        procedure AddSession(const ParaTitle: string);
        property Resources: TArray<TGrispResource> read mResources;
        property Sessions: TArray<TGrispSession> read mSessions;
        property Messages: TArray<TGrispMessage> read mMessages;
        property Plan: TArray<TGrispPlanItem> read mPlan;
        property SelectedResource: Integer read mSelectedResource write mSelectedResource;
        property SelectedSession: Integer read mSelectedSession write mSelectedSession;
        property InputText: string read mInputText write mInputText;
    end;

implementation

constructor TGrispModel.Create;
begin
    inherited Create;

    mSelectedResource := 0;
    mSelectedSession := 0;

    SetLength(mResources, 11);

    mResources[0].Name := 'GRISP';
    mResources[0].Kind := 'Project';
    mResources[0].Trust := 85;
    mResources[0].ReadAllowed := True;
    mResources[0].WriteAllowed := True;
    mResources[0].ExecuteAllowed := True;
    mResources[0].Depth := 0;
    mResources[0].IsFolder := True;
    mResources[0].Expanded := True;

    mResources[1].Name := 'Local';
    mResources[1].Kind := 'Folder';
    mResources[1].Trust := 90;
    mResources[1].ReadAllowed := True;
    mResources[1].WriteAllowed := True;
    mResources[1].ExecuteAllowed := False;
    mResources[1].Depth := 1;
    mResources[1].IsFolder := True;
    mResources[1].Expanded := True;

    mResources[2].Name := 'Projects';
    mResources[2].Kind := 'Folder';
    mResources[2].Trust := 90;
    mResources[2].ReadAllowed := True;
    mResources[2].WriteAllowed := True;
    mResources[2].ExecuteAllowed := False;
    mResources[2].Depth := 2;
    mResources[2].IsFolder := True;
    mResources[2].Expanded := True;

    mResources[3].Name := 'GRISP';
    mResources[3].Kind := 'Folder';
    mResources[3].Trust := 85;
    mResources[3].ReadAllowed := True;
    mResources[3].WriteAllowed := True;
    mResources[3].ExecuteAllowed := True;
    mResources[3].Depth := 3;
    mResources[3].IsFolder := True;
    mResources[3].Expanded := True;

    mResources[4].Name := 'src';
    mResources[4].Kind := 'Folder';
    mResources[4].Trust := 85;
    mResources[4].ReadAllowed := True;
    mResources[4].WriteAllowed := True;
    mResources[4].ExecuteAllowed := False;
    mResources[4].Depth := 4;
    mResources[4].IsFolder := True;

    mResources[5].Name := 'tests';
    mResources[5].Kind := 'Folder';
    mResources[5].Trust := 85;
    mResources[5].ReadAllowed := True;
    mResources[5].WriteAllowed := True;
    mResources[5].ExecuteAllowed := False;
    mResources[5].Depth := 4;
    mResources[5].IsFolder := True;

    mResources[6].Name := 'docs';
    mResources[6].Kind := 'Folder';
    mResources[6].Trust := 85;
    mResources[6].ReadAllowed := True;
    mResources[6].WriteAllowed := True;
    mResources[6].ExecuteAllowed := False;
    mResources[6].Depth := 4;
    mResources[6].IsFolder := True;

    mResources[7].Name := 'Models';
    mResources[7].Kind := 'Folder';
    mResources[7].Trust := 90;
    mResources[7].ReadAllowed := True;
    mResources[7].WriteAllowed := False;
    mResources[7].ExecuteAllowed := False;
    mResources[7].Depth := 1;
    mResources[7].IsFolder := True;

    mResources[8].Name := 'Agents';
    mResources[8].Kind := 'Folder';
    mResources[8].Trust := 80;
    mResources[8].ReadAllowed := True;
    mResources[8].WriteAllowed := True;
    mResources[8].ExecuteAllowed := False;
    mResources[8].Depth := 1;
    mResources[8].IsFolder := True;

    mResources[9].Name := 'Knowledge';
    mResources[9].Kind := 'Folder';
    mResources[9].Trust := 75;
    mResources[9].ReadAllowed := True;
    mResources[9].WriteAllowed := True;
    mResources[9].ExecuteAllowed := False;
    mResources[9].Depth := 1;
    mResources[9].IsFolder := True;

    mResources[10].Name := 'Workspace';
    mResources[10].Kind := 'Folder';
    mResources[10].Trust := 95;
    mResources[10].ReadAllowed := True;
    mResources[10].WriteAllowed := True;
    mResources[10].ExecuteAllowed := True;
    mResources[10].Depth := 1;
    mResources[10].IsFolder := True;

    SetLength(mSessions, 4);

    mSessions[0].Title := 'GRISP architecture';
    mSessions[0].DateTimeText := '22 Sep 2026 14:32';
    mSessions[1].Title := 'Data model discussion';
    mSessions[1].DateTimeText := '22 Sep 2026 11:48';
    mSessions[2].Title := 'Bug investigation';
    mSessions[2].DateTimeText := '21 Sep 2026 16:20';
    mSessions[3].Title := 'Feature planning';
    mSessions[3].DateTimeText := '20 Sep 2026 09:10';

    SetLength(mPlan, 4);
    mPlan[0].Title := 'Analyze architecture';
    mPlan[0].State := 'DONE';
    mPlan[1].Title := 'Review component details';
    mPlan[1].State := 'ACTIVE';
    mPlan[2].Title := 'Create diagram';
    mPlan[2].State := 'TODO';
    mPlan[3].Title := 'Update documentation';
    mPlan[3].State := 'TODO';

    AddUserMessage('Explain the GRISP architecture and its main components.');
    AddAssistantMessage([
        'GRISP is organized as a deterministic graph-based execution pipeline.',
        '',
        '1. SIR        Source Intermediate Representation',
        '2. Planner     Creates an execution plan',
        '3. Evaluator   Executes graph operations',
        '4. Validator   Validates the resulting state',
        '5. EIR         Execution Intermediate Representation',
        '6. Runtime     Performs deterministic execution',
        '7. WorldState  Holds persistent execution state',
        '',
        'The same session can expose resources, permissions, plans and events without',
        'turning the main workspace into a monitoring dashboard.'
    ]);
end;

procedure TGrispModel.AddUserMessage(const ParaText: string);
var
    vMessage: TGrispMessage;
    vIndex: Integer;
begin
    vMessage.Role := 'YOU';
    vMessage.TimeText := FormatDateTime('hh:nn', Now);
    vMessage.Lines := ParaText.Split([sLineBreak]);
    vIndex := Length(mMessages);
    SetLength(mMessages, vIndex + 1);
    mMessages[vIndex] := vMessage;
end;

procedure TGrispModel.AddAssistantMessage(const ParaLines: array of string);
var
    vMessage: TGrispMessage;
    vIndex: Integer;
    vLineIndex: Integer;
begin
    vMessage.Role := 'GRISP';
    vMessage.TimeText := FormatDateTime('hh:nn', Now);
    SetLength(vMessage.Lines, Length(ParaLines));
    for vLineIndex := 0 to High(ParaLines) do
        vMessage.Lines[vLineIndex] := ParaLines[vLineIndex];

    vIndex := Length(mMessages);
    SetLength(mMessages, vIndex + 1);
    mMessages[vIndex] := vMessage;
end;

procedure TGrispModel.AddSession(const ParaTitle: string);
var
    vIndex: Integer;
begin
    vIndex := Length(mSessions);
    SetLength(mSessions, vIndex + 1);
    mSessions[vIndex].Title := ParaTitle;
    mSessions[vIndex].DateTimeText := FormatDateTime('dd mmm yyyy hh:nn', Now);
    mSelectedSession := vIndex;
end;

end.
