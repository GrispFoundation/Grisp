unit Grisp.Core.Tests;

interface

procedure RunCoreTests;

implementation

uses
  System.SysUtils, Grisp.Types, Grisp.Artifact, Grisp.ArtifactParser,
  Grisp.StateMachine;

procedure Require(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

procedure RunCoreTests;
var
  A, B: TGrispArtifactBundle;
  ErrorText: string;
begin
  A := Default(TGrispArtifactBundle);
  Require(ParseMarkdownArtifact('```delphi:main.pas' + sLineBreak +
    'begin end.' + sLineBreak + '```', 'task', A, ErrorText) = prParsed,
    'valid markdown must parse');
  B := A;
  B.Files[0].Content[0] := Ord('x');
  Require(B.ArtifactId <> ComputeArtifactId(B), 'mutation must change identity');
  Require(ParseMarkdownArtifact('```delphi:a.pas' + sLineBreak + 'x' +
    sLineBreak + '```' + sLineBreak + '```delphi:b.pas' + sLineBreak +
    'y' + sLineBreak + '```', 'task', A, ErrorText) = prParseAmbiguous,
    'multiple blocks must be ambiguous');
end;

end.
