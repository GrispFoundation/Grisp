# GRISP TUI Prototype v0.1

A minimal Delphi 13 Windows console prototype for the GRISP user interface.

## Design goals

This prototype intentionally avoids dashboard/monitoring clutter. It focuses on:

1. Chat workspace
2. Optional collapsible Think view
3. Chat input bar
4. Session history
5. Optional Explorer
6. Read / Write / Execute permissions
7. Optional in-chat Plan

The Explorer and Sessions panel are mutually exclusive and can be hidden so the chat can occupy the full terminal.

## Controls

- `F2` Explorer
- `F3` Sessions
- `F4` Think
- `F5` Plan
- `Ctrl+N` New session
- `Ctrl+L` Focus chat input
- `Tab` Focus chat input
- `Enter` Send
- `Backspace` Edit input
- `Esc` Leave input / quit

## Build

Open `GRISP.TUI.dpr` in Delphi 13 Florence and build a Win32 or Win64 Console application.

No third-party components are required by this prototype. It uses the Windows console API directly, including Unicode output and Virtual Terminal sequences where supported.

## Notes

This is deliberately a UI prototype. The sample data is contained in `GRISP.TUI.Model.pas`. The next architectural step should be replacing the sample model with the actual GRISP session/resource/event interfaces without changing the renderer/input layer.
