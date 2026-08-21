# PhraseKey

**Your phrases, everywhere. Open IME that puts your data first.**

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

PhraseKey is an open-source, cross-platform input method engine (IME).  
It frees your phrases, dictionaries, and typing habits from proprietary lock-in — so they follow you across devices, not companies.

<img src="BrandAssets/PhraseKey.svg" width="80" alt="PhraseKey logo">

## The Problem

| Pain | Business IMEs | PhraseKey |
|------|---------------|-----------|
| **Phrases locked in** | Proprietary format, export requires reverse engineering | Open JSON, **compatible with common hotword export formats** |
| **No cross-device sync** | Rebuild phrase memory on every new device | Data directory can point to **iCloud Drive / cloud drive / git** |
| **Privacy vs convenience** | Cloud sync uploads; local doesn't sync | **Self-hosted**: data stays on your devices and your cloud, formats are fully open |

## Features

| Capability | Description |
|---|---|
| **Input schemes** | Pinyin / **Xiaohe Shuangpin** / **Xiaohe Xingma** (switchable from menu) |
| **Phrases first** | Key matches (your shortcut → long text) always top the candidate list |
| **Import phrases** | Import from other IMEs' CSV/JSON exports (format compatible) |
| **Cross-platform data** | Open formats → same data on macOS, iOS, Windows, Linux |
| **Privacy-first** | Data directory is yours: local, cloud, or git — you choose |
| **Gboard-inspired UI** | Clean candidate bar with Google-style blue accent and dark mode |
| **Pinyin engine** | Self-contained, cross-platform (11072-character pinyin table, no Apple CFString dependency) |

## Cross-Platform Architecture

```
┌─ Input Shell (thin, per-platform) ────────────────┐
│  macOS: InputMethodKit    iOS: Keyboard Extension  │
│  Windows: TSF (planned)   Linux: ibus (planned)     │
└──────────────────┬─────────────────────────────────┘
┌─ Core Engine (platform-agnostic, reusable) ───────┐
│  Pinyin/Shuangpin/Xingma · Dictionary · Phrases    │
│  Candidate ranking                                 │
│  (Pure Foundation + built-in tables, no AppKit)    │
└──────────────────┬─────────────────────────────────┘
┌─ Data Layer (open formats, syncable) ─────────────┐
│  hotwords.json (compatible hotword format)          │
│  user_dict.tsv · xingma.tsv · config.json           │
│  Directory: iCloud Drive / cloud drive / git repo  │
└────────────────────────────────────────────────────┘
```

## Quick Start

```bash
bash Scripts/build_app.sh   # Build macOS release
bash Scripts/install.sh     # Install to ~/Library/Input Methods
```

Then: **Log out / restart** → System Settings → Keyboard → Input Sources → Add "PhraseKey".

### iOS (Keyboard Extension)

```bash
cd ios && xcodegen generate      # Generate Xcode project
# 模拟器构建（无需签名）：
xcodebuild -scheme PhraseKeyHost -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# 装到已启动的模拟器：
#   xcrun simctl boot "$(xcrun simctl list devices available -j | jq -r '.devices[][] | select(.name=="iPhone 17 Pro") | .udid' | head -1)"
#   xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/PhraseKey.app
#   xcrun simctl launch booted com.phrasekey.ime
```

**真机运行（免费 Apple ID 即可，无需 $99）：**

1. 打开 `ios/PhraseKeyIOS.xcodeproj`，按 [Docs/iOS-HARDWARE-SIGNING.md](Docs/iOS-HARDWARE-SIGNING.md) 操作
2. 两个 target（PhraseKeyHost / PhraseKeyKeyboard）都选你的 Apple ID 作为 Team
3. 连接 iPhone → ⌘R 运行 → iPhone 上信任开发者 → 设置里添加 PhraseKey 键盘并开启「允许完全访问」

> 免费账号限制：签名 7 天过期（重新 ⌘R 即可续签）、最多 3 个 Bundle ID。

## Xiaohe Shuangpin / Xingma

- **Xiaohe Shuangpin**: Built-in complete key table (zero-initials, ü/ui context, iang/uang, iong/ong, ua/uo/uai context). Bidirectional encode/decode.  
  Examples: `nihc` = 你好, `iyjp` = 春节, `jv` = 居.
- **Xiaohe Xingma**: Shuangpin + shape code. Place a full Xingma code table at `~/Library/Application Support/PhraseKey/xingma.tsv` (format: `char\tcode`). Falls back to pure Shuangpin when no table is installed.
- **Phrase keys** (your custom shortcuts) always win — they're your personal shape codes.

## Open Data Formats (Key to Cross-Device Sync)

- **Phrases**: `[{"hw_id":"...","text":"...","key":"..."}]` (compatible with mainstream hotword exports)
- **Dictionary**: `pinyin\tword\tfrequency` (built-in `dict.tsv` + user `user_dict.tsv`)
- **Settings**: `config.json` (scheme, data directory — syncs with your data dir)
- **Defaults**: `~/Library/Application Support/PhraseKey/`, configurable in config.json

## Roadmap

- [x] v0.1: IMK skeleton + engine + phrases + Gboard UI
- [x] v0.2: Xiaohe Shuangpin/Xingma + cross-platform data layer + iOS keyboard extension (App Group shared data)
- [x] User dictionary learning (auto-learn committed words) — see [Docs/DATA-AND-IMPORT.md](Docs/DATA-AND-IMPORT.md)
- [ ] Clipboard history (cross-device)
- [x] Full dictionary / Xingma code table import docs — see [Docs/DATA-AND-IMPORT.md](Docs/DATA-AND-IMPORT.md)
- [x] iOS hardware signing guide (free Apple ID supported — see [Docs/iOS-HARDWARE-SIGNING.md](Docs/iOS-HARDWARE-SIGNING.md))
- [ ] Windows/Linux (TSF/ibus — port core engine)

## Repository

- GitHub: https://github.com/jaminliu89/phrasekey-ime
- Gitee: https://gitee.com/jaminkim/phrasekey-ime

## License

MIT