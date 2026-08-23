# 迁移评估：把 PhraseKey 逻辑迁到 Hamster 外壳

> 2026-08-24。触发：用户「拉一个之前那个开源的产品把我们的逻辑数据迁移过去，你写的是个半成品」。
> 上一轮我只抄了配色就号称「套开源」，等于没做。本文是真做之前的代价核算。

---

## 0. 先说一个改变判断的发现

**Hamster 没有短语功能。** `grep -ri "phrase\|customPhrase" Packages/ --include=*.swift` 零命中。

这意味着迁移不是「把我们的东西搬进一个更完整的产品」，而是
**「拿它的键盘外壳，把我们的核心装进去」** —— 核心功能仍得自己写。

---

## 1. 实测代价（不是估算）

| 项 | 数字 | 说明 |
|---|---|---|
| 白拿的键盘 UI | **28402 行** | `HamsterKeyboardKit`，196 个 Swift 文件 |
| 要接管的引擎适配器 | **1029 行** | `RimeContext.swift`，唯一 import RimeKit 的文件 |
| 引用该适配器的文件 | **18 处** | 键盘包 15 + iOS 包 3 |
| 引擎胶水层 | 428 行 | `RimeKit`，可整包丢弃 |
| 依赖 KeyboardKit | **否** | 自己实现的按键系统，无第三方 UI 依赖 |

**耦合浅** —— 引擎只从一个文件进来，这是标准适配器结构，可换。

---

## 2. 迁过去能白拿什么（我们现在没有的）

| 能力 | 文件 | 我们的现状 |
|---|---|---|
| 候选栏**手动分页** | `CandidatesPagingView.swift` | 只有横向滚动，长列表翻不动 |
| 候选栏对齐布局 | `AlignedCollectionViewFlowLayout.swift` | UIStackView 硬排 |
| 按键**长按气泡** | `InputCalloutView.swift`（156 行） | 无，按了没反馈 |
| 九宫格键盘 | `ChineseNineGridKeyboard.swift` | 无 |
| 符号**分类面板** | `ClassifySymbolic/`（5 文件） | 只有两页平铺符号 |
| Emoji 键盘 | `EmojisKeyboard.swift` | 无 |
| 工具栏 | `KeyboardToolbarView.swift` | 无 |
| 键盘皮肤/配色体系 | `Color/`、`Colors.xcassets` | 上一轮只抄了色值 |

---

## 3. 迁移必须保住的东西（我们的资产）

| 资产 | 位置 | 实测状态 |
|---|---|---|
| 自研双拼引擎 | `Engine/`（1129 行） | 查询 0.017ms，零声母 12/12 |
| 整句切分 | `PinyinEngine.segmentSentence` | 多字连打 8/8 |
| **518 条真实短语** | `hotwords.json` | 从微信输入法导入，10/10 置顶 |
| 短语置顶逻辑 | `HotwordsStore.search` | 长文本只认简码（防吃掉正常输入） |
| 20 万条词库 | `dict.tsv` | 含 284 条手工补的口语搭配 |
| **80+ 条回归断言** | `Tests/Bench/main.swift` | 每一条都对应一个真实踩过的坑 |

---

## 4. 三个方案与取舍

### 方案 A：整体迁到 Hamster 外壳（fork 它，换掉引擎）
- 做法：fork Hamster → 删 RimeKit → 用我们的引擎实现 `RimeContext` 的对外接口 → 装短语面板
- 得：28402 行成熟 UI，产品完成度一步到位
- 代价：① 要读懂 18 处调用约定；② Hamster 用 Combine + UICollectionView + 自研按键系统，
  与我们现有 200 行 UIStackView 键盘是两套世界，等于**iOS 端重写**；
  ③ 它的构建体系（6 个 SPM 包 + xcframework 脚本）要跑通；
  ④ 我们的 80 条回归全在引擎层，UI 换掉不影响 —— 这点是好事
- 风险：**一次性大改，中途失败无法回退到「能用」**。你现在手机上已在日常使用。

### 方案 B：只移植缺的组件（按需搬）
- 做法：保留现有键盘骨架，逐个搬 Hamster 的组件（先候选分页 → 再长按气泡 → 再符号分类）
- 得：每搬一个都能立刻装机验证，**始终保持可用**
- 代价：搬的过程要适配它的 style/context 抽象，单个组件搬完可能仍要改
- 风险：低。任一步失败只影响那一个组件

### 方案 C：不迁，自己补
- 得：完全可控
- 代价：等于放弃 28402 行现成代码，重复造轮子
- 风险：低但慢

---

## 5. 选定：B（按需移植），理由是可回退

判据来自你的实际处境：**手机上已经在日常用它打字**。
方案 A 一旦中途卡住，你连现在能用的版本都没了 —— 这个代价不可接受。

B 的每一步都是：搬一个组件 → 构建 → 装机 → 你实测 → 不行就丢掉这一步。

顺序按「你实际会碰到的频率」排：
1. **候选栏分页 + 对齐布局** —— 打字每次都碰，现在长列表翻不动
2. **短语面板搜索框** —— 518 条靠首字母分类仍偏多（你上一轮反馈的痛点）
3. **按键长按气泡** —— 打字反馈，缺它显得廉价
4. 符号分类面板 —— 用得少，靠后
5. 九宫格 / Emoji —— 你是双拼用户，九宫格用不上；Emoji 系统自带

---

## 6. 明确不迁的部分

- **不迁 librime**：我们引擎实测可用（0.017ms / 8/8 多字连打），
  换成 librime 要带整个 RIME 运行时 + 方案配置文件，且 §7 McBopomofo 已证自研非造轮子
- **不迁 Hamster 的设置界面**（`HamsteriOS` 11965 行）：它为「支持任意 RIME 方案」而设计，
  我们只需小鹤双拼一种，那套复杂度是负债
- **不迁文件服务器**（`HamsterFileServer`）：为传 RIME 方案文件用，我们不需要
- **不做主题系统**：已列 out of scope

---

## 7. 待验证 → **已验证**（2026-08-24）

- [x] **候选栏可剥离**。它依赖 `RimeContext` + `KeyboardContext` 两个上下文，
      但 `KeyboardContext` 本体只 **19 行**，且候选栏只用到其中 **5 个属性**：
      `candidatesViewState` / `enableEmbeddedInputMode` / `hamsterConfiguration` /
      `heightOfCodingArea` / `heightOfToolbar`。
      `hamsterConfiguration`（879 行的大配置）只用了 `.toolbar` 一个字段
      → 移植时用我们自己的轻配置替换即可。
- [x] **`CandidateSuggestion` 可直接映射**：字段是 `index` / `label` / `text` /
      `title` / `subtitle` / `isAutocomplete` / `isUnknown` / `additionalInfo`，
      与我们 `Searcher.Result`（text / type / score）是子集关系，
      `type == "hotword"` 可映射为 `subtitle` 或 `additionalInfo`。
- [ ] 长按气泡是否依赖它的自研触摸系统 `KeyboardTouchView`（搬到那一步再验）

---

## 变更日志
- 2026-08-24 创建。核算迁移代价，选定按需移植路线。


---

## 8. 鼠须管 / 同文评估（2026-08-24，用户提议）

用户问「鼠须管或者同文呢」。先查平台 —— 这是决定性判据：

| 项目 | 星 | 语言 | 平台 | 对本项目 |
|---|---|---|---|---|
| `rime/squirrel` 鼠须管 | 6278★ | Swift | **macOS 专属**（`DTPlatformName = macosx`） | 只能用于 macOS 端 |
| `osfans/trime` 同文 | 4584★ | **Kotlin** | **Android 专属** | ❌ 完全不可用 |
| `imfuxiao/Hamster` 仓 | 1621★ | Swift | iOS | 唯一可用于 iOS |

**结论：用户当前焦点在 iPhone，鼠须管与同文都不适用。**
- 同文是 Kotlin/Android，一行代码都搬不过来
- 鼠须管是 macOS IMK，与 iOS 键盘扩展是两套完全不同的 API

→ iOS 端仍只有 Hamster 一个可参考标杆（这也印证 §8 那次调研方向修正是对的）。

### 但鼠须管对 macOS 端有价值（且价值很大）

已克隆 `/tmp/squirrel_ref`。规模对比揭示了「看起来不成熟」的直接原因：

| 组件 | 鼠须管 | 我们 |
|---|---|---|
| 候选面板 | `SquirrelView.swift` 756 行 + `SquirrelPanel.swift` 566 行 = **1322 行** | `CandidatePanel.swift` **194 行** |
| 主题/样式 | `SquirrelTheme.swift` 364 行 | 无独立主题层 |
| 输入控制器 | `SquirrelInputController.swift` 642 行 | `Controller.swift` |
| 全部 Swift | **3605 行** | — |

鼠须管**整体只 3605 行**（比 Hamster 的 28402 行精简得多），且是纯 macOS IMK，
与我们 macOS 端同构 —— 移植难度远低于 Hamster→iOS。

它已经是本项目的对照标本：`28aa050` 那次修 IMK 注册（输入法从未被系统注册）
就是拿本机 `/Library/Input Methods/Squirrel.app` 的 Info.plist 做对照才定位到的。

### 决策：分平台选标杆

| 平台 | 标杆 | 理由 |
|---|---|---|
| **iOS**（当前焦点） | Hamster | 唯一 iOS 键盘扩展标杆 |
| **macOS**（暂缓） | **鼠须管** | 同构、精简、已验证可作对照标本 |

macOS 端暂不动 —— 用户明确当前优先手机（见 03-plan.md 优先级失误记录）。
待 iOS 稳定后再用鼠须管改造 macOS 候选面板。


---

## 9. 切到 macOS + 鼠须管（2026-08-24，用户选定）

用户选「鼠须管」。开工前先验证 macOS 端可达性 —— 结果发现比面板美观更根本的问题。

### ★ 根因：macOS 端你从来没能用过它

实测：
```
~/Library/Input Methods/PhraseKey.app        存在（用户级）
/Library/Input Methods/PhraseKey.app         不存在
defaults read com.apple.HIToolbox AppleEnabledInputSources | grep PhraseKey
  → 0 条
pgrep -fl PhraseKey → 77829（进程在跑）
```

**进程能被 `open` 拉起，但系统从未注册它** —— 系统设置的输入法列表里找不到，
所以无法添加、无法切换、无法使用。

对照标本：本机正常工作的鼠须管在 **`/Library/Input Methods/`（系统级）**。

→ 定性（**已验证**）：macOS 对用户级输入法的注册不可靠。
  这与 `28aa050` 那次「Info.plist 缺 ComponentInputModeDict」是**两个独立问题**，
  当时修完 plist 结构就以为好了，没验证注册结果 —— 又一次「构建成功 ≠ 可用」。

### 已修
`Scripts/install.sh` 改为：
- 安装到 `/Library/Input Methods/`（sudo），并清掉用户级旧安装
  （两份并存会让系统看到重复 bundle ID）
- 安装后**出厂验证**：bundle 存在 / 签名有效 / 4 个 IMK 关键键 / 词库 ≥10000 条
- 验证不过直接 `exit 1`，不允许声称可用
- 输出里给出重登后的自查命令，用户可自己确认是否真被注册

### 鼠须管候选面板凭什么 1322 行 —— 逐项对比

| 能力 | 鼠须管 | 我们 | 差距性质 |
|---|---|---|---|
| 双主题（light/dark 独立 Theme 对象） | `SquirrelTheme` 364 行 | 已有双色板（`Palette` 式静态色） | **不大**，我们够用 |
| 圆角/高亮背景 | CGPath 精确绘制 | 已有 `cornerRadius` | **不大** |
| **翻页指示**（`canPageUp/canPageDown` + 箭头 CGPath） | 有 | **无** | 候选多了用户不知道还有下一页 |
| **预编辑区**（`preeditRange` + 高亮已输入拼音） | 有 | **无** | 打字时面板上看不到已输入内容 |
| NSTextLayoutManager 精确排版 | 有 | NSTextField 拼 | 影响长候选换行与对齐 |

→ 结论：**差距在功能不在配色**。我上一轮以为是"不够漂亮"，
  实际是"缺翻页指示与预编辑区"这两个功能性缺失。

### 本轮顺序（先可用，再好看）
1. [x] 安装改系统级 + 出厂验证 —— 否则一切改动你都看不到
2. [ ] 你注销重登，确认能在系统设置里添加 PhraseKey
3. [ ] 补翻页指示（候选 >N 时显示 ▲▼，学鼠须管 canPageUp/canPageDown）
4. [ ] 补预编辑区（面板顶部显示已输入拼音串 + 高亮当前音节）
5. [ ] 长候选排版（评估是否需要上 NSTextLayoutManager）
