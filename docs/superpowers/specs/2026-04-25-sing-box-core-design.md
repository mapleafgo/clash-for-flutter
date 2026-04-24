# sing-box Core Migration Design

**Date**: 2026-04-25
**Status**: Draft
**Affects**: Core engine, FFI layer, config system, all platforms

## Background

clash-for-flutter currently uses cff-core, based on the original Dreamacro/Clash (v1.18.0). This core does NOT support VLESS, REALITY, Hysteria2, or any modern proxy protocols. When users import subscriptions containing only VLESS+REALITY proxies, the core silently skips all proxies, leaving proxy-groups referencing non-existent entries, resulting in 400 errors.

## Decision

Replace cff-core with sing-box as the proxy engine. sing-box supports all modern protocols (VLESS, REALITY, Hysteria2, TUIC, etc.) and provides `libbox` — a ready-made FFI library for embedding.

## Architecture

### FlClash-style Pure FFI

Follow FlClash's proven architecture: Flutter communicates with the Go core exclusively through FFI calls. No HTTP REST API between Flutter and core. All data passes as JSON strings through FFI function calls.

```
┌─────────────────────────────────────────────┐
│                  Flutter UI                  │
│  (Signals state, Widgets, Pages)             │
└──────────────┬──────────────────────────────┘
               │ dart:ffi (JSON strings)
               ▼
┌─────────────────────────────────────────────┐
│           Go Bridge (hub.go)                 │
│  ┌───────────────────────────────────────┐   │
│  │     Config Translator                  │   │
│  │  mihomo YAML ──► sing-box JSON         │   │
│  └───────────────────────────────────────┘   │
│  ┌───────────────────────────────────────┐   │
│  │     sing-box Engine (libbox)           │   │
│  └───────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### Why Pure FFI over HTTP REST

| Aspect | Pure FFI | HTTP REST |
|--------|----------|-----------|
| Latency | Zero (in-process) | Network overhead |
| Reliability | No port conflicts | Port availability issues |
| Complexity | Single FFI call | HTTP server lifecycle |
| Proven | FlClash uses this | mihomo uses this |
| Mobile friendly | No socket needed | Requires localhost binding |

## FFI Interface

### Exported Functions (Go → C)

```go
// Lifecycle
export fn CoreInit(homeDir: *const c_char) -> c_int
export fn CoreStart(configPath: *const c_char) -> c_int
export fn CoreStop() -> c_int
export fn CoreClose()

// Configuration
export fn CoreLoadConfig(yamlPath: *const c_char) -> c_int   // auto-detect & translate
export fn CoreReloadConfig() -> c_int

// Queries (return JSON strings, caller frees)
export fn CoreQueryProxies() -> *const c_char                  // all proxy groups & nodes
export fn CoreQueryConnections() -> *const c_char
export fn CoreQueryTraffic() -> *const c_char                  // delta snapshot
export fn CoreQueryLogs() -> *const c_char                     // recent entries

// Actions
export fn CoreSelectProxy(group: *const c_char, tag: *const c_char) -> c_int
export fn CoreCloseConnection(id: *const c_char) -> c_int
export fn CoreCloseAllConnections() -> c_int
export fn CoreTestDelay(name: *const c_char, url: *const c_char) -> c_int  // ms, -1=error
export fn CoreGetVersion() -> *const c_char
```

### Dart Side

```dart
class CoreControl {
  static DynamicLibrary? _lib;

  static Future<void> init(String homeDir) async { ... }
  static Future<void> start(String configPath) async { ... }
  static Future<void> stop() async { ... }
  static Future<String> queryProxies() async { ... }
  static Future<void> selectProxy(String group, String tag) async { ... }
  // etc.
}
```

### Streaming Data

Traffic, logs, and connections use a Go→Dart callback pattern. The Go bridge layer implements its own event loop — it subscribes to sing-box/libbox's internal event interfaces and forwards data to Flutter via a registered C function pointer.

```go
export fn CoreSetCallback(cb: extern fn(eventType: c_int, data: *const c_char))
```

```dart
typedef CoreCallback = Void Function(Int32 eventType, Pointer<Utf8> data);
// eventType: 0=traffic, 1=log, 2=connection
```

Note: The exact libbox subscription mechanism (whether via `box.PlatformInterface` or direct channel subscription) will be determined during Phase 1 implementation after inspecting the libbox API surface.

## Config Translator

### Strategy

The Go bridge layer auto-detects config format and translates:

1. **mihomo YAML** → parse with `gopkg.in/yaml.v3` → translate → emit sing-box JSON → feed to libbox
2. **sing-box JSON** → pass through directly
3. **Detection**: check if file is valid JSON first; if not, treat as YAML

The translator is a one-way pipeline: mihomo YAML → sing-box JSON. No reverse translation.

### Mapping Reference

All field-level mappings are documented in `docs/mihomo-singbox-config-mapping.md` (version baseline: mihomo v1.19.24 ↔ sing-box v1.13.11).

Key translation rules:
- `name` → `tag` (proxies, groups, DNS rules)
- `port` → `server_port`
- `cipher` → `method` (Shadowsocks)
- `type: ss` → `type: "shadowsocks"`
- `type: vmess` → `type: "vmess"` (unchanged)
- Seconds (int) → Go Duration strings (`"30s"`)
- `skip-cert-verify: true` → `insecure: true`
- Proxy groups: `type: Select` → `type: "selector"`, `type: URLTest` → `type: "urltest"`
- Rules: `DOMAIN-SUFFIX,google.com,Proxy` → `{ "domain_suffix": ["google.com"], "outbound": "Proxy" }`

### Unsupported Fallback

When a mihomo field has no sing-box equivalent (e.g., Snell protocol, `authentication`, `tunnels`):
- Log a warning during translation
- Skip the field gracefully
- Do NOT crash or fail the entire config

## Flutter Side Changes

### What Changes

| Component | Before | After |
|-----------|--------|-------|
| `core_control.dart` | FFI to cff-core | FFI to sing-box bridge |
| `clash_api.dart` | HTTP REST (Dio) | FFI calls via CoreControl |
| `ws_streams.dart` | WebSocket streams | FFI callbacks |
| `app_config.dart` | HTTP PATCH configs | FFI CoreReloadConfig |
| `clash_generated_bindings.dart` | cff-core bindings | sing-box bridge bindings |

### What Stays

| Component | Reason |
|-----------|--------|
| UI pages | No changes to visual design |
| Signals state management | Still used for reactive UI |
| Profile management | File-based, format-agnostic |
| Subscription download | YAML download unchanged |
| Settings page | Most settings map to sing-box equivalents |

### ClashApi Refactor

`ClashApi` transforms from an HTTP client to a thin wrapper around FFI calls:

```dart
class ClashApi {
  Future<void> hello() async => CoreControl.init(homeDir);

  Future<Map<String, dynamic>> getProxies() async {
    final json = CoreControl.queryProxies();
    return jsonDecode(json);
  }

  Future<bool> selectProxy({required String group, required String tag}) async {
    return CoreControl.selectProxy(group, tag) == 0;
  }
  // ...
}
```

The class name `ClashApi` is retained for minimal code change, but all HTTP internals are removed.

## Platform Support

All platforms supported via gomobile cross-compilation:

| Platform | Output | Path |
|----------|--------|------|
| Linux | `libclash.so` | `linux/core/` |
| Windows | `libclash.dll` | `windows/core/` |
| macOS | `libclash.dylib` | `macos/Frameworks/` |
| Android | `libclash.aar` | `android/app/libs/` |
| iOS | `libclash.xcframework` | `ios/Frameworks/` |

## Build Pipeline

```
Go source (hub.go + translator)
    │
    ├─ gomobile bind ──► .aar / .xcframework
    ├─ go build -buildmode=c-shared ──► .so / .dll / .dylib
    │
    ▼
Flutter assets ──► platform-specific paths
```

## Migration Scope

### Phase 1: Core & Config
- Go bridge with config translator
- FFI bindings in Dart
- CoreControl rewrite
- Basic lifecycle (init, start, stop)

### Phase 2: Data Layer
- ClashApi → FFI wrapper
- WebSocket streams → FFI callbacks
- Proxies, connections, logs, traffic

### Phase 3: UI Integration
- Proxies page (group selection, delay test)
- Connections page
- Logs page
- Settings page (verify all fields work)

### Phase 4: Platform & Polish
- Cross-platform builds
- TUN mode configuration
- Edge cases and error handling
- Testing

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Config translation gaps | Comprehensive mapping doc, fallback logging |
| FFI memory management | Go allocates, Dart frees via explicit free() |
| Platform-specific TUN | Platform-conditional config fields |
| gomobile ABI stability | Pin sing-box version, test per-platform |
| Breaking existing users | Translator handles all mihomo YAML configs |
