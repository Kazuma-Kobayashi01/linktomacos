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
