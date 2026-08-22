# PhraseKey — 从 demo 到能日常用的输入法

> 计划落盘时间：2026-08-23
> 目标：让 PhraseKey 成为可以真的拿来打字的输入法，而不是 108 词的演示品。

## 现状盘点（已验证）

- `swift build` 通过，`dist/PhraseKey.app` 已构建，已安装到 `~/Library/Input Methods/`
- macOS IME（IMK）：拼音 / 小鹤双拼 / 小鹤音形 + 常用语优先 + 自学习 + 常用语面板 ✅
- iOS 键盘扩展：可加载、可弹出；闪烁已定性为免费 Apple ID 签名固有问题（上轮结论）
- **致命短板：内置词库 `Sources/PhraseKeyIME/Resources/dict.tsv` 仅 108 条**
- 次要问题：`PinyinSyllable.all` 用「声母 × 韵母」笛卡尔积生成，含大量非法音节（如 `fai`/`ruang`），影响连续拼音切分准确度

## 目标（本轮验收标准）

1. 内置词库 ≥ 10 万条，覆盖日常高频词（打「明天开会」「辛苦了」「人工智能」都必须出）
2. 引擎在 349k 级词条下**启动 < 300ms**、macOS 内存增量可接受
3. iOS 键盘扩展**不因词库变大而超内存被杀**（键盘扩展内存上限约 30-60MB）
4. 连续拼音切分正确率提升：非法音节从表里剔除
5. 有回归测试脚本，改引擎后能一键验证

## 阶段

### Phase 1 — 词库工程（核心）
- [ ] 用 jieba `dict.txt`（349k 词 + 词频）+ pypinyin 生成全量词库
- [ ] 按词频降序排列（引擎可按 N 截断加载）
- [ ] 分两档产出：`dict.tsv`（macOS 全量）+ `dict_mobile.tsv`（iOS 精简档）
- [ ] 体积/加载耗时实测，确定各档条数

### Phase 2 — 引擎承载能力
- [ ] 基准测试：加载耗时 / 索引构建耗时 / 内存
- [ ] 按需优化：懒建索引（只建当前方案要的索引）、reserveCapacity、按档截断
- [ ] iOS 侧走精简档，键盘扩展内存实测

### Phase 3 — 拼音音节表修正
- [ ] 用标准 413 音节表替换笛卡尔积生成
- [ ] 切分回归用例（nihao / xianzai / zhongguoren / lvyou ...）

### Phase 4 — 验证与交付
- [ ] 回归脚本 `Scripts/test_engine.swift`（离线跑查询断言）
- [ ] 重新构建 + 安装 macOS，人工试打
- [ ] iOS 构建通过
- [ ] README / Docs 更新，MASTER-TASK 更新

## 决策记录

- **为什么用 jieba dict.txt**：本机已装（349046 条，含词频），MIT 兼容，无需联网，词频是真实语料统计
- **为什么用 pypinyin**：本机已装 0.55.0，带短语库，多音字在词语上下文中读音更准
- **为什么分两档**：iOS 键盘扩展内存预算远小于 App，全量词库会被系统杀

## 进度日志

- 2026-08-23 计划落盘，开始 Phase 1

---

## 2026-08-23 真机排障 + 引擎实测记录

### 已证伪的猜想（每条都有对照证据）
| 猜想 | 证伪方式 | 结论 |
|---|---|---|
| 扩展崩溃 | 438 份崩溃报告全量 grep，无 PhraseKeyKeyboard | 证伪 |
| 内存被 Jetsam 杀 | 7 份 JetsamEvent 快照，扩展进程从未出现 | 证伪 |
| entitlements/profile 不匹配 | codesign -d 与 embedded.mobileprovision 逐项比对一致，有效期至 8/28 | 证伪 |
| Debug Dylib 坑 | nm -gU 确认主类符号在主可执行内，无 *debug.dylib | 已修复 |
| App Group 被拒 | 设备端容器存在且被写入（8/22 05:30） | 证伪 |
| 「从未被拉起」 | 用户实测：键盘在列表里，偶尔能弹但活不久 | 证伪（改为"能启动但被终止"） |

### 症状精确描述（用户口述）
设置→键盘 里 **有** PhraseKey；切换时**偶尔能弹出**；**存活时间很短**，之后不再弹出。
→ 不是注册失败，不是崩溃，是**加载成功后被系统终止**或**加载超时被放弃**。

### 未排除变量
- 设备为 **iOS 27.0 Beta (24A5408d)** —— 第三方键盘在 Beta 上有历史性问题，最大嫌疑
- 免费 Personal Team profile 7 天有效期与扩展存活的关系
- UIInputViewController 首次布局超时预算（尚无实测数字）

### 引擎实测数据（Scripts/bench_engine.sh，20 万词条）
- 加载 + 索引：1443 ms
- 内存：+93 MB（优化前 110 MB）
- 查询：0.032 ms
- 内存分布：读文件 +9 / 切行 +14.5 / struct +9 / **单份索引 +16.8（×3 份）**
- **结论：Dictionary String 键是瓶颈。iOS 键盘扩展需二进制词库 + mmap，Swift 原生容器方案不可行。**
- 注：iOS 端当前打包的仍是旧 108 条词库，故内存不是本次"活不久"的原因。

### 已修复（Phase 3 完成）
- PinyinSyllable.all：23×34 笛卡尔积（782 项，含 fai/ruang 等非法音节）→ 真实 417 音节表
- segment() 匹配窗口 3 → 6：修复 xianzai→xia/n/zai、zhongguoren→zho/n/g/guo/ren 等 4 项切分错误
- 回归 10 项失败 → 全绿

### 待验证清单（遵循调试铁律，不许无对照结论）
- [ ] 用 Xcode 官方 Custom Keyboard 空模板在同机对照 —— 若空模板也活不久，则确定为系统/签名层问题，与我们代码无关
- [ ] 不锁屏连续切换键盘 10 次，记录第几次开始失效
- [ ] 抓取键盘切换瞬间日志（Scripts/capture_keyboard_log.sh），找 pkd/PlugInKit 的 reason code
- [ ] 查证 iOS 26/27 是否有第三方键盘已知 bug（调研中）

---

## 2026-08-23 定性完成：真凶是 Info.plist 缺必需键

### 结论（已验证）
键盘扩展 `NSExtensionAttributes` **缺 `PrimaryLanguage`**（另缺 `IsASCIICapable`、`PrefersRightToLeft`）。
缺失时系统能把键盘注册进「设置→键盘」列表，但**拉起扩展进程时判定配置无效直接拒绝**。

**验证证据**：
```
$ xcrun devicectl device info processes | grep PhraseKey
46985  .../PhraseKey.app/PlugIns/PhraseKeyKeyboard.appex/PhraseKeyKeyboard
```
补键前该进程从不出现，补键后出现且用户实测键盘正常存活。

### 这解释了所有此前无法解释的现象
| 现象 | 解释 |
|---|---|
| 设置里看得见键盘 | 注册进列表只需 bundle 结构正确 |
| 切过去不出现 / 闪 | 拉起进程时配置校验失败 |
| 崩溃报告里找不到它 | 从未启动，自然没有崩溃 |
| Jetsam 里找不到它 | 同上 |
| 进程列表里 BareKBExt 在跑、它没有 | 直接证据 |

### 定位手段：空壳对照组法（本轮最大收获）
编译零依赖键盘 BareKB，**同设备/同系统/同免费 Team/同签名**，唯独代码极简。
它长期存活 → 一刀切开「环境问题」与「本项目问题」。
随后逐项 diff：先 diff 代码（发现手动 frame 布局、缺高度约束），
再 **dump 两份 Info.plist 逐键对比** → 定位到 plist 必需键缺失。

**教训：应该在做代码 diff 之前就先 diff 配置**，这一步零成本且不需要用户参与，我却放到最后才做。

### 一并修掉的真问题（非死因但必要）
1. 手动 frame 布局依赖 `keyArea.bounds`（viewDidLoad 时为 0）与 `UIScreen.main`（扩展内不代表键盘尺寸）
   → 已重写为 UIStackView 纯约束。这是用户反馈「不像完整输入法、像占位」的原因。
2. `inputView` 关掉 autoresizing 后无高度来源 → 已加 heightAnchor 268
3. 键盘包内曾打入 20 万词全量词库（实测净增 93MB，超扩展预算）→ 已换 3 万条移动版（10.6MB）
4. 引擎音节表与切分器 10 项 bug → 已修，回归全绿
5. 补齐输入法必备功能：拼音显示区、候选横滑（30 候选）、Shift、符号层、handleInputModeList

### 已证伪并需清理的错误结论
- ~~「免费 Apple ID 签名固有问题」~~ —— 曾写进源码注释，已删除
- ~~「Debug Dylib 会导致加载失败」~~ —— BareKB 带 debug.dylib 照样活，注释已更正
- ~~「切换键盘无法自动化」~~ —— 项目本就有 UITests target

### 下一步（iOS 优先）
- [ ] 长时存活观察：正常使用一段时间后复查进程是否仍在
- [ ] 真机内存实测（3 万词库实际占用，此前为 macOS 等比推算）
- [ ] 输入体验验收：候选准确率、常用语优先级、双拼/音形切换
- [ ] 常用语在 iOS 端的读取（当前扩展内 HotwordsStore 被 gate 掉，键盘用不到常用语——这是核心卖点缺失）
