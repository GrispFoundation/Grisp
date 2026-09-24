# GRISP OS - Delphi 13 Florence - v0.02 GUI Improved

Same filenames, new subfolder v0.02 (from v0.01 -> v0.02)

## Wat is nieuw t.o.v. screenshot v0.01

### Fixes uit screenshot
- FIX: `port UNICO` afgekapt -> nu `Export UNICODE` / `ASCII` / `ANSI` met AutoSize=False en juiste Width
- FIX: `Analyze architect...` afgekapt -> kolommen breder + Hint met volledige tekst + OwnerDraw met badge
- FIX: `Me...` bij Prio -> nu `[High]` rood, `[Med]` amber, `[Low]` blauw badge, niet afgekapt
- FIX: `+ New Session` te breed -> nu anchored en juiste Height
- FIX: Explorer R W X zwart/wit -> nu gekleurd: R=blauw #4F7CFF, W=groen #00FF88, X=amber #FFAA00, Trust % in cyan

### Nieuw in v0.02
- TSplitter tussen Left/Center/Right voor resizable panels (zoals VS Code)
- Chat bubbles: User rechts blauw #1A3A6B, Assistant links #0E1B33 met avatar, Think collapsible met 3 steps + checks
- Header: Agent dot pulse groen #00FF88 + Ready + tijd 08:13 live update met TTimer
- Explorer: OwnerDraw met indent + expand/collapse glyphs, R W X kleuren, Trust:85 in cyan
- Plan / Work Items: OwnerDraw ListView met [v] [o] [ ] icons + Status kleuren Completed=groen, In progress=amber, Pending=grijs
- Footer: ACTIVE: GRISP://Workspace | Delphi 13 Florence | Skia 7.3 optional | SEC check
- Skia optional: define USE_SKIA voor TSkPanel glow #00D4FF 12px radius, zonder define pure VCL (compileert altijd)
- Search in Explorer: edtSearch met live filter
- Geen flicker: DoubleBuffered + BeginUpdate/EndUpdate

## Bestanden (zelfde namen als v0.01)

- GRISP_OS_D13.dpr
- MainForm.pas (v0.02 improved)
- MainForm.dfm
- GRISP.Data.pas
- GRISP.Terminal.pas

## Compileren Delphi 13 Florence

1. Maak nieuwe folder `GRISP_v0.02`
2. Unzip hierin
3. Open GRISP_OS_D13.dpr in Delphi 13
4. (Optioneel) Project Options > Conditional defines > USE_SKIA voor glow
5. F9 - compileert pure VCL zonder externe libs

Alle 6 kern eisen zitten erin:
1. Chat window (bubbles)
2. Think window (collapsable 3 steps)
3. Chat bar (met Attach @ + Send >)
4. Session window/history (Subject + Day + Time)
5. Plan/Work Items (met Prio badges)
6. Explorer met R W X Trust
