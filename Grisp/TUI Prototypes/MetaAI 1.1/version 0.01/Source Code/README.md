# GRISP OS - TUI (Textual User Interface) voor cmd.exe

Deze TUI draait 100% in cmd.exe / Windows Terminal / PowerShell - geen GUI, alleen tekst.

## Features - alle 6 kern eisen

1. Chat window - centraal, scrollable
2. Think window - collapseable met T, toont hoe AI denkt
3. Chat bar - onderaan GRISP> met echte input
4. Session window/history - onderwerp + dag + tijdstip
5. Plan/Work Items - rechts, met [✓][○][ ] en High/Med/Low
6. Explorer links - met R W X permissies (R=blauw, W=groen, X=amber)

Blauw/futuristisch met Unicode box drawing ┌┐└┘─│ en ANSI kleuren #00D4FF

## Keyboard - geen muis!

- F1 Explorer, F2 Sessions, F3 Chat, F4 Plan, F5 Think toggle, F10/Q Quit
- Tab / Shift+Tab cycle panels
- Up/Down navigeren, Enter selecteren, Space markeer Plan complete
- T toggle Think, C collapse links/rechts voor maximale chat focus
- In Input panel: typen + Enter verstuurt bericht

## Compileren in Delphi 13 Florence

1. Delphi 13 Community Edition (gratis) openen
2. Nieuwe Console Application
3. Voeg alle 4 files toe aan project
4. Project Options > Set to Console
5. F9 compileren

Geen externe libs nodig - alleen Winapi.Windows voor Console API.
Werkt in cmd.exe Windows 10+ met VirtualTerminalLevel enabled (standaard in Windows 11).

Enable ANSI in cmd.exe als kleuren niet werken:
  reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f

## Bestanden

- GRISP_TUI.dpr - hoofdprogramma console
- GRISP.TUI.Data.pas - data structures R W X etc
- GRISP.TUI.Core.pas - ANSI drawing, box drawing, kleuren voor cmd.exe
- GRISP.TUI.App.pas - main TUI loop, keyboard handling, panels

## Verschil met GUI versie

GUI versie gebruikt VCL + TPanel, TTreeView etc.
Deze TUI versie gebruikt alleen Write() met ANSI escape codes en ReadConsoleInput voor keyboard - draait echt in cmd.exe zonder window.

Voor Python versie zie grisp_tui.py (werkt ook in cmd.exe met pip install windows-curses)
