program GrispConformance;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Grisp.Types in '..\Core\Grisp.Types.pas',
  Grisp.Hash in '..\Core\Grisp.Hash.pas',
  Grisp.Canonical in '..\Core\Grisp.Canonical.pas',
  Grisp.Artifact in '..\Core\Grisp.Artifact.pas',
  Grisp.ArtifactParser in '..\Core\Grisp.ArtifactParser.pas',
  Grisp.Evidence in '..\Core\Grisp.Evidence.pas',
  Grisp.StateMachine in '..\Core\Grisp.StateMachine.pas',
  Grisp.Policy in '..\Core\Grisp.Policy.pas',
  Grisp.Commit in '..\Core\Grisp.Commit.pas';

var
  Artifact: TGrispArtifactBundle;
  ErrorText: string;
  ParseResult: TGrispParseResult;
  State, NextState: TGrispCandidateState;
  Evidence: TGrispEvidence;
begin
  Artifact := Default(TGrispArtifactBundle);
  ParseResult := ParseMarkdownArtifact(
    '```delphi:HelloWorld.dpr' + sLineBreak +
    'program HelloWorld;' + sLineBreak +
    'begin' + sLineBreak +
    '  Writeln(''Hello, World!'');' + sLineBreak +
    'end.' + sLineBreak + '```',
    NewUuid, Artifact, ErrorText);
  if ParseResult <> prParsed then
    raise Exception.Create('Conformance parser failure: ' + ErrorText);
  State := csCreated;
  if not CanTransition(State, 'parsed', NextState, ErrorText) then
    raise Exception.Create(ErrorText);
  State := NextState;
  if not CanTransition(State, 'normalized', NextState, ErrorText) then
    raise Exception.Create(ErrorText);
  State := NextState;
  if not CanTransition(State, 'static_ok', NextState, ErrorText) then
    raise Exception.Create(ErrorText);
  if not CommitArtifact(Artifact, '..\..\..\Output\Delphi Produced Executables',
    Evidence, ErrorText) then
    raise Exception.Create(ErrorText);
  Writeln('GRISP core conformance slice passed: ', Artifact.ArtifactId);
end.
