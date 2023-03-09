# Clash For Flutter

这是一个 **Clash** 的桌面客户端，支持 windows、linux、macos。

> [使用说明](https://mapleafgo.github.io/clash-for-flutter)

## 界面

![主页](./docs/images/home_page.png)

![代理页](./docs/images/proxy_page.png)

![订阅页](./docs/images/profile_page.png)

![设置页](./docs/images/settings_page.png)

## 开发、打包说明

- 基础环境

  `GCC`、`Go v1.19+`、`Flutter v3.3.9+`

  > `Linux`环境下 [tray_manager](https://github.com/leanflutter/tray_manager) 需要 `libayatana-appindicator3-dev`
  or `libappindicator3-dev`

- 编译项目

  ```shell
  # 1. 获取项目依赖
  $ flutter pub get
  # 2. 生成 .g.dart 文件
  $ flutter pub run build_runner build --delete-conflicting-outputs

  # 3. 编译 Clash 内核
  $ cd core
  # windows
  $ go build -ldflags="-w -s" -buildmode=c-shared -o ./dist/libclash.dll
  # Linux
  $ go build -ldflags="-w -s" -buildmode=c-shared -o ./dist/libclash.so
  # macos
  $ go build -ldflags="-w -s" -buildmode=c-shared -o ./dist/libclash.dylib
  
  # 回到项目根目录
  $ cd ../
  # macos 系统需要移动下编译的内核路径
  $ cp -f ./core/dist/libclash.dylib ./macos/Frameworks/libclash.dylib

  # 4. 运行项目 (linux)
  $ flutter run -d linux
  # 4. 运行项目 (windows)
  $ flutter run -d windows
  # 4. 运行项目 (macos)
  $ flutter run -d macos
  ```

- 打包项目

  该项目用 [flutter_distributor](https://distributor.leanflutter.org/) 打包，打包步骤看 `flutter_distributor` 的官方文档吧

## 主要技术

- [Go](https://go.dev/)
- [Clash](https://github.com/Dreamacro/clash)
- [Flutter](https://flutter.dev)
- [tray_manager](https://github.com/leanflutter/tray_manager)
- [window_manager](https://github.com/leanflutter/window_manager)
- [proxy_manager](https://github.com/Kingtous/proxy_manager)
- [flutter_modular](https://github.com/Flutterando/modular)
- [flutter_distributor](https://distributor.leanflutter.org/)

## 写在后面

自 1.0.0 版本开始，本软件全面从之前的 Go-Flutter 迁移到了官方 Flutter
版本。迁移中部分参考了 [Fclash](https://github.com/Kingtous/Fclash) 非常感谢！
