# LinkToMacOS 方案（已按实际环境调整）

环境：Samsung Galaxy S23 Ultra 港版（One UI 7 / Android 15）· macOS 15+ · 免费 Apple 账号 · 仅自用 · 接受无线调试 / Shizuku。

## 功能与优先级

| # | 功能 | 核心技术 | 风险 | 阶段 |
|---|---|---|---|---|
| 1 | 通知推送 + 连接时自动免打扰 | NotificationListenerService · AutomaticZenRule · UNUserNotificationCenter | 低 | M1 |
| 6 | macOS 小组件 | WidgetKit + App Group | 低 | M1 |
| 4 | Finder 位置 | NSFileProviderReplicatedExtension + MANAGE_EXTERNAL_STORAGE | 中 | M2 |
| 3 | 相册浏览 / 复制 | 复用 #4 的文件层，条目即 File Provider URL | 中 | M2 |
| 5 | 投屏 / 反控 / 单应用 | shell 权限服务端（无线调试或 Shizuku）+ H.264 + VideoToolbox | 中 | M3 |
| 2 | 电脑接打电话 | 蓝牙 HFP，Mac 作为免提端（IOBluetoothHandsFreeDevice） | 高 | M4（M0 先做验证） |

## 里程碑

- **M0 基础**：二维码配对、双向证书锁定 TLS、帧协议、心跳、断线重连、前台服务、菜单栏 App。同时验证 HFP（`spikes/hfp-spike`）。
- **M1**：通知（回复 / 清除同步 / 应用过滤）+ 自动免打扰 + 设备状态 + 小组件。
- **M2**：远程文件服务 → File Provider → 相册窗口。
- **M3**：全屏投屏和反控 → 单应用虚拟显示器。
- **M4**：通话（根据验证结果选方案 A / B / C）。

## 针对 S23 Ultra / One UI 7 的注意点

- **保活**：设置 → 电池 → 后台使用限制 → 将本应用加入“从不休眠的应用”；应用电池设置选“不受限制”。
- **自动拦截器（Auto Blocker）** 必须关闭，否则会拦截侧载安装和 USB/调试命令。
- **受限设置**：用 `adb install` / Android Studio 安装通常不会触发；若从文件管理器安装，需在“应用信息 → ⋮ → 允许受限制的设置”中放行，才能打开通知访问权限。
- **免打扰**：One UI 7 的“模式”应能显示我们的 AutomaticZenRule，M1 时需在真机上验证。
- **无线调试**：开发者选项 → 无线调试；同时打开“停用 adb 授权超时”，避免 7 天后授权失效。重启或换 Wi‑Fi 后需重新拉起 shell 服务端。
- 三星自带“连接至 Windows”的特权，我们拿不到，这也是反控必须走 shell 权限的原因。

## 免费 Apple 账号的影响

- **M0**：主 App 用“Sign to Run Locally”（ad-hoc 签名）即可，不开沙盒；身份密钥存在文件里，不依赖钥匙串，避免每次重新编译后弹钥匙串授权。
- **M1 起**：小组件和 File Provider 扩展需要个人团队签名（Xcode → Settings → Accounts 登录 Apple ID）。App Group 使用 macOS 的 `<TeamID>.com.linktomacos` 形式，不需要描述文件授权。若扩展因签名无法加载，再考虑付费账号。
