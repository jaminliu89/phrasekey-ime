# PhraseKey iOS Alpha：公开协作接手说明

## 项目目标

PhraseKey 是 iOS 优先的实验性中文输入与快捷短语工具；核心不是输入历史，而是用户主动保存、检索和复用的快捷短语资产。

目标闭环：复制一段有用文字 → 键盘顶部「短语」→ `＋` → 保存 → 短语列表或快捷码召回 → 一键上屏。短语需按最新保存排序，并可在键盘内导出 `.xlsx`。

## 当前真实状态

- iOS 键盘基于 HamsterKeyboardKit，中文输入核心和短语工作区已接入。
- App Group `group.com.phrasekey.ime` 已签名；键盘扩展可访问共享容器并创建导出目录。
- `.xlsx` 导出已实现为本地生成后拉起系统分享页。
- Host App 当前存在黑屏启动问题，不能作为验收路径。
- 快捷短语从键盘 `＋` 保存的真机闭环尚未通过，需优先修复并提供 UI 证据。

## P0：请优先解决

1. 在真机复现并修复键盘内保存失败，保存后确认 App Group 的 `PhraseKey/hotwords.json` 发生变化。
2. 保证键盘工具栏的「短语」文字入口、`＋`、导出按钮在浅色和深色模式下均可见、可点。
3. 真机走通：保存一条测试短语 → 退出再打开仍存在 → 点按上屏 → 快捷码候选上屏 → 导出 `.xlsx` 并用 Numbers／Excel／WPS 打开。
4. 修复 Host App 黑屏，作为键盘设置与高级管理页，但不让核心短语闭环依赖它。

## 验收纪律

- 不能以 `BUILD SUCCEEDED` 代替 UI 验收。
- 不上传、提交或内置任何用户的真实短语、剪贴板内容、签名文件、App Group 数据或 DerivedData。
- 用户主动点击「剪贴板」或 `＋` 才可读取剪贴板；禁止后台读取或自动保存完整输入历史。
- 基础中文输入不得因快捷短语候选受到破坏。

## 构建

```bash
cd ios/HamsterBase
xcodebuild -project Hamster.xcodeproj -scheme Hamster -configuration Debug \
  -destination 'generic/platform=iOS' build
```

真机需要自行配置 Apple Development Team 与 App Group；不要提交个人 provisioning profile 或证书。

## 贡献方式

提交 PR 时请附：复现步骤、真机机型／iOS 版本、修改范围、构建命令、以及不包含私人内容的 UI 截图或录屏。一个 PR 只解决一个可验证问题。
