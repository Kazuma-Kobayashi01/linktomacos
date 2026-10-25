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

## 下一步：投屏时用电脑的扬声器和麦克风（计划，尚未开始）

目标：投屏时，手机里应用的声音从 Mac 扬声器出来；Mac 麦克风的声音能被手机上的应用当作麦克风输入（语音消息、视频通话等）。两个方向难度差很多，分开做，先做声音输出。

### 一、手机声音 → Mac 扬声器（把握较大）

做法参考 scrcpy 的音频转发（Apache-2.0，已在 THIRD_PARTY_NOTICES 里致谢）：

- shell 服务里用 `AudioRecord` 的 `REMOTE_SUBMIX` 音源录系统混音。shell 身份不需要 App 的录音权限，也不需要每次弹 MediaProjection 授权。需要用伪造的 `com.android.shell` 上下文来构造，和现在读屏的做法一样。
- 编码成 Opus（`MediaCodec` 的 audio/opus 编码器，Android 10+）；没有就退到 AAC-LC。48 kHz 立体声。
- 传输：shell → 手机 App 新增一种帧（类型 3，音频包，带 pts）→ 现有加密连接上的第二条数据流（和视频同一套流控，音频优先，不丢帧）。`mirrorStart` 加 `audio: Bool`，结果里带 `audioStreamId`。
- Mac：`AVAudioConverter` 解码，`AVAudioEngine` + `AVAudioPlayerNode` 播放，做一个 80～150 ms 的抖动缓冲；音画同步先不做精确对齐，只保证延迟别超过 200 ms。
- 手机是否同时外放：`REMOTE_SUBMIX` 会把声音从手机本体抢走，所以默认手机静音、只有 Mac 出声，正好适合息屏用。需要“手机也响”时，再评估 Android 13+ 的副本捕获方式。

待验证（决定做不做）：
1. One UI 7 上 shell 身份能否创建 `REMOTE_SUBMIX` 的 `AudioRecord`，以及息屏、锁屏时还有没有数据。
2. 独立显示（虚拟显示器）上的应用声音，是否也进系统混音。
3. Opus 编码器在 `c2` 系列里有没有；Mac 端 `AVAudioConverter` 解 Opus 的延迟。

### 二、Mac 麦克风 → 手机应用的麦克风输入（风险高，先做验证）

Android 没有公开的“注入麦克风”接口，有两条路，各做一个验证：

- **路线 A：音频策略回环（AudioPolicy + 回环混音）**。shell 身份可能拿得到 `MODIFY_AUDIO_ROUTING`，构造一个只匹配 `MIC` 采集预设的回环混音，再用一个 `AudioTrack` 往里写 Mac 传来的 PCM。成功的话任何应用录音都会拿到 Mac 的声音，音质好。风险：三星可能限制，接口在不同版本里不一样。
- **路线 B：蓝牙 HFP**。把 Mac 当作免提耳机连到手机，手机应用走蓝牙 SCO 录音。`spikes/hfp-spike` 是为通话做的，同一条链路可以顺便给应用提供麦克风。优点是不依赖隐藏接口；缺点是音质低（窄带 / 宽带语音），要等 HFP 验证有结果。
- 两条都不通：麦克风只在通话里可用（走将来的通话功能），并在界面里说明。

Mac 端采集：`AVAudioEngine` 开启语音处理（回声消除），否则 Mac 扬声器播出来的手机声音会被麦克风再录进去，形成回声。需要在 Info.plist 加麦克风用途说明（已有本地化流程）。

### 三、界面与设置

- 投屏窗口底部栏“⋯”菜单：声音开关、麦克风开关（麦克风默认关，开启时有明显指示）。
- 设置 → 投屏：默认是否转发声音、是否使用麦克风、音量。
- 菜单栏的“投屏”菜单加静音（⇧⌘M）。
- 所有新文字走现有的翻译脚本（简中、繁中、英、日）。

### 四、里程碑（每步都能单独验收）

| 步骤 | 内容 | 验收 |
|---|---|---|
| A1 | 手机端音频捕获 spike：`--selftest` 里加音频项，只读检查接口，再录 1 秒到日志（不播放） | 自检通过，息屏时也有数据 |
| A2 | 音频流打通：Opus 编码 → 数据流 → Mac 解码播放，先不做界面 | 能听到，延迟 < 200 ms，热点下不卡 |
| A3 | 界面、设置、静音、翻译、单元测试（帧编解码、协议字段） | 开关生效，重启后记住 |
| B1 | 麦克风 spike：路线 A 和路线 B 各做一个最小验证 | 选定一条，或决定放弃 |
| B2 | 麦克风流打通 + 回声消除 + 界面 | 在手机的语音消息 / 通话应用里能被听到 |

### 五、风险与取舍

- 音频捕获接口在 Android 15 / One UI 7 上的行为未知，所以 A1 先只验证，不写完整功能。
- 增强服务的版本号要加 1（`ShellMain.VERSION` 和 `SHELL_VERSION`），安装后必须重启服务，否则 App 会提示“版本过旧”。
- 电量和带宽：Opus 约 64～128 kbps，相对视频可以忽略；麦克风回传同量级。
- 隐私：麦克风默认关，开着时窗口里有指示；音频只走已有的加密连接，不落盘。
- 不在范围内：多路混音、手机侧的音效处理、蓝牙耳机转发。

### A1 结果（2026-10-25，S23 Ultra / One UI 7 / Android 15）

在手机上用 `ShellMain --audio-selftest` 实测（独立进程，不碰已安装的 App 和正在运行的服务）：

- shell 身份可以创建 `REMOTE_SUBMIX` 的 `AudioRecord`（`Builder.setContext(伪造的 shell 上下文)`），不需要 RECORD_AUDIO 权限，不弹授权。
- 能读到数据：1.5 秒读到 288000 字节，正好是 48 kHz 立体声 16 位的 1.5 秒；同时播放的 440 Hz 提示音峰值 3000，和写入的振幅一致，说明读到的是真实的系统混音，不是静音。
- 有 Opus 编码器（`c2.android.opus.encoder`）和 AAC 编码器（`c2.sec.aac.encoder` 等），所以 A2 直接用 Opus。
- 还没验证：屏幕关闭或锁屏时是否仍有数据；虚拟显示器上的应用声音是否进混音；录音期间手机本体是不是真的静音（自检时没有核对）；Mac 端 Opus 解码的延迟。这几项放在 A2 里边做边验。

结论：声音输出这条路通，进入 A2。

### A2 状态（2026-10-25）

已实现，尚未在真机上端到端验证：

- 手机：`AudioCapture`（REMOTE_SUBMIX → Opus 编码，20 ms 一包）→ shell 到 App 的音频帧（类型 3）→ App 在第二条数据流上转发（`audioStreamId`，积压丢最旧的）。服务版本升到 3，装完要重启增强服务。
- Mac：`PhoneRemote.mirrorStart` 新增 `audio` 处理器（提前到达的音频包也会按顺序补发）；`AudioPlayer` 用 AudioToolbox 解 Opus，`AVAudioEngine` 播放，先攒 80 ms，积压超过 300 ms 就丢新包，播空了暂停再攒。
- 没有界面：默认开启，用 `defaults write com.linktomacos.mac mirrorAudio -bool false` 关闭（A3 做成界面）。
- 已验证：LinkCore 37 个测试通过（含音频流登记和提前到达的包）；Mac 端用系统编码器生成 Opus，取出原始包再用同样的 `AVAudioConverter` 做法解码，51 个包全部成功，峰值与输入一致。
- 待真机验证：声音是否从 Mac 出、手机是否静音、延迟、息屏时是否还有声音、虚拟显示器上的应用声音、热点下是否卡。

### B1 结果（2026-10-25）：路线 A 可行

在手机上用 `ShellMain --mic-selftest` 实测（独立进程，不碰已安装的 App 和正在运行的服务）：shell 身份可以注册音频策略（MODIFY_AUDIO_ROUTING），里面一个只匹配麦克风类录音预设的回环混音；往它的 AudioTrack 写 440 Hz 提示音（峰值 6000），本进程里一个普通的 `MIC` 录音读到峰值 5526。也就是手机上任何应用用麦克风录音，拿到的都是我们写进去的声音。不需要蓝牙，音质也不受限；路线 B（HFP）只留给通话功能。

### B2 状态（2026-10-25）

已实现，尚未在真机上端到端验证：

- Mac：`AudioPlayer` 和麦克风放在同一个 `AVAudioEngine` 里，打开语音处理（回声消除，扬声器放的手机声音会从麦克风里消掉）和“不压低其他应用声音”；采集后取第一个声道，转成 48 kHz 单声道 16 位，每 20 ms 一包，通过 `micStreamId` 数据流发给手机。需要麦克风权限，第一次会弹系统授权框。
- 手机：App 把 Mac 的数据帧转给增强服务（类型 4），`MicInjector` 注册回环策略并写入 AudioTrack（写不过来时丢最旧的，约 1 秒）。服务版本升到 4，装完要重启服务。
- 传输用 PCM 而不是 Opus：约 768 kbps，相对视频可以接受，没有编解码的延迟和兼容问题；热点下如果觉得占带宽，再换 Opus。
- 没有界面，默认关闭：`defaults write com.linktomacos.mac mirrorMicrophone -bool true` 打开。
- 已验证：LinkCore 38 个测试通过（含 `micStreamId` 和 PCM 数据帧）；Android 构建、单元测试、lint 通过。
- 待真机验证：Mac 麦克风权限弹框；手机上的应用（语音消息、视频通话）能不能听到；回声消除效果；声音延迟；开着麦克风时 Mac 播放手机声音的音质（语音处理会改变输出路径）。
