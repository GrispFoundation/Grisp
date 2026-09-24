# GRISP OS - Delphi 13 Florence Prototype (V5 + Terminal)

Dit is het prototype dat ALLES kan wat je vroeg:

1. Chat window - gemaximaliseerd
2. Think window - collapseable
3. Chat bar
4. Session window/history - onderwerp + dag + tijdstip
5. Side panels voor Plan/Work Items - embedded EN rechts, collapseable
6. Windows Explorer links - collapseable, met R W X permissies
7. ASCII / ANSI / UNICODE ontwerp voor cmd.exe - ingebouwd!
8. Blauw/futuristisch - Skia 7.3

## Delphi 13 Florence vereisten

- Delphi 13 Community Edition (gratis) - https://blogs.embarcadero.com/delphi-13-community-edition-is-now-available/
- Skia4Delphi 7.3 is INGEBOUWD in Delphi 13: "Since Delphi 12.1, it has gained a broad set of enhancements, including: Updated Skia4Delphi integration" en "Skia4Delphi moves to version 7.3"
- Optioneel: VirtualTreeView via GetIt (MIT) voor betere Explorer performance

## Features

- VCL + Skia: TSkPanel en TSkLabel voor glow effects en rounded corners
- Collapsible panels: Links Explorer+Sessions (300px -> 0), Rechts Plan (340px -> 0), Think (110px -> 32px)
- Chat met embedded plan kaarten + think window
- Terminal Mode: knop [⌘ Terminal] schakelt naar ASCII/UNICODE view binnen de app
- Export knoppen: Exporteer direct naar grisp_unicode.txt, grisp_ascii.txt, grisp_ansi.bat die in cmd.exe draaien
- RWX permissies: zichtbaar als R W X met kleuren (groen=ja, grijs=nee)
- Delphi 13 HighDPI Per-Monitor v2 support

## Installatie

1. Nieuwe VCL Application in Delphi 13
2. Kopieer alle .pas files naar project folder
3. Voeg toe aan .dpr: MainForm, GRISP.Data, GRISP.Terminal
4. Compileer - werkt zonder extra libs
5. Optioneel: Installeer VirtualTreeView via GetIt voor 100x betere tree performance

## Gebruik

- E / knop linksboven: Explorer toggle -> maximaliseert chat
- Rechts knop: Plan toggle
- Think header ▼/▲: Think collapse
- Chat tab vs Terminal tab: wissel tussen GUI en ASCII view
- Export knoppen rechts onder: maak cmd.exe files

## Bestanden

- GRISP_OS_D13.dpr - hoofdprogramma
- MainForm.pas/.dfm - hoofd GUI met alle panels
- GRISP.Data.pas - kleuren, types, permissies
- GRISP.Terminal.pas - ASCII/ANSI/UNICODE generator voor cmd.exe

Dit prototype benadert zowel je ChatGPT minimal design als mijn V4 Core, maar dan native in Delphi 13 met Skia 7.3.
