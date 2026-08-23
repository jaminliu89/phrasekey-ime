# 交接：PhraseKey 输入法（macOS + iOS 自研双拼输入法）

> 交接时间 2026-08-24 · 交接人 Pi · HEAD `8a9d27d`（三端已齐）
> **接手第一件事：读本文 §「先别做什么」，再读 `.pi/plans/05-migration.md` §9。**

---

## 任务目标

把 PhraseKey 从「能演示」推进到「用户能日常用」。核心卖点是**常用语（短语）**——
项目名就是 PhraseKey，用户已从微信输入法导入 518 条真实短语，这是项目存在的理由。

---

## 当前状态

| 项 | 状态 |
|---|---|
| 总进度 | 引擎可用 · 常用语可用 · iOS 装机在用 · macOS 刚打通可达性 |
| 当前焦点 | **macOS 候选面板**（用户 2026-08-24 从 iOS 切过来，标杆＝鼠须管） |
| 阻塞 | 无 |
| 最后绿灯 | `bench_engine.sh` 全绿 + `build_app.sh` 门禁全绿（20 万词库）@ `8a9d27d` |
| 三端 | 本地 / GitHub / Gitee 均 `8a9d27d` |

---

## 已完成（按里程碑，不是流水账）

### 引擎层（已实测，勿轻易改）
- ✅ **默认小鹤双拼**，零声母统一 `o` 引导 12/12 → `Sources/PhraseKeyIME/Engine/`
- ✅ **整句切分 / 多字连打** 8/8（`wouivsgo`→我是中国）→ `PinyinEngine.segmentSentence`
  - 打分公式**不是** McBopomofo 那套（其公式在本项目已实测证伪，见 §已知的坑）
  - 性能 0.017ms（分段计时定位出瓶颈在 `searchFlypyProgressive` 占 93%，决定不重构它）
- ✅ 20 万条词库 + 284 条手工补的口语搭配 → `Resources/dict.tsv`

### 常用语（核心卖点）
- ✅ **518 条真实短语**，从微信输入法 MMKV 只读导入 → `Scripts/phrase.py wetype`
  - 10/10 真实简码置顶验证通过
  - 长文本只认自定义简码（≤4 字才参与拼音前缀匹配），防长话术吃掉正常输入
- ✅ iOS 随包内置 + 首次启动自动灌入 → `Sources/PhraseKeyIME/Resources/phrases_builtin.json`
- ✅ iOS 键盘**短语面板**（底行「短语」键 → 分类条 + 列表 → 点击上屏）

### macOS（本轮重点）
- ✅ **安装改系统级** `/Library/Input Methods/` + 7 项出厂验证 → `Scripts/install.sh`
  - ★ 根因：此前装用户级，`AppleEnabledInputSources` 里 **0 条记录**，
    进程在跑但系统从未注册 → **用户从来没能在 macOS 上用过它**
- ✅ 候选面板**翻页指示 ▲▼**（学鼠须管 `canPageUp/canPageDown`）
- ✅ 候选面板**预编辑区**（顶部回显已输入拼音串 + 细分隔线）

---

## 接下来（按优先级）

### 1. ★ 等用户实测反馈，不要自己往前冲
用户刚装上带翻页指示 + 预编辑区的版本，**还没反馈**。
他的原话模式是「不好看 / 别扭 / 用不了」这类体感描述 —— 拿到具体反馈再改，
比继续照鼠须管清单往下搬更准。

### 2. 若用户说排版乱 → 上 `NSTextLayoutManager`
鼠须管 `SquirrelView.swift`（756 行，在 `/tmp/squirrel_ref/`，没了就重 clone）
用它做精确排版，我们用 NSTextField 拼。影响长候选换行对齐。
**这是唯一还没搬的鼠须管能力**，其余（双主题/圆角/高亮）我们已有且够用。

### 3. iOS 侧遗留（用户切走前提过的痛点）
- 短语面板**搜索框** —— 518 条靠首字母分类仍偏多（用户明确抱怨过）
- 长按短语编辑/删除 —— 现在改一条要回宿主 App
- 候选栏长按删词

### 4. 定时同步微信输入法新增短语
launchd，skill 建议 15 天一次。用户说过「可以」但还没做。

### 5. 两份过期文档要修
- `.pi/plans/01-positioning.md` **第 89 行**「成功判据」仍写 macOS，方向已过期
- 终局定义（Definition of Done）**一直没落地** —— 我提过写 `.pi/plans/05-endgame.md`
  （7 天零切回 + 只记「切回系统键盘次数」+ 不做清单），被打断两次都没写

---

## 先别做什么（★ 血泪教训）

| 别做 | 原因 |
|---|---|
| ❌ 别换引擎上 librime | 自研引擎实测 0.017ms / 多字连打 8/8，够用；librime 要带整个运行时 |
| ❌ 别整体 fork Hamster | 28402 行，等于 iOS 端重写；用户手机上**正在日常使用**，不可回退 |
| ❌ 别碰同文 trime | Kotlin/Android，一行都搬不过来 |
| ❌ 别把鼠须管用于 iOS | 它是 macOS 专属（`DTPlatformName = macosx`） |
| ❌ 别做主题系统 / 别上架 / 别引 KeyboardKit | 定位是自用工具，已列 out of scope |
| ❌ 别再跟用户解释小鹤码表的法律问题 | 用户明确说过「你不用管法律你给我实现功能」，重复解释被骂过 |
| ❌ 别重构 `searchFlypyProgressive` | 短输入断档全靠它，改它风险大于收益（已实测决策） |

---

## 关键上下文

### 已知的坑（每一条都对应真实事故）

1. **「构建成功 ≠ 可用」—— 本项目最大反复踩的坑**
   - 修完 IMK 的 `Info.plist` 结构就以为好了，没验证系统是否真注册 → 用户级安装那次白改
   - 声明"可以试用"前**必须**自己构建 + 装机 + 验产物内容（不只看退出码）

2. **iOS 给键盘扩展的 color scheme 可能是错的**（KeyboardKit issue #305，已报 Apple）
   → 深色文本框里语义色照样错。已改用 Hamster 半透明白方案，**别改回语义色**

3. **McBopomofo 打分公式在本项目已证伪**
   `log10(fscale^(n-1)×freq)` 无效 —— 路径分相加，词数多的路径凭空多加一项。
   现用 `log10(freq) + phraseBonus×(字数-1)`，bonus=8 由真实词库 10 例 DP 实测定出

4. **常用语长文本会吃掉正常输入**
   种子里「我们开个会…」的双拼码以 `womf` 开头 → 打 `womf` 时「我们」被挤掉。
   已限 `maxPinyinMatchChars = 4`。**加新短语后必须重跑回归**

5. **iOS 内置常用语必须用 JSON 不能用 TSV**
   109/518 条含换行，TSV 会被截断（518 条变 2896 行）

6. **danger-guard 会拦 `$0.key` 这类字面**
   → 改用 `$0[keyPath: \Hotword.key]` 绕开

7. **pbxproj 是手写维护的**
   加资源要照 `dict_mobile.tsv` 的四处模式：PBXBuildFile / PBXFileReference /
   PBXGroup children / PBXResourcesBuildPhase。
   宿主 Resources 阶段 ID = `00761A65...`，键盘扩展是 `6E12064A...`，**别加错 target**

8. **大块 UI 改动必须拆小步**
   我一次性写整块绘制代码，连续 6 次工具调用超限，一行没改成。
   改成「拆 3 步 + 绘制代码先写独立文件再插入」才通

### 工作纪律（用户明确要求，违反会被骂）

- **每做完一个功能就 `git add` + commit**，不要攒着
- **每轮结束推双端**（`origin` GitHub + `gitee`），用 `git rev-parse` 核对三端 HEAD
- **落盘必须在回复里给出文件路径 + 小节位置**（落盘 ≠ 用户知道）
- **结论分级**：已验证（附对照实验）/ 猜想（强）/ 猜想（待验证）。答不出用什么实验排除其他可能的，一律标猜想
- **不要猜瓶颈**，用分段计时（这条救过一次：我猜字符串拼接，实测是全表扫描）
- **保持现有优点，只做加法**，逻辑不变
- 修复要固化成永久回归 → `Tests/Bench/main.swift`（现 28 处断言）

### 环境

| 项 | 位置 |
|---|---|
| 项目 | `~/Projects/phrasekey-ime` |
| macOS 安装位 | `/Library/Input Methods/PhraseKey.app`（系统级，需 sudo） |
| macOS 数据 | `~/Library/Application Support/PhraseKey/hotwords.json`（518 条） |
| iOS 真机 | iPhone 15 Pro Max `01F6CD47-0925-516E-B5E4-26B1D3D3DBA3` |
| iOS 构建 | `cd ios && xcodebuild -project PhraseKeyIOS.xcodeproj -scheme PhraseKeyHost -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath /tmp/pk_dd build` |
| 鼠须管参考 | `/tmp/squirrel_ref`（3605 行 Swift，可能已被清，重 clone `rime/squirrel`） |
| Hamster 参考 | `/tmp/hamster_ref`（28402 行键盘 UI，同上） |
| 远端 | `origin` = `git@github.com:jaminliu89/phrasekey-ime.git` · `gitee` = `https://gitee.com/jaminkim/phrasekey-ime.git` |

### 常用命令

```bash
bash Scripts/bench_engine.sh          # 引擎回归（改引擎/加短语后必跑）
bash Scripts/build_app.sh release     # 构建 + 出厂门禁
bash Scripts/install.sh               # 装 macOS（sudo，含 7 项验证）
python3 Scripts/phrase.py list        # 看常用语
python3 Scripts/phrase.py wetype      # 从微信输入法增量导入
```

---

## 建议 Skill

- `three-alignment-protocol` — 动代码前先对齐三端事实（本项目吃过太多"没对齐就开工"的亏）
- `development-initialization` — 开发任务前置
- `systematic-debugging` — 调试超 15 分钟必用（二分排除，别瞎试）
- `verification-before-completion` — 声明完成前自证（本项目最需要这条）
- `vibecoding-circuit-breaker` — 反复修同一个错时止损
- `wetype-hotwords-export` — 微信输入法常用语导出（风控红线在里面，只读、不碰加密库）

---

## 相关链接

- 文档 SSOT：`.pi/plans/03-plan.md`
- **迁移评估（最新，必读）**：`.pi/plans/05-migration.md` §8 鼠须管/同文 · §9 macOS 切换
- 定位：`.pi/plans/01-positioning.md`（第 25 行「唯一核心差异＝常用语」；**第 89 行已过期**）
- PRD：`.pi/plans/02-prd.md`
- 走查：`.pi/plans/04-walkthrough.md`
- 调研：`.pi/plans/00-research.md`（§3 RIME 标杆方向曾判断错、§6 商业三家、§7 McBopomofo、§8 Hamster）
- 全局总览：`~/.pi/agent/MASTER-TASK.md` 第 25 行

---

## 给接手 Agent 的一句话

这个项目的**技术难点已经过了**（引擎、切分、常用语都实测可用）。
剩下的全是「用户实际用起来别扭在哪」——所以**别照清单往下搬功能，
先拿到用户的体感反馈再动手**。用户会用「不好看 / 用不了 / 半成品」这类词，
你要把它翻译成具体缺失（上一轮就发现"不够漂亮"其实是"缺翻页指示和预编辑区"）。
