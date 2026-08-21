# PhraseKey IME

**开源跨端输入法，以「常用语/词库跨端同步」为核心差异化，外观借鉴 Google 输入法（Gboard）。**

完全自研，不 fork 上游。Swift 原生 + InputMethodKit（macOS）+ 键盘扩展（iOS），引擎层平台无关可跨端复用。

- GitHub: https://github.com/jaminliu89/phrasekey-ime
- Gitee: https://gitee.com/jaminkim/phrasekey-ime

## 解决大部分人的痛点（调研结论）

调研了 Rime/Fcitx/Google 输入法生态（rime-ice 18.9k★、weasel 7.9k★、squirrel 6.3k★、fcitx5 2.5k★、google/mozc 3.0k★ 等），高星项目的共同点：
**大家都在意「词库、常用语、输入习惯」——但数据都被锁在各平台各输入法的私有格式里。**

最痛的三个点：

| 痛点 | 商业输入法现状 | PhraseKey 方案 |
|---|---|---|
| **常用语/词库被锁死** | 商业输入法常用语私有格式，导出要逆向（剪贴板甚至加密） | 常用语开放 JSON（与主流 hotword 格式兼容），**一条不丢直接导入** |
| **跨设备不互通** | 换设备/换输入法 = 重新养词库、重新记常用语 | 数据目录开放可同步：指向 iCloud Drive/云盘/git 即多端互通 |
| **隐私两难** | 云同步要上传，本地又不同步 | 自托管：数据 100% 在自己设备/自己的云端，格式全开放 |

## 功能

| 能力 | 说明 |
|---|---|
| **输入方案** | 全拼 / **小鹤双拼** / **小鹤音形**（菜单即切，音形可装码表） |
| **常用语优先** | 命中简码/双拼/首字母的常用语置顶，空格一键上屏长文本 |
| 拼音引擎 | 自研轻量，跨平台汉字→拼音表（11072 字），不依赖 Apple 专属 API |
| **常用语管理** | 设置面板增删改查（简码 + 多行文本），key 即自定义形码 |
| **导入常用语** | 直接导入其他输入法导出的 CSV/JSON（格式兼容） |
| **跨端同步** | 数据目录可设 iCloud Drive/云盘/git；引擎平台无关（macOS→iOS→Win/Linux 复用） |
| Google 外观 | Gboard 风格候选条：圆角卡片、Google 蓝高亮、深色适配 |

## 跨端架构

```
┌─ 输入通道/UI（每端独立，薄壳）────────────────────┐
│  macOS: InputMethodKit   iOS: 键盘扩展   Win: TSF   │
└──────────────┬──────────────────────────────────────┘
┌─ 核心引擎（平台无关，可跨端复用）──────────────────┐
│  拼音/双拼/音形 · 词库 · 常用语 · 候选排序          │
│  (纯 Foundation + 内置数据表，无 AppKit/CFString)   │
└──────────────┬──────────────────────────────────────┘
┌─ 数据层（开放格式，可同步）────────────────────────┐
│  hotwords.json (兼容主流 hotword) · user_dict.tsv │
│  xingma.tsv (音形码表) · config.json               │
│  目录可指向 iCloud Drive / 云盘 / git 仓库          │
└─────────────────────────────────────────────────────┘
```

## 快速开始

```bash
bash Scripts/build_app.sh      # 构建
bash Scripts/install.sh        # 安装到 ~/Library/Input Methods
```

安装后：注销/重启 → 系统设置→键盘→输入法 添加「PhraseKey」→ 菜单切换方案 → 设置里导入常用语。

## 小鹤双拼 / 小鹤音形

- **小鹤双拼**：内置完整键位表（含零声母、ü/ui 上下文、iang/uang、iong/ong、ua/uo/uai 上下文规则），解码/编码双向。示例：`nihc`=你好、`iyjp`=春节、`jv`=居。
- **小鹤音形**：双拼 + 形码。把完整小鹤音形码表放 `~/Library/Application Support/PhraseKey/xingma.tsv`（格式 `字\t形码`）即启用形码过滤；未装码表时自动退化为小鹤双拼。
- 常用语 key 在任何方案下优先命中——key 就是你自己定义的「一键出短语」形码。

## 数据格式（跨端互通的关键）

- 常用语：`[{"hw_id":"...","text":"...","key":"..."}]`（兼容主流输入法 hotword 导出格式）
- 词库：`全拼\t词\t词频`（dict.tsv 内置 / user_dict.tsv 用户扩展）
- 设置：`config.json`（方案、数据目录），随数据目录同步
- 目录：默认 `~/Library/Application Support/PhraseKey/`，可在 config.json 改到云盘目录

## Roadmap

- [x] v0.1：IMK 骨架 + 引擎 + 常用语 + Google 外观
- [x] v0.2：小鹤双拼/音形 + 跨端数据层 + iOS 键盘扩展（双端数据 App Group 共享）
- [ ] 词库用户学习（自动收录上屏词）
- [ ] 剪贴板历史（跨端同步）
- [ ] 完整词库/音形码表接入文档
- [ ] iOS 真机签名发布（需 Apple 开发者账号）
- [ ] Windows/Linux（引擎 Rust/C 移植）
- [ ] 自建同步服务（可选，零依赖云端）

## 目录结构

```
Sources/PhraseKeyIME/    # macOS IMK 输入法（SwiftPM）
  ├── Engine/            # 平台无关引擎（拼音/双拼/音形/词库/常用语）
  ├── Hotwords/          # 常用语存储（兼容主流 hotword 格式）
  ├── Settings/          # 方案/配置（config.json，可同步）
  ├── UI/                # Gboard 外观候选条
  └── Controller.swift   # IMK 主逻辑
ios/                     # iOS 键盘扩展 + 宿主 App（XcodeGen 生成 xcodeproj）
  ├── project.yml        # 工程定义（xcodegen generate）
  ├── PhraseKeyKeyboard/ # 键盘扩展（复用 Engine/）
  └── PhraseKeyHost/     # 宿主引导 App
Scripts/                 # 构建/安装脚本
```

## 许可

MIT
