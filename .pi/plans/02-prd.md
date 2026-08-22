# PRD — phrasekey-ime — 2026-08-23

> 铁律：**每个功能必须有「完成定义（DoD）」，且 DoD 必须可写成断言。**
> 没有 DoD 的功能一律标 `PLANNED`，**禁止写进 README 的 Features 表**。
> 本项目已付真实代价：README 宣称支持小鹤音形，但依赖的 `xingma.tsv` 根本不存在 → 功能恒空转。
>
> 定位为 **(a) 自用工具**（见 01-positioning.md），因此本 PRD 只服务单一用户，
> 不考虑通用性、不考虑他人上手成本、不承担对外兼容承诺。

---

## 默认配置（跨端项目必填）

默认值就是我的实际路径，**必须最先明确、最先测试**。

| 配置项 | 默认值 | 各端是否一致 | 来源文件 |
|---|---|---|---|
| 输入方案 | `.flypy`（小鹤双拼） | ✅ 已对齐（7c49895 修复 iOS 硬编码） | `Settings/InputScheme.swift` |
| 数据目录（macOS） | `~/Library/Application Support/PhraseKey/` | — | `PhraseKeySettings.resolvedDataDir` |
| 数据目录（iOS） | App Group 容器 `/PhraseKey` | ✅ 宿主与键盘均已指向 | `HotwordsStore.appGroupID` |
| 词库（macOS） | `dict.tsv` 20 万条 | 分档 | `Resources/` |
| 词库（iOS） | `dict_mobile.tsv` 3 万条 | 分档（内存约束） | `Resources/` |
| 音形码表 | **无内置**，需自备 `xingma.tsv` | 一致（都没有） | `CodeTable.swift` |

> **教训：默认路径没被测 = 等于没测。** 前两轮修断档/排序全按全拼验，
> 而默认是双拼 → 双拼奇数键位全线断档数月无人发现。回归必须优先覆盖默认配置。

### ⚠️ 已发现的默认值不一致（本轮新增，待修）

`HotwordsStore.search(_:scheme:)` 的默认参数是 `.pinyin`（HotwordsStore.swift:157），
与产品默认 `.flypy` 不一致。与 iOS 硬编码 `.pinyin` 是**同源问题**：
默认参数写死全拼，调用方漏传就静默走错方案。
→ 已列入 Phase 0，见 03-plan.md。

---

## 功能清单

状态取值：`DONE` / `WIP` / `PLANNED`（无 DoD 只能是 PLANNED）

| 功能 | 状态 | DoD 是否可验证 | 对外宣称 |
|---|---|---|---|
| 小鹤双拼输入（默认方案） | DONE | ✅ 已固化回归 | 可宣称 |
| 全拼输入 | DONE | ✅ 已固化回归 | 可宣称 |
| 常用语命中置顶 | DONE（macOS）/ WIP（iOS 真机未验） | ✅ | 可宣称，需注明 iOS 待验 |
| 常用语管理（增删改查搜索） | DONE 双端 | ✅ | 可宣称 |
| 剪贴板一键收藏 | DONE（macOS） | ✅ | **需改口径**：是「面板→上屏」不是「剪贴板→收藏」 |
| 导入 CSV/JSON | DONE | ✅ | 可宣称 |
| 用户词典自学习 | DONE | ⚠️ 与新排序的交互未设计 | 可宣称，但需补验证 |
| 候选排序（覆盖度优先） | DONE | ✅ 已固化回归 | 可宣称 |
| **小鹤音形** | **PLANNED** | ❌ 无码表则不可达 | **禁止列入 Features 表** |
| iOS 键盘长时存活 | WIP | ✅ 可量化（1 小时） | 不宣称 |
| Windows / Linux | **不做** | — | **从 README 删除** |
| 剪贴板历史 | **不做** | — | 从 Roadmap 删除 |

---

### 功能：小鹤双拼输入（默认方案）

- **状态**：DONE
- **用户故事**：作为小鹤双拼用户，我要按肌肉记忆敲双拼码，以便不用重学键位
- **完成定义（DoD）**：
  - [x] 逐键模拟输入任意常用词，**每一步都有候选**（含奇数键位）
  - [x] 整串输入时目标词为第 1 候选
  - [x] 同一输入的候选顺序**恒定**（全序排序）
  - [x] `FlypyCodec` encode/decode 往返可逆率 ≥ 410/417（不可逆项 ≤10）
- **验收方式**：
  ```bash
  bash Scripts/bench_engine.sh   # 全绿
  ```
- **明确不含**：不做双拼方案自定义（只支持小鹤键位）
- **依赖**：`dict.tsv`、`hanzi_pinyin.tsv`（均已内置）

---

### 功能：常用语命中置顶

- **状态**：DONE（macOS）/ WIP（iOS 真机未验）
- **用户故事**：作为重复输入长文本的人，我要打拼音缩写直接上屏长文本，
  以便不用切面板、不用记特殊前缀符号
- **完成定义（DoD）**：
  - [x] key 精确命中 → score 10000，**必为第 1 候选**（压过任何词库词）
  - [x] 首字母命中 → score 3000
  - [x] 写入后立即从磁盘重读可命中（不依赖内存缓存）
  - [ ] **iOS 端：宿主 App 加一条 → 回键盘打那个 key 能命中**（真机未验）
  - [ ] `search()` 默认 scheme 与产品默认一致（当前为 `.pinyin`，待修）
- **验收方式**：
  ```bash
  bash Scripts/bench_engine.sh              # macOS 侧断言（含落盘重读）
  bash Scripts/probe_query.sh --flypy <key> # 人工确认置顶
  ```
  iOS：宿主加常用语 → 切键盘 → 打 key → 观察是否第 1 候选
- **明确不含**：不做常用语分组/标签/云同步
- **依赖**：App Group（iOS）

---

### 功能：候选排序（覆盖度优先）

- **状态**：DONE
- **用户故事**：作为打字的人，我多敲一个字母就是在收窄意图，
  我要候选跟着收窄，以便建立肌肉记忆
- **完成定义（DoD）**：
  - [x] `coverBonus`（公共前缀/输入长度）为主信号，词频降级为 tiebreak
  - [x] 排序**全序**（score → freqBonus → 词长 → text），同输入永远同顺序
  - [x] 双拼下覆盖度坐标系对齐（候选拼音先 encode 成双拼码再比）
  - [x] 查询耗时 < 0.5ms
- **验收方式**：`bash Scripts/bench_engine.sh`（含覆盖度优先断言）
- **明确不含**：不做基于使用频次的大数据调优；不对标商业输入法候选质量
- **依赖**：无

---

### 功能：小鹤音形

- **状态**：**PLANNED**（依赖不存在，功能不成立）
- **用户故事**：作为小鹤音形用户，我要用形码消除重码
- **完成定义（DoD）**：
  - [ ] 用户自备 `xingma.tsv` 放入数据目录后，音形过滤生效
  - [ ] `applyXingmaFilter` 有测试覆盖（**当前为完全未测代码**）
  - [ ] 未装码表时静默退化为双拼，**不丢输入**（已有回归覆盖）
- **验收方式**：需先有码表才能验；退化行为已在 bench 中断言
- **明确不含**：
  - **不内置官方码表** —— EULA 禁止反向工程、著作权全归小鹤官方
    （证据见 00-research.md §1），且与本项目 MIT 冲突
  - 不采用 BY-NC 整理词库（会使项目不能商用）
  - 不改用墨奇音形等替代码表（键位不同，会破坏「默认小鹤」这一事实）
- **依赖**：**用户自备 `xingma.tsv`（仓库永不包含）**

> 决策：(a) 自用工具定位下，我自己装一次码表即可，零成本。
> 对外口径统一为「需自备码表，未装则退化为双拼」。

---

## 非功能需求

| 维度 | 目标 | 测量方式 | 当前实测 |
|---|---|---|---|
| 词库加载耗时（macOS） | < 2s | `bench_engine.sh` | **1453ms** ✅ |
| 内存增量（macOS 20万条） | < 120MB | `bench_engine.sh` | **+90.9MB** ✅ |
| 单次查询耗时 | < 0.5ms | `bench_engine.sh` | **0.164ms** ✅ |
| iOS 键盘存活 | 连续使用 1 小时不被杀 | 真机手动 | **未测** ❌ |
| iOS 内存（3万条） | 不触发系统 kill | 真机 Instruments | **未测**（此前为 macOS 等比推算） ❌ |

---

## 与 README 的一致性检查

> 每次改 README 的 Features 表都要回来核对这张表。
> **当前 README 有 3 处名不副实，必须修。**

| README 宣称 | PRD 状态 | 代码证据（文件:行） | 是否名副其实 |
|---|---|---|---|
| Features 表列「Xiaohe Xingma」 | PLANNED | `CodeTable.swift:34` hasLoaded 恒 false | ❌ **需去勾/加注** |
| Roadmap `[x] v0.2 Xingma` 打勾 | PLANNED | 同上 | ❌ **需改为未完成** |
| README:87 「需自备码表」 | 与 PRD 一致 | — | ✅ 口径正确 |
| 「Save from clipboard」 | DONE 但语义相反 | `PhrasesPanel.swift:121` 是面板→上屏 | ❌ **需改描述** |
| Windows/Linux (planned) | **不做** | 无代码 | ❌ **需删除** |
| 「Cross-platform data」 | DONE | 开放 TSV/JSON | ✅ |
| 「Auto-learn」 | DONE | `PinyinEngine.swift:104` | ✅ |
| 「Import phrases」 | DONE | `HotwordsStore.swift:112/131` | ✅ |
| 「Phrase Manager 双端」 | DONE | `PhrasesPanel.swift` + `PhraseKeyHostApp.swift` | ✅ |

---

## 变更日志

- 2026-08-23 PRD 初稿。按 (a) 自用工具定位，音形定为 PLANNED（不内置码表）、
  Windows/Linux 与剪贴板历史定为不做。核对出 README 3 处名不副实、
  1 处默认值不一致（`HotwordsStore.search` 默认 `.pinyin`）。
