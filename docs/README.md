# Clash For Flutter

> 该软件是 Clash 的桌面端实现，使用[Go-Flutter](https://github.com/go-flutter-desktop/go-flutter)开发。支持 Windows、Linux、MacOS

### 下载

当前下载页面都只提供了 64 位的安装包[releases](https://github.com/mapleafgo/clash-for-flutter/releases)，由于当前是我自己手动在各个平台打包，所以做不到每个版本都提供的了安装包

- Linux:

  linux 安装包目前打包的为`appimage`的，这种包各个发行版都能直接使用

- Windows:

  windows 提供的是`msi`包

- MacOS:

  macos 提供的是`dmg`包

### 开始使用

该软件目前主要操作就三个，订阅、开启代理、切换代理节点。如下

- #### 订阅

  订阅页可以说是一切的源头，因为所有的代理节点地址都得通过订阅获取。

  ![profile](./images/profile_page.png)

  这是已有订阅的界面，**在没有订阅或未选择订阅时是无法开启代理的**，添加订阅只需点击右下角的`+`按钮。在弹出的窗口中输入订阅地址(当前仅支持联网订阅)

  > 需要说明的是，当前**暂时不未支持自动更新订阅**，需手动在此页更新订阅

- #### 开启代理

  在已选择订阅的情况下，只需在本页点击开启即可。

  ![home_page](./images/home_page.png)

  > 当前代理使用的是 PAC 自动设置代理的方式，在各平台通用。这种方式有一定的局限性，因为不是所有程序都会走代理，浏览器是没问题

- #### 切换代理节点

  **在开启代理后此页才会有数据**

  ![profile](./images/proxy_page.png)

  此页就是最常用的页面了，经常使用的 **切换节点、测延迟(右下角按钮)** 都在此页。

  可能很多人对页面头的几个列表有疑问，这个的话，是订阅配置带过来的。是 Clash 的代理组，它是与规则搭配使用，可以做到对每个 IP、每个地址进行代理配置，具体可查看[Clash 的文档](https://github.com/Dreamacro/clash/wiki/configuration#proxy-groups)。这个功能我们软件当前不负责维护，只提供基本的节点切换
