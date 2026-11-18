# Android Clash 客户端 → iOS 移植实录

> 对象:`ClashMetaForAndroid` (learn 分支) → 纯 iOS 客户端
> 结果:Go 内核成功编译为 `ClashCore.xcframework`(device + simulator),SwiftUI App 与
> Network Extension 在模拟器上编译运行通过,真机待签名验证。

---

## 1. 核心结论(最重要的一条)

**不要重写内核。** Android 版与 iOS 版共用同一份 Go 内核,只有三处平台差异需要替换:

| Android | iOS | 说明 |
| --- | --- | --- |
| JNI (`main.c` + `jni_helper.c`) | 纯 C 回调表 | Go 侧 `//export` 生成的 `.h` 直接给 Swift 用 |
| `VpnService.establish().detachFd()` | `NEPacketTunnelProvider` + socketpair 假 utun | 关键技巧,见第 3 节 |
| AIDL `IClashManager` | `NETunnelProviderSession.sendProviderMessage` | JSON 协议,职责一一对应 |

业务逻辑(配置加载、覆写、TUN 启动、流量统计、日志、订阅校验)全部原样保留。

---

## 2. Go 内核改造清单(改动越小越好)

原路径 `core/src/main/golang/native/...`(module `cfa`,包路径 `cfa/native/*`)整体迁移到
`core/`,并把 import 前缀 `cfa/native/` 全部改为 `cfa/`。

| 文件 | 改动 | 原因 |
| --- | --- | --- |
| `main.go` | `#cgo LDFLAGS: -llog` → `#cgo android LDFLAGS: -llog` | iOS 没有 liblog |
| `bridge.h/.c` | 删除 `<android/log.h>`;日志改为可注册的 `clash_log_func`;所有回调指针判空 | 平台无关 |
| `bridge.c` | 新增 `core_register_callbacks(clash_callbacks*)` | 替代 `JNI_OnLoad` 注册函数指针 |
| `callbacks.go`(新增) | `//export coreRegisterCallbacks` | Swift 一次性注册全部回调 |
| `platform/procfs.go` | 仅 linux;新增 `procfs_darwin.go`,返回 -1 | iOS 无 `/proc`、无 UID 概念 |
| `platform/limit.go` | 仅 linux;新增 `limit_darwin.go` | `ShouldBlockConnection` 接口要存在 |
| `app/content.go` | 保留接口;新增 `file://` 分支在 `config/fetch.go` | iOS 直接读文件路径,不用 ContentResolver |
| `app/dns.go` | 拆成 `dns_android.go` + `dns_other.go` | `dns.UpdateSystemDNS` 只存在于 `android && cmfa` |
| `config/fetch.go` | UA 改为 `ClashMetaForIOS/x` | 订阅服务器识别客户端 |

**踩坑 1**:迁移目录后必须同步改 import path,否则 `go build` 全红。
**踩坑 2**:mihomo 的部分函数只在 `android && cmfa` 标签下存在(如 DNS 补丁),
非 Android 平台要自己提供同签名实现,不要试图给 submodule 加文件(无法提交)。

---

## 3. TUN 通路:iOS 没有 fd,但可以"伪造"一个

`NEPacketTunnelProvider` 只给 `packetFlow`(读包/写包),不给文件描述符。而
`metacubex/sing-tun` 的 darwin 实现支持 `Options.FileDescriptor`:给了 fd 就直接包成
`os.File` 读写,不建 utun、不配路由,并且按 utun 线格式自动**剥/加 4 字节地址族头**。

于是:

```
系统 ⇄ utun ⇄ NEPacketTunnelFlow ⇄ TunBridge ⇄ socketpair(SOCK_DGRAM) ⇄ sing-tun
```

- 读向:`readPacketObjects()` → 前置 4 字节头(`00 00 00 02` / `00 00 00 1E`)→ `write(fdA)`
- 写向:`read(fdA)` → 去掉 4 字节头 → `writePacketObjects()`
- `SOCK_DGRAM` 保证一包一帧,和 utun 的报文语义一致
- **Go 侧零改动**

网络参数照抄 Android `TunService`:

| 项 | 值 |
| --- | --- |
| IPv4 | `172.19.0.1/30`,portal/DNS `172.19.0.2` |
| IPv6 | `fdfe:dcba:9876::1/126`,portal `fdfe:dcba:9876::2` |
| MTU | 9000 |
| DNS | `NEDNSSettings(servers: [172.19.0.2])` + `matchDomains = [""]` |
| 劫持 | `bypassPrivateNetwork` 时只加私网路由;DNS 劫持时向内核传 `0.0.0.0` |

**防回环**:Android 用 `VpnService.protect(fd)`;iOS 没有 `SO_MARK`,改成
`setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &ifindex)` + IPv6 版(`IPV6_BOUND_IF`),
接口索引用 `getifaddrs` 选 `en0`/`pdp_ip*`,跳过 `utun*`。
Go 侧 `mark_socket` 回调原样接上即可。

---

## 4. 构建链:c-archive → xcframework

```bash
GOOS=ios GOARCH=arm64 CGO_ENABLED=1 \
CC="$(xcrun -sdk iphoneos -find clang)" \
CGO_CFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path) -target arm64-apple-ios16.0" \
  go build -buildmode=c-archive -tags "ios,with_gvisor" -o libClashCore.a .
```

要点:

- **必须 `-buildmode=c-archive`**,产出 `.a` + 自动生成的 `libClashCore.h`
- 模拟器 slice 的 target 是 `arm64-apple-ios16.0-simulator`
- 两个 slice 用 `xcodebuild -create-xcframework` 合并
- 生成的头文件里有一行 `#include "bridge.h"` → 必须把 `bridge.h` 一起拷到 framework headers,
  否则 Xcode 报 `'bridge.h' file not found`
- tag 用 `ios,with_gvisor`(`cmfa` 是 Android 专用,不需要)
- 版本号:Android 用 CMake 注入 `version.h`;iOS 直接通过 `coreInit(home, version, gitVersion, sdk)` 传参

---

## 5. Swift 侧桥接模型

Go 的 C 回调指针没有 context 概念,Swift 闭包又无法直接转 C 函数指针,做法:

1. 定义 `clash_callbacks` 结构体(日志 / mark_socket / complete / fetch_report / logcat / release)
2. Swift 顶层函数填表,启动时调一次 `coreRegisterCallbacks`
3. 需要一个"对象令牌"时,把 Swift 对象存进 `ObjectRegistry`(字典),把字典 key 强转成指针传给 Go
4. Go 用完调 `release_object(ptr)` 删除;`complete` 之后不要自己释放,避免 double free
5. Go 侧异步接口全部用 `withCheckedThrowingContinuation` 包装成 `async throws`,
   actor `ClashCore` 就是 Android 里 `object Clash` 的翻版

**注意**:Android `healthCheck` 没有调用 `release_object`(原实现的小泄漏),移植时保持行为一致即可。

---

## 6. 跨进程:用 Provider 消息,而不是 external-controller

最初计划用 mihomo 的 `external-controller` 暴露 REST API,实际更简单可靠的做法是
`NETunnelProviderSession.sendProviderMessage`:

```
App  --JSON-->  Provider(内核所在进程)  --C 调用-->  ClashCore
```

- 一一对应 Android 的 AIDL 方法(queryGroups / select / healthCheck / providers / reload / override)
- 流量与状态:Provider 每秒写一次 App Group 的 `tunnel.status`,App 直接读,避免高频 IPC
- 日志:Provider 内存环形缓冲 500 行 + 落盘,App 轮询
- 选节点后立即 `patchSelector` 并回读 group,和 Android 行为一致

---

## 7. 编译期踩坑记录

| 报错 | 原因 | 解决 |
| --- | --- | --- |
| `undefined: dns.UpdateSystemDNS` | 函数只在 `android && cmfa` 文件里 | 按平台拆分 `app/dns.go` |
| `'bridge.h' file not found` | cgo 生成头文件里有 include | 拷 `bridge.h` 到 framework headers |
| `cannot convert NSNumber to sa_family_t` | `NEPacket(data:protocolFamily:)` 在 iOS 26 SDK 里是 `UInt8` | 传 `UInt8`,不用 `NSNumber` |
| destination 不存在 / "iOS 26.2 is not installed" | 只装了 SDK,没装 simulator runtime | `xcodebuild -downloadPlatform iOS` |
| 0 valid identities | 本地没有开发证书 | 需在 Xcode 登录付费开发者账号 |

另外:`ContentUnavailableView`、`onChange(of:_:)` 双参闭包都是 iOS 17+ API,最低版本 16 时要替换。

---

## 8. 复现步骤(干净环境)

```bash
git submodule update --init --recursive
brew install go xcodegen
bash scripts/build-core.sh     # 产出 build/ClashCore.xcframework
xcodegen generate              # 产出 Clash.xcodeproj
open Clash.xcodeproj           # 设置 Team / Bundle ID / App Group
```

真机要求:付费开发者账号 + `com.apple.developer.networking.networkextension`
(packet-tunnel-provider)+ App Group;免费 Apple ID 用不了 Network Extension。
模拟器只能看 UI,不能跑隧道。

---

## 9. 待验证 / 下一步

1. **真机隧道链路**:`packetFlow ⇄ socketpair ⇄ sing-tun` 是否被 sing-tun 的批量读写
   (`recvmmsg`/`sendmmsg`)接受。若报 `ENOTSOCK`,备选方案是 fork mihomo,在
   `listener/sing_tun` 注入自定义 `PacketTun`(实现 `io.ReadWriter + Close` 即可)。
2. 订阅更新:目前 App 用 URLSession 下载,Provider 内 `fetchAndValid` 只做校验;
   可改为完全走内核下载,行为和 Android 完全一致。
3. 后台保活、低电量模式、`NWPathMonitor` 网络切换后的 DNS/接口索引刷新。
4. 分应用代理:iOS 无 `addAllowedApplication`,只能靠规则实现,UI 需要说明差异。
