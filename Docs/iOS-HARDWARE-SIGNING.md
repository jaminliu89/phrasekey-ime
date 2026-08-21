# PhraseKey iOS 真机签名指南（免费 Apple ID）

> 用**免费** Apple ID（Personal Team）在自己的 iPhone 上运行 PhraseKey，
> 不需要 $99/年的 Apple Developer Program。

---

## 免费账号能做什么 / 不能做什么

| 项目 | 免费账号（Personal Team） | 付费账号（$99/年） |
|------|--------------------------|-------------------|
| 真机运行自己签名的 App | ✅ | ✅ |
| App Groups（键盘 ⇄ 宿主共享短语数据） | ✅ | ✅ |
| 签名有效期 | ⚠️ **7 天**，过期需重新 Run | 1 年 |
| 可注册的 Bundle ID 数量 | ⚠️ 最多 **3 个** | 不限 |
| 发布 App Store / TestFlight | ❌ | ✅ |

**两个免费账号特有的坑：**

1. **7 天过期**：签名 7 天后 App 打不开（提示"无法验证开发者"）。解决：连上 iPhone，
   在 Xcode 里再点一次 **Run**，自动重新签名，又续 7 天。日常开发完全够用。
2. **Bundle ID 全局唯一**：`com.phrasekey.ime` 若已被其他免费账号注册过，会冲突。
   冲突时把 Bundle ID 改一个后缀（如 `com.phrasekey.ime.<你的昵称>`），见下方步骤 4。

---

## 操作步骤（约 10 分钟）

### 前置条件
- macOS 上的 Xcode（已安装并打开本项目 `ios/PhraseKeyIOS.xcodeproj`）
- iPhone 一台，iOS 16 及以上
- 数据线连接 Mac，iPhone 解锁并**信任这台电脑**

### 第 1 步：确认 Apple ID 已登录 Xcode

Xcode 菜单：**Xcode → Settings → Accounts**，确认列表里有你的 Apple ID。
没有就点左下角 **＋ → Apple ID** 登录（用你的 Apple ID 即可，无需付费）。

### 第 2 步：确认签名团队

> **本项目已将 Team ID 写死在 `ios/project.yml`（`DEVELOPMENT_TEAM: 63PZWHLKMU`），
> 跑 `xcodegen generate` 后无需再手动选 Team，直接 ⌘R 即可。**
> 换人签名时，改 project.yml 里的 Team ID 再重新生成。

1. Xcode 左侧选中 **PhraseKeyHost** target（项目导航器里点项目名，再点 PhraseKeyHost）
2. 切到 **Signing & Capabilities** 标签页
3. 确认 **Team** 下拉框显示的是你的 Apple ID（如 "Kurt Gibson (Personal Team)"）
4. 若不是，勾 **Automatically manage signing** 并重新选 Team

> ⚠️ 如果跑 `xcodegen generate` 重新生成项目，Team 来自 project.yml（已内置），无需重选。

### 第 3 步：给键盘扩展选签名团队

同样操作再来一遍：
1. 选中 **PhraseKeyKeyboard** target
2. **Signing & Capabilities** → 勾 **Automatically manage signing** → Team 选同一 Apple ID

（键盘扩展必须和宿主 App 用同一个 Team，否则 embed 时会签名失败。）

### 第 4 步：处理 Bundle ID（如遇冲突）

- `PhraseKeyHost` 的 Bundle ID：`com.phrasekey.ime`
- `PhraseKeyKeyboard` 的 Bundle ID：`com.phrasekey.ime.keyboard`

如果签名时报 **"Bundle ID already used"** 或 provisioning profile 报错：
在各自 target 的 **Signing & Capabilities** 里把 Bundle Identifier 改唯一值，例如：

```
com.phrasekey.ime.<你的昵称>            # PhraseKeyHost
com.phrasekey.ime.<你的昵称>.keyboard  # PhraseKeyKeyboard
```

改完 **App Group** 不用动（`group.com.phrasekey.ime` 与 Bundle ID 无关）。

> 免费账号最多 3 个 Bundle ID：PhraseKey 占 2 个（host + keyboard），
> 还留 1 个给你其他实验项目。

### 第 5 步：真机运行

1. Xcode 顶部设备栏：从 "Any iOS Device" 切到你的 **iPhone**（未显示先插线等几秒）
2. 点 ▶ **Run**（⌘R）
3. 首次会弹 **"iPhone 未信任此开发者"** 之类提示 → 看第 6 步

### 第 6 步：iPhone 上信任开发者

iPhone：**设置 → 通用 → VPN与设备管理 → 开发者 App** →
点你的 Apple ID → 点 **信任**。

> 这一步只在第一次签名时做；7 天后重新签名若提示"无法验证开发者"，
> 回到这里再信任一次即可。

### 第 7 步：启用 PhraseKey 键盘

iPhone：**设置 → 通用 → 键盘 → 键盘 → 添加新键盘** → 选 **PhraseKey**。

然后**务必打开完全访问**（否则键盘和宿主 App 之间无法通过 App Group 共享短语数据）：

**设置 → 通用 → 键盘 → PhraseKey → 打开"允许完全访问"**。

---

## 日常开发循环（免费账号）

```
改代码 → 连 iPhone → Xcode ⌘R → 真机验证
```

每 **7 天**重新 ⌘R 一次即可续签，其他什么都不用做。

---

## 常见报错

| 报错 | 原因 | 解决 |
|------|------|------|
| `No profiles for 'com.phrasekey.ime' were found` | Team 没选 / project.yml 没配 | 确认 project.yml 的 DEVELOPMENT_TEAM 后重新 `xcodegen generate` |
| `App has not been granted permission to use this App Group` | 键盘没开完全访问 | 做第 7 步 |
| `Unable to launch ... cannot verify developer` | 签名过期 | 重连 iPhone，Xcode ⌘R 续签，再信任一次 |
| `Bundle ID already used` | Bundle ID 被占用 | 做第 4 步改唯一后缀 |
| `Signing for "PhraseKeyKeyboard" requires a development team` | 键盘扩展没选 Team | 做第 3 步 |

---

## 卸载

iPhone 上删掉 PhraseKey App（键盘会自动移除）；想彻底清掉设备上的开发者配置：
**设置 → 通用 → VPN与设备管理 → 删除你的开发者 App 描述文件**。
