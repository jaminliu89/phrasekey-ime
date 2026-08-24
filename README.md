# PhraseKey

PhraseKey 是一款实验性的中文输入与快捷短语工具。用户主动保存有用文字，通过快捷码或短语面板在任意输入位置复用。

> 项目处于 iOS Alpha 阶段。请以 [公开协作接手说明](Docs/OPEN-SOURCE-HANDOFF.md) 中的真实状态为准。

## 产品目标

- 实验性中文输入作为日常编辑基础。
- 键盘顶部固定提供「短语」入口。
- 用户主动执行「复制 → 短语 → ＋ → 保存」，不自动收集完整输入历史。
- 已保存短语按最新保存时间优先展示，可通过快捷码召回并一键上屏。
- iOS 优先；后续以同一数据模型接入 macOS 与 Apple 多端同步。

## 当前状态

| 能力 | 状态 |
|---|---|
| 中文输入核心 | 已接入，仍需持续真机回归 |
| 键盘短语入口与面板 | 已实现，需真机 UI 走查 |
| 剪贴板主动保存 | 正在修复真机写入闭环 |
| 键盘内 `.xlsx` 导出 | 已实现，待系统分享与表格应用实机验证 |
| Host App 管理页 | 存在黑屏问题，待修复 |
| CloudKit 与 macOS 同步 | 未开始 |

请勿将构建成功视为功能验收通过。

## 本地构建

```bash
cd ios/HamsterBase
xcodebuild -project Hamster.xcodeproj -scheme Hamster -configuration Debug \
  -destination 'generic/platform=iOS' build
```

真机调试需在 Xcode 中配置自己的开发签名与 App Group。请勿提交证书、provisioning profile、App Group 数据或 DerivedData。

## 数据格式

快捷短语使用开放 JSON：

```json
[
  {
    "hw_id": "1720000000000",
    "text": "您好，方案已经整理好了。",
    "key": "hfa"
  }
]
```

- `hw_id`：保存时的毫秒时间戳。
- `text`：完整短语。
- `key`：用户可记忆的快捷码。

任何开源样例必须使用虚构短语，禁止提交个人剪贴板或真实常用语。

## 参与贡献

优先解决 iOS 真机保存、短语入口可见性、上屏、导出和 Host 黑屏问题。详细验收标准见 [公开协作接手说明](Docs/OPEN-SOURCE-HANDOFF.md) 和 [贡献规范](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)
