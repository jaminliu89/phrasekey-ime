# PhraseKey 走查报告

> 项目：PhraseKey IME（双拼输入法）
> 仓库：~/Developer/phrasekey-ime
> 起点 HEAD：ffed498（2026-08-23）
> 终点定义：M0 / v0.3 —— 键盘稳定可用，核心交互不别扭（双拼分号选词 + 视觉重做 + iOS 存活 + 常用语自动展开）
> 规则：每完成一个 Task 追加一轮走查，含「做了什么 / 改了哪些文件 / 验证结果 / 遗留问题 / 下一步」

---

## 第 0 轮 · 起点走查（2026-08-23）

### 当前位置
HEAD ffed498 · main 分支 · 引擎回归全绿（bench_engine.sh 全部通过）

### 已完成盘点
- 引擎：拼音 + 小鹤双拼 + 整句切分 + Searcher 排序融合
- 常用语：563 条 WeType 导入 + HotwordsStore CRUD + 导入导出
- macOS：IMK 骨架 + 候选面板（翻页指示▲▼ + 预编辑区）+ 系统级安装
- iOS：键盘扩展 UI + 短语面板 + 3 万条精简词库 + App Group

### 未完成（M0 / v0.3 待办，按优先级）
1. [ ] Task 1 — 双拼分号/引号选词（; 选第2个，' 选第3个）
2. [ ] Task 2 — 候选栏视觉重做（灰度字重体系，去蓝色）
3. [ ] Task 3 — 常用语自动展开（空格触发，精确匹配自动上屏全文）
4. [ ] Task 4 — iOS 键盘存活稳定性真机验证

### 终点定义（M0 Definition of Done）
- 双拼模式下，; / ' 选词可用，候选不足时直接上屏符号
- 候选栏无蓝色，选中态靠浅灰背景 + 字重区分，深色模式一致
- 打常用语简码 + 空格 → 自动展开全文（可配置，默认开）
- iOS 键盘连续使用 20 分钟不崩，切换 App 不重新加载

### 已知禁区（先别做什么）
- 别换引擎上 librime
- 别整体 fork Hamster
- 别碰同文 trime
- 别把鼠须管用于 iOS
- 别做主题系统 / 别上架 / 别引 KeyboardKit
- 别重构 searchFlypyProgressive

---

## 第 1 轮 · Task 1 双拼分号/引号选词
> 状态：已完成 · commit 1f71503 · 2026-08-23

### 做了什么
- macOS Controller：`;` 选第 2 个候选，`'` 选第 3 个候选
- iOS KeyboardVC：同样逻辑
- 优先级：选词 > 音节分隔 > 直接上屏
- 候选不足或非双拼模式时，正常上屏符号或走分隔符逻辑
- 空输入时 `'` 放行给系统（英文上下文打 don't 等）

### 改动文件
- `Sources/PhraseKeyIME/Controller.swift` — +34 行
- `ios/PhraseKeyKeyboard/KeyboardViewController.swift` — +25/-12 行

### 验证结果
- ✅ swift build 通过
- ✅ 引擎回归全绿
- ⚠️ 真机/真实输入法环境待用户实测

### 验收对照（MASTER-TASK Task 1）
- 双拼模式下候选≥2 时按 `;` → 上屏第 2 个 ✓
- 双拼模式下候选≥3 时按 `'` → 上屏第 3 个 ✓
- 只有 1 个候选时按 `;` → 直接上屏分号 ✓
- 没有输入时按 `'` → 直接上屏撇号 ✓

---

## 第 2 轮 · Task 2 候选栏视觉重做
> 状态：已完成 · commit 5196afa · 2026-08-23

### 做了什么
- GBoardTheme → PhraseKeyTheme（灰度字重体系）
- 去掉所有 accent 蓝色，选中态靠浅灰背景 + medium 字重区分
- 序号/标记用 sub 色，选中时加重到 subSelected
- 深/浅两套主题 token 对齐：bg / highlightBg / text / textSelected / sub / subSelected / border
- 字重体系：text=regular, textSelected=medium, sub=semibold
- 边框、分隔线统一用 border 色值

### 改动文件
- `Sources/PhraseKeyIME/UI/CandidatePanel.swift` — +51/-40 行

### 验证结果
- ✅ swift build 通过
- ⚠️ 视觉效果待真机/真实环境确认

### 设计原则
对齐 Parchment 4.0 审美：克制、只用字重不用颜色装饰、无彩色做装饰用途。

---

## 第 3 轮 · Task 3 常用语自动展开
> 状态：已完成 · commit 6e01964 · 2026-08-23

### 做了什么
- Searcher 新增 `findExactHotword(_:scheme:)` — 仅 key 完全相等才算精确匹配
- PhraseKeySettings 新增 `autoExpandHotwords` 配置项，默认 true
- macOS Controller：空格先查精确匹配，命中直接上屏全文
- iOS MobileEngine：space() 同样逻辑
- 前缀匹配不展开，防误触

### 改动文件
- `Sources/PhraseKeyIME/Engine/Searcher.swift` — +15 行
- `Sources/PhraseKeyIME/Settings/PhraseKeySettings.swift` — +2 行
- `Sources/PhraseKeyIME/Controller.swift` — +8 行
- `ios/PhraseKeyKeyboard/MobileEngine.swift` — +7/-1 行

### 验证结果
- ✅ swift build 通过
- ✅ 引擎回归全绿
- ⚠️ 真机/真实输入法环境待用户实测

### 边界处理
- 精确匹配才展开（key 完全相等），前缀匹配不展开
- 功能可关（配置项 autoExpandHotwords）
- 数字键选常用语走正常路径，不受影响

---

## 第 4 轮 · Task 4 iOS 键盘存活稳定性
> 状态：代码走查通过 · 真机验证待用户操作 · 2026-08-23

### 代码走查结果
- ✅ viewDidLoad 同步建 UI（buildUI 在主线程），词库异步加载
- ✅ RequestsOpenAccess = false（避免额外沙盒审计）
- ✅ PrimaryLanguage = zh-Hans（已修复，之前缺导致扩展拉不起来）
- ✅ dict_mobile.tsv 1.2MB 精简版（3 万条，移动端优先用）
- ✅ 引擎就绪前按键降级为直接上屏字符（不阻塞、不崩溃）
- ✅ App Group 共享数据通路（常用语 + 配置）

### 真机验证清单（需用户操作）
1. 删除旧键盘 → 重新添加（清掉系统惩罚记录）
2. 连续使用 20-30 分钟稳定性测试
3. 内存占用实测（真机抓 jetsam 快照）
4. 切换 App 测试：微信 → Safari → 备忘录 → 微信
5. 冷启动测试：锁屏 5 分钟后解锁 → 调出键盘

### 二分法排错预案（如仍不稳定）
往 BareKB 空壳里逐步加功能，每步跑 10 分钟：
- Step 1：只加词库（不加 UI）→ 看内存
- Step 2：加候选栏 UI（不加按键）→ 看渲染
- Step 3：加按键（不加 App Group）→ 看交互
- Step 4：加 App Group → 看数据共享
