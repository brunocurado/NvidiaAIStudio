# Master Implementation Plan: Nvidia AI Studio v3.0
*The autonomous multi-agent operating system exclusively for macOS.*

This document outlines the architectural changes required to transition Nvidia AI Studio to version 3.0, incorporating a 24/7 God-Mode Dashboard alongside the 5 visionary pillars of productivity.

**Core Decision Logged:** The classic `ChatView` (1-on-1 interaction) will **co-exist** with the new `SwarmDashboardView`. The UI will introduce side-navigation to switch between "Studio Chat" and "Agent Operations (War Room)".

---

## Pillar 1: 🧠 Swarm Mode & The "God-Mode" Dashboard
Currently, background agents (`AgentTask`) run transiently in memory. We need a persistent queue system where agents communicate with each other.

### Architecture Changes
- **Database Layer**: Implement SwiftData or SQLite to persist `SwarmTask`, `AgentPersona`, and `AgentState` so agents run 24/7 even if the UI refreshes.
- **Swarm Orchestrator (`ViewModels/SwarmOrchestrator.swift`)**: A new singleton service that checks the queue, dispatches tasks to agents, and handles agent-to-agent message passing (e.g., *Architect* generates a spec -> *Developer* reads it).
- **Dashboard UI (`Views/Dashboard/SwarmDashboardView.swift`)**: A grid representation replacing the center console when navigating to the "War Room". Shows live tiles for each agent, highlighting current status, waiting states, and token usage.

---

## Pillar 2: 🤖 "Auto-Pilot" Terminal (Agent-in-the-Loop)
We built the `PTYProcess` (Feature 2 of v2.0.49). Now we connect the agent's brain to it.

### Architecture Changes
- **PTY Binding**: When `SwarmOrchestrator` spins up a "Developer" agent, it creates a dedicated `PTYProcess` for that agent.
- **Raw Input (Tab Completion & History)**: Replace the standard SwiftUI `TextField` with a custom invisible `NSView` key-event responder. Raw bytes (like `\t` for Tab, `\u{1B}[A` for Up Arrow) are sent immediately to `pty.write()`. This allows `zsh` to handle auto-completion and history navigating natively, echoing the result back to our display.
- **XTerm ANSI Parsing**: Update the `ANSIParser` Regex to correctly strip XTerm mode-setting escape sequences (like `[?2004h` / `[?2004l` used by `zsh` for bracketed paste) so they don't echo as raw text.
- **Skill Evolution (`Skills/BashSkill.swift`)**: Instead of running a hidden, blocking `Process()` command, the agent's bash skill executes `pty.write(command)`. 
- **Telemetry UI (`Views/RightPanel/TerminalContent.swift`)**: When you click an agent's tile in the Dashboard, the Right Panel instantly updates to stream that specific agent's live PTY output. You see exactly what they see (compiler errors, `npm start`, etc.). You can intervene via the `⌃C` button.

---

## Pillar 3: 🌍 Live Canvas (App Previewer)
When agents build React/Vite web apps, you should see them function instantly within the app.

### Architecture Changes
- **WebView Integration (`Views/RightPanel/LiveCanvasView.swift`)**: Create a new tab in the Right Panel using Apple's `WKWebView`. 
- **Auto-Host Resolution**: If the agent's PTY detects a server starting (e.g., regex match on `http://localhost:5173`), it automatically triggers the `WKWebView` to load that URL.
- **Vision Loop**: If the WebView throws a JS error or fails to render, we capture a snapshot of the `WKWebView`, pass it back to the agent using the existing `NVIDIAAPIService` multi-modal vision capabilities, and the agent auto-corrects the CSS/JS.

---

## Pillar 4: ⚡ Global Spotlight (macOS Integration)
A floating prompt accessible from anywhere on the Mac, feeding tasks directly into the Swarm without opening the main window.

### Architecture Changes
- **Global Hotkey Registration**: Use macOS native `NSEvent.addGlobalMonitorForEvents` or a framework like `HotKey` in `NvidiaAIStudioApp.swift` to bind `Cmd + Space` (or similar).
- **Floating Panel (`Views/Floating/SpotlightPanel.swift`)**: Create an `NSPanel` (instead of `NSWindow`) that behaves like Raycast (level = floating, standard transparent glass effect).
- **Context Injection API**: When the shortcut is pressed, use macOS Accessibility APIs (`AXUIElement`) or AppleScript hooks to grab the currently active application's window title or selected text, injecting it immediately into the agent's specific context.

---

## Pillar 5: 🔌 MCP (Model Context Protocol) 
*Note: The core MCP Client and UI are ALREADY built and functional in Nvidia AI Studio.*

The goal for v3.0 is connecting the newly built Swarm to the existing MCP architecture.

### Architecture Changes
- **Swarm Tool Inheritance (`ViewModels/AgentCoordinator.swift`)**: Currently, MCP tools are injected into the 1-on-1 Chat view. We will update the background `AgentRunner` to dynamically fetch the available tools from the existing `SkillRegistry` (which is populated by your active MCP servers like Puppeteer, Memory, etc.).
- **Headless MCP Execution**: Ensuring that when a background agent triggers an MCP tool (e.g., using Puppeteer to scrape a site while the app is minimized), the stdio streams handle the payload correctly without requiring UI thread interaction.

---

## Pillar 6: 🎨 UI Consistency & New Themes
Ensuring the app feels cohesive across every window, including preferences.

### Architecture Changes
- **Settings View Theming (`Views/Settings/SettingsView.swift`)**: The Settings window currently defaults to the system appearance rather than respecting the custom `AppTheme` selected in the app. We will inject the `@Environment(AppState.self)` into the Settings hierarchy so the background and accent colors match the rest of the studio (or force it via `preferredColorScheme`).
- **New App Themes (`Models/AppTheme.swift`)**: Add new curated themes to the roster:
  - **Lights Out (OLED Dark)**: True `#000000` backgrounds for maximum contrast on modern Mac displays.
  - **Nord / Arctic (Light)**: A clean, high-end light theme (since we currently lean heavily towards dark variants) for users who prefer bright workspaces during the day.

---

## Action Plan Outline (No codebase modifications)

When development for v3.0 begins, execution will follow these distinct phases to ensure stability:

1. **Phase 1: Foundation & Persistence** (SwiftData + SwarmOrchestrator). The invisible layer that makes 24/7 autonomy possible.
2. **Phase 2: The Command Center UI** (SwarmDashboard + Top-level Navigation). Keeping classic chat alive while introducing the agent tiles.
3. **Phase 3: Agent Senses** (PTY Auto-Pilot Binding + Live Canvas). Giving the agents hands (terminals) and eyes (webview screenshots).
4. **Phase 4: macOS Deep Integration** (Global Spotlight + MCP hooks). Making the app an OS-level companion rather than just an isolated application.
5. **Phase 5: UI Polish & Theming** (Settings consistency + New Themes like *Lights Out*). Making sure every corner of the app feels premium.
