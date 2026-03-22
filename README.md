# Nvidia AI Studio

> A native macOS AI coding assistant powered by NVIDIA NIM — with agentic file access, GitHub integration, and a glassmorphism interface built entirely in SwiftUI.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Version](https://img.shields.io/badge/version-2.0.0-green?style=flat-square)

---

## What is this?

Nvidia AI Studio is a standalone macOS app that gives you a local AI coding assistant with **real access to your filesystem**. Unlike browser-based tools, this app runs natively on your Mac — it can read your files, write code, run shell commands, commit to GitHub, and work across your entire project, all from a single interface.

It connects to the **NVIDIA NIM API**, giving you access to over 16 frontier models including DeepSeek, Kimi, Qwen, Llama, and Mistral — for free during the NVIDIA NIM preview.

---

## Screenshots

> *(Add your own screenshots here)*

---

## Features

### 🤖 Multi-Model Support
Switch between 16+ frontier models mid-conversation. Each model is labelled with its capabilities:
- 🔮 **DeepSeek V3.2** — Top reasoning, 128K context
- 🌙 **Kimi K2.5** — Fast, 256K context
- 💻 **Qwen3 Coder 480B** — Best-in-class code generation
- 👁️ **Vision models** — Attach images directly to your messages
- 🧠 **Thinking models** — Extended reasoning with configurable depth (Low / Medium / High)

### 🛠️ Agentic Skills
The AI can take real actions on your Mac through a set of built-in skills:

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

### 🔒 Full Access vs Sandboxed Mode
Control how much of your system the AI can see:
- **Full Access** — the AI can read, write, and run commands anywhere on your Mac
- **Sandboxed** — restricted to the active workspace folder you choose; all file operations outside that folder are blocked at the skill level

Switch modes live at any point in a conversation from the toolbar.

### 📁 Workspace Management
- **Open Workspace** — pick any project folder as your working context
- Sessions are grouped by project in the sidebar
- Rename project folders directly from the sidebar (right-click)
- New threads automatically inherit the active workspace path

### 🐙 GitHub Integration
Connect your GitHub account with a Personal Access Token:
1. Click **Settings → GitHub**
2. Click **Open GitHub → New Token** (opens the page with scopes pre-filled)
3. Paste the token and click **Connect**

Once connected:
- **Clone Repository** — browse all your repos and clone with one click, authenticated via HTTPS
- **Commit & Push** — see changed files, write a commit message, and push — no Terminal needed
- Token is stored securely in the macOS Keychain

### 🎨 Glassmorphism UI
- Translucent window with adjustable transparency and frosted glass effect
- Dark / Light / System theme
- Smooth animations throughout
- Sidebar with collapsible project folders and thread search

---

## Requirements

- macOS 14.0 (Sonoma) or later
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
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+

---

## Getting Your NVIDIA NIM API Key

1. Go to [build.nvidia.com](https://build.nvidia.com)
2. Create a free account
3. Navigate to your profile → **API Keys**
4. Generate a key — it starts with `nvapi-`
5. Paste it in **Settings → API Keys** inside the app

The free tier includes generous usage limits across all available models.

---

## GitHub Integration Setup

To enable the GitHub OAuth Browser flow (optional, for users who prefer not to use a PAT):

1. Register a free OAuth App at [github.com/settings/applications/new](https://github.com/settings/applications/new)
2. Set the Homepage URL to your repo
3. Enable **Device Flow**
4. Copy the **Client ID** and replace `deviceFlowClientID` in `Services/GitHubService.swift`

For most users, the **Personal Access Token** method in Settings → GitHub is simpler and works out of the box.

---

## Project Structure

```
NvidiaAIStudio/
├── App/
│   ├── NvidiaAIStudioApp.swift    # Entry point, window config
│   └── AppState.swift             # Global observable state
├── Models/
│   ├── AIModel.swift              # Model definitions + defaults
│   ├── Message.swift              # Chat message + tool call types
│   └── Session.swift              # Conversation session
├── Services/
│   ├── NVIDIAAPIService.swift     # Streaming API client (OpenAI-compatible)
│   ├── ModelFetcher.swift         # Live model list from NVIDIA NIM
│   └── GitHubService.swift        # OAuth + REST + clone/push
├── Skills/
│   ├── Skill.swift                # Protocol + SkillRegistry + sandbox enforcement
│   ├── FileSkills.swift           # read_file, write_file, list_directory, search, run_command
│   ├── GitSkill.swift             # git operations
│   ├── SSHSkill.swift             # ssh_command
│   └── ImageGenerationSkill.swift # NVIDIA image generation
├── ViewModels/
│   └── ChatViewModel.swift        # Agentic loop, streaming, tool execution
└── Views/
    ├── ContentView.swift           # Main 3-column layout
    ├── Chat/                       # ChatView, InputAreaView, MessageBubbleView
    ├── Sidebar/                    # SidebarView with project folders
    ├── Settings/                   # All settings tabs including GitHub
    ├── GitPanelView.swift          # Commit & Push panel
    └── CloneRepoView.swift         # Repository browser + clone
```

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Send message | `Enter` |
| New line in message | `Shift + Enter` |
| Commit & Push (in Git panel) | `Cmd + Enter` |
| Toggle sidebar | Toolbar button |
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

Built with [NVIDIA NIM](https://build.nvidia.com) — access to world-class AI models through a single OpenAI-compatible API.
