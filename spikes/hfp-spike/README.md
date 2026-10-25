# hfp-spike：蓝牙 HFP 实验

验证 Mac 能不能作为“蓝牙耳机”（免提设备）接打手机电话。**结论：不行。** HFP 连接、来电和通话状态都能用，
但语音链路（SCO）在 macOS 15 / Apple 芯片上返回 `kIOReturnUnsupported`（`0xE00002C7`），通话的声音到不了 Mac。
所以应用只做来电提示，不转发通话声音。完整结果和取舍见 [docs/PLAN.md](../../docs/PLAN.md) 的“C0 结果”。

这个工具留作记录，也可以在别的 Mac 上重新验证。

## 用法

1. 在 Mac 的“系统设置 → 蓝牙”里与手机配对；手机配对时允许“通话音频”（三星在蓝牙设置里每个设备有“通话音频 / 媒体音频”开关）。
2. 自动验证。首次运行会请求蓝牙和麦克风权限，请点允许；运行后用另一部手机拨打这台手机，接通后按提示对着话筒说话 4 秒：
   ```bash
   swift run hfp-spike --auto Galaxy
   ```
   工具会自动：连接 HFP → 等来电 → 2 秒后接听 → 打开语音链路 → 检查系统里有没有蓝牙通话音频设备（以及是宽带还是窄带）→
   录 4 秒对方的声音 → 向对方播 2 秒“嘟”声 → 挂断，最后打印汇总，并把全部过程写进当前目录的 `hfp-spike.log`。
   - 想测从 Mac 拨出：加 `--dial <号码>`，例如 `swift run hfp-spike --auto Galaxy --dial 10086`。
   - 等来电的时间默认 180 秒，用 `--wait <秒>` 修改。
   - 只想看系统音频设备：`swift run hfp-spike --list-audio`（不碰蓝牙）。
3. 交互验证（手动输入命令）：
   ```bash
   swift run hfp-spike Galaxy
   ```
   命令：`a` 接听，`e` 挂断，`d <号码>` 拨号，`sco` / `nosco` 打开或关闭语音链路，`mac` / `phone` 切换声音，
   `calls` 当前通话，`at <命令>` 发送 AT 命令，`audio` 列出音频设备，`status` 状态，`q` 退出。
