# PhraseKey Master Task — 架构与任务总览

> 版本：v1.0
> 日期：2026-08-23
> 视角：解决方案架构师（SA） / 技术负责人
> 状态：活文档

---

## 一、技术架构总览

### 1.1 分层架构

```
┌─────────────────────────────────────────────────────────┐
│  Shell 层（平台相关，薄壳）                              │
│  ┌──────────────┐  ┌──────────────────────┐            │
│  │ macOS IMK    │  │ iOS Keyboard Ext     │            │
│  │ Controller   │  │ KeyboardViewController│           │
│  └──────┬───────┘  └──────────┬───────────┘            │
└─────────┼─────────────────────┼─────────────────────────┘
          │                     │
┌─────────▼─────────────────────▼─────────────────────────┐
│  Engine 层（平台无关，纯 Foundation）                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ Searcher │ │ PinyinEng│ │ FlypyCode│ │ CodeTable│  │
│  │ 排序融合  │ │ 词库查询  │ │ 双拼编解码│ │ 形码过滤  │  │
│  └─────┬────┘ └─────┬────┘ └─────┬────┘ └─────┬────┘  │
└────────┼─────────────┼───────────┼──────────────┼──────┘
         │             │           │              │
┌────────▼─────────────▼───────────▼──────────────▼──────┐
│  Data 层（开放格式，可同步）                             │
│  ┌──────────────┐ ┌────────────┐ ┌─────────────────┐  │
│  │ HotwordsStore│ │ PinyinDict │ │ PhraseKeySettings│  │
│  │ 常用语 JSON   │ │ TSV 词库   │ │ config.json      │  │
│  └──────────────┘ └────────────┘ └─────────────────┘  │
│  数据目录：~/Library/Application Support/PhraseKey/     │
│  可指向 iCloud Drive / 任意同步盘 / Git 仓库             │
└─────────────────────────────────────────────────────────┘
```

### 1.2 核心设计原则

1. **引擎层纯 Foundation**：不依赖 AppKit / UIKit，Mac 和 iOS 共用同一套
2. **Shell 层尽量薄**：只做平台 API 对接 + UI 渲染，业务逻辑全在 Engine
3. **数据格式开放**：JSON / TSV，人可读、git 可 diff、脚本可处理
4. **资源分档**：桌面用全量词库（20 万条），iOS 键盘用精简版（3 万条）
5. **优雅降级**：词库未加载 → 按键直接上屏；码表不存在 → 退化为纯双拼

### 1.3 技术选型理由

| 决策 | 选择 | 理由 |
|------|------|------|
| 语言 | Swift | Apple 生态原生，性能足够，内存安全 |
| Mac 端框架 | InputMethodKit | 系统官方输入法框架，虽然坑多但是唯一正路 |
| iOS 端 | UIInputViewController | 系统键盘扩展标准接口 |
| 包管理 | Swift Package Manager | 原生，无需额外依赖 |
| UI 方案 | 手动绘制（Mac）+ Auto Layout（iOS） | Mac 候选栏用 NSView 自绘更灵活；iOS 键盘必须用约束否则被系统判定失效 |
| 数据格式 | JSON + TSV | 开放、可 diff、脚本友好 |
| 词库索引 | Dictionary<String, [Int32]> | 简单直接，3 万条规模完全够用；未来瓶颈了再上 mmap 二进制词库 |
| 测试 | XCTest + 脚本基准测试 | 单元测试 + 性能基准 |

---

## 二、当前状态盘点

### 2.1 已完成

- ✅ 基础 IMK 骨架（Mac 端 Controller / ServerDelegate）
- ✅ 拼音引擎（音节表 417 个、切分器窗口 6 字符）
- ✅ 小鹤双拼编解码（含零声母 o 规则、w/y 掩音修正）
- ✅ Searcher 排序融合（常用语 + 词库 + 覆盖度主排序 + 词频 tiebreak）
- ✅ 常用语数据层（HotwordsStore，CRUD + 搜索 + CSV/JSON 导入）
- ✅ Mac 端候选栏（CandidatePanel，Gboard 风格，但配色需要改）
- ✅ Mac 端常用语面板（PhrasesPanel）
- ✅ iOS 键盘扩展 UI（Auto Layout 全约束，存活问题已定位）
- ✅ iOS 词库精简版（3 万条 dict_mobile.tsv）
- ✅ 用户自学习（learned_dict.tsv + debounce 写盘）
- ✅ 形码过滤代码路径（CodeTable，需用户自备码表）
- ✅ App Group 共享数据（iOS 端配置持久化已通）

### 2.2 已知问题

- ❌ **双拼没有分号选词**——老用户第一分钟就撞上
- ❌ **候选栏配色乱**——蓝字黑字混在一起，没有层次
- ❌ **iOS 键盘不稳定**——词库异步加载导致首帧空白，系统惩罚性拉黑（根因已定位，修复待验证）
- ❌ **iOS 键盘读不到常用语**——HotwordsStore 在键盘扩展里 return 空
- ❌ **常用语没有自动展开**——还停留在候选栏显示阶段
- ❌ **iOS 没有常用语管理界面**——只能在 Mac 端加
- ❌ **没有设置 UI**——改配置要手动编辑 JSON

### 2.3 技术债

| 项目 | 严重度 | 说明 |
|------|--------|------|
| 词库索引内存 | 中 | 3 万条 × 3 份索引 + Dictionary 开销，移动端 10MB+，未来词库扩容会成瓶颈 |
| 自学习只在桌面端 | 高 | iOS 键盘扩展沙盒限制导致用户词典无法写盘，学习数据丢失 |
| 没有单元测试覆盖 UI 层 | 中 | Engine 层有回归测试，但 UI 全靠人眼 |
| 配置没有 schema 校验 | 低 | 用户手动改 JSON 改错了不会提示 |

---

## 三、Milestone 规划

### M0：生存（v0.3）—— 1 周

**目标：键盘稳定可用，核心交互不别扭**

P0 任务：
1. 双拼分号/引号选词
2. 候选栏视觉重做（灰度字重体系）
3. iOS 键盘存活稳定性修复 + 真机验证
4. 常用语自动展开（空格触发）

### M1：核心体验（v0.4）—— 2 周

**目标：常用语闭环，自学习跑通**

P1 任务：
5. iOS 常用语数据打通（App Group + HotwordsStore 适配键盘扩展沙盒）
6. iOS 宿主 App 常用语管理界面
7. 常用语管理面板完善（搜索优化 + 批量导入导出）
8. 自学习机制 iOS 端适配（共享容器写入）
9. Mac 设置面板（可视化配置，不用手改 JSON）

### M2：方案完备（v0.5）—— 2 周

**目标：多种输入方案，高级功能**

P2 任务：
10. 多种双拼方案（自然码 / 微软双拼 / 紫光双拼）
11. 模糊拼音支持
12. 形码过滤测试 + 完善
13. iOS 设置界面
14. 候选排序可配置化

### M3：产品化（v1.0）—— 2 周

**目标：可以对外发布**

15. 官网 / 介绍页
16. 使用文档（快速上手 + 高级配置 + 常见问题）
17. 安装体验优化（Mac 端安装脚本 + iOS TestFlight）
18. 性能优化（冷启动 + 内存）
19. 全量回归测试

---

## 四、当前迭代（M0 / v0.3）任务拆解

### Task 1：双拼分号/引号选词

**文件改动**：
- `Sources/PhraseKeyIME/Controller.swift` — Mac 端按键处理，加 `;` 和 `'` 的特殊逻辑
- `ios/PhraseKeyKeyboard/KeyboardViewController.swift` — iOS 端按键处理，同样逻辑

**实现要点**：
```swift
// 伪代码
case ";":
    if isComposing && candidates.count >= 2 {
        commit(at: 1)  // 选第 2 个
    } else {
        insertText(";")
    }
case "'":
    if isComposing && candidates.count >= 3 {
        commit(at: 2)  // 选第 3 个
    } else {
        insertText("'")
    }
```

**边界处理**：
- 候选不足时直接上屏符号
- 选中态不移动，直接提交
- 全拼模式默认关闭（配置项留口子）

**验收标准**：
- 双拼模式下，打 `nih` → 候选有「你好」「你」「拟」→ 按 `;` → 上屏第 2 个
- 没有输入时按 `;` → 直接上屏分号
- 只有 1 个候选时按 `;` → 直接上屏分号

---

### Task 2：候选栏视觉重做

**文件改动**：
- `Sources/PhraseKeyIME/UI/CandidatePanel.swift` — Mac 端候选栏
- `ios/PhraseKeyKeyboard/KeyboardViewController.swift` — iOS 端候选渲染
- 新增 `Sources/PhraseKeyIME/UI/Theme.swift` — 统一主题常量（两端复用）

**改动清单**：

| 改动项 | 当前 | 改成 |
|--------|------|------|
| 候选文字（未选中） | 黑色 text 常量 | 近黑（#1A1A1A），Regular 字重 |
| 候选文字（选中） | 蓝色 accent | 近黑（同未选中），Medium 字重，靠背景区分 |
| 序号数字 | 选中时蓝色 | 始终灰色，选中时字重加重 |
| 选中态 | 蓝色背景 + 蓝色文字 | 浅灰背景 + 加字重 |
| 拼音串颜色 | 蓝色 | 灰色，Regular 字重 |
| 常用语 ⌘ 标记 | 灰色 | 同序号灰色，保持一致 |

**主题体系**：
```swift
enum PhraseKeyTheme {
    // 颜色只用灰度 + 一个极弱的强调色（用于调试/特殊标记）
    enum Light {
        static let text = #colorLiteral(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)      // 正文
        static let textSelected = #colorLiteral(red: 0.1, green: 0.1, blue: 0.1, alpha: 1) // 选中同色，靠字重
        static let sub = #colorLiteral(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)         // 次要文字（序号、标记）
        static let subSelected = #colorLiteral(red: 0.4, green: 0.4, blue: 0.4, alpha: 1) // 选中时次要文字加重
        static let background = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
        static let highlight = #colorLiteral(red: 0.94, green: 0.94, blue: 0.94, alpha: 1) // 选中背景
        static let border = #colorLiteral(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
    }
    enum Dark {
        // ...对应深色版
    }
    // 字重体系
    enum Weight {
        static let text = NSFont.Weight.regular
        static let textSelected = NSFont.Weight.medium
        static let sub = NSFont.Weight.semibold  // 小字号需要更粗才能看清
    }
}
```

**验收标准**：
- 整体风格克制，没有扎眼的蓝色
- 选中态靠背景色 + 字重区分，一目了然
- 深色模式同样干净
- Mac 和 iOS 视觉一致

---

### Task 3：iOS 键盘存活稳定性修复

**根因回顾**（已定位，见 iOS 键盘扩展存活实录）：
1. viewDidLoad 里词库异步加载 → UI 延迟构建 → 系统判定键盘加载失败 → 惩罚性拉黑
2. 词库太大（20 万条）→ 内存超预算 → 被 jetsam 杀
3. RequestsOpenAccess: true → 额外沙盒审计路径

**修复状态**：代码层面已修复（同步建 UI + 3 万条词库 + RequestsOpenAccess=false），待真机验证。

**剩余工作**：
- [ ] 真机安装 + 删除旧键盘 + 重新添加（清掉系统惩罚记录）
- [ ] 连续使用 20-30 分钟稳定性测试
- [ ] 内存占用实测（真机抓 jetsam 快照）
- [ ] 切换 App 测试（微信 → Safari → 备忘录 → 微信）
- [ ] 冷启动测试（锁屏 5 分钟后解锁 → 调出键盘）

**如果仍不稳定**：
- 二分法定位：往 BareKB 空壳里逐步加功能
  - Step 1：只加词库（不加 UI）→ 看内存
  - Step 2：加候选栏 UI（不加按键）→ 看渲染
  - Step 3：加按键（不加 App Group）→ 看交互
  - Step 4：加 App Group → 看数据共享
- 每一步都跑 10 分钟，哪一步开始出问题就是哪一步的锅

---

### Task 4：常用语自动展开

**文件改动**：
- `Sources/PhraseKeyIME/Engine/Searcher.swift` — 增加「精确匹配常用语」查询接口
- `Sources/PhraseKeyIME/Controller.swift` — Mac 端空格处理，加自动展开逻辑
- `ios/PhraseKeyKeyboard/KeyboardViewController.swift` — iOS 端空格处理，同样逻辑
- `Sources/PhraseKeyIME/Settings/PhraseKeySettings.swift` — 加配置项

**实现逻辑**：
```swift
// 空格按下时
func spacePressed() {
    // 1. 检查是否有常用语 key 精确匹配
    if let hotword = Searcher.shared.findExactHotword(composing) {
        // 2. 自动展开：删拼音 + 插全文
        deleteComposing()
        insertText(hotword.text)
        return
    }
    // 3. 否则正常上屏首选
    commitFirstCandidate()
    insertText(" ")
}
```

**配置项**：
- `autoExpandHotwords: Bool`（默认 true）
- `autoExpandTrigger: String`（默认 "space"，预留 "enter"/"tab"）

**边界情况**：
- 用户按数字键 1 选常用语 → 正常上屏，不触发自动展开逻辑
- 多个常用语匹配（精确 + 前缀）→ 只有精确匹配才自动展开
- 自动展开关闭时 → 常用语在候选栏正常显示，按空格上屏首选 + 空格

---

## 五、风险与应对

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| iOS 键盘稳定性修复后仍不稳定 | 中 | 高 | 二分法定位 + 降功能（先保证最基本的拼音输入） |
| 词库索引内存移动端瓶颈 | 低 | 中 | 二进制词库 + mmap 方案（已做技术储备） |
| 自学习 iOS 端写盘失败 | 中 | 中 | App Group 共享容器写入 + 宿主 App 合并 |
| Mac 端 IMK 兼容性问题（不同 App 行为不一致） | 高 | 中 | 主流 App 逐一测试 + 兼容列表 |
| 审核被拒（iOS 键盘扩展） | 低 | 高 | 严格遵守键盘扩展审核指南，不碰隐私 API |

---

## 六、质量门禁

每个版本发布前必须通过：

### 功能测试
- [ ] 全拼输入常用词准确
- [ ] 双拼输入常用词准确
- [ ] 分号选词正确
- [ ] 常用语增删改查正常
- [ ] 常用语自动展开正确
- [ ] 自学习生效（选词后下次靠前）
- [ ] 深色模式正常
- [ ] 数据导入导出正常

### 性能测试
- [ ] 冷启动 < 300ms（iOS）/ < 100ms（Mac）
- [ ] 候选响应 < 16ms
- [ ] 内存 < 30MB（iOS 键盘扩展）

### 稳定性测试
- [ ] 连续使用 30 分钟不崩溃
- [ ] 切换 10 个 App 键盘都正常弹出
- [ ] 锁屏后解锁键盘正常

### 回归测试
- [ ] Engine 层 10 项基准测试全绿（音节表 + 切分器 + 编解码）
- [ ] Searcher 排序稳定性测试（同输入同顺序）

---

## 七、目录结构与文件职责

```
phrasekey-ime/
├── Sources/PhraseKeyIME/
│   ├── main.swift                 # 入口
│   ├── Controller.swift           # Mac 端 IMK 控制器（按键处理 + 候选管理）
│   ├── ServerDelegate.swift       # IMK Server 委托
│   ├── Engine/
│   │   ├── PinyinEngine.swift     # 拼音引擎（词库加载 + 索引 + 查询）
│   │   ├── PinyinSyllable.swift   # 音节表 + 切分器
│   │   ├── FlypyCodec.swift       # 小鹤双拼编解码
│   │   ├── CodeTable.swift        # 形码表（用户自备）
│   │   └── Searcher.swift         # 搜索融合（常用语 + 词库 + 排序）
│   ├── Hotwords/
│   │   └── HotwordsStore.swift    # 常用语数据层（CRUD + 搜索 + 导入导出）
│   ├── Settings/
│   │   ├── InputScheme.swift      # 输入方案枚举
│   │   ├── PhraseKeySettings.swift# 配置加载保存
│   │   └── SettingsWindow.swift   # Mac 设置窗口
│   ├── UI/
│   │   ├── CandidatePanel.swift   # Mac 候选栏
│   │   ├── PhrasesPanel.swift     # Mac 常用语面板
│   │   └── Theme.swift            # ← 新增：统一主题常量
│   └── Resources/
│       ├── dict.tsv               # 桌面全量词库（20 万条）
│       └── dict_mobile.tsv        # 移动精简词库（3 万条）
├── ios/
│   ├── PhraseKeyHost/             # iOS 宿主 App
│   │   └── PhraseKeyHostApp.swift # 宿主入口（常用语管理 + 设置）
│   ├── PhraseKeyKeyboard/         # iOS 键盘扩展
│   │   ├── KeyboardViewController.swift  # 键盘主控制器
│   │   └── MobileEngine.swift     # 移动版引擎封装
│   └── project.yml                # xcodegen 配置
├── Tests/
│   ├── Bench/main.swift           # 性能基准测试
│   └── Probe/main.swift           # 内存探针
├── Scripts/                       # 构建、安装、测试脚本
├── Docs/                          # 文档（本文件所在目录）
└── README.md
```

---

*更新日志：*
- *2026-08-23：v1.0 首版。完整架构盘点 + M0 任务拆解 + 质量门禁。*
