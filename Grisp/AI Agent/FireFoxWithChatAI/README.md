# Firefox AI Automation

This repository provides a modified version of Firefox with a built-in AI automation service. It enables programmatic interaction with top AI chat services through a simple TCP-based Python console tool.

## Supported Sites

| Key | Site |
|-----|------|
| `gemini` | https://gemini.google.com/app |
| `grok` | https://grok.com/ |
| `chatgpt` | https://chatgpt.com/ |
| `copilot` | https://copilot.microsoft.com/ |
| `claude` | https://claude.ai/ |
| `perplexity` | https://www.perplexity.ai/ |
| `deepseek` | https://chat.deepseek.com/ |
| `inception` | https://chat.inceptionlabs.ai/ |

---

## 🚀 Setup & Installation

### 1. Clone the Firefox Source

Clone the official Firefox source repository (a sibling directory is recommended):

```bash
git clone --depth 1 https://github.com/mozilla-firefox/firefox L:\Firefox
```

### 2. Integrate AI Automation Logic

Copy the `ai_automation_logic` folder from this repository into the Firefox source tree:

```bash
mkdir L:\Firefox\browser\components\aistarter
xcopy /E /I L:\FireFoxWithChatAi\ai_automation_logic\* L:\Firefox\browser\components\aistarter\
```

### 3. Register the Component

You must register the new component in the Firefox build system.

Add the following entries to `L:\Firefox\browser\components\moz.build`:

```python
DIRS += [
    "aistarter",
]
```

And add `L:\Firefox\browser\components\aistarter\moz.build` (already included in `ai_automation_logic\moz.build`) which registers the JS actors:

```python
# browser/components/aistarter/moz.build
EXTRA_JS_MODULES.aistarter += [
    "AIAutomation.sys.mjs",
]

EXTRA_JS_MODULES.aistarter.actors += [
    "actors/AIAutomationChild.sys.mjs",
    "actors/AIAutomationParent.sys.mjs",
]
```

### 4. Build Firefox

Use the Mozilla build environment:

```bash
./mach build faster
./mach run
```

---

## ⚡ Quick Start

### AI Chat Prompting

Use the Python console to send prompts to specific AI sites:

```bash
python ai_console.py --site gemini --prompt "Hello Gemini!"
python ai_console.py --site grok --prompt "What is Rust?"
```

### Tab Management

The API allows you to manage browser tabs and re-use them for continuing chat sessions:

```bash
# List all open tabs with their indices and titles
python ai_console.py --list-tabs

# Open a new tab
python ai_console.py --open-url "https://google.com"

# Re-use an existing tab for a chat session (by index, title, or URL)
python ai_console.py --tab 0 --site gemini --prompt "Continue our chat"
python ai_console.py --tab "Gemini" --site gemini --prompt "Another message"

# Duplicate a tab
python ai_console.py --duplicate --tab 0

# Close a tab
python ai_console.py --close --tab "Google"
```

### Batch Scripts

Or use the pre-made test scripts:

```
TestGemini.bat
TestGrok.bat
TestChatGPT.bat
TestCopilot.bat
TestClaude.bat
TestDeepSeek.bat
TestInception.bat
TestPerplexity.bat
```

---

## 🏗️ Core Architecture

| Layer | File | Role |
|-------|------|------|
| **TCP Service** | `AIAutomation.sys.mjs` | Listens on port `9999`, receives JSON commands, opens tabs, polls for responses |
| **Content Actor** | `AIAutomationChild.sys.mjs` | Handles DOM injection and response scraping using site-specific CSS selectors |
| **Parent Actor** | `AIAutomationParent.sys.mjs` | Thin IPC bridge (queries resolved by the service) |

### Two-Phase Response Flow

1. **Ready-wait** — Parent polls `CheckReady` until the AI site's input box is visible
2. **Inject** — Child actor types the prompt and clicks Send, then returns immediately
3. **Response poll** — Parent re-polls `FetchResponse` on the new page (survives SPA navigation)

This design prevents the `Actor destroyed before query resolved` crash that occurs when AI sites (e.g. Gemini) navigate to a new conversation URL after submission.

---

## 🔧 Development

All automation logic lives in `ai_automation_logic/`. To apply changes:

1. Edit files in `ai_automation_logic/`
2. Copy them back to the Firefox source tree:
   ```bash
   xcopy /E /Y L:\FireFoxWithChatAi\ai_automation_logic\* L:\Firefox\browser\components\aistarter\
   ```
3. Run `./mach build faster` and restart Firefox

The `ai_automation_logic/` folder is kept in sync with `L:\Firefox\browser\components\aistarter\` after every change.
