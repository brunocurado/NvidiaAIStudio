# Nvidia AI Studio

> A native macOS AI coding assistant powered by NVIDIA NIM — with agentic file access, GitHub integration, and Apple's Liquid Glass interface built entirely in Swift.

![macOS](https://img.shields.io/badge/macOS-26.0+(Tahoe)-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.2-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Version](https://img.shields.io/badge/version-2.0.0-green?style=flat-square)

---

## What is this?

Nvidia AI Studio is a standalone macOS app that gives you a local AI coding assistant with **real access to your filesystem**. Unlike browser-based tools, this app runs natively on your Mac — it can read your files, write code, run shell commands, commit to GitHub, and work across your entire project, all from a single interface.

It connects to the **NVIDIA NIM API**, giving you access to over 16 frontier models including DeepSeek, Kimi, Qwen, Llama, and Mistral — for free during the NVIDIA NIM preview.

---

## Screenshots

 ### SPLASH SCREEN ###
 <img width="1800" height="1130" alt="Captura de ecrã 2026-03-23, às 10 23 56" src="https://github.com/user-attachments/assets/3f2b68fd-7d08-49ed-a254-d050146434de" />
 ### MAIN INTERFACE ###
 <img width="1800" height="1130" alt="Captura de ecrã 2026-03-23, às 10 24 08" src="https://github.com/user-attachments/assets/a5d44572-3ac2-4f5c-9078-c10713355a29" />
 ### THEME SELECTOR AND BACKGROUND TINT ###
 <img width="611" height="650" alt="Captura de ecrã 2026-03-23, às 10 27 09" src="https://github.com/user-attachments/assets/4ebd49cf-01c7-4cb0-b4b9-eae7fe773c2b" />
 ### SKILLS SELECTOR ###
 <img width="409" height="529" alt="Captura de ecrã 2026-03-23, às 10 25 09" src="https://github.com/user-attachments/assets/0b16638f-384b-4a4c-9bf8-f0a8c28288d3" />
 ### AVAILABLE MODELS >>> OVER 100 MODELS AVAILABLE THROUGH NVIDIA NIM ###
 <img width="611" height="641" alt="Captura de ecrã 2026-03-23, às 10 27 02" src="https://github.com/user-attachments/assets/7ada1729-29c7-4970-ab89-bb185872a24a" />
 ### YOU CAN ALSO CHOOSE FROM ANTHROPIC OPEN AI OR BYOK ###
 <img width="615" height="641" alt="Captura de ecrã 2026-03-23, às 10 51 30" src="https://github.com/user-attachments/assets/34f03f3f-a9ef-440f-9d40-d389fd72acfb" />
 ### SSH CONNECTION ###
 <img width="620" height="644" alt="Captura de ecrã 2026-03-23, às 10 28 57" src="https://github.com/user-attachments/assets/aa6301f0-1f50-48f4-aac0-a43c39aa9a6c" />
 ### BACKGROUND AGENTS ###
 <img width="512" height="467" alt="Captura de ecrã 2026-03-23, às 10 26 27" src="https://github.com/user-attachments/assets/bcfc2998-30f0-4d62-958f-70537937373b" />
 ### MCP SERVERS AND CONNECTORS ###
 <img width="616" height="553" alt="Captura de ecrã 2026-03-23, às 10 27 28" src="https://github.com/user-attachments/assets/a389f71e-fd78-44f9-a1a8-fb960f1e5f74" />
 ### AND GITHUB INTEGRATION ### 
 <img width="641" height="654" alt="Captura de ecrã 2026-03-23, às 10 27 15" src="https://github.com/user-attachments/assets/f810b171-3881-41ee-8cbd-69e94a05765a" />


---

## Features

### 🤖 Multi-Model & Multi-Provider Support
Switch between 16+ frontier models mid-conversation. Supports multiple AI providers:

| Provider | Models | Highlights |
|----------|--------|------------|
| **NVIDIA NIM** | DeepSeek V3.2, Kimi K2.5, Qwen3 Coder 480B, Llama 3.3, Mistral, etc. | Free preview, 128K–256K context |
| **Anthropic** | Claude 4 Sonnet, Claude 4 Opus | Best reasoning |
| **OpenAI** | GPT-4o, GPT-4o-mini | Vision + function calling |
| **Custom** | Any OpenAI-compatible endpoint | Self-hosted models |

Each model is labelled with its capabilities:
- 👁️ **Vision models** — Attach images directly to your messages
- 🧠 **Thinking models** — Extended reasoning with configurable depth (Low / Medium / High / Off)

### 🛠️ Agentic Skills (Tool Calling)
The AI can take real actions on your Mac through a set of built-in skills with an **autonomous agent loop** (up to 10 iterations):

| Skill | What it does |
|---|---|
| `read_file` | Read any file on your system |
| `write_file` | Create or overwrite files |
| `list_directory` | Browse directory contents |
| `search_files` | Grep across your codebase |
| `run_command` | Execute shell commands |
| `git` | Run any git operation |
| `ssh_command` | Execute commands on a remote VPS |
| `image_generation` | Generate images via NVIDIA NIM |
| `fetch_images` | Fetch and inject images for vision-capable models |
| `web_search` / `web_fetch` | Search the web and fetch page content |

Tool calls are displayed as **GlassCode-style inline pills** showing the tool name, edited filename, `+additions` / `-deletions` diff stats, and expandable results.

### 🔒 Full Access vs Sandboxed Mode
Control how much of your system the AI can see:
- **Full Access** — the AI can read, write, and run commands anywhere on your Mac
- **Sandboxed** — restricted to the active workspace folder; all file operations outside that folder are blocked at the skill level

Switch modes live at any point in a conversation from the bottom toolbar.

### 📁 Workspace Management
- **Open Workspace** — pick any project folder as your working context
- Sessions are grouped by project in the sidebar
- **Right-click context menu** on folders: New Thread, Rename, Remove Workspace
- **Show less / Show more** to collapse folder listings
- New threads automatically inherit the active workspace path
- **Export threads** as `.txt` via the share button

### 🐙 GitHub Integration
Connect your GitHub account via OAuth Device Flow or Personal Access Token:

**Setup:**
1. Click **Settings → GitHub**
2. Click **Connect with GitHub** (opens Device Flow) or paste a Personal Access Token
3. Authorize the app on github.com

**Once connected:**
- **Clone Repository** — browse all your repos and clone with one click
- **Commit & Push** — see changed files with diff stats, write a commit message, and push — no Terminal needed
- Token is stored securely in the **macOS Keychain**

### 🪟 Apple Liquid Glass UI
Built natively with macOS 26 Tahoe's **Liquid Glass** design language:
- `.glassEffect()` used throughout — sidebar, message bubbles, input area, toolbar, tool call pills, toasts
- `.buttonStyle(.glass)` for all toolbar buttons
- Translucent window with adjustable **opacity** and **blur** sliders in Settings
- **7 built-in color themes**: Dark, Midnight, Ocean, Forest, Sunset, Nord, Light
- Smooth spring animations on panels, messages, and state transitions

### 💬 Premium Chat Experience
- **Markdown rendering** — full GFM with syntax-highlighted code blocks, headings, lists, blockquotes
- **"Worked for Xm Ys"** timing badge after each assistant response
- **Inline diff pills** — "Edited `filename.swift` +14 -5 >" for file edit tool calls
- **Streaming dots** animation while the model is generating
- **Collapsible reasoning** — see the model's chain-of-thought with character count
- **User & assistant avatars** with subtle glow circles
- **Context compression** — auto-summarizes older messages when context usage exceeds 80%
- **Context usage indicator** — circular ring showing how much of the model's context window is used

### 📊 Usage Tracking
- Track token usage per model, session, and provider
- View total prompt/completion tokens over time
- Available from the sidebar **Usage** panel or the **Tokens** toolbar button

### ⚡ Background Agents
- Multiple agents can work in the background
- Live badge counter on the **Agents** toolbar button
- Floating panel in the chat view shows running agents

### 🔔 Native Notifications
- Desktop notification when a response completes (with model name)
- Permission requested on first launch

### 🔌 MCP (Model Context Protocol) Support
- Configure external MCP servers in **Settings → MCP**
- Auto-connect on app launch
- Extend the app's capabilities with custom tool servers

---

## Requirements

- **macOS 26.0 (Tahoe)** or later — required for Liquid Glass APIs
- Apple Silicon or Intel Mac
- A free [NVIDIA NIM API key](https://build.nvidia.com)

---

## Installation

### Option 1 — Download DMG (easiest)
1. Download `Nvidia-AI-Studio.dmg` from the [Releases](../../releases) page
2. Open the DMG and drag the app to your Applications folder
3. Launch the app, go to **Settings → API Keys**, and add your NVIDIA NIM key

### Option 2 — Build from source
```bash
# Clone the repo
git clone https://github.com/brunocurado/NvidiaAIStudio.git
cd NvidiaAIStudio

# Add your API key to a .env file
echo "NVIDIA_NIM_API_KEY=nvapi-your-key-here" > .env

# Build and package
bash build_app.sh release

# The app will be at:
# NvidiaAIStudio/build/Nvidia AI Studio.app
```

**Requirements for building:**
- Xcode 26+ with Swift 6.2
- macOS 26.0 (Tahoe)

---

## Getting Your NVIDIA NIM API Key

1. Go to [build.nvidia.com](https://build.nvidia.com)
2. Create a free account
3. Navigate to your profile → **API Keys**
4. Generate a key — it starts with `nvapi-`
5. Paste it in **Settings → API Keys** inside the app

The free tier includes generous usage limits across all available models.

---

## Project Structure

```
NvidiaAIStudio/
├── App/
│   ├── NvidiaAIStudioApp.swift    # Entry point, window config, Liquid Glass
│   └── AppState.swift             # Global observable state
├── Models/
│   ├── AIModel.swift              # Model definitions + multi-provider defaults
│   ├── AppTheme.swift             # 7 color themes + glass effect config
│   ├── Message.swift              # Chat message + tool call types
│   ├── Session.swift              # Conversation session with project grouping
│   └── SystemPrompt.swift         # Dynamic system prompt with workspace context
├── Services/
│   ├── NVIDIAAPIService.swift     # Streaming API client (OpenAI-compatible)
│   ├── OpenAIAPIService.swift     # OpenAI/Anthropic provider
│   ├── ModelFetcher.swift         # Live model list from NVIDIA NIM
│   ├── GitHubService.swift        # OAuth Device Flow + REST API
│   └── MCPManager.swift           # Model Context Protocol server manager
├── Skills/
│   ├── Skill.swift                # Protocol + SkillRegistry + sandbox enforcement
│   ├── FileSkills.swift           # File operations + shell commands
│   ├── GitSkill.swift             # Git operations
│   ├── SSHSkill.swift             # Remote SSH execution
│   ├── WebSkills.swift            # Web search + fetch
│   └── ImageGenerationSkill.swift # NVIDIA image generation
├── ViewModels/
│   └── ChatViewModel.swift        # Agent loop, streaming, tool execution, context compression
├── Utilities/
│   └── KeychainHelper.swift       # Secure storage for API keys + GitHub tokens
└── Views/
    ├── ContentView.swift           # Main 3-column layout + toolbar
    ├── OnboardingView.swift        # First-launch setup
    ├── Chat/
    │   ├── ChatView.swift          # Message list + background agents panel
    │   ├── InputAreaView.swift     # Rich input with attachments + model picker
    │   └── MessageBubbleView.swift # Markdown bubbles, tool pills, timing badges
    ├── Sidebar/
    │   └── SidebarView.swift       # Threads, workspaces, skills, usage, settings
    ├── Settings/
    │   └── SettingsView.swift      # API Keys, GitHub, Theme, Models, MCP tabs
    ├── RightPanel/
    │   └── RightPanelView.swift    # Git diff viewer + terminal
    ├── Components/
    │   └── ToastView.swift         # Notification toasts
    ├── GitPanelView.swift          # Commit & Push panel
    ├── CloneRepoView.swift         # Repository browser + clone
    └── SkillsPanelView.swift       # Skills toggle panel
```

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Send message | `Enter` |
| New line in message | `Shift + Enter` |
| Commit & Push (in Git panel) | `Cmd + Enter` |
| Open settings | `Cmd + ,` |

---

## Configuration via .env

You can pre-configure the app by placing a `.env` file in the same directory as the app binary:

```env
NVIDIA_NIM_API_KEY=nvapi-your-key-here
```

The app auto-loads this key on first launch if no key is configured in Settings.

---

## Dependencies

- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — Markdown rendering in chat messages

All other functionality is built on native Apple frameworks: SwiftUI, AppKit, Foundation, Security.

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgements

- Built with [NVIDIA NIM](https://build.nvidia.com) — access to world-class AI models through a single OpenAI-compatible API.
- Designed with Apple's **Liquid Glass** design language on macOS 26 Tahoe.
