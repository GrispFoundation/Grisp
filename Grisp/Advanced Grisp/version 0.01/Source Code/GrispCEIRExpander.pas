unit GrispCEIRExpander;

interface

uses
  SysUtils, Classes, Generics.Collections;

function ExpandCEIR(const AText: string): string;

implementation

type
  TCEIRExpander = class
  private
    FLines: TStringList;
    FOut: TStringList;
    FIndex: Integer;
    function GetIndent(const Line: string): string;
    function StripIndent(const Line: string): string;
    procedure AppendLine(const Line: string);
    procedure ExpandSet(const Line: string);
    procedure ExpandCall(const Line: string);
    procedure ExpandTransition(const Line: string);
    procedure ExpandIf(var idx: Integer);
    procedure ExpandWhile(var idx: Integer);
    procedure ExpandOnError(var idx: Integer);
    function ExpandBranch(const BranchText: TStringList; const Indent: string): TStringList;
    procedure EmitDecisionTree(const BranchBodies: TArray<TStringList>;
                               const BranchConditions: TArray<string>;
                               const Indent: string;
                               const StartIdx: Integer);
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Execute: string;
  end;

{ TCEIRExpander }

constructor TCEIRExpander.Create(const AText: string);
begin
  FLines := TStringList.Create;
  FLines.Text := AText;
  FOut := TStringList.Create;
  FIndex := 0;
end;

destructor TCEIRExpander.Destroy;
begin
  FLines.Free;
  FOut.Free;
  inherited;
end;

function TCEIRExpander.GetIndent(const Line: string): string;
var
  i: Integer;
begin
  i := 1;
  while (i <= Length(Line)) and (Line[i] in [' ', #9]) do
    Inc(i);
  Result := Copy(Line, 1, i-1);
end;

function TCEIRExpander.StripIndent(const Line: string): string;
begin
  Result := TrimLeft(Line);
end;

procedure TCEIRExpander.AppendLine(const Line: string);
begin
  FOut.Add(Line);
end;

function TCEIRExpander.ExpandBranch(const BranchText: TStringList; const Indent: string): TStringList;
var
  BranchExpander: TCEIRExpander;
  StrippedText: TStringList;
  i: Integer;
  Expanded: string;
begin
  Result := TStringList.Create;
  StrippedText := TStringList.Create;
  try
    for i := 0 to BranchText.Count - 1 do
      StrippedText.Add(TrimLeft(BranchText[i]));
    BranchExpander := TCEIRExpander.Create(StrippedText.Text);
    try
      Expanded := BranchExpander.Execute;
      var ExpandedLines := TStringList.Create;
      try
        ExpandedLines.Text := Expanded;
        for i := 0 to ExpandedLines.Count - 1 do
          Result.Add(Indent + ExpandedLines[i]);
      finally
        ExpandedLines.Free;
      end;
    finally
      BranchExpander.Free;
    end;
  finally
    StrippedText.Free;
  end;
end;

procedure TCEIRExpander.EmitDecisionTree(const BranchBodies: TArray<TStringList>;
                                         const BranchConditions: TArray<string>;
                                         const Indent: string;
                                         const StartIdx: Integer);
var
  ExpandedBody: TStringList;
  i: Integer;
begin
  if StartIdx >= Length(BranchBodies) then Exit;
  ExpandedBody := ExpandBranch(BranchBodies[StartIdx], Indent + '  ');
  try
    AppendLine(Indent + '⟦BEGIN DECISION⟧');
    AppendLine(Indent + '  ⟦BEGIN CONDITION⟧' + BranchConditions[StartIdx] + '⟦END CONDITION⟧');
    AppendLine(Indent + '  ⟦BEGIN STATEMENT⟧');
    for i := 0 to ExpandedBody.Count - 1 do
      AppendLine(ExpandedBody[i]);
    AppendLine(Indent + '  ⟦END STATEMENT⟧');
    if StartIdx + 1 < Length(BranchBodies) then
    begin
      AppendLine(Indent + '  ⟦BEGIN ELSE⟧');
      EmitDecisionTree(BranchBodies, BranchConditions, Indent + '    ', StartIdx + 1);
      AppendLine(Indent + '  ⟦END ELSE⟧');
    end;
    AppendLine(Indent + '⟦END DECISION⟧');
  finally
    ExpandedBody.Free;
  end;
end;

procedure TCEIRExpander.ExpandSet(const Line: string);
var
  expr, indent: string;
begin
  indent := GetIndent(Line);
  expr := Copy(Line, Pos('⟦SET ', Line) + 6, Length(Line));
  expr := Trim(Copy(expr, 1, Length(expr)-1)); // remove trailing ⟧
  AppendLine(indent + '⟦BEGIN ASSIGNMENT⟧' + expr + '⟦END ASSIGNMENT⟧');
end;

procedure TCEIRExpander.ExpandCall(const Line: string);
var
  rest, targetPart, args, intoVar: string;
  parenPos, dotPos, intoPos: Integer;
  indent: string;
begin
  indent := GetIndent(Line);
  rest := Copy(Line, Pos('⟦CALL ', Line) + 7, Length(Line));
  rest := Trim(Copy(rest, 1, Length(rest)-1)); // remove trailing ⟧
  intoPos := Pos(' INTO ', rest);
  if intoPos > 0 then
  begin
    intoVar := Trim(Copy(rest, intoPos + 6, MaxInt));
    rest := Trim(Copy(rest, 1, intoPos - 1));
  end
  else
    intoVar := '';

  parenPos := Pos('(', rest);
  if parenPos = 0 then Exit;
  targetPart := Trim(Copy(rest, 1, parenPos - 1));
  args := Trim(Copy(rest, parenPos + 1, Length(rest) - parenPos - 1));
  dotPos := Pos('.', targetPart);
  if dotPos = 0 then Exit;
  var target := Trim(Copy(targetPart, 1, dotPos - 1));
  var action := Trim(Copy(targetPart, dotPos + 1, MaxInt));

  AppendLine(indent + '⟦BEGIN TOOL CALL⟧');
  AppendLine(indent + '  ⟦BEGIN TOOL TARGET⟧' + target + '⟦END TOOL TARGET⟧');
  AppendLine(indent + '  ⟦BEGIN ACTION⟧' + action + '⟦END ACTION⟧');
  AppendLine(indent + '  ⟦BEGIN ARGUMENTS⟧' + args + '⟦END ARGUMENTS⟧');
  AppendLine(indent + '⟦END TOOL CALL⟧');

  if intoVar <> '' then
    AppendLine(indent + '⟦BEGIN ASSIGNMENT⟧' + intoVar + ' = result⟦END ASSIGNMENT⟧');
end;

procedure TCEIRExpander.ExpandTransition(const Line: string);
var
  rest, fromState, toState, cond: string;
  arrowPos, ifPos: Integer;
  indent: string;
begin
  indent := GetIndent(Line);
  rest := Copy(Line, Pos('⟦TRANSITION ', Line) + 13, Length(Line));
  rest := Trim(Copy(rest, 1, Length(rest)-1)); // remove ⟧
  arrowPos := Pos(' -> ', rest);
  if arrowPos = 0 then Exit;
  fromState := Trim(Copy(rest, 1, arrowPos - 1));
  ifPos := Pos(' IF ', rest);
  if ifPos > 0 then
  begin
    toState := Trim(Copy(rest, arrowPos + 4, ifPos - arrowPos - 4));
    cond := Trim(Copy(rest, ifPos + 4, MaxInt));
  end
  else
  begin
    toState := Trim(Copy(rest, arrowPos + 4, MaxInt));
    cond := 'true';
  end;
  AppendLine(indent + '⟦BEGIN TRANSITION⟧');
  AppendLine(indent + '  ⟦BEGIN FROM STATE⟧' + fromState + '⟦END FROM STATE⟧');
  AppendLine(indent + '  ⟦BEGIN TO STATE⟧' + toState + '⟦END TO STATE⟧');
  AppendLine(indent + '  ⟦BEGIN TRANSITION CONDITION⟧' + cond + '⟦END TRANSITION CONDITION⟧');
  AppendLine(indent + '⟦END TRANSITION⟧');
end;

procedure TCEIRExpander.ExpandIf(var idx: Integer);
var
  startLine, indent, cond: string;
  i, depth, endIdx: Integer;
  branchBodies: TList<TStringList>;
  branchConditions: TList<string>;
  currentBody: TStringList;
  currentCond: string;
  line, stripped: string;
begin
  startLine := FLines[idx];
  indent := GetIndent(startLine);
  cond := Copy(StripIndent(startLine), Pos('⟦IF ', StripIndent(startLine)) + 5, MaxInt);
  cond := Trim(Copy(cond, 1, Length(cond)-4)); // remove " THEN" and ⟧

  // Find matching END IF
  i := idx + 1;
  depth := 1;
  endIdx := -1;
  while i < FLines.Count do
  begin
    stripped := StripIndent(FLines[i]);
    if stripped.StartsWith('⟦IF ') or stripped.StartsWith('⟦WHILE ') or stripped.StartsWith('⟦ON ERROR ') then
      Inc(depth)
    else if stripped.StartsWith('⟦END IF⟧') or stripped.StartsWith('⟦END WHILE⟧') or stripped.StartsWith('⟦END ON ERROR⟧') then
    begin
      Dec(depth);
      if (depth = 0) and stripped.StartsWith('⟦END IF⟧') then
      begin
        endIdx := i;
        Break;
      end;
    end;
    Inc(i);
  end;
  if endIdx = -1 then
  begin
    AppendLine(startLine);
    Exit;
  end;

  // Collect branches
  branchBodies := TList<TStringList>.Create;
  branchConditions := TList<string>.Create;
  try
    currentBody := TStringList.Create;
    currentCond := cond;
    i := idx + 1;
    while i < endIdx do
    begin
      line := FLines[i];
      stripped := StripIndent(line);
      if (GetIndent(line) = indent) and
         (stripped.StartsWith('⟦ELSE IF ') or stripped.StartsWith('⟦ELSE⟧')) then
      begin
        if currentBody.Count > 0 then
        begin
          branchBodies.Add(currentBody);
          branchConditions.Add(currentCond);
          currentBody := TStringList.Create;
        end;
        if stripped.StartsWith('⟦ELSE IF ') then
        begin
          currentCond := Copy(stripped, Pos('⟦ELSE IF ', stripped) + 10, MaxInt);
          currentCond := Trim(Copy(currentCond, 1, Length(currentCond)-4)); // remove " THEN" and ⟧
        end
        else
          currentCond := 'true';
        Inc(i);
        Continue;
      end;
      currentBody.Add(line);
      Inc(i);
    end;
    if currentBody.Count > 0 then
    begin
      branchBodies.Add(currentBody);
      branchConditions.Add(currentCond);
    end
    else
      currentBody.Free;

    // Emit decision tree
    if branchBodies.Count > 0 then
      EmitDecisionTree(branchBodies.ToArray, branchConditions.ToArray, indent, 0);

    idx := endIdx; // skip processed lines
  finally
    for var b in branchBodies do b.Free;
    branchBodies.Free;
    branchConditions.Free;
  end;
end;

procedure TCEIRExpander.ExpandWhile(var idx: Integer);
var
  startLine, indent, cond: string;
  i, depth, endIdx: Integer;
  bodyLines: TStringList;
  stripped: string;
  ExpandedBody: TStringList;
begin
  startLine := FLines[idx];
  indent := GetIndent(startLine);
  cond := Copy(StripIndent(startLine), Pos('⟦WHILE ', StripIndent(startLine)) + 8, MaxInt);
  cond := Trim(Copy(cond, 1, Length(cond)-4)); // remove " DO" and ⟧

  i := idx + 1;
  depth := 1;
  endIdx := -1;
  while i < FLines.Count do
  begin
    stripped := StripIndent(FLines[i]);
    if stripped.StartsWith('⟦IF ') or stripped.StartsWith('⟦WHILE ') or stripped.StartsWith('⟦ON ERROR ') then
      Inc(depth)
    else if stripped.StartsWith('⟦END IF⟧') or stripped.StartsWith('⟦END WHILE⟧') or stripped.StartsWith('⟦END ON ERROR⟧') then
    begin
      Dec(depth);
      if (depth = 0) and stripped.StartsWith('⟦END WHILE⟧') then
      begin
        endIdx := i;
        Break;
      end;
    end;
    Inc(i);
  end;
  if endIdx = -1 then
  begin
    AppendLine(startLine);
    Exit;
  end;

  bodyLines := TStringList.Create;
  try
    for i := idx + 1 to endIdx - 1 do
      bodyLines.Add(FLines[i]);
    ExpandedBody := ExpandBranch(bodyLines, indent + '  ');
    try
      AppendLine(indent + '⟦BEGIN LOOP⟧');
      AppendLine(indent + '  repeat until ' + cond);
      AppendLine(indent + '  ⟦BEGIN STATEMENT⟧');
      for i := 0 to ExpandedBody.Count - 1 do
        AppendLine(ExpandedBody[i]);
      AppendLine(indent + '  ⟦END STATEMENT⟧');
      AppendLine(indent + '⟦END LOOP⟧');
    finally
      ExpandedBody.Free;
    end;
  finally
    bodyLines.Free;
  end;
  idx := endIdx;
end;

procedure TCEIRExpander.ExpandOnError(var idx: Integer);
var
  startLine, indent, cond: string;
  i, depth, endIdx: Integer;
  bodyLines: TStringList;
  stripped: string;
  ExpandedBody: TStringList;
begin
  startLine := FLines[idx];
  indent := GetIndent(startLine);
  cond := Copy(StripIndent(startLine), Pos('⟦ON ERROR ', StripIndent(startLine)) + 10, MaxInt);
  cond := Trim(Copy(cond, 1, Length(cond)-4)); // remove " DO" and ⟧

  i := idx + 1;
  depth := 1;
  endIdx := -1;
  while i < FLines.Count do
  begin
    stripped := StripIndent(FLines[i]);
    if stripped.StartsWith('⟦IF ') or stripped.StartsWith('⟦WHILE ') or stripped.StartsWith('⟦ON ERROR ') then
      Inc(depth)
    else if stripped.StartsWith('⟦END IF⟧') or stripped.StartsWith('⟦END WHILE⟧') or stripped.StartsWith('⟦END ON ERROR⟧') then
    begin
      Dec(depth);
      if (depth = 0) and stripped.StartsWith('⟦END ON ERROR⟧') then
      begin
        endIdx := i;
        Break;
      end;
    end;
    Inc(i);
  end;
  if endIdx = -1 then
  begin
    AppendLine(startLine);
    Exit;
  end;

  bodyLines := TStringList.Create;
  try
    for i := idx + 1 to endIdx - 1 do
      bodyLines.Add(FLines[i]);
    ExpandedBody := ExpandBranch(bodyLines, indent + '  ');
    try
      AppendLine(indent + '⟦BEGIN ON FAILURE⟧');
      AppendLine(indent + '  ⟦BEGIN FAILURE CONDITION⟧' + cond + '⟦END FAILURE CONDITION⟧');
      AppendLine(indent + '  ⟦BEGIN FALLBACK⟧');
      for i := 0 to ExpandedBody.Count - 1 do
        AppendLine(ExpandedBody[i]);
      AppendLine(indent + '  ⟦END FALLBACK⟧');
      AppendLine(indent + '⟦END ON FAILURE⟧');
    finally
      ExpandedBody.Free;
    end;
  finally
    bodyLines.Free;
  end;
  idx := endIdx;
end;

function TCEIRExpander.Execute: string;
var
  line, stripped: string;
begin
  FIndex := 0;
  while FIndex < FLines.Count do
  begin
    line := FLines[FIndex];
    stripped := StripIndent(line);
    if stripped.StartsWith('⟦SET ') then
      ExpandSet(line)
    else if stripped.StartsWith('⟦CALL ') then
      ExpandCall(line)
    else if stripped.StartsWith('⟦TRANSITION ') then
      ExpandTransition(line)
    else if stripped.StartsWith('⟦IF ') then
      ExpandIf(FIndex)
    else if stripped.StartsWith('⟦WHILE ') then
      ExpandWhile(FIndex)
    else if stripped.StartsWith('⟦ON ERROR ') then
      ExpandOnError(FIndex)
    else
      AppendLine(line);
    Inc(FIndex);
  end;
  Result := FOut.Text;
end;

// ----------------------------------------------------------------------------
function ExpandCEIR(const AText: string): string;
var
  exp: TCEIRExpander;
begin
  exp := TCEIRExpander.Create(AText);
  try
    Result := exp.Execute;
  finally
    exp.Free;
  end;
end;

end.
