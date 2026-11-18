# 🔍 DadSearch

<p align="center">
  <img src="Resources/AppIcon.png" width="160" height="160" alt="DadSearch Icon" style="border-radius: 36px; box-shadow: 0 10px 30px rgba(0,0,0,0.25);" />
  <br>
  <strong>A lightweight, elegant, native macOS universal search app.</strong>
  <br>
  <em>Purpose-built for finding downloaded documents, emails, apps, screenshots, and chat attachments without Finder confusion.</em>
</p>

<p align="center">
  <a href="https://github.com/iamsaahilkapoor/DadSearch/releases/latest"><img src="https://img.shields.io/badge/Download-macOS%20DMG-blue?style=for-the-badge&logo=apple" alt="Download macOS DMG"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=for-the-badge&logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-lightgrey?style=for-the-badge&logo=apple" alt="macOS 14.0+">
</p>

---

## 💡 Why DadSearch?

Finder and Spotlight are powerful, but for many non-tech or older users (including parents who love their Macs), searching for a file is frustrating:
- Downloaded PDF statements, invoices, or medical bills disappear into a giant `~/Downloads` folder.
- Work and personal emails get buried inside Outlook caches or Apple Mail.
- Important confirmation screenshots sit on the Desktop named `Screenshot 2026-11-16 at 8.45.12 PM.png`.
- Documents sent over WhatsApp Desktop, Telegram, or Messages are hidden inside deep `~/Library/Containers/` directories.
- Typos like `"recipt"` or `"invoce"` yield zero results in traditional search tools.

**DadSearch** brings all of these into one forgiving, fast, and beautiful interface with instant zero-battery launch time.

---

## ✨ Features

- **🚀 3-in-1 Interaction Modes:**
  - **Global Floating Launcher:** Summon instantly from anywhere in macOS with **`⌥ + Space`** (Option + Space). Zero system permissions required.
  - **Menu Bar Utility:** Lives in the top menu bar for quick searches without switching applications.
  - **Standalone Window:** Clean split view with high-contrast labels and a dedicated Quick Look & metadata panel.
- **🧠 Forgiving Natural Language & Typo-Tolerance:**
  - Automatically corrects common typos: *"recipt"* $\rightarrow$ *receipt*, *"invoce"* $\rightarrow$ *invoice*, *"statment"* $\rightarrow$ *statement*, *"perscription"* $\rightarrow$ *prescription*.
  - Understands dates: *"today"*, *"yesterday"*, *"this week"*, *"last month"*.
  - Understands file types: *"pdf"*, *"word"*, *"excel"*, *"screenshot"*, *"whatsapp"*.
  - Relative dates (*"Today at 10:15 AM"*, *"Yesterday"*) instead of confusing ISO timestamps.
- **🌐 Universal Search Providers:**
  - **Applications:** Search and launch installed apps (`/Applications`, `/System/Applications`, `~/Applications`).
  - **Emails:** Native indexing for both **Apple Mail** (`.emlx`) and **Microsoft Outlook** caches.
  - **Contacts & Calendar:** Instant lookup of phone numbers, emails, and upcoming appointments via Apple's native frameworks.
  - **Screenshots & Recordings:** Real-time crawler for Desktop and Pictures screen captures.
  - **Chat Attachments:** Discovers files received on WhatsApp Desktop, Telegram, Apple Messages, and Mail Downloads.
- **⚡ 1-Click Quick Actions & Previews:**
  - **Live File Thumbnails:** Generated asynchronously via QuickLook.
  - **Full Preview:** Tap `Space` for macOS Quick Look preview.
  - **Instant Open:** Tap `Return` to open or launch.
  - **Finder Reveal:** Tap `⌘ + Return` or click to reveal directly in Finder.
- **♿ Senior-Friendly & Accessible:**
  - Designed according to Apple Human Interface Guidelines.
  - Full VoiceOver labels and hints.
  - High-contrast text exceeding WCAG AA 4.5:1 ratio.
  - Interactive First-Run welcome sheet.

---

## 📥 Installation

1. Go to the [**Releases**](https://github.com/iamsaahilkapoor/DadSearch/releases) page and download `DadSearch.dmg`.
2. Open the `.dmg` file and drag **DadSearch** into your **Applications** folder.
3. **First launch note (macOS Gatekeeper):** Because DadSearch is open-source and distributed outside the Mac App Store:
   - **Method A:** Right-click `DadSearch.app` in your Applications folder, choose **Open**, and click **Open** on the confirmation prompt.
   - **Method B (Terminal):** Run `xattr -cr /Applications/DadSearch.app` to clear the quarantine flag.

---

## 🛠️ Building from Source

### Requirements
- macOS 14.0 or newer
- Xcode 15+ or Swift 6.0 toolchain

### Build & Run
```bash
# Clone the repository
git clone https://github.com/iamsaahilkapoor/DadSearch.git
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

## 🔒 Privacy & Security

- **100% On-Device:** DadSearch does not send any search queries, file metadata, or personal data to external servers or cloud services.
- **Zero Telemetry:** No tracking, no analytics, no third-party SDKs.
- **Zero Battery Overhead:** Piggybacks on macOS Spotlight's local index via `NSMetadataQuery` rather than running a constant background indexing daemon.

---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
