# Third-party notices / 第三方说明

Link to macOS is released under the [MIT License](LICENSE). It uses and was inspired by the open-source software
listed below. The full Apache License 2.0 text is in [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt).

Link to macOS 以 [MIT 许可证](LICENSE) 发布。它使用了下面这些开源软件，并参考了其中一个项目的思路。
Apache License 2.0 的全文见 [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt)。

## Inspiration / 参考的项目

### scrcpy

The enhanced service on the phone (`android/app/src/main/java/com/linktomacos/android/shell/`) follows the approach of
[scrcpy](https://github.com/Genymobile/scrcpy) (Copyright (C) Genymobile, Apache License 2.0):

- faking an `ActivityThread` and a system context inside `app_process`, which has no app context (`Hidden.java`);
- mirroring a display with `DisplayManager.createVirtualDisplay` and encoding it with MediaCodec;
- creating a separate virtual display for apps, turning off only the physical panel, injecting touches and keys through
  `InputManager.injectInputEvent`, and recording the system audio mix with `REMOTE_SUBMIX`.

The code was written from these ideas and does not copy scrcpy source files. The names of the system-internal APIs and the
order in which they are called come from scrcpy's implementation.

手机上的增强服务按这些思路重新编写，没有复制 scrcpy 的源文件；系统内部接口的名称和调用顺序来自 scrcpy 的实现。

## Mac app (Swift packages) / Mac 端（Swift 包）

All of the following are licensed under the **Apache License 2.0**. Versions are the ones resolved in
`macos/Packages/LinkCore/Package.resolved`.

| Package | Version | Used for |
|---|---|---|
| [swift-nio](https://github.com/apple/swift-nio) | 2.104.0 | Network I/O, framing, the TLS server and connections |
| [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) | 2.37.5 | TLS 1.3 for NIO (contains BoringSSL) |
| [swift-certificates](https://github.com/apple/swift-certificates) | 1.21.0 | Creating and reading the self-signed X.509 certificates |
| [swift-crypto](https://github.com/apple/swift-crypto) | 4.5.2 | SHA-256 fingerprints, HMAC, key handling (contains BoringSSL) |
| [swift-asn1](https://github.com/apple/swift-asn1) | 1.7.3 | ASN.1 / DER, used by swift-certificates |
| [swift-atomics](https://github.com/apple/swift-atomics) | 1.3.1 | Used by swift-nio |
| [swift-collections](https://github.com/apple/swift-collections) | 1.7.4 | Used by swift-nio |
| [swift-system](https://github.com/apple/swift-system) | 1.8.1 | Used by swift-nio |

`swift-nio-ssl` and `swift-crypto` include code from **BoringSSL**, which is under a combination of the ISC and OpenSSL licenses:
<https://boringssl.googlesource.com/boringssl/+/refs/heads/master/LICENSE>.

The NOTICE files of these packages, reproduced as the Apache License 2.0 asks:

### swift-nio

```text
The SwiftNIO Project
                            ====================

Please visit the SwiftNIO web site for more information:

  * https://github.com/apple/swift-nio

Copyright 2017, 2018 The SwiftNIO Project

The SwiftNIO Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.<component>.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

-------------------------------------------------------------------------------

This product is heavily influenced by Netty.

  * LICENSE (Apache License 2.0):
    * https://github.com/netty/netty/blob/4.1/LICENSE.txt
  * HOMEPAGE:
    * https://netty.io

---

This product contains NodeJS's llhttp.

  * LICENSE (MIT):
    * https://github.com/nodejs/llhttp/blob/1e1c5b43326494e97cf8244ff57475eb72a1b62c/LICENSE-MIT
  * HOMEPAGE:
    * https://github.com/nodejs/llhttp

---

This product contains "cpp_magic.h" from Thomas Nixon & Jonathan Heathcote's uSHET

  * LICENSE (MIT):
    * https://github.com/18sg/uSHET/blob/c09e0acafd86720efe42dc15c63e0cc228244c32/lib/cpp_magic.h
  * HOMEPAGE:
    * https://github.com/18sg/uSHET

---

This product contains "sha1.c" and "sha1.h" from FreeBSD (Copyright (C) 1995, 1996, 1997, and 1998 WIDE Project)

  * LICENSE (BSD-3):
    * https://opensource.org/licenses/BSD-3-Clause
  * HOMEPAGE:
    * https://github.com/freebsd/freebsd-src

---

This product contains a derivation of Fabian Fett's 'Base64.swift'.

  * LICENSE (Apache License 2.0):
    * https://github.com/swift-extras/swift-extras-base64/blob/b8af49699d59ad065b801715a5009619100245ca/LICENSE
  * HOMEPAGE:
    * https://github.com/fabianfett/swift-base64-kit

---

This product contains a derivation of "XCTest+AsyncAwait.swift" & "StructuredConcurrencyHelpers" from AsyncHTTPClient.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/swift-server/async-http-client

---

This product contains a derivation of "_TinyArray.swift" from SwiftCertificates.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-certificates

---

This product contains a derivation of the mocking infrastructure from Swift System.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-system

---

This product contains a derivation of "TokenBucket.swift" from Swift Package Manager.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/swiftlang/swift-package-manager
```

### swift-nio-ssl

```text
The SwiftNIO Project
                            ====================

Please visit the SwiftNIO web site for more information:

  * https://github.com/apple/swift-nio

Copyright 2017, 2018 The SwiftNIO Project

The SwiftNIO Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.<component>.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

-------------------------------------------------------------------------------

This product is heavily influenced by Netty.

  * LICENSE (Apache License 2.0):
    * https://github.com/netty/netty/blob/4.1/LICENSE.txt
  * HOMEPAGE:
    * https://netty.io

---

This product contains a derivation of the Tony Stone's 'process_test_files.rb'.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://codegists.com/snippet/ruby/generate_xctest_linux_runnerrb_tonystone_ruby

---

This product contains code derived from grpc-swift.

  * LICENSE (Apache License 2.0):
    * https://github.com/grpc/grpc-swift/blob/0.7.0/LICENSE
  * HOMEPAGE:
    * https://github.com/grpc/grpc-swift

---

This product contains code from boringssl.

  * LICENSE (Combination ISC and OpenSSL license)
    * https://boringssl.googlesource.com/boringssl/+/refs/heads/master/LICENSE
  * HOMEPAGE:
    * https://boringssl.googlesource.com/boringssl/
```

### swift-certificates

```text
The SwiftCertificates Project
                            =====================

Please visit the SwiftCertificates web site for more information:

  * https://github.com/apple/swift-certificates

Copyright 2022 The SwiftCertificates Project

The SwiftCertificates Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

---

This product contains derivations of various scripts from SwiftNIO.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio
    
---

This product contains test data derived from Webpki.

  * LICENSE (ISC):
    * https://github.com/briansmith/webpki/blob/main/LICENSE
  * HOMEPAGE:
    * https://github.com/briansmith/webpki/
    
---

This product contains derivations of various ASN1 types from SwiftASN1.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-asn1

---

This product contains test vectors from pyca/cryptography.

  * LICENSE (Apache License 2.0):
    * https://github.com/pyca/cryptography/blob/main/LICENSE.APACHE
  * HOMEPAGE:
    * https://github.com/pyca/cryptography

---

This product contains code to calculate and decompose UNIX timestamps derived from musl libc.

  * LICENSE (MIT):
    * https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
  * HOMEPAGE:
    * https://musl.libc.org
    
---
    
This product contains derivations of various scripts from SwiftNIO SSH.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio-ssh
    
---

This product contains derivations of various scripts from Swift OpenAPI Generator.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-openapi-generator
```

### swift-crypto

```text
The SwiftCrypto Project
                            =======================

Please visit the SwiftCrypto web site for more information:

  * https://github.com/apple/swift-crypto

Copyright 2019 The SwiftCrypto Project

The SwiftCrypto Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.<component>.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

-------------------------------------------------------------------------------

This product contains test vectors from Google's wycheproof project.

  * LICENSE (Apache License 2.0):
    * https://github.com/C2SP/wycheproof/blob/31387e2cd596587c859c611027b6a44d2e2b65ff/LICENSE
  * HOMEPAGE:
    * https://github.com/google/wycheproof

---

This product contains a derivation of various files from SwiftNIO.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio
```

### swift-asn1

```text
The SwiftASN1 Project
                            =====================

Please visit the SwiftASN1 web site for more information:

  * https://github.com/apple/swift-asn1

Copyright 2022 The SwiftASN1 Project

The SwiftASN1 Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

---

This product contains derivations of various scripts from SwiftNIO.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio
    
---

This product contains derivations of various scripts from Swift OpenAPI Generator.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-openapi-generator
```

## Android app / Android 端

All of the following are licensed under the **Apache License 2.0**.

| Library | Version | Link |
|---|---|---|
| AndroidX Core KTX | 1.19.1 | <https://developer.android.com/jetpack/androidx> |
| AndroidX Activity Compose | 1.13.0 | <https://developer.android.com/jetpack/androidx> |
| AndroidX Lifecycle (runtime-compose, service) | 2.11.0 | <https://developer.android.com/jetpack/androidx> |
| Jetpack Compose (BOM 2026.09.00): UI, Material 3 | — | <https://developer.android.com/jetpack/compose> |
| AndroidX CameraX (camera2, lifecycle, view) | 1.6.2 | <https://developer.android.com/jetpack/androidx/releases/camera> |
| ZXing core | 3.5.4 | <https://github.com/zxing/zxing> |
| kotlinx.serialization (JSON) | 1.12.0 | <https://github.com/Kotlin/kotlinx.serialization> |
| kotlinx.coroutines (Android) | 1.11.0 | <https://github.com/Kotlin/kotlinx.coroutines> |
| Kotlin standard library | 2.4.21 | <https://github.com/JetBrains/kotlin> |

## Not distributed with the app / 不随应用分发

These are used only while developing and are not part of the apps: JUnit 4 (EPL-1.0) for the Android unit tests,
Swift Testing for the Mac tests, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (MIT) to generate the Xcode project,
[OpenCC](https://github.com/BYVoid/OpenCC) (Apache-2.0, via `opencc-python-reimplemented`) to convert Simplified to
Traditional Chinese in `tools/i18n`, and [Pillow](https://python-pillow.org/) (HPND) to draw the Mac icon.

## System resources / 系统资源

The Mac app draws its symbols with Apple's SF Symbols through the system; they are not copied into this repository and
are licensed by Apple for use in apps for Apple platforms. The system sounds used for call alerts are the ones that ship
with macOS. The app icons and the logo are original artwork under the same MIT license as the code.

Mac 端的符号通过系统使用 Apple 的 SF Symbols，不在本仓库里；来电提示音是 macOS 自带的系统提示音；应用图标和 logo 是原创，和代码同属 MIT 许可证。

## Trademarks / 商标

*Link to Windows* and *Phone Link* are Microsoft products, *macOS* and *SF Symbols* are trademarks of Apple Inc.,
*Android* is a trademark of Google LLC, *Samsung* and *Galaxy* are trademarks of Samsung Electronics. This project is
independent and is not affiliated with or endorsed by any of them.
