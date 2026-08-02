# sing-box 订阅全量迁移设计

版本：v1.0
日期：2026-08-02
状态：已确认

## 背景与目标

当前订阅链路全部围绕 Clash/mihomo YAML 设计：订阅下载保存为 `.yaml`、配置合并走 YAML 编辑器、应用设置存储 `config.yaml` 使用 Clash 字段名。singcast-cli 内核侧已经支持 sing-box JSON 透传与 Clash YAML 翻译，但转换结果不会返回给客户端。

本次改造将订阅链路全量迁移为 sing-box JSON：

- 订阅下载后统一通过内核转换为 sing-box JSON 保存。
- 配置合并、应用设置存储全部改用 sing-box 字段。
- 旧版 `config.yaml` 与旧 YAML 订阅由统一迁移入口一次性处理。

## 现状

- `singcast-cli/translator` 支持 Clash YAML → sing-box JSON 翻译，以及 JSON 透传。
- `core.CheckConfig` 对 YAML 先翻译再校验，对 JSON 直接校验。
- `core.Service.StartWithContent` 内部翻译 YAML，但转换结果不对外返回。
- Flutter 订阅保存固定 `.yaml` 文件名；`mergeProfileConfig` 仅支持 YAML；文件导入仅允许 `yaml/yml`。
- 应用设置 `config.yaml` 使用 Clash 键名（`mixed-port`、`allow-lan`、`mode` 等）。

## 内核接口

### `core.convert`（IPC JSON-RPC）

新增 `MethodConvert = "core.convert"`，参数为 `content`，返回转换后的 sing-box JSON 字符串。内容解码与识别全部在内核层完成：

- base64 检测与解码（URI 列表、base64 包裹的 YAML/JSON）。
- 格式识别：Clash YAML、节点 URI 列表、sing-box JSON。
- URI 列表组装为 Clash YAML 中间态后走翻译；YAML 翻译为 JSON；JSON 直接透传。
- 不启动内核、不写入运行状态。
- 转换时不携带 rule_set 代理前缀，保存的 profile 保持干净；前缀仍由 `startCoreWithContent(ruleSetProxy)` 在下发时处理。
- 转换失败返回 JSON-RPC error。

### 移动端 FFI

新增 `Singcast.Convert(content string) (string, error)`，实现与 IPC 相同。
iOS 主 App 通过 Runner 本地 FFI（MethodChannel `convert`）提供同一能力，转换不依赖 VPN/RPC 连接。

### Flutter 调用链

`LibCorePlatform` 新增 `Future<String> convert(String content)`；`IpcWorker` 与 `LibCoreChannel` 分别实现。

## 订阅链路

### 下载与转换

1. `downloadSubscription` 只负责下载，把原始内容作为字符串直接传给 `LibCore.convert()`。
2. base64 解码、Clash/sing-box 判断、URI 列表解析全部由内核处理，app 不再判断内容类型。
3. 将内核返回的 sing-box JSON 保存为 `.json` 文件（文件名生成改为 `$ms.json`）。
4. 校验对转换后的 JSON 调用 `checkConfig`；转换失败或校验失败均抛错并清理文件。
5. 移除 app 侧 `isBase64Content`/`decodeBase64Subscription`/`parseProxyUri` 等解析逻辑及对应测试，职责移交内核。

### 配置合并（`mergeProfileConfig`）

只保留 JSON 分支，删除 YAML 分支：

- 解析 profile JSON 为 map。
- 移除订阅自带的 `mixed`/`http`/`socks`/`tun` inbound（应用统一管理）。
- 按应用设置注入：
  - mixed inbound：`listen_port`、`listen`（`allow-lan` 时 `0.0.0.0`，否则 `127.0.0.1`）、`set_system_proxy`（系统代理开启时）。
  - `log.level`。
  - `experimental.clash_api.external_controller` 与 `default_mode`（`mode` 映射）。
  - TUN 开启时注入 `tun` inbound（`auto_route`、`strict_route`、`stack`、Linux `auto_redirect`、按 `ipv6` 生成地址）。
  - `dns.strategy` 映射 `ipv6` 开关（`ipv4_only`/`prefer_ipv6`）。

## 应用设置存储

### 文件与字段

- `config.yaml` → `config.json`（`Constants.clashConfig` 改为 sing-box 命名）。
- `CoreConfigStorage` 只读写 `config.json`，不包含旧 `config.yaml` 的读取逻辑。
- 存储为 sing-box 字段结构的 JSON，例如：

```json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 7890
    }
  ],
  "experimental": {
    "clash_api": {
      "default_mode": "Rule",
      "external_controller": "127.0.0.1:9090"
    }
  },
  "dns": { "strategy": "prefer_ipv4" }
}
```

- 领域模型 `ClashConfig` 改名 `SingboxConfig`，`clashConfig` signal 与 `updateClashConfig` 同步改名。
- TUN 仍不持久化，行为与现状一致。
- `mergedConfigCache` 改为 `cache-merged.json`。

`createDefault` 改为创建 `config.json`。

## 统一迁移入口

新增统一入口 `migrateLegacy()`，在启动最早阶段（任何设置读取之前）开始执行：

检测方式：仅当 `config.yaml` 存在时执行迁移，否则直接跳过。

迁移内容：

1. 设置存储：`config.yaml` → `config.json`。此步骤必须最先执行，位于 `CoreConfigStorage.load()` 之前，迁移完成前不读取任何设置。
2. 订阅：在内核就绪、profiles 加载后，遍历 profiles 中 `.yaml`/`.yml` 文件：
   - URL 型与文件型统一处理：读取本地文件，调用 `core.convert` 转 JSON 保存，更新 profile 文件名。
   - 迁移期不重新拉取订阅（应用尚未就绪，避免依赖网络与订阅服务器）。
3. 全部完成后删除 `config.yaml`（作为完成标记，下次启动不再触发）。

不设计失败回退分支：能走通的订阅转换必然成功。异常只记日志并保留 `config.yaml` 标记，不阻塞启动。

## 导入与 UA

- 本地文件导入允许 `yaml/yml/json`，统一转换后以 JSON 保存。
- UA 预设补充 sing-box 项，便于服务端直接返回 sing-box 格式。

## 测试

- singcast-cli：`core.convert` 返回转换 JSON、JSON 透传、YAML 翻译结果测试。
- singcast-cli：base64 解码、URI 列表组装测试（从 Flutter 侧迁入）。
- singcast：
  - 下载转换后保存 `.json`。
  - `mergeProfileConfig` JSON 合并（端口、allow-lan、log、clash_api、tun、ipv6）。
  - `CoreConfigStorage` 旧 `config.yaml` 迁移。
  - `migrateLegacy` 统一入口：URL 与文件型统一本地转换、完成标记删除。
  - 文件导入扩展名。
  - 移除 app 侧 base64/URI 解析相关测试。
- 运行 `flutter test` 与 `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./...`。
