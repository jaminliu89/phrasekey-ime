# PhraseKey Master Task

> 版本：v2.0
> 日期：2026年08月24日
> 状态：当前唯一任务排序
> 规则：没有端到端证据，不得标记完成

## 一、状态定义

| 状态 | 含义 |
|---|---|
| `DONE` | 已实现且有当前环境端到端证据 |
| `VERIFY` | 有代码或局部测试，用户链路未验收 |
| `DOING` | 当前唯一进行中的工作包 |
| `TODO` | 尚未开始 |
| `BLOCKED` | 有明确阻塞与复现证据 |
| `FROZEN` | 首版冻结 |

## 二、事实基线

| 能力 | 状态 | 事实 |
|---|---|---|
| macOS Release | `VERIFY` | 构建和静态门禁通过，真实注册与跨 App 输入未完成本轮验收 |
| 中文输入 Engine | `VERIFY` | bench通过，仍需 iOS 真机闭环 |
| iOS Host App | `VERIFY` | 已替换为 PhraseKey 资产管理器，支持搜索、新增、编辑、删除和输入测试；待真机 UI 走查 |
| iOS Keyboard | `VERIFY` | 真机签名构建、安装、启动成功；键盘内完整点击闭环待验证 |
| App Group | `VERIFY` | entitlement和路径存在，需真机验证 |
| 快捷短语面板 | `VERIFY` | 顶部“短语”常驻入口、剪贴板/短语页签、`＋` 预览确认、自动快捷码、点击上屏已实现；待真机点击证据 |
| CloudKit同步 | `TODO` | 尚未实现，旧文档中的“已同步”不成立 |
| macOS多端接入 | `FROZEN` | 等 iOS alpha 门禁通过 |

## 三、执行工作包

### WP-00 文档与范围收口

状态：`DONE`

- 更新产品定义、PRD和Master Task。
- 锁定iOS首发、macOS第二阶段。
- 重置虚假完成状态。
- 冻结音形、多方案、AI和非核心工具。

门禁：三份文档对定位、首发端、同步和范围表述一致。2026年08月24日已通过 `git diff --check` 与关键词一致性扫描。

### WP-01 恢复 iOS 构建

状态：`DONE`

- 复现并记录 package graph。
- 对比 `project.yml`、`project.pbxproj` 和 workspace 引用。
- 保留单一 package 声明源，最小化修复重复 `RimeKit`。
- 完成真机签名构建；Simulator 架构债务单独记录，不作为真机首发阻断。
- 不覆盖当前用户未提交的 Xcode 工程修改。

当前诊断：`project.pbxproj` 同时挂载两个外部 Hamster 工程，依赖图各自提供 `RimeKit`，触发重复顶层 package。修复目标是移除 PhraseKey 不使用的外部工程引用，不修改中文输入与快捷短语业务代码。

完成证据：2026年08月24日已移除两份外部工程引用；`plutil -lint` 与 `git diff --check` 通过；通用 iOS 真机目标使用 Apple Development 签名构建成功，Host App 与 Keyboard Extension 嵌入验证通过。Simulator 构建在链接阶段因遗留 `librime.xcframework` 无 arm64-simulator slice 失败，已列入底座瘦身任务，不虚报通过。

### WP-02 iOS 中文输入生存门禁

状态：`DOING`

- 安装、启用与 Full Access 降级。
- 验证候选、删除、空格、回车、分隔符、中英文、数字和符号。
- 验证首帧、词库加载和内存。
- 微信、备忘录、Safari真机输入。
- 切换键盘20次，锁屏解锁后复测。

### WP-03 快捷短语交互原型

状态：`VERIFY`

- 顶部工具栏：短语、添加、剪贴板、更多。
- 最近、置顶、分组、搜索和空状态。
- 键盘内主动新增确认；复杂编辑由 Host App 承担。
- 覆盖默认、加载、空、失败、无权限和离线状态。
- 参考对标截图完成正式 UI；待真机可点击证据。

### WP-03A iOS 键盘底座迁移

状态：`VERIFY`

- 冻结旧 `UIStackView` 手写键盘，只保留回退能力。
- 以 Hamster commit `6569370` 的 `HamsterKeyboardKit` 作为 iOS 键盘外壳。
- 已移除无关 `HamsterFileServer`，workspace 内隔离构建通过。
- 已嵌入 PhraseKey 中文输入核心和移动词库，并用 `MobileEngine` 接管标准输入路径。
- 适配完成后移除临时 RimeKit 与 librime 二进制。

### WP-04 本地快捷短语闭环

状态：`VERIFY`

- 统一 `QuickPhrase` 契约并迁移旧 `Hotword`。
- 打通 Host App、App Group和Keyboard Extension。
- 已实现“复制文字 → 点＋ → 剪贴板自动带入预览 → 自动建议快捷码 → 确认保存”；手动编辑放在 Host App。
- 最近上屏只保留为可选能力，首版不默认记录、不自动保存。
- Host App 默认按保存时间倒序展示，并可一键导出完整短语库为 `.xlsx`；待真机点按与文件打开证据。
- 已实现按键建议和即时索引刷新；冲突提示待补。
- 实现最近、置顶、搜索和真实分组。
- 重启、升级和迁移不丢数据。

### WP-05 CloudKit多端同步

状态：`TODO`

- 配置 CloudKit Container、entitlement与schema。
- Host App增量上传、下载、游标和重试。
- 定义更新、软删除和冲突合并。
- 远端变化原子写入App Group本地库。
- 验证双端、离线、删除不复活和同步故障降级。

### WP-06 iOS发布门禁

状态：`TODO`

- 30分钟真机持续输入。
- 多App兼容测试。
- 断网、同步失败、App Group不可写、Full Access关闭测试。
- 首装、升级、重启、导入导出和隐私验收。
- 生成可安装alpha产物和真实交付记录。

### WP-07 macOS接入

状态：`FROZEN`

解冻条件：WP-06完成。复用相同模型和CloudKit，完成中文输入、短语召回、管理和跨端同步。

## 四、冻结清单

附加编码方案、AI、图片、文件、语音、翻译、表情、皮肤、团队共享、Windows、Android、自动采集输入历史、高级模板和插件均冻结。

## 五、当前下一步

当前执行WP-02：最新包已签名安装到连接设备；等待设备可镜像操作后完成键盘启用、短语新增、快捷码召回、点击上屏及重启持久化的真实输入门禁。并行清理遗留 Rime 链接，使底座恢复 Simulator 可测。

---

更新记录：2026年08月24日，v2.0，按iOS首发、快捷短语核心和CloudKit同步重建任务顺序。
