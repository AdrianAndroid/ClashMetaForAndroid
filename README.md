## Clash for iOS

An iOS client for the [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta) kernel.

This repository started as a fork of [ClashMetaForAndroid](https://github.com/MetaCubeX/ClashMetaForAndroid).
The Android application has been removed; what remains is the Go core adapted for Apple platforms
plus a brand new SwiftUI app and Network Extension. **Every piece of business logic (profile
loading and validation, TUN startup, selector patching, traffic statistics, overrides, log
streaming) is ported one-to-one from the Android implementation.**

### Architecture

```
┌─────────────────────── App process ───────────────────────┐
│ Clash (SwiftUI)  ──  NETunnelProviderManager  ──  profile │
│      │  sendProviderMessage(JSON)                         │
└──────┼────────────────────────────────────────────────────┘
       │
┌──────▼───────────── Extension process ────────────────────┐
│ PacketTunnelProvider                                      │
│   ├── ClashCore (Swift actor, mirrors core/Clash.kt)      │
│   ├── TunBridge  packetFlow ⇄ SOCK_DGRAM socketpair       │
│   └── mihomo (Go, c-archive → ClashCore.xcframework)      │
└───────────────────────────────────────────────────────────┘
```

| Android | iOS |
| --- | --- |
| `core/src/main/golang` (cgo + JNI) | `core/` (cgo, plain C callback table) |
| `libbridge.so` + `Bridge.kt` | `ClashCore.xcframework` + `ClashCoreKit` (Swift) |
| `VpnService.establish().detachFd()` | `NEPacketTunnelProvider` + socketpair-backed fake utun |
| `VpnService.protect()` | `setsockopt(IP_BOUND_IF / IPV6_BOUND_IF)` |
| AIDL `IClashManager` | `NETunnelProviderSession.sendProviderMessage` |
| Room database | App Group JSON (`clash/profiles.json`) |
| `design/` + `app/` | SwiftUI views in `Clash/` |

### TUN data path

`NEPacketTunnelProvider` does not expose a tun file descriptor, so the app fakes one:

```
kernel peer ⇄ utun ⇄ NEPacketTunnelFlow ⇄ TunBridge ⇄ socketpair(SOCK_DGRAM) ⇄ sing-tun
```

`sing-tun`'s darwin backend accepts an external `FileDescriptor` and speaks the utun wire
format (4 byte address-family header + IP packet). `TunBridge` adds/strips that header on
the Swift side, so the Go core needs no changes at all.

### Requirements

- macOS with Xcode 15+
- Go 1.21+ (`brew install go`)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Apple developer account (Network Extension entitlement, App Group)

### Build

```bash
git submodule update --init --recursive
bash scripts/build-core.sh     # builds ClashCore.xcframework
xcodegen generate              # creates Clash.xcodeproj
open Clash.xcodeproj
```

Then:

1. Set your development team for both `Clash` and `ClashTunnel`.
2. Change the bundle identifiers and update the App Group id
   (`ClashCoreKit/Shared.swift`, both `*.entitlements` files, and `project.yml`).
3. Run on a real device. Network Extensions do not work in the simulator.

### Notes

- The core only runs inside the tunnel extension, exactly like the Android service.
- The app never talks to the core directly: it sends JSON messages to the extension, which
  performs the same calls the AIDL interface used to expose.
- Per-app routing (`addAllowedApplication`) has no iOS equivalent; only rule based routing
  is available.
- `mark_socket` is mapped to interface binding, the darwin equivalent of `SO_MARK`.

### License

GPL-3.0, inherited from ClashMetaForAndroid and mihomo.
