# 连接协议 v1

## 传输

- Mac 作为服务端：TCP，默认端口 `47152`（被占用时改用系统分配的端口）。Bonjour 服务类型为 `_linktomacos._tcp`，TXT 记录中 `fp=<证书指纹前 16 位>`。
- TLS 1.3，**双向证书**，双方均为自签名证书，靠 SHA-256 指纹锁定，不走 CA 校验：
  - 手机：用二维码里的 `fp` 校验 Mac 的证书；
  - Mac：首次配对用一次性令牌接纳手机证书，并记录其指纹；之后只接受已记录的指纹。
- 帧格式：`[4 字节大端长度][UTF-8 JSON]`，单帧最大 1 MiB（大文件和视频以后走独立连接）。
- 每个 JSON 对象都有一个 `type` 字段作为消息类型。

## 配对二维码

```
linktomacos://pair?v=1&n=<Mac 名称>&h=<ip1,ip2>&p=<port>&fp=<sha256 十六进制>&t=<令牌>
```

令牌只能使用一次，有效期 5 分钟。

## 消息

| type | 方向 | 字段 |
|---|---|---|
| `hello` | 手机 → Mac（第一帧） | `protocolVersion` `deviceId` `deviceName` `model` `osVersion` `appVersion` `pairingToken?` |
| `helloAck` | Mac → 手机 | `accepted` `macName` `reason?` |
| `ping` / `pong` | 双向 | `t`（毫秒时间戳） |
| `deviceStatus` | 手机 → Mac | `batteryLevel` `charging` `signalLevel?`(0-4) `networkType?` `carrier?` `wifiConnected` `storageTotal` `storageFree` `timestamp` |
| `notification` | 手机 → Mac | `key` `packageName` `appName` `title` `text` `subText?` `timestamp` `iconPng?`（base64） |
| `notificationRemoved` | 手机 → Mac | `key` |
| `goodbye` | 双向 | `reason`（`quit` / `sleep` / `unpaired` …） |

## 心跳

- Mac 每 5 秒发一次 `ping`，任一方向 20 秒没有收到任何帧，就判定连接断开。
- 手机收到 `goodbye` 或心跳超时，都视为“Mac 已离开”。M1 起会在这时关闭免打扰。

## 投屏（增强服务）

增强服务是手机上以 shell 身份运行的常驻进程（`com.linktomacos.android.shell.ShellMain`，由 Mac 通过 USB 上的 adb 启动，之后不再需要 adb）。
画面和输入的通路：

```
Mac 窗口 ⇄（本协议，加密连接）⇄ 手机 App ⇄（127.0.0.1:47153）⇄ shell 服务 → 读屏、H.264 硬件编码、注入触摸和按键
```

### Mac ↔ 手机 App

| 方法 / 消息 | 说明 |
|---|---|
| `mirrorStatus` | 请求 → `{ready, outdated, port, secret, apkPath, sdk}`。`secret` 是握手密钥，只经加密连接传递。`outdated` 为真表示连上来的 shell 服务是旧版本（重装 App 不会重启它），此时 `ready` 为假，Mac 要通过 USB 重新启动服务 |
| `mirrorStart` | 请求 `{mode, maxSize, bitRate, fps, width, height, app?, forceStop?, audio?, mic?}` → `{streamId, width, height, deviceWidth, deviceHeight, displayId, mode, audioStreamId, micStreamId}`；之后手机在 `streamId` 上发视频包。`audio` 为真时，手机把系统混音编码成 Opus，在另一条数据流 `audioStreamId` 上发音频包（手机本体静音）；没有请求音频时 `audioStreamId` 是 0。`mic` 为真时，手机分配一个 `micStreamId`：Mac 往这个流上发数据帧（Mac → 手机），内容是麦克风 PCM（48 kHz、单声道、16 位小端，没有头，每包 20 ms = 1920 字节），手机把它注入系统的麦克风录音（手机上的应用录音时拿到的是 Mac 的声音）。没有请求麦克风时 `micStreamId` 是 0。`mode`：`new` 在手机里新建一个独立的虚拟显示器（`width`/`height` 是初始像素尺寸，0 表示和手机屏幕同样的宽高比（长边不超过 `maxSize`；`maxSize` 不小于手机长边时，显示器和手机屏幕一样大、dpi 也一样）。应用请求横屏或竖屏时，手机会自动把虚拟显示器的宽高对调，并发 `resized`；`app` 是开始时在上面打开的应用包名），`mirror` 镜像手机主屏 |
| `mirrorResize` | 请求 `{width, height}`，独立显示模式：调整虚拟显示器的像素尺寸，应用按新尺寸重新排版；手机随后发 `mirrorEvent resized` |
| `mirrorLaunch` | 请求 `{package, forceStop}`，独立显示模式：在虚拟显示器上打开应用 |
| `listApps` / `appIcon` | 请求。手机上能启动的应用 `{apps:[{package,label}]}`；某个应用的图标 `{data}`（PNG，base64，96 像素） |
| `mirrorStop` | 请求，停止投屏 |
| `mirrorInput` | Mac → 手机，无响应。`k`：`t` 触摸（`a` 0 按下 1 抬起 2 移动，`x`/`y` 为 0…1 的相对位置）、`s` 滚轮（`h`/`v`）、`key`（`a` 0/1，`c` Android 键值，`m` 修饰键）、`text`、`cmd`（back / home / recents / notifications / wake / power / sync / screenOff / screenOn） |
| `mirrorEvent` | 手机 → Mac。`event`：`resized`（旋转或尺寸变化，带新的 `width`/`height`）、`error`、`stopped` |
| `callState` | 手机 → Mac，无响应，不是请求。`{state, name?, timestamp}`。`state`：`ringing`（来电响铃）、`offhook`（通话中，接通或拨出）、`idle`（空闲，通话结束）。`name` 是来电的联系人名或号码，取自手机上的来电通知，拿不到时为空；响铃期间可能再发一次带名字的 `ringing`。Mac 据此弹出来电提示、播放铃声，不转发通话的声音 |
| `clipboard` | 双向，无响应，不是请求。`{text, timestamp?}`。一端复制了文字就发给另一端，对方写进自己的剪贴板。文本上限 200 000 个字符；刚连上时不发送已有的剪贴板内容，只同步之后的复制。收到的文本要记下来，不能再当作本机新复制的回传。Mac 端跳过带 `org.nspasteboard.ConcealedType` / `TransientType` 的内容，手机端跳过标为敏感（`EXTRA_IS_SENSITIVE`）的内容 |
| `airOffer` | 手机 → Mac，无响应。`{id, files:[{name, size, mime}]}`。AirSend：手机分享出一批文件的清单。Mac 用 `download` 请求逐个来取：`{source:"airsend", offer:id, index}`，沿用普通下载的流程（`streamId`、数据帧、`streamEnd`）。手机在分享时就打开了文件描述符（分享页面关闭后系统给的权限会失效，描述符还能读），清单 10 分钟后或全部取完就作废 |
| `airPush` | Mac → 手机，无响应。`{streamId, name, size, mime}`。AirSend：Mac 推一个文件给手机，紧跟 `streamId` 的数据帧，最后是同一个 `streamId` 的 `streamEnd`。Mac 分配的 `streamId` 从 `0x40000000` 起，和手机分配的不冲突；Mac 逐块等待写入完成，不把整个文件堆在内存里。手机存进“下载/AirSend” |
| `airText` | 双向，无响应。`{text}`。AirSend：一段文字或链接。接收方放进剪贴板并弹通知，是链接时点通知打开 |

视频包走二进制数据帧（见上），内容：`[标志 1 字节][pts 8 字节大端，微秒][H.264 Annex-B 数据]`。标志位 1 = 配置包（SPS/PPS），2 = 关键帧。
音频包格式相同：`[标志 1 字节][pts 8 字节大端，微秒][一个 Opus 包]`，48 kHz 立体声，每包 20 ms，约 128 kbps；标志位 1 = 配置（Opus 头，播放时可以忽略）。音频积压超过约 100 个包时手机丢最旧的，不会拖慢视频。
尺寸变化后手机会先发新的配置包。数据帧可能比 `mirrorStart` 的响应先到，Mac 端会先缓存再补发。

流控：Mac 读得慢时，手机端队列积压超过约 1.5 MB 就丢弃后续非关键帧，直到下一个关键帧，并让编码器立即产生关键帧。

### 手机 App ↔ shell 服务（127.0.0.1:47153）

帧：`[类型 1 字节][长度 4 字节大端][内容]`，类型 1 = JSON，类型 2 = 视频包，类型 3 = 音频包（格式同上），类型 4 = Mac 麦克风的 PCM（App → 服务，没有头）。`start` 指令带 `mic` 时，服务注册一个只匹配麦克风录音的回环音频策略，把类型 4 的数据写进去。`start` 指令带 `audio` 时，shell 用 REMOTE_SUBMIX 录系统混音并编码成 Opus。
剪贴板：App 发 `{t:"clip", on:true|false}` 让服务开始或停止监听手机剪贴板，服务在手机上复制文字时发 `{t:"clip", text}`；App 发 `{t:"clipSet", text}` 让服务写入手机剪贴板。普通 App 在后台读不了剪贴板（Android 10 起），shell 身份可以；服务不可用时 App 只能在回到前台时读一次。
握手是挑战应答：shell 服务连上后发 `hello{nonce}`，App 回 `auth{mac = HMAC-SHA256(secret, nonce)}`，验证通过后 shell 发 `ready`。
密钥不上线，所以即使别的 App 抢先监听了这个端口，也无法冒充 App 控制 shell 服务。
shell 的 `hello` 里带 `v`（服务版本）。App 要求的版本不同就认为服务过期（见上面的 `outdated`）；改了服务的行为要同时加大 `ShellMain.VERSION` 和 `SHELL_VERSION`。
指令：`start{mode,display,maxSize,bitRate,fps,width,height,app,forceStop}`、`resize{width,height}`、`launch{pkg,forceStop}`、`stop`、`sync`、`input{…}`、`screen{on}`；事件：`started`/`resized{mode,width,height,deviceWidth,deviceHeight,rotation,displayId}`、`launched{pkg,ok,message}`、`error`、`stopped`。

独立显示模式的虚拟显示器带这些标志位：可信、独立显示组、始终解锁、独立焦点、移除时销毁内容，并把它的输入法策略设为隐藏（Mac 键盘直接输入，手机上不弹软键盘）。因此手机自己的屏幕可以关掉或锁屏，应用在虚拟显示器上照常运行。投屏期间手机 App 持有部分唤醒锁，保证 CPU 不休眠。
