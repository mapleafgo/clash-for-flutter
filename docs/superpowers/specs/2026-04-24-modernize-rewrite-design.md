# Clash for Flutter 现代化重写设计

## 背景

项目停更两年，存在依赖过旧、部分包已停止维护（build_resolvers、build_runner_core 标记 discontinued）、dart_json_mapper + reflectable 代码生成链路过重等问题。需要全面重写以适配 Flutter 3.41+ / Dart 3.11+。

## 决策记录

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 实施策略 | 大爆炸重写 | 用户明确选择 |
| 状态管理 | Signals (signals_flutter) | 最简洁直观，代码量最少 |
| DI | Signals 自带 | 无需额外 DI 框架 |
| JSON 序列化 | json_serializable + build_runner | 社区标准方案 |
| 路由 | go_router | Flutter 官方推荐 |
| 架构蓝图 | Flutter 官方架构指南（presentation/domain/data） | 无第三方模板依赖 |
| UI | 同步现代化 | 升级/替换旧 UI 包 |
| 平台 | 全部保留 | Windows/Linux/macOS/Android/iOS |

## 技术栈

### 新增/替换

| 用途 | 包 |
|------|----|
| 状态管理 | `signals_flutter` |
| 路由 | `go_router` |
| JSON 序列化 | `json_serializable` + `json_annotation` |
| 代码生成 | `build_runner` |

### 保留升级

| 用途 | 包 |
|------|----|
| 网络 | `dio` |
| 系统托盘 | `tray_manager` |
| 窗口管理 | `window_manager` |
| FFI | `ffi` + `ffigen` |
| 文件选择 | `file_picker` |
| 包信息 | `package_info_plus` |
| URL 启动 | `url_launcher` |
| WebSocket | `web_socket_channel` |
| 路径 | `path_provider` |
| 开机启动 | `launch_at_startup` |
| 桌面生命周期 | `desktop_lifecycle` |
| 代理设置 | `proxy_manager` |
| 协议处理 | `protocol_handler` |
| 通知 | `local_notifier` |

### 移除

| 包 | 原因 |
|----|------|
| `flutter_modular` | 路由和 DI 均被替代 |
| `mobx` / `flutter_mobx` / `mobx_codegen` | 被 Signals 替代 |
| `dart_json_mapper` / `dart_json_mapper_mobx` | 被 json_serializable 替代 |
| `reflectable` | dart_json_mapper 的依赖，一并移除 |
| `easy_sidemenu` | 重写时用自定义侧边栏替代 |
| `settings_ui` | 升级到 3.x 或用 Material 3 原生组件替代 |
| `asuka` | 评估是否需要，可用 ScaffoldMessenger 替代 |
| `dart_json_mapper_mobx` | 不再需要 |

## 目录结构

```
lib/
├── main.dart                        # 入口：初始化 FFI、窗口、路由、托盘
├── core_control.dart                # 内核控制（FFI / MethodChannel），保留
├── clash_generated_bindings.dart    # FFI 绑定，保留
│
├── data/                            # 数据层
│   ├── api/                         # Clash REST API 客户端
│   │   ├── clash_api.dart           # HTTP 请求封装
│   │   └── ws_streams.dart          # WebSocket 流（traffic/logs/connections）
│   ├── repositories/                # 仓库层（可选，按需抽象）
│   └── local/                       # 本地存储
│       ├── app_config_storage.dart  # 应用配置持久化
│       └── core_config_storage.dart # 内核配置持久化
│
├── domain/                          # 领域层（纯 Dart 模型）
│   ├── config.dart
│   ├── proxy.dart
│   ├── proxy_group.dart
│   ├── connection.dart
│   ├── profile.dart
│   ├── log.dart
│   ├── net_speed.dart
│   └── subscription_info.dart
│
├── presentation/                    # 展示层
│   ├── app.dart                     # MaterialApp + GoRouter 配置
│   ├── router.dart                  # 路由定义
│   │
│   ├── pages/
│   │   ├── init/                    # 初始化页
│   │   │   └── init_page.dart
│   │   ├── home/                    # 首页（代理开关）
│   │   │   └── home_page.dart
│   │   ├── proxies/                 # 代理页
│   │   │   └── proxies_page.dart
│   │   ├── logs/                    # 日志页
│   │   │   └── logs_page.dart
│   │   ├── connections/             # 连接页
│   │   │   └── connections_page.dart
│   │   ├── profiles/                # 订阅页
│   │   │   └── profiles_page.dart
│   │   ├── settings/                # 设置页
│   │   │   └── settings_page.dart
│   │   └── shell/                   # 布局壳
│   │       ├── desktop_shell.dart   # 桌面端：侧边栏 + 内容区
│   │       └── mobile_shell.dart    # 移动端：底部导航 + 内容区
│   │
│   └── widgets/                     # 通用组件
│       ├── loading.dart
│       └── app_bar.dart
│
└── services/                        # 服务层（全局单例）
    ├── app_config.dart              # 应用配置（Signals 状态）
    ├── core_config.dart             # 内核配置（Signals 状态）
    └── tray_service.dart            # 托盘服务
```

## 架构模式

### Signals 状态管理

```dart
// services/app_config.dart — 全局信号
final systemProxy = signal(false);
final profiles = signal<List<Profile>>([]);

// pages/home/home_page.dart — Watch 自动重建
class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final enabled = systemProxy.value;
      return Switch(value: enabled, onChanged: _toggle);
    });
  }
}
```

### GoRouter 路由

```dart
// presentation/router.dart
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const InitPage()),
    StatefulShellRoute.indexedStack(
      builder: (_, state, shell) {
        return Constants.isDesktop
          ? DesktopShell(shell: shell)
          : MobileShell(shell: shell);
      },
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/proxies', builder: (_, __) => const ProxiesPage()),
        ]),
        // ... logs, connections, profiles, settings
      ],
    ),
  ],
);
```

### JSON 序列化

```dart
// domain/profile.dart
@JsonSerializable()
class Profile {
  final String name;
  final String url;
  final String file;
  // ...
  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);
  Map<String, dynamic> toJson() => _$ProfileToJson(this);
}
```

## 功能清单与验收检查点

每个模块写完后必须逐条验证。方括号 `[ ]` 用于实施时逐项勾选。

### 导航与布局

- [ ] 桌面端：左侧固定侧边栏（6 项菜单：首页/代理/日志/连接/订阅/设置） + 右侧内容区
- [ ] 移动端：底部导航栏（6 项） + 内容区
- [ ] 侧边栏菜单项：图标 + 文字，选中态高亮
- [ ] 菜单项定义：首页(home_outlined)、代理(cloud_outlined)、日志(list_alt_outlined)、连接(link_rounded)、订阅(code_rounded)、设置(settings_outlined)
- [ ] 页面切换时保持各页面状态（StatefulShellRoute）

### 首页

- [ ] 代理开关大按钮，尺寸 200x70
- [ ] 开启态：绿色卡片 + flight_takeoff 图标 + "开启" 文字
- [ ] 关闭态：主题色卡片 + flight_land 图标 + "关闭" 文字
- [ ] 操作中：灰色卡片 + CircularProgressIndicator
- [ ] 开关逻辑：tunIf 模式下切换 TUN，否则切换系统代理
- [ ] TUN 模式开关（仅桌面端显示，Switch 控件）
- [ ] 实时网速显示（WebSocket `ws://{addr}/traffic`，上传/下载速率）

### 代理页

- [ ] 顶部 TabBar，Tab 数量 = 代理分组数量，每个 Tab 显示分组名称
- [ ] 每个 Tab 下展示该分组的代理列表（ListTile）
- [ ] 列表项：代理名称(14px) + 副标题(12px，显示类型/当前选中) + 右侧延迟
- [ ] 选中项高亮（`selected: true`）
- [ ] 延迟显示：负数不显示、0 显示"..."（测速中）、正数显示毫秒数
- [ ] 点击代理项切换选择（PUT `/proxies/{name}`）
- [ ] 浮动按钮：全组延迟测速（GET `/proxies/{name}/delay`，并发测试）
- [ ] 测速时显示 loading 遮罩
- [ ] 排序功能：底部弹出选择（默认/按名称/按延迟）
- [ ] Global 模式下在分组列表头部插入 GLOBAL 分组

### 日志页

- [ ] 实时 WebSocket 日志流（`ws://{addr}/logs?level={level}`）
- [ ] 日志格式：`[yyyy/MM/dd HH:mm:ss] [LEVEL] payload`
- [ ] SelectableText 支持选中复制
- [ ] 自动滚动到最新日志
- [ ] 按级别过滤：底部弹出选择（debug/info/warning/error/silent）
- [ ] 切换级别时重新建立 WebSocket 连接
- [ ] 清空日志浮动按钮
- [ ] 队列最大容量 1000 条，超出时移除最早条目

### 连接页

- [ ] 表格列：域名(L)、网络(S)、类型(M)、节点链(L)、规则(L)、进程(S)、速率(M)、上传(S)、下载(S)、来源IP(S)、连接时间(M)
- [ ] 域名显示：优先 metadata.host，否则显示 IP
- [ ] 速率计算：当前值与上次值的差值（需缓存上一次连接列表）
- [ ] 连接时间：`timeago.format()` 显示相对时间
- [ ] 点击行弹出详情弹窗：ID、Network、Type、Host、IP、Process、Path、Rule、Upload、Download、Status(连接中/已断开)
- [ ] 关闭单个连接：DELETE `/connections/{id}`
- [ ] 关闭全部连接浮动按钮：DELETE `/connections`
- [ ] 数据按连接时间降序排列

### 订阅页

- [ ] MasonryGridView 布局：桌面 2 列、移动端 1 列，间距 20px
- [ ] 卡片内容：名称(单行溢出省略) + 类型 + 更新时间(timeago)
- [ ] 选中卡片高亮
- [ ] 卡片操作按钮：修改名称(edit_note) / 修改源(code) / 移除(delete) / 更新(refresh，仅 URL 类型)
- [ ] URL 类型显示流量进度条（LinearProgressIndicator，已用/总量）
- [ ] URL 类型显示过期时间（如有）
- [ ] 添加订阅：底部弹出选择"文件"或"URL"
- [ ] 文件导入：FilePicker 选取 .yml/.yaml，复制到 profiles 目录，文件名取 basename
- [ ] URL 导入：输入框输入 URL，自动下载，文件名为时间戳毫秒 `.yaml`
- [ ] URL 导入时解析 `subscription-userinfo` 响应头（upload/download/total/expire）
- [ ] 编辑名称：弹出输入框修改 name 字段
- [ ] 编辑源：根据类型弹出文件选择器或 URL 输入框
- [ ] 删除：SnackBar 确认后删除，若删除的是当前选中项则自动选中第一个
- [ ] 更新：重新下载 URL 订阅，替换旧文件
- [ ] 外链导入：`install-config://install-config?url=xxx&name=xxx` 自动解析并导入，显示 loading + SnackBar 反馈

### 设置页

- [ ] Mixed Port（int，默认 7890）
- [ ] Redir Port（int，可空）
- [ ] Tproxy Port（int，可空）
- [ ] 允许局域网开关（bool，默认 false）
- [ ] IPv6 开关（bool，默认 false）
- [ ] 代理模式选择（Rule / Global / Direct）
- [ ] 日志级别选择（info / warning / error / silent）
- [ ] MMDB URL 输入框 + 刷新按钮（下载时显示进度，完成后显示成功/失败图标）
- [ ] 延迟测试 URL 输入框
- [ ] 关于区：官网链接、源码仓库链接、版本检查
- [ ] 端口值校验：必须为合法整数
- [ ] 所有设置变更实时生效（PATCH `/configs`）

### 系统托盘（仅桌面端）

- [ ] 设置托盘图标：Windows 用 `assets/icon.ico`，其他平台用 `assets/logo_64.png`
- [ ] 右键菜单项：显示窗口 / 分隔线 / 代理开关(checkbox) / 模式子菜单(Rule/Global/Direct，均为 checkbox) / 退出
- [ ] 左键点击：显示窗口
- [ ] 右键点击：弹出上下文菜单
- [ ] 代理开关状态与页面 `systemProxy` 信号同步
- [ ] 模式选中状态与页面 `core.clash.mode` 信号同步
- [ ] 点击退出：先关闭系统代理，再关闭窗口

### 初始化流程

- [ ] 启动后显示 InitPage，执行以下步骤：
- [ ] 1. `hello()` 检测内核连接 → 失败跳转错误页
- [ ] 2. `coreConfig.init()` 初始化内核配置
- [ ] 3. `appConfig.init()` 初始化应用配置
- [ ] 4. 检查 MMDB 文件是否存在 → 不存在则下载，显示进度条 + "正在初始下载 Country.mmdb 文件"
- [ ] 5. `coreConfig.asyncConfig()` 加载配置文件
- [ ] 6. 若上次 TUN 已开启，自动重新启用
- [ ] 7. 启动日志订阅
- [ ] 8. 全部完成后导航到 `/home`
- [ ] 任何步骤异常：显示 SnackBar 错误信息，不崩溃

### 窗口管理（仅桌面端）

- [ ] 拦截关闭按钮 → 隐藏窗口而非关闭
- [ ] 窗口获焦时 `setState` 刷新
- [ ] 桌面前后台监听（desktop_lifecycle）
- [ ] 移动端前后台监听（WidgetsBindingObserver）

### 数据层

- [ ] ClashApi 封装所有 REST 接口（见下方 API 表）
- [ ] WebSocket 流封装：traffic、logs、connections，支持自动重连
- [ ] AppConfig 持久化到本地文件，变更后自动保存
- [ ] CoreConfig 通过 REST API 与内核双向同步
- [ ] 全局状态通过 Signals 暴露，无 MobX / ChangeNotifier

## REST API 接口（保留不变）

| 方法 | 路径 | 用途 |
|------|------|------|
| GET | `/` | 健康检查 |
| GET | `/proxies` | 获取全部代理 |
| GET | `/proxies/{name}` | 获取单个代理/分组 |
| GET | `/proxies/{name}/delay` | 测速 |
| PUT | `/proxies/{name}` | 切换代理选择 |
| GET | `/configs` | 获取配置 |
| PUT | `/configs` | 更换配置文件 |
| PATCH | `/configs` | 更新配置项 |
| GET | `/providers/proxies` | 获取代理提供者 |
| GET | `/version` | 获取版本 |
| DELETE | `/connections` | 关闭全部连接 |
| DELETE | `/connections/{id}` | 关闭单个连接 |

## WebSocket 流（保留不变）

| 路径 | 用途 |
|------|------|
| `ws://{addr}/traffic` | 实时网速 |
| `ws://{addr}/logs?level={level}` | 实时日志 |
| `ws://{addr}/connections` | 实时连接 |

## 代码风格

**简洁高效优雅易读**。写完即自查，不达标就改，循环至全部通过：

- 无冗余：不多一层抽象，不留 unused import，不写"以防万一"的参数
- 无啰嗦：一行能搞定不写两行，表达式优先于语句块
- 命名即文档：名字读起来就是人话，不需要注释解释
- 嵌套 ≤ 3 层，函数 ≤ 30 行，文件 ≤ 200 行
- 注释只写 WHY，永远不写 WHAT
- `flutter analyze` 零 warning 零 error
- 禁止过度封装、过度泛化、样板代码、上帝类

## 不动的部分

以下文件/模块保持原样，不参与重写：
- `core_control.dart` — FFI / MethodChannel 内核通信
- `clash_generated_bindings.dart` — FFI 绑定（ffigen 生成）
- `assets/` — 图标等资源文件
- 平台原生代码：`android/`、`ios/`、`linux/`、`macos/`、`windows/`
