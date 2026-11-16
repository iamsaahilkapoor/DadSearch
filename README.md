# 🔍 DadSearch

<p align="center">
  <img src="Resources/AppIcon.png" width="160" height="160" alt="DadSearch Icon" style="border-radius: 36px; box-shadow: 0 10px 30px rgba(0,0,0,0.25);" />
  <br>
  <strong>A lightweight, elegant, native macOS universal search app.</strong>
  <br>
  <em>Purpose-built for finding downloaded documents, Outlook emails, screenshots, and chat attachments without Finder confusion.</em>
</p>

<p align="center">
  <a href="https://github.com/saahilironbond/DadSearch/releases/latest"><img src="https://img.shields.io/badge/Download-macOS%20DMG-blue?style=for-the-badge&logo=apple" alt="Download macOS DMG"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=for-the-badge&logo=swift" alt="Swift 6.0">
</p>

---

## 💡 Why DadSearch?

Finder is powerful, but for many older users (including dads who otherwise love their Macs), searching for a file is frustrating:
- Downloaded PDF statements or bills disappear into a giant `~/Downloads` folder.
- Work and personal emails get buried inside Outlook caches.
- Important confirmation screenshots sit on the Desktop named `Screenshot 2026-11-16 at 8.45.12 PM.png`.
- Documents sent over WhatsApp Desktop, Telegram, or Messages are hidden inside deep `~/Library/Containers/` directories.

**DadSearch** brings all of these into one forgiving, fast, and beautiful interface with 0ms launch time.

---

## ✨ Features

- **🚀 3-in-1 Interaction Modes:**
  - **Floating Launcher:** Summon instantly with `⌥ + Space` (Option + Space) or `⌥ + F`.
  - **Menu Bar Utility:** Lives in the top menu bar for quick searches without switching applications.
  - **Standalone Window:** Clean 3-pane split view with high-contrast labels and a dedicated Quick Look & metadata panel.
- **🧠 Forgiving Natural Language & Query Parsing:**
  - Understands dates: *"today"*, *"yesterday"*, *"this week"*, *"last month"*.
  - Understands file types: *"pdf"*, *"word"*, *"excel"*, *"screenshot"*, *"whatsapp"*.
  - Uses relative dates (*"Today at 10:15 AM"*, *"Yesterday"*) instead of confusing ISO timestamps.
- **⚡ Hybrid Fast Search:**
  - Native macOS Spotlight metadata (`NSMetadataQuery`) for instant zero-battery search.
  - Dedicated `~/Downloads` real-time watcher.
  - Deep Outlook identity cache & message parser (`.eml`, `.olk15Message`).
  - Dedicated Screenshots & Screen Recordings indexer (`~/Desktop`, `~/Pictures`).
  - Chat Attachments indexer (WhatsApp Desktop, Telegram, Apple Messages, Mail downloads).
- **⚡ 1-Click Quick Actions:**
  - Press `Space` for macOS Quick Look preview.
  - Press `Return` to open in default app.
  - Press `⌘ + Return` or click to reveal directly in Finder.
  - Quick action buttons on every result row.

---

## 📥 Installation

1. Go to the [**Releases**](https://github.com/saahilironbond/DadSearch/releases) page and download `DadSearch.dmg`.
2. Open the `.dmg` file and drag **DadSearch** into your **Applications** folder.
3. **First launch note:** Because this app is independently distributed outside the Mac App Store, right-click `DadSearch` in Applications and choose **Open**, then click **Open** on the prompt.

---

## 🛠️ Building from Source

### Requirements
- macOS 14.0 or newer
- Xcode 15+ or Swift 6.0 toolchain

### Build & Run
```bash
# Clone the repository
git clone https://github.com/saahilironbond/DadSearch.git
cd DadSearch

# Run unit tests
swift test

# Build and run the app
swift run
```

### Packaging into a .DMG
To create the standalone `.app` bundle and installer `.dmg`:
```bash
./scripts/build-app.sh
```
The output will be created inside `./build/DadSearch.dmg`.

---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
