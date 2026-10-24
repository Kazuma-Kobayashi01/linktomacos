# LinkToMacOS

让 Android 手机与 macOS 互联，参照“连接到 Windows”复刻。方案与里程碑见 [docs/PLAN.md](docs/PLAN.md)，协议见 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

| 目录 | 内容 |
|---|---|
| `macos/` | Mac 端：SwiftUI 菜单栏 App + `Packages/LinkCore`（协议、TLS 服务、配对） |
| `android/` | Android 端：Kotlin + Jetpack Compose，常驻前台服务 |
| `spikes/hfp-spike/` | 蓝牙 HFP 通话技术验证（命令行） |

## 当前进度：M0 基础

- 二维码配对，双向证书锁定的 TLS 1.3 连接
- Bonjour 自动发现，断线自动重连
- 心跳：5 秒一次，20 秒超时
- Mac 退出或睡眠前通知手机
- 手机电量、信号、网络、存储实时显示在 Mac 菜单栏

## 运行

**Mac**

```bash
cd macos && xcodegen generate && open LinkToMacOS.xcodeproj
```

在 Xcode 中运行即可，App 只显示在菜单栏。首次运行时如果系统询问“本地网络”权限，请选择允许。

测试：

```bash
cd macos/Packages/LinkCore && swift test
```

**Android**（S23 Ultra 先打开 USB 调试或无线调试）

```bash
cd android && ./gradlew installDebug
```

测试：

```bash
cd android && ./gradlew testDebugUnitTest
```

**配对**：Mac 菜单栏 → “配对新手机…”，然后在手机 App 里点“扫码配对 Mac”。

## HFP 通话验证（M0 必做）

1. 在 Mac 的“系统设置 → 蓝牙”里与手机配对。
2. 运行验证工具。首次运行时，终端需要获得蓝牙权限：
   ```bash
   cd spikes/hfp-spike && swift run hfp-spike Galaxy
   ```
3. 按顺序记录以下结果：
   1. 是否出现“✅ HFP 已连接”；
   2. 用另一部手机拨打 S23U，能否看到 📞 来电和号码；
   3. 输入 `a` 能否接听；
   4. 输入 `sco` 后能否看到“✅ 语音链路已打开”，`audio` 的输出里是否出现 🔵 蓝牙音频设备；
   5. 能否用 Mac 的麦克风和扬声器正常通话；
   6. 输入 `e` 能否挂断，`d <号码>` 能否拨出。
