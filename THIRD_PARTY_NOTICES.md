# 第三方说明

## scrcpy

手机上的 shell 服务（`android/app/src/main/java/com/linktomacos/android/shell/`）的做法参考了
[scrcpy](https://github.com/Genymobile/scrcpy)（Copyright (C) Genymobile，Apache License 2.0）：

- 在没有 App 上下文的 `app_process` 里伪造 `ActivityThread` 和系统上下文（`Hidden.java`）；
- 通过 `DisplayManager.createVirtualDisplay` 镜像显示器内容并用 MediaCodec 编码；
- 通过 `InputManager.injectInputEvent` 注入触摸和按键。

代码是按这些思路重新编写的，没有复制 scrcpy 的源文件；系统内部接口的名称和调用顺序来自 scrcpy 的实现。
Apache License 2.0 全文见 <https://www.apache.org/licenses/LICENSE-2.0>。
