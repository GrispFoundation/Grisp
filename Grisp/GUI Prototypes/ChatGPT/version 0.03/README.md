# GRISP GUI v0.1.2

Delphi 13 VCL prototype of the simplified GRISP GUI.

This version includes a real Delphi `.dfm` resource for `TGrispMainForm`.
The form itself remains code-driven for the prototype controls.

## Files

- `GRISP.GUI.dpr`
- `GRISP.GUI.Main.pas`
- `GRISP.GUI.Main.dfm`

## Important

`GRISP.GUI.Main.pas` contains:

```pascal
{$R *.dfm}
```

This is required so `Application.CreateForm(TGrispMainForm, GrispMainForm)` can find
the `TGrispMainForm` resource.

## Features

- Central chat workspace
- Collapsible Think section
- Chat input
- Session history
- Collapsible resource Explorer
- Read / Write / Execute permissions
- Plan / Work Items in the chat workspace
- Dark blue/cyan futuristic appearance
- No third-party dependencies

## Keyboard

F2       Explorer
F3       Sessions
F4       Think
Ctrl+N   New chat

The ZIP is intentionally flat; no root/version directory is included.
