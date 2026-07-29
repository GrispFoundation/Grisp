unit GrispToolManifest;

interface

uses
  SysUtils, Classes, Generics.Collections, GrispMarkerParser;

type
  TArgumentSchema = record
    Name: string;
    ArgType: string;
    Required: Boolean;
    Min: string;
    Max: string;
    Default: string;
    Description: string;
  end;

  TActionDefinition = record
    ActionName: string;
    Arguments: TList<TArgumentSchema>;
    ReturnsType: string;
    ReturnsDescription: string;
    SideEffects: TStringList;
    Idempotent: Boolean;
    CostExpression: string;
    TimeoutMs: Integer;
    RetryMaxAttempts: Integer;
    RetryDelayMs: Integer;
    Permissions: TStringList;
    Preconditions: TStringList;
    Postconditions: TStringList;
    BundleStrategy: string;
  end;

  TToolManifest = class
  public
    Name: string;
    Version: string;
    Description: string;
    Capabilities: TStringList;
    Actions: TList<TActionDefinition>;
    constructor Create;
    destructor Destroy; override;
    function LoadFromBlock(Block: TBlock): Boolean;
    function FindAction(const ActionName: string): TActionDefinition;
  end;

  TToolManifestRegistry = class
  private
    FManifests: TDictionary<string, TToolManifest>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromDirectory(const Dir: string);
    function GetManifest(const ToolName: string): TToolManifest;
    function HasTool(const ToolName: string): Boolean;
  end;

implementation

{ TToolManifest }

constructor TToolManifest.Create;
begin
  Capabilities := TStringList.Create;
  Actions := TList<TActionDefinition>.Create;
end;

destructor TToolManifest.Destroy;
var
  a: TActionDefinition;
begin
  Capabilities.Free;
  for a in Actions do
  begin
    a.Arguments.Free;
    a.SideEffects.Free;
    a.Permissions.Free;
    a.Preconditions.Free;
    a.Postconditions.Free;
  end;
  Actions.Free;
  inherited;
end;

function TToolManifest.LoadFromBlock(Block: TBlock): Boolean;
var
  Child, Sub, ArgBlock: TBlock;
  i, j: Integer;
  ActionDef: TActionDefinition;
  ArgSchema: TArgumentSchema;
begin
  Result := False;
  if not Assigned(Block) then Exit;
  Name := Block.GetContent('NAME');
  Version := Block.GetContent('VERSION');
  Description := Block.GetContent('DESCRIPTION');
  Child := Block.FindChild('CAPABILITIES');
  if Assigned(Child) then
    for i := 0 to Child.Children.Count - 1 do
      Capabilities.Add(Child.Children[i].Content);
  Child := Block.FindChild('ACTIONS');
  if Assigned(Child) then
  begin
    for i := 0 to Child.Children.Count - 1 do
    begin
      Sub := Child.Children[i];
      if SameText(Sub.Name, 'ACTION') then
      begin
        ActionDef.ActionName := Sub.GetContent('ACTION NAME');
        ActionDef.ReturnsType := '';
        ActionDef.ReturnsDescription := '';
        ActionDef.Idempotent := False;
        ActionDef.CostExpression := '';
        ActionDef.TimeoutMs := 0;
        ActionDef.RetryMaxAttempts := 0;
        ActionDef.RetryDelayMs := 0;
        ActionDef.BundleStrategy := 'lazy';
        ActionDef.Arguments := TList<TArgumentSchema>.Create;
        ActionDef.SideEffects := TStringList.Create;
        ActionDef.Permissions := TStringList.Create;
        ActionDef.Preconditions := TStringList.Create;
        ActionDef.Postconditions := TStringList.Create;
        ArgBlock := Sub.FindChild('ARGUMENTS');
        if Assigned(ArgBlock) then
        begin
          for j := 0 to ArgBlock.Children.Count - 1 do
          begin
            if SameText(ArgBlock.Children[j].Name, 'ARGUMENT') then
            begin
              ArgSchema.Name := ArgBlock.Children[j].GetContent('NAME');
              ArgSchema.ArgType := ArgBlock.Children[j].GetContent('TYPE');
              ArgSchema.Required := SameText(ArgBlock.Children[j].GetContent('REQUIRED'), 'true');
              ArgSchema.Min := ArgBlock.Children[j].GetContent('MIN');
              ArgSchema.Max := ArgBlock.Children[j].GetContent('MAX');
              ArgSchema.Default := ArgBlock.Children[j].GetContent('DEFAULT');
              ArgSchema.Description := ArgBlock.Children[j].GetContent('DESCRIPTION');
              ActionDef.Arguments.Add(ArgSchema);
            end;
          end;
        end;
        Sub := Sub.FindChild('RETURNS');
        if Assigned(Sub) then
        begin
          ActionDef.ReturnsType := Sub.GetContent('TYPE');
          ActionDef.ReturnsDescription := Sub.GetContent('DESCRIPTION');
        end;
        Sub := Sub.FindChild('SIDE EFFECTS');
        if Assigned(Sub) then
          for j := 0 to Sub.Children.Count - 1 do
            ActionDef.SideEffects.Add(Sub.Children[j].Content);
        ActionDef.Idempotent := SameText(Sub.GetContent('IDEMPOTENT'), 'true');
        ActionDef.CostExpression := Sub.GetContent('COST EXPRESSION');
        ActionDef.TimeoutMs := StrToIntDef(Sub.GetContent('TIMEOUT MS'), 0);
        Sub := Sub.FindChild('RETRY POLICY');
        if Assigned(Sub) then
        begin
          ActionDef.RetryMaxAttempts := StrToIntDef(Sub.GetContent('MAX ATTEMPTS'), 1);
          ActionDef.RetryDelayMs := StrToIntDef(Sub.GetContent('DELAY MS'), 0);
        end;
        Sub := Sub.FindChild('PERMISSIONS');
        if Assigned(Sub) then
          for j := 0 to Sub.Children.Count - 1 do
            ActionDef.Permissions.Add(Sub.Children[j].Content);
        Sub := Sub.FindChild('PRECONDITIONS');
        if Assigned(Sub) then
          for j := 0 to Sub.Children.Count - 1 do
            ActionDef.Preconditions.Add(Sub.Children[j].Content);
        Sub := Sub.FindChild('POSTCONDITIONS');
        if Assigned(Sub) then
          for j := 0 to Sub.Children.Count - 1 do
            ActionDef.Postconditions.Add(Sub.Children[j].Content);
        ActionDef.BundleStrategy := Sub.GetContent('BUNDLE STRATEGY');
        if ActionDef.BundleStrategy = '' then ActionDef.BundleStrategy := 'lazy';
        Actions.Add(ActionDef);
      end;
    end;
  end;
  Result := True;
end;

function TToolManifest.FindAction(const ActionName: string): TActionDefinition;
var
  a: TActionDefinition;
begin
  for a in Actions do
    if SameText(a.ActionName, ActionName) then Exit(a);
  Result.ActionName := '';
end;

{ TToolManifestRegistry }

constructor TToolManifestRegistry.Create;
begin
  FManifests := TDictionary<string, TToolManifest>.Create;
end;

destructor TToolManifestRegistry.Destroy;
var
  m: TToolManifest;
begin
  for m in FManifests.Values do m.Free;
  FManifests.Free;
  inherited;
end;

procedure TToolManifestRegistry.LoadFromDirectory(const Dir: string);
var
  SR: TSearchRec;
  FilePath: string;
  Doc: TDocument;
  Manifest: TToolManifest;
  Content: string;
begin
  if FindFirst(Dir + '\*.manifest', faAnyFile, SR) = 0 then
  begin
    repeat
      FilePath := Dir + '\' + SR.Name;
      Content := '';
      with TStringList.Create do
      try
        LoadFromFile(FilePath);
        Content := Text;
      finally
        Free;
      end;
      Doc := TDocument.Create;
      try
        if Doc.Parse(Content) then
        begin
          Manifest := TToolManifest.Create;
          if Manifest.LoadFromBlock(Doc.Root) then
          begin
            if not FManifests.ContainsKey(Manifest.Name) then
              FManifests.Add(Manifest.Name, Manifest)
            else
              Manifest.Free;
          end
          else
            Manifest.Free;
        end;
      finally
        Doc.Free;
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function TToolManifestRegistry.GetManifest(const ToolName: string): TToolManifest;
begin
  if FManifests.TryGetValue(ToolName, Result) then Exit;
  Result := nil;
end;

function TToolManifestRegistry.HasTool(const ToolName: string): Boolean;
begin
  Result := FManifests.ContainsKey(ToolName);
end;

end.