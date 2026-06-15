<div align="center">
  <img src="assets/logo.svg" alt="Singcast" width="120" height="120">
  <h1>Singcast</h1>
  <p><strong>Multi-platform proxy client powered by <a href="https://github.com/SagerNet/sing-box">sing-box</a>, with Clash config support</strong></p>
</div>

<p align="center">
  <a href="README.md">English</a> | <a href="README_zh.md">中文</a>
</p>

<p align="center">
  <a href="https://t.me/+xcHAK5RADfY4NmZl">
    <img src="https://img.shields.io/badge/Telegram-Group-blue?logo=telegram&logoColor=white" alt="Telegram">
  </a>
</p>

Singcast is an open-source multi-platform proxy client built with Flutter and powered by a customized [sing-box](https://github.com/SagerNet/sing-box) core. It supports Clash subscription links and configuration files out of the box — just import and go.

Available on **Windows**, **Linux**, **macOS**, and **Android**. **iOS** is not supported.

- **Desktop**: Core runs as an independent privileged process communicating via JSON-RPC (IPC), keeping the UI sandboxed and stable.
- **Android**: Core is loaded as a native library via FFI, integrated with Android VPN service.

- **TUN mode**: Transparent proxy with automatic route management — no manual system proxy setup needed.

> [Documentation](https://mapleafgo.github.io/singcast)

## Preview

![Home](./docs/images/home_page.png)

## Features

- Support Clash subscriptions and configuration files
- System proxy and TUN mode (transparent proxy)
- Proxy node selection and latency testing
- Real-time traffic statistics
- Subscription management, import and update subscription links
- Log viewer with export
- System tray on desktop

## Usage

### Linux

Make sure to install the following dependencies before using

```bash
sudo apt-get install libayatana-appindicator3
```

### Download

[GitHub Releases](https://github.com/mapleafgo/singcast/releases/latest)

## Build

1. Install `Flutter v3.41+`

   > Follow the Flutter official documentation to set up the environment for your target platform. For example, Android development requires Android SDK.

2. Download core

   Download the core for your platform from [singcast-cli Releases](https://github.com/mapleafgo/singcast-cli/releases/latest) and place it at:

   ```shell
   # Desktop (IPC standalone process)
   windows/core/singcast-core.exe
   linux/core/singcast-core
   macos/Frameworks/singcast-core

   # Mobile (FFI native library)
    android/app/libs/libsingcast.aar
   ```

3. Build and run

   ```shell
   # Install dependencies
   flutter pub get
   # Generate code
   dart run build_runner build --delete-conflicting-outputs
   # Run
   flutter run -d linux
   ```

## FAQ

### Subscription fetch / update failed

If the subscription keeps loading or returns an error, the provider may be restricting certain User-Agent strings. Try changing the UA in **Settings → General → Subscription User-Agent** (e.g. `clash-verge/v2.0.0`, `clash-meta`), then update the subscription again.

## Tech Stack

- [sing-box](https://github.com/SagerNet/sing-box)
- [Flutter](https://flutter.dev)
- [signals_flutter](https://github.com/rodydavis/signals.dart)
- [go_router](https://pub.dev/packages/go_router)
- [window_manager](https://github.com/leanflutter/window_manager)
- [desktop_tray](https://pub.dev/packages/desktop_tray)
- [dart_ipc](https://pub.dev/packages/dart_ipc)
- [ffi](https://dart.dev/guides/libraries/c-interop)
