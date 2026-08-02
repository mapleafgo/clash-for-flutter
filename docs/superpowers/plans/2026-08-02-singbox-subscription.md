# sing-box 订阅全量迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 订阅、配置合并、应用设置全部迁移到 sing-box JSON，内核统一处理 base64/格式识别/URI 列表转换。

**Architecture:** singcast-cli 新增 `core.convert`（IPC + 移动端 FFI），内部把 base64 解码、URI 列表组装、Clash YAML 翻译、JSON 透传统一为 `translator.Convert`。Flutter 端只下载原文并调用 `convert`，保存返回的 JSON；`mergeProfileConfig` 改为纯 JSON 合并；启动最早阶段通过 `migrateLegacy()` 迁移旧 `config.yaml` 与旧 YAML 订阅。

**Tech Stack:** Go（sing-box v1.13.14）、Flutter/Dart、JSON-RPC、MethodChannel。

## Global Constraints

- 代码注释与 commit message 使用中文。
- 订阅保存文件一律为 `.json`，内容为 sing-box JSON。
- app 不再判断内容类型，base64/URI/格式识别全部由内核处理。
- `config.yaml` 只在迁移入口被读取；`CoreConfigStorage.load()` 只读 `config.json`。
- 迁移不设计失败回退分支，异常只记日志，不阻塞启动；任一环节失败保留 `config.yaml` 标记，下次启动重试。
- Go 测试命令：`go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./translator/... ./core/... ./ipc/...`
- Flutter 测试命令：`flutter test`、`dart analyze`。

---

## Task 1: 内核订阅输入归一化（base64 + URI 列表）

**Files:**
- Create: `singcast-cli/translator/input.go`
- Create: `singcast-cli/translator/input_test.go`

**Interfaces:**
- Produces: `NormalizeInput(data []byte) ([]byte, error)` — base64 解码并识别 URI 列表，URI 列表组装为 mihomo YAML。

- [ ] **Step 1: 写失败测试**

`singcast-cli/translator/input_test.go`:

```go
package translator

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestNormalizeInputBase64URIList(t *testing.T) {
	ssBody := base64.StdEncoding.EncodeToString([]byte("aes-128-gcm:pass@host.com:8080"))
	raw := "ss://" + ssBody + "#p1\n"
	encoded := base64.StdEncoding.EncodeToString([]byte(raw))
	out, err := NormalizeInput([]byte(encoded))
	if err != nil {
		t.Fatalf("NormalizeInput: %v", err)
	}
	s := string(out)
	if !strings.Contains(s, "proxies:") || !strings.Contains(s, "p1") {
		t.Fatalf("expected mihomo YAML with proxies, got: %s", s)
	}
}

func TestNormalizeInputBase64JSON(t *testing.T) {
	jsonStr := `{"log":{"level":"info"},"outbounds":[{"type":"direct","tag":"direct"}]}`
	encoded := base64.StdEncoding.EncodeToString([]byte(jsonStr))
	out, err := NormalizeInput([]byte(encoded))
	if err != nil {
		t.Fatalf("NormalizeInput: %v", err)
	}
	if string(out) != jsonStr {
		t.Fatalf("expected decoded JSON, got: %s", out)
	}
}

func TestNormalizeInputRawYAMLPassthrough(t *testing.T) {
	yaml := "mixed-port: 7890\nproxies:\n  - name: p\n    type: ss\n"
	out, err := NormalizeInput([]byte(yaml))
	if err != nil {
		t.Fatalf("NormalizeInput: %v", err)
	}
	if string(out) != yaml {
		t.Fatalf("expected passthrough, got: %s", out)
	}
}
```

- [ ] **Step 2: 运行确认失败**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./translator/ -run TestNormalizeInput`
Expected: FAIL（`NormalizeInput` 未定义）。

- [ ] **Step 3: 实现 NormalizeInput**

`singcast-cli/translator/input.go`:

```go
package translator

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

// proxyListYAML 只序列化 proxies 字段，避免把 RawConfig 的零值字段全部输出。
type proxyListYAML struct {
	Proxies []map[string]any `yaml:"proxies"`
}

// NormalizeInput 统一订阅输入：base64 解码；URI 列表组装为 mihomo YAML。
func NormalizeInput(data []byte) ([]byte, error) {
	if decoded, ok := decodeBase64Input(data); ok {
		data = decoded
	}
	if isProxyURIList(data) {
		return buildClashYAMLFromURIs(data)
	}
	return data, nil
}

func decodeBase64Input(data []byte) ([]byte, bool) {
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return nil, false
	}
	for _, enc := range []*base64.Encoding{
		base64.StdEncoding,
		base64.RawStdEncoding,
		base64.URLEncoding,
		base64.RawURLEncoding,
	} {
		decoded, err := enc.DecodeString(trimmed)
		if err != nil {
			continue
		}
		if looksLikeSubscription(decoded) {
			return decoded, true
		}
	}
	return nil, false
}

func looksLikeSubscription(data []byte) bool {
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return false
	}
	if strings.Contains(trimmed, "://") {
		return true
	}
	if strings.HasPrefix(trimmed, "{") && json.Valid([]byte(trimmed)) {
		return true
	}
	return strings.Contains(trimmed, "proxies:")
}

func isProxyURIList(data []byte) bool {
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return false
	}
	for _, line := range strings.Split(trimmed, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if !strings.Contains(line, "://") {
			return false
		}
	}
	return true
}

func buildClashYAMLFromURIs(data []byte) ([]byte, error) {
	proxies := []map[string]any{}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if p := parseProxyURI(line); p != nil {
			proxies = append(proxies, p)
		}
	}
	if len(proxies) == 0 {
		return nil, fmt.Errorf("no valid proxies found in subscription")
	}
	return yaml.Marshal(proxyListYAML{Proxies: proxies})
}

func parseProxyURI(uri string) map[string]any {
	if !strings.Contains(uri, "://") {
		return nil
	}
	typeEnd := strings.Index(uri, "://")
	scheme := strings.ToLower(uri[:typeEnd])
	rest := uri[typeEnd+3:]
	name := "proxy"
	body := rest
	if hashIdx := strings.Index(rest, "#"); hashIdx >= 0 {
		if decoded, err := url.QueryUnescape(rest[hashIdx+1:]); err == nil && decoded != "" {
			name = decoded
		}
		body = rest[:hashIdx]
	}
	switch scheme {
	case "ss":
		return parseSS(body, name)
	case "vmess":
		return parseVmess(body, name)
	case "vless":
		return parseVless(body, name)
	case "trojan":
		return parseTrojan(body, name)
	case "hysteria2", "hy2":
		return parseHysteria2(body, name)
	default:
		return nil
	}
}

func parseSS(body, name string) map[string]any {
	decoded := ""
	var serverPort []string
	if strings.Contains(body, "@") {
		atIdx := strings.Index(body, "@")
		dec, err := base64Decode(body[:atIdx])
		if err != nil {
			return nil
		}
		decoded = dec
		serverPort = strings.Split(strings.Split(body[atIdx+1:], "?")[0], ":")
	} else {
		dec, err := base64Decode(strings.Split(body, "?")[0])
		if err != nil {
			return nil
		}
		decoded = dec
		atIdx := strings.LastIndex(decoded, "@")
		if atIdx < 0 {
			return nil
		}
		serverPort = strings.Split(decoded[atIdx+1:], ":")
		decoded = decoded[:atIdx]
	}
	if len(serverPort) < 2 {
		return nil
	}
	colonIdx := strings.Index(decoded, ":")
	if colonIdx < 0 {
		return nil
	}
	return map[string]any{
		"name":     name,
		"type":     "ss",
		"server":   serverPort[0],
		"port":     strToInt(serverPort[1]),
		"cipher":   decoded[:colonIdx],
		"password": decoded[colonIdx+1:],
	}
}

func parseVmess(body, name string) map[string]any {
	dec, err := base64Decode(body)
	if err != nil {
		return nil
	}
	var raw map[string]any
	if json.Unmarshal([]byte(dec), &raw) != nil {
		return nil
	}
	return map[string]any{
		"name":    name,
		"type":    "vmess",
		"server":  fmt.Sprint(raw["add"]),
		"port":    strToInt(raw["port"]),
		"uuid":    fmt.Sprint(raw["id"]),
		"alterId": strToInt(raw["aid"]),
		"cipher":  strOr(raw["scy"], "auto"),
	}
}

func parseVless(body, name string) map[string]any {
	u, err := url.Parse("vless://" + body)
	if err != nil {
		return nil
	}
	q := u.Query()
	security := q.Get("security")
	p := map[string]any{
		"name":   name,
		"type":   "vless",
		"server": u.Hostname(),
		"port":   strToInt(u.Port()),
		"udp":    true,
		"tls":    security == "tls" || security == "reality",
	}
	if flow := q.Get("flow"); flow != "" {
		p["flow"] = flow
	}
	if sni := q.Get("sni"); sni != "" {
		p["servername"] = sni
	}
	if network := q.Get("type"); network != "" {
		p["network"] = network
	}
	return p
}

func parseTrojan(body, name string) map[string]any {
	u, err := url.Parse("trojan://" + body)
	if err != nil {
		return nil
	}
	return map[string]any{
		"name":     name,
		"type":     "trojan",
		"server":   u.Hostname(),
		"port":     strToInt(u.Port()),
		"password": u.User.Username(),
	}
}

func parseHysteria2(body, name string) map[string]any {
	u, err := url.Parse("hysteria2://" + body)
	if err != nil || u.Hostname() == "" {
		return nil
	}
	q := u.Query()
	p := map[string]any{
		"name":     name,
		"type":     "hysteria2",
		"server":   u.Hostname(),
		"port":     443,
		"password": u.User.Username(),
	}
	if port := strToInt(u.Port()); port != 0 {
		p["port"] = port
	}
	if sni := q.Get("sni"); sni != "" {
		p["sni"] = sni
	}
	if q.Get("insecure") == "1" {
		p["skip-cert-verify"] = true
	}
	if obfs := q.Get("obfs"); obfs != "" {
		p["obfs"] = obfs
	}
	if obfsPwd := q.Get("obfs-password"); obfsPwd != "" {
		p["obfs-password"] = obfsPwd
	}
	return p
}

func base64Decode(s string) (string, error) {
	for _, enc := range []*base64.Encoding{
		base64.StdEncoding,
		base64.RawStdEncoding,
		base64.URLEncoding,
		base64.RawURLEncoding,
	} {
		if dec, err := enc.DecodeString(s); err == nil {
			return string(dec), nil
		}
	}
	return "", fmt.Errorf("invalid base64")
}

func strToInt(v any) int {
	switch n := v.(type) {
	case int:
		return n
	case float64:
		return int(n)
	case string:
		i, _ := strconv.Atoi(n)
		return i
	default:
		return 0
	}
}

func strOr(v any, def string) string {
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return def
}
```

> 注：base64 URL 解码包一层判断会吃掉错误 padding；四个编码变体按顺序尝试即可，`base64Decode` 同时服务 SS/vmess 的 userinfo。

- [ ] **Step 4: 运行确认通过**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./translator/ -run TestNormalizeInput`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add translator/input.go translator/input_test.go
git commit -m "feat(translator): 订阅输入支持 base64 解码与 URI 列表组装"
```

---

## Task 2: translator.Convert 统一转换入口

**Files:**
- Modify: `singcast-cli/translator/translator.go`
- Modify: `singcast-cli/translator/translator_test.go`

**Interfaces:**
- Consumes: `NormalizeInput`（Task 1）。
- Produces: `Convert(data []byte) (string, []string, error)` — 归一化后走现有 Translate（JSON 透传 / YAML 翻译）。

- [ ] **Step 1: 写失败测试**

追加到 `singcast-cli/translator/translator_test.go`：

```go
func TestConvertBase64URIList(t *testing.T) {
	raw := "trojan://pass@example.com:443#tr\n"
	encoded := base64.StdEncoding.EncodeToString([]byte(raw))
	jsonStr, warnings, err := Convert([]byte(encoded))
	if err != nil {
		t.Fatalf("Convert: %v", err)
	}
	if len(warnings) != 0 {
		t.Fatalf("unexpected warnings: %v", warnings)
	}
	out := parseJSON(t, jsonStr)
	outbounds, _ := out["outbounds"].([]any)
	if len(outbounds) == 0 {
		t.Fatalf("expected outbounds, got: %s", jsonStr)
	}
}

func TestConvertJSONPassthrough(t *testing.T) {
	raw := `{"log":{"level":"info"},"outbounds":[{"type":"direct","tag":"direct"}]}`
	jsonStr, _, err := Convert([]byte(raw))
	if err != nil {
		t.Fatalf("Convert: %v", err)
	}
	if jsonStr != raw {
		t.Fatalf("expected passthrough, got: %s", jsonStr)
	}
}
```

需要补 `encoding/base64` import。

- [ ] **Step 2: 运行确认失败**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./translator/ -run TestConvert`
Expected: FAIL（`Convert` 未定义）。

- [ ] **Step 3: 实现 Convert**

在 `singcast-cli/translator/translator.go` 增加：

```go
// Convert 统一处理订阅输入：base64 解码与 URI 列表组装后，再走格式识别与翻译。
// JSON 直接透传，YAML 翻译为 sing-box JSON。
func Convert(data []byte) (string, []string, error) {
	normalized, err := NormalizeInput(data)
	if err != nil {
		return "", nil, err
	}
	return Translate(normalized)
}
```

- [ ] **Step 4: 运行确认通过**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./translator/ -run TestConvert`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add translator/translator.go translator/translator_test.go
git commit -m "feat(translator): 新增 Convert 统一订阅转换入口"
```

---

## Task 3: core.Convert 与启动/校验链路统一

**Files:**
- Modify: `singcast-cli/core/service.go`
- Create: `singcast-cli/core/convert_test.go`

**Interfaces:**
- Consumes: `translator.Convert`、`translator.NormalizeInput`。
- Produces: `core.Convert(content string) (string, error)`。

- [ ] **Step 1: 写失败测试**

`singcast-cli/core/convert_test.go`：

```go
package core

import (
	"encoding/base64"
	"context"
	"strings"
	"testing"
)

func TestConvertYAML(t *testing.T) {
	yaml := "proxies:\n  - name: p\n    type: ss\n    server: 1.2.3.4\n    port: 443\n    cipher: aes-128-gcm\n    password: x\n"
	jsonStr, err := Convert(yaml)
	if err != nil {
		t.Fatalf("Convert: %v", err)
	}
	if !strings.Contains(jsonStr, `"outbounds"`) {
		t.Fatalf("expected sing-box JSON, got: %s", jsonStr)
	}
}

func TestConvertBase64URIList(t *testing.T) {
	raw := "ss://" + base64.StdEncoding.EncodeToString([]byte("aes-128-gcm:x@1.2.3.4:443")) + "#p\n"
	encoded := base64.StdEncoding.EncodeToString([]byte(raw))
	jsonStr, err := Convert(encoded)
	if err != nil {
		t.Fatalf("Convert: %v", err)
	}
	if !strings.Contains(jsonStr, `"outbounds"`) {
		t.Fatalf("expected sing-box JSON, got: %s", jsonStr)
	}
}

func TestCheckConfigBase64URIList(t *testing.T) {
	raw := "trojan://pass@example.com:443#tr\n"
	encoded := base64.StdEncoding.EncodeToString([]byte(raw))
	if err := CheckConfig(context.Background(), encoded); err != nil {
		t.Fatalf("CheckConfig: %v", err)
	}
}
```

- [ ] **Step 2: 运行确认失败**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./core/ -run 'TestConvert|TestCheckConfigBase64'`
Expected: FAIL（`Convert` 未定义）。

- [ ] **Step 3: 实现**

`singcast-cli/core/service.go`：

```go
// Convert 统一处理订阅输入并返回 sing-box JSON，不启动内核。
func Convert(content string) (string, error) {
	jsonStr, warnings, err := translator.Convert([]byte(content))
	if err != nil {
		return "", err
	}
	for _, w := range warnings {
		slog.Warn("convert config", "warning", w)
	}
	return jsonStr, nil
}
```

`CheckConfig` 改为复用统一入口：

```go
func CheckConfig(ctx context.Context, content string) error {
	data := []byte(content)
	jsonStr, warnings, err := translator.Convert(data)
	if err != nil {
		return fmt.Errorf("convert config: %w", err)
	}
	for _, w := range warnings {
		slog.Warn("check config", "warning", w)
	}
	data = []byte(jsonStr)
	ctx = include.Context(ctx)
	_, err := singjson.UnmarshalExtendedContext[option.Options](ctx, data)
	return err
}
```

`StartWithContent` 先归一化再走原翻译路径（保留 ruleSetProxy 能力）：

```go
func (s *Service) StartWithContent(content, ruleSetProxy string) error {
	data := []byte(content)
	normalized, err := translator.NormalizeInput(data)
	if err != nil {
		return err
	}
	jsonContent, stubTags, err := s.translateConfig(normalized, translator.DetectFormat(normalized), ruleSetProxy)
	if err != nil {
		return err
	}
	mySeq := s.startSeq.Add(1)

	s.startMu.Lock()
	defer s.startMu.Unlock()

	// A newer request arrived while we waited — let it win.
	if s.startSeq.Load() != mySeq {
		return nil
	}

	// Stop any running/starting instance first.
	if err := s.Stop(); err != nil {
		slog.Warn("stop previous instance", "error", err)
	}

	if !s.casState(StateInitialized, StateStarting) {
		return fmt.Errorf("start: invalid state %s", s.State())
	}

	if err := s.startWithJSON(jsonContent, stubTags); err != nil {
		s.casState(StateStarting, StateInitialized)
		return err
	}
	return nil
}
```

> 只替换函数开头到 `translateConfig` 之间的段落，其余代码与原实现一致。

- [ ] **Step 4: 运行确认通过**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./core/...`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add core/service.go core/convert_test.go
git commit -m "feat(core): 新增 Convert 并统一校验与启动的订阅归一化"
```

---

## Task 4: IPC core.convert 与移动端 FFI Convert

**Files:**
- Modify: `singcast-cli/ipc/types.go`
- Modify: `singcast-cli/ipc/handler.go`
- Modify: `singcast-cli/mobile/api.go`
- Create: `singcast-cli/ipc/handler_convert_test.go`

**Interfaces:**
- Consumes: `core.Convert`（Task 3）。
- Produces: IPC 方法 `core.convert`（参数 `content`，成功返回 `{"json": "..."}`）；移动端 `Singcast.Convert(content string) (string, error)`。

- [ ] **Step 1: 写失败测试**

`singcast-cli/ipc/handler_convert_test.go`：

```go
package ipc

import (
	"encoding/json"
	"testing"

	"github.com/mapleafgo/singcast/core"
)

func TestHandleConvert(t *testing.T) {
	h := NewHandler(core.NewService())
	raw := `{"content":"proxies:\n  - name: p\n    type: ss\n    server: 1.2.3.4\n    port: 443\n    cipher: aes-128-gcm\n    password: x\n"}`
	resp := h.Handle(&JSONRPCRequest{
		Method: MethodConvert,
		Params: json.RawMessage(raw),
	})
	if resp.Error != nil {
		t.Fatalf("unexpected error: %v", resp.Error.Message)
	}
	var result map[string]string
	if err := json.Unmarshal(resp.Result, &result); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if result["json"] == "" {
		t.Fatal("expected non-empty json result")
	}
}
```

- [ ] **Step 2: 运行确认失败**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/ -run TestHandleConvert`
Expected: FAIL（`MethodConvert` 未定义）。

- [ ] **Step 3: 实现**

`singcast-cli/ipc/types.go`：

```go
MethodConvert = "core.convert"
```

```go
// ConvertParams holds parameters for core.convert.
type ConvertParams struct {
	Content string `json:"content"`
}
```

`singcast-cli/ipc/handler.go`：

```go
case MethodConvert:
	return h.handleConvert(req, id)
```

```go
func (h *Handler) handleConvert(req *JSONRPCRequest, id int64) JSONRPCResponse {
	var params ConvertParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return newError(id, -32602, "invalid params: "+err.Error())
	}
	jsonStr, err := core.Convert(params.Content)
	if err != nil {
		return newError(id, 1, err.Error())
	}
	return newResult(id, map[string]string{"json": jsonStr})
}
```

`singcast-cli/mobile/api.go`（`CheckConfig` 附近）：

```go
// Convert converts a Clash YAML / URI list / base64 subscription to sing-box JSON.
func (s *Singcast) Convert(content string) (string, error) {
	return core.Convert(content)
}
```

- [ ] **Step 4: 运行确认通过**

Run: `go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./ipc/... ./mobile/...`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add ipc/types.go ipc/handler.go ipc/handler_convert_test.go mobile/api.go
git commit -m "feat(ipc): 新增 core.convert 与移动端 Convert 接口"
```

---

## Task 5: Flutter LibCore convert 接口

**Files:**
- Modify: `singcast/lib/core/lib_core.dart`
- Modify: `singcast/lib/core/ipc_worker.dart`
- Modify: `singcast/lib/core/lib_core_channel.dart`
- Modify: `singcast/lib/core/ios_vpn_bridge.dart`
- Modify: `singcast/android/app/src/main/kotlin/cn/mapleafgo/singcast/Mobile.kt`
- Modify: `singcast/android/app/src/main/kotlin/cn/mapleafgo/singcast/MainActivity.kt`
- Modify: `singcast/ios/Runner/AppDelegate.swift`

**Interfaces:**
- Produces: `LibCorePlatform.convert(String content) → Future<String>`；Android/iOS MethodChannel 新增 `convert`（iOS 走 Runner 本地 FFI，不依赖 VPN/RPC）。

> 前置：singcast-cli Task 4 后需重新生成移动端绑定（`task mobile-all` 产出 AAR/XCFramework），
> 并同步到 `android/app/libs/libsingcast.aar` 与 `ios/Frameworks/libsingcast-darwin.xcframework`，
> 否则 Kotlin/Swift 侧看不到 `convert`。仓库 CI 从 singcast-cli release 下载绑定，发布顺序为先 singcast-cli 后 singcast。

- [ ] **Step 1: 实现接口（本任务为跨层接线，测试随使用方任务落地）**

`lib/core/lib_core.dart` 接口：

```dart
Future<String> convert(String content);
```

`lib/core/lib_core.dart` 公共方法（`checkConfig` 附近）：

```dart
Future<String> convert(String content) => _platform.convert(content);
```

`lib/core/ipc_worker.dart`：

```dart
@override
Future<String> convert(String content) {
  final impl = convertImpl;
  if (impl != null) return impl(content);
  return _convertRpc(content);
}

Future<String> _convertRpc(String content) async {
  final result = await _call('core.convert', {'content': content});
  if (result is Map<String, dynamic>) {
    final json = result['json'] as String?;
    if (json != null && json.isNotEmpty) return json;
  }
  throw StateError('core.convert returned no json result');
}
```

`lib/core/ipc_worker.dart` 增加移动端钩子（与 `startCoreWithContentImpl` 同一模式）：

```dart
/// 移动端本地转换钩子（iOS）：主 App 无 RPC 连接时也能转订阅。
Future<String> Function(String content)? convertImpl;
```

`lib/core/lib_core_channel.dart`：

```dart
@override
Future<String> convert(String content) async {
  final result = await _channel.invokeMethod<String>('convert', {'content': content});
  if (result != null && result.isNotEmpty) return result;
  throw StateError('convert returned no json result');
}
```

`android/.../Mobile.kt`（`checkConfig` 附近）：

```kotlin
fun convert(content: String): String {
    return singcast.convert(content)
}
```

`android/.../MainActivity.kt` 的 `handleMethodCall` 中 `checkConfig` 附近：

```kotlin
"convert" -> safeReply(result) { Mobile.convert(args?.str("content") ?: "") }
```

`lib/core/ios_vpn_bridge.dart` 的 `wireInto` 注入本地转换（与 `_reloadCore` 同一模式）：

```dart
worker.convertImpl = _convert;

Future<String> _convert(String content) async {
  final result = await _channel.invokeMethod<String>('convert', {'content': content});
  if (result != null && result.isNotEmpty) return result;
  throw StateError('iOS convert returned no json result');
}
```

`ios/Runner/AppDelegate.swift` 增加 `import Singcast` 与本地转换实例，并在 `handle` 中新增分支：

```swift
private let converter = MobileSingcast()

case "convert":
    do {
        result(try converter.convert(args["content"] as? String ?? ""))
    } catch {
        result(FlutterError(code: "CONVERT_ERROR", message: "\(error)", details: nil))
    }
```

- [ ] **Step 2: 编译确认**

Run: `dart analyze lib/core/`
Expected: 无新增错误。

- [ ] **Step 3: 提交**

```bash
git add lib/core/lib_core.dart lib/core/ipc_worker.dart lib/core/lib_core_channel.dart lib/core/ios_vpn_bridge.dart android/app/src/main/kotlin/cn/mapleafgo/singcast/Mobile.kt android/app/src/main/kotlin/cn/mapleafgo/singcast/MainActivity.kt ios/Runner/AppDelegate.swift
git commit -m "feat(core): LibCore 接入 core.convert"
```

---

## Task 6: 常量与领域模型迁移到 sing-box 命名

**Files:**
- Modify: `singcast/lib/utils/constants.dart`
- Modify: `singcast/lib/domain/config.dart`
- Modify: `singcast/lib/domain/enums.dart`（如需要）
- Modify: `singcast/lib/services/core_config.dart`（signal 与函数改名）
- Modify: `singcast/lib/services/core_reload.dart`
- Modify: `singcast/lib/services/tray_service.dart`
- Modify: `singcast/lib/presentation/pages/home_page.dart`
- Modify: `singcast/lib/presentation/pages/settings_page.dart`
- Modify: `singcast/test/utils/constants_test.dart`
- Modify: `singcast/test/services/core_config_test.dart`
- Modify: `singcast/test/services/app_config_test.dart`（仅同步改名，YAML 场景由 Task 8 重写）
- Modify: `singcast/test/domain/config_test.dart`

**Interfaces:**
- Produces: `SingboxConfig`（原 `ClashConfig`）、`coreConfig` signal、`updateCoreConfig(...)`。

- [ ] **Step 1: 改名实现**

`lib/utils/constants.dart`：

```dart
static const coreConfigFile = "config.json";
static const mergedConfigCache = "cache-merged.json";
```

`lib/utils/constants.dart` 的 `uaPresets` 增加：

```dart
'sing-box/1.13.14',
```

`lib/domain/config.dart`：`ClashConfig` 改名 `SingboxConfig`，字段与 getter 不变。

`lib/services/core_config.dart`：`clashConfig` → `coreConfig`、`updateClashConfig` → `updateCoreConfig`，其余引用同步。

同步替换以下文件中的 `clashConfig` 引用：

- `lib/services/core_reload.dart`：`show clashConfig, mergeProfileConfig` → `show coreConfig, mergeProfileConfig`，3 处 `clashConfig.value` 使用，doc 注释里 `[ClashConfig]` → `[SingboxConfig]`。
- `lib/services/tray_service.dart`：`clashConfig.value.systemProxyEnabled` → `coreConfig.value.systemProxyEnabled`。
- `lib/presentation/pages/home_page.dart`：`clashConfig.value.tunEnabled/systemProxyEnabled` → `coreConfig.value...`。
- `test/domain/config_test.dart`：group 名与 `ClashConfig` → `SingboxConfig`。

`lib/presentation/pages/settings_page.dart`：改用 `coreConfig.value` 与 `updateCoreConfig(...)`。

`test/utils/constants_test.dart`：

```dart
test('coreConfigFile is config.json', () {
  expect(Constants.coreConfigFile, 'config.json');
});
```

`test/services/core_config_test.dart`：`ClashConfig` → `SingboxConfig`、`clashConfig` → `coreConfig`、`updateClashConfig` → `updateCoreConfig`。

`test/services/app_config_test.dart`：仅把 `ClashConfig`/`clashConfig` 同步改名，保证本任务结束时全量测试可编译；测试内容保持 YAML 场景，Task 8 再整体重写。

- [ ] **Step 2: 测试确认**

Run: `flutter test test/utils/constants_test.dart test/services/core_config_test.dart`
Expected: PASS。

- [ ] **Step 3: 提交**

```bash
git add lib/utils/constants.dart lib/domain/config.dart lib/services/core_config.dart lib/services/core_reload.dart lib/services/tray_service.dart lib/presentation/pages/home_page.dart lib/presentation/pages/settings_page.dart test/utils/constants_test.dart test/services/core_config_test.dart test/services/app_config_test.dart test/domain/config_test.dart
git commit -m "refactor: 配置模型与常量迁移到 sing-box 命名"
```

---

## Task 7: CoreConfigStorage 纯 JSON 存储

**Files:**
- Modify: `singcast/lib/data/local/core_config_storage.dart`
- Create: `singcast/test/data/local/core_config_storage_test.dart`

**Interfaces:**
- Consumes: `SingboxConfig`（Task 6）。
- Produces: `CoreConfigStorage.load()/save()/createDefault()` 只操作 `config.json`。

- [ ] **Step 1: 写失败测试**

`singcast/test/data/local/core_config_storage_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/constants.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('singcast-storage-test');
    Constants.homeDir = tmp;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('save/load roundtrip with sing-box keys', () {
    CoreConfigStorage.save(SingboxConfig(
      mixedPort: 8080,
      allowLan: true,
      mode: Mode.global,
      logLevel: LogLevel.warning,
      ipv6: true,
      externalController: true,
      externalControllerAddr: '127.0.0.1:9091',
      portEnabled: true,
    ));

    final raw = jsonDecode(
      File('${tmp.path}/config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect((raw['inbounds'] as List).first['listen_port'], 8080);
    expect(raw['log']['level'], 'warn');
    expect(raw['experimental']['clash_api']['default_mode'], 'Global');
    expect(raw['dns']['strategy'], 'prefer_ipv6');

    final loaded = CoreConfigStorage.load();
    expect(loaded.mixedPort, 8080);
    expect(loaded.allowLan, true);
    expect(loaded.mode, Mode.global);
    expect(loaded.logLevel, LogLevel.warning);
    expect(loaded.ipv6, true);
    expect(loaded.portEnabled, true);
  });

  test('load returns defaults when file missing', () {
    final loaded = CoreConfigStorage.load();
    expect(loaded.mixedPort, isNull);
    expect(loaded.portEnabled, isNull);
  });

  test('createDefault writes config.json', () {
    CoreConfigStorage.createDefault();
    expect(File('${tmp.path}/config.json').existsSync(), isTrue);
  });

  test('createDefault skips when config.yaml exists', () {
    File('${tmp.path}/config.yaml').writeAsStringSync('mixed-port: 1\n');
    CoreConfigStorage.createDefault();
    expect(File('${tmp.path}/config.json').existsSync(), isFalse);
  });
}
```

> `Constants.homeDir` 是 `late final`，测试中首次赋值即可。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/local/core_config_storage_test.dart`
Expected: FAIL（当前写 `config.yaml`）。

- [ ] **Step 3: 实现**

`lib/data/local/core_config_storage.dart` 重写为 JSON 存储：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';

class CoreConfigStorage {
  static String get _path =>
      p.join(Constants.homeDir.path, Constants.coreConfigFile);

  static bool exists() => File(_path).existsSync();

  static SingboxConfig load() {
    try {
      final file = File(_path);
      if (!file.existsSync()) return SingboxConfig();
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final inbound = _mixedInbound(json);
      final clashApi =
          (json['experimental'] as Map<String, dynamic>?)?['clash_api']
              as Map<String, dynamic>?;
      final dns = json['dns'] as Map<String, dynamic>?;
      return SingboxConfig(
        mixedPort: (inbound?['listen_port'] as num?)?.toInt(),
        allowLan: inbound != null && inbound['listen'] != '127.0.0.1',
        mode: _parseEnum(
          (clashApi?['default_mode'] as String?)?.toLowerCase(),
          Mode.values,
        ),
        logLevel: _parseEnum(_logLevelName(json), LogLevel.values),
        ipv6: dns?['strategy'] == null
            ? null
            : dns!['strategy'] == 'prefer_ipv6',
        externalController: json['api_enabled'] as bool?,
        externalControllerAddr:
            clashApi?['external_controller'] as String?,
        portEnabled: json['port_enabled'] as bool?,
      );
    } catch (e) {
      LogFileWriter.instance?.log(
        'Failed to load core config, using defaults: $e',
        level: LogLevel.warning,
        name: 'settings',
      );
      return SingboxConfig();
    }
  }

  static void save(SingboxConfig config) {
    final json = <String, dynamic>{
      if (config.logLevel != null)
        'log': {'level': _singboxLogLevel(config.logLevel!)},
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': config.allowLan == true ? '0.0.0.0' : '127.0.0.1',
          'listen_port':
              config.mixedPort ?? Constants.defaultMixedPort,
        }
      ],
      'experimental': {
        'clash_api': {
          if (config.mode != null) 'default_mode': _modeName(config.mode!),
          if (config.externalControllerAddr != null)
            'external_controller': config.externalControllerAddr,
        },
      },
      if (config.ipv6 != null)
        'dns': {'strategy': config.ipv6! ? 'prefer_ipv6' : 'ipv4_only'},
      'port_enabled': config.portEnabled ?? false,
      'api_enabled': config.externalController ?? false,
    };
    File(_path)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }

  static void createDefault() {
    final file = File(_path);
    if (file.existsSync()) return;
    // 旧版标记存在时交给迁移入口处理，避免抢先创建 config.json
    if (File(p.join(Constants.homeDir.path, 'config.yaml')).existsSync()) {
      return;
    }
    try {
      file.writeAsStringSync(jsonEncode({
        'inbounds': [
          {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
            'listen_port': Constants.defaultMixedPort,
          }
        ],
        'port_enabled': false,
        'api_enabled': false,
      }));
    } on FileSystemException catch (_) {}
  }

  static Map<String, dynamic>? _mixedInbound(Map<String, dynamic> json) {
    final list = json['inbounds'] as List?;
    if (list == null) return null;
    for (final item in list) {
      if (item is Map<String, dynamic> && item['type'] == 'mixed') {
        return item;
      }
    }
    return null;
  }

  static String? _logLevelName(Map<String, dynamic> json) {
    final log = json['log'] as Map<String, dynamic>?;
    final level = log?['level'] as String?;
    if (level == 'warn') return 'warning';
    return level;
  }

  static String _singboxLogLevel(LogLevel level) =>
      level == LogLevel.warning ? 'warn' : level.name;

  static String _modeName(Mode mode) =>
      mode.name[0].toUpperCase() + mode.name.substring(1);

  static T? _parseEnum<T extends Enum>(dynamic value, List<T> values) {
    if (value is! String) return null;
    return values.where((e) => e.name == value).firstOrNull;
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/data/local/core_config_storage_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/data/local/core_config_storage.dart test/data/local/core_config_storage_test.dart
git commit -m "feat(storage): 内核设置存储迁移为 config.json sing-box 字段"
```

---

## Task 8: mergeProfileConfig 纯 JSON 合并

**Files:**
- Modify: `singcast/lib/services/core_config.dart`
- Modify: `singcast/test/services/app_config_test.dart`

**Interfaces:**
- Consumes: `coreConfig`、`tunStack`（Task 6）。
- Produces: `mergeProfileConfig(String jsonContent) → String`（sing-box JSON）。

- [ ] **Step 1: 重写测试**

`test/services/app_config_test.dart` 替换为 JSON 场景：

```dart
const _profileJson = '''
{
  "log": {"level": "debug"},
  "inbounds": [
    {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 7890}
  ],
  "outbounds": [
    {"type": "direct", "tag": "DIRECT"},
    {"type": "selector", "tag": "PROXY", "outbounds": ["DIRECT"]}
  ],
  "experimental": {
    "clash_api": {"external_controller": "127.0.0.1:9090"}
  }
}
''';

void main() {
  group('mergeProfileConfig sing-box JSON', () {
    test('overrides mixed inbound and log level', () {
      coreConfig.value = SingboxConfig(
        mixedPort: 8080,
        logLevel: LogLevel.warning,
        portEnabled: true,
      );
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      final inbounds = (result['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds.single['listen_port'], 8080);
      expect(result['log']['level'], 'warn');
    });

    test('removes mixed inbound when port disabled', () {
      coreConfig.value = SingboxConfig(portEnabled: false);
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      expect(result['inbounds'], isNull);
    });

    test('injects tun inbound with ipv6 address', () {
      coreConfig.value = SingboxConfig(
        tun: TunConfig(enable: true),
        ipv6: true,
      );
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      final tun = (result['inbounds'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((e) => e['type'] == 'tun');
      expect(tun['auto_route'], true);
      expect((tun['address'] as List).length, 2);
    });

    test('injects clash_api when api enabled', () {
      coreConfig.value = SingboxConfig(
        externalController: true,
        externalControllerAddr: '127.0.0.1:9091',
        mode: Mode.global,
      );
      final result = jsonDecode(mergeProfileConfig(_profileJson));
      final api =
          (result['experimental'] as Map)['clash_api'] as Map<String, dynamic>;
      expect(api['external_controller'], '127.0.0.1:9091');
      expect(api['default_mode'], 'Global');
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/app_config_test.dart`
Expected: FAIL（当前实现是 YAML 合并）。

- [ ] **Step 3: 实现**

`lib/services/core_config.dart` 替换 `mergeProfileConfig`：

```dart
/// Overlay [SingboxConfig] values onto the profile JSON.
String mergeProfileConfig(String jsonContent) {
  final doc = jsonDecode(jsonContent) as Map<String, dynamic>;
  final config = coreConfig.value;

  const managedTypes = {'mixed', 'http', 'socks', 'tun'};
  final inbounds = (doc['inbounds'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .where((e) => !managedTypes.contains(e['type']))
          .toList() ??
      <Map<String, dynamic>>[];

  final portOn = config.userPortEnabled || config.systemProxyEnabled;
  if (portOn) {
    inbounds.add({
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': config.allowLan == true ? '0.0.0.0' : '127.0.0.1',
      'listen_port': config.mixedPort ?? Constants.defaultMixedPort,
      if (config.systemProxyEnabled) 'set_system_proxy': true,
    });
  }

  if (config.tun?.enable == true) {
    inbounds.add({
      'type': 'tun',
      'tag': 'tun-in',
      'auto_route': true,
      'strict_route': true,
      'stack': tunStack.value.name,
      if (Platform.isLinux) 'auto_redirect': true,
      'address': [
        '172.18.0.1/30',
        if (config.ipv6 == true) 'fdfe:dcba:9876::1/126',
      ],
    });
  }

  if (inbounds.isNotEmpty) {
    doc['inbounds'] = inbounds;
  } else {
    doc.remove('inbounds');
  }

  if (config.logLevel != null) {
    final log =
        (doc['log'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    log['level'] = config.logLevel == LogLevel.warning
        ? 'warn'
        : config.logLevel!.name;
    doc['log'] = log;
  }

  if (config.apiEnabled) {
    final exp =
        (doc['experimental'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final clashApi =
        (exp['clash_api'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    clashApi['external_controller'] = config.apiAddr;
    if (config.mode != null) {
      clashApi['default_mode'] =
          config.mode!.name[0].toUpperCase() + config.mode!.name.substring(1);
    }
    exp['clash_api'] = clashApi;
    doc['experimental'] = exp;
  } else {
    final exp = doc['experimental'] as Map<String, dynamic>?;
    exp?.remove('clash_api');
    if (exp != null && exp.isEmpty) doc.remove('experimental');
  }

  if (config.ipv6 != null) {
    final dns =
        (doc['dns'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    dns['strategy'] = config.ipv6! ? 'prefer_ipv6' : 'ipv4_only';
    doc['dns'] = dns;
  }

  return jsonEncode(doc);
}
```

删除文件顶部 `yaml`/`yaml_edit` import，补 `dart:convert`。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/app_config_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/services/core_config.dart test/services/app_config_test.dart
git commit -m "feat(config): mergeProfileConfig 改为 sing-box JSON 合并"
```

---

## Task 9: 订阅下载全链路转换

**Files:**
- Modify: `singcast/lib/services/subscription.dart`
- Modify: `singcast/test/services/subscription_test.dart`

**Interfaces:**
- Consumes: `LibCore.instance.convert`（Task 5）。
- Produces: `downloadSubscription` 保存 `.json`；`validateConfigFile` 校验转换后 JSON。

- [ ] **Step 1: 重写实现**

`lib/services/subscription.dart`：

- `_uniqueFileName()` 返回 `'$ms.json'`。
- 删除 `isBase64Content`、`decodeBase64Subscription`、`parseProxyUri` 及所有 `parse*` 函数。
- `downloadSubscription` 改为：

```dart
final raw = utf8.decode(bytes);
final jsonContent = await LibCore.instance.convert(raw);
await File(savePath).writeAsString(jsonContent);
```

> 转换失败会抛异常，由上层 `importSubscription`/`refreshProfile` 透出。

- [ ] **Step 2: 更新测试**

`test/services/subscription_test.dart` 删除 base64/URI 相关 group，保留并补上纯函数测试：

```dart
void main() {
  group('extractFilename', () {
    test('parses filename* parameter', () {
      expect(
        extractFilename("attachment; filename*=UTF-8''profile.yaml"),
        'profile.yaml',
      );
    });

    test('returns null for null header', () {
      expect(extractFilename(null), isNull);
    });
  });

  group('parseSubInfo', () {
    test('parses subscription-userinfo header', () {
      final info = parseSubInfo(
        'upload=100; download=200; total=1000; expire=1750000000',
      );
      expect(info, isNotNull);
      expect(info!.upload, 100);
      expect(info.download, 200);
      expect(info.total, 1000);
    });

    test('returns null for null header', () {
      expect(parseSubInfo(null), isNull);
    });
  });
}
```

- [ ] **Step 3: 运行确认**

Run: `flutter test test/services/subscription_test.dart test/services/app_config_test.dart`
Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add lib/services/subscription.dart test/services/subscription_test.dart
git commit -m "feat(subscription): 订阅下载统一转 sing-box JSON 保存"
```

---

## Task 10: 文件导入与 UA 预设

**Files:**
- Modify: `singcast/lib/presentation/pages/profiles_page.dart`

**Interfaces:**
- Consumes: `LibCore.instance.convert`、`validateConfigFile`。

- [ ] **Step 1: 实现**

`_addFromFile` 改为：

```dart
final result = await FilePicker.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['yaml', 'yml', 'json'],
);
if (result == null || result.files.isEmpty) return;
final sourcePath = result.files.single.path;
if (sourcePath == null) return;

final fileName = p.basename(sourcePath);
if (profiles.value.any((e) => e.name == fileName)) {
  if (context.mounted) {
    showErrorDialog(context, t.profiles.configExists(name: fileName));
  }
  return;
}

try {
  final content = await File(sourcePath).readAsString();
  final jsonContent = await LibCore.instance.convert(content);
  final savedName =
      '${p.withoutExtension(fileName)}_${DateTime.now().millisecondsSinceEpoch}.json';
  final destPath = p.join(profilesFullPath, savedName);
  await File(destPath).writeAsString(jsonContent);
  await validateConfigFile(destPath);

  final profile = Profile(
    file: savedName,
    name: fileName,
    type: ProfileType.file,
    time: DateTime.now(),
  );
  final wasEmpty = profiles.value.isEmpty;
  profiles.value = [...profiles.value, profile];
  if (wasEmpty) selectedFile.value = savedName;
} catch (e) {
  if (context.mounted) showErrorDialog(context, t.profiles.fileCopyFailed(error: '$e'));
}
```

补 `import 'package:singcast/core/lib_core.dart';`。`_uniqueFileName` 若不再使用则删除。

- [ ] **Step 2: 编译确认**

Run: `dart analyze lib/presentation/pages/profiles_page.dart`
Expected: 无错误。

- [ ] **Step 3: 提交**

```bash
git add lib/presentation/pages/profiles_page.dart
git commit -m "feat(profiles): 文件导入支持 yaml/yml/json 并统一转 sing-box"
```

---

## Task 11: 统一迁移入口 migrateLegacy

**Files:**
- Create: `singcast/lib/services/migration.dart`
- Create: `singcast/test/services/migration_test.dart`
- Modify: `singcast/lib/main.dart`

**Interfaces:**
- Consumes: `CoreConfigStorage`、`AppSettingsStorage`、`validateConfigFile`、`LibCore.instance.convert`。
- Produces: `migrateLegacy({convert, validate}) → Future<void>`，两个依赖均可注入以便测试。

- [ ] **Step 1: 写失败测试**

`singcast/test/services/migration_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/services/migration.dart';
import 'package:singcast/utils/constants.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('singcast-migrate-test');
    Constants.homeDir = tmp;
    final profiles = Directory(p.join(tmp.path, 'profiles'));
    profiles.createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('migrates settings and file profile, deletes config.yaml marker', () async {
    File(p.join(tmp.path, 'config.yaml')).writeAsStringSync(
      'mixed-port: 8080\nmode: global\n',
    );
    final oldProfile = '123.yaml';
    File(p.join(tmp.path, 'profiles', oldProfile))
        .writeAsStringSync('proxies:\n  - name: p\n    type: ss\n');
    AppSettingsStorage.save({
      'profiles': [
        {
          'file': oldProfile,
          'name': 'legacy',
          'type': 'file',
          'time': '2026-08-02T00:00:00.000',
        }
      ],
    });

    await migrateLegacy(
      convert: (_) async => '{"outbounds":[]}',
      validate: (_) async {},
    );

    expect(File(p.join(tmp.path, 'config.yaml')).existsSync(), isFalse);
    expect(File(p.join(tmp.path, 'config.json')).existsSync(), isTrue);
    final stored = AppSettingsStorage.load()['profiles'] as List;
    final saved = stored.single as Map<String, dynamic>;
    expect((saved['file'] as String).endsWith('.json'), isTrue);
    expect(File(p.join(tmp.path, 'profiles', oldProfile)).existsSync(), isFalse);
  });

  test('skips when config.yaml missing', () async {
    AppSettingsStorage.save({'profiles': []});
    await migrateLegacy(convert: (_) async => '{}');
    expect(File(p.join(tmp.path, 'config.json')).existsSync(), isFalse);
  });

  test('url profile converts local file without refreshing', () async {
    File(p.join(tmp.path, 'config.yaml')).writeAsStringSync('mixed-port: 7890\n');
    final oldProfile = '456.yaml';
    File(p.join(tmp.path, 'profiles', oldProfile))
        .writeAsStringSync('proxies:\n  - name: p\n    type: ss\n');
    AppSettingsStorage.save({
      'profiles': [
        {
          'file': oldProfile,
          'name': 'legacy-url',
          'type': 'url',
          'time': '2026-08-02T00:00:00.000',
          'url': 'https://example.com/sub',
          'interval': 24,
        }
      ],
    });

    await migrateLegacy(
      convert: (_) async => '{"outbounds":[]}',
      validate: (_) async {},
    );

    expect(File(p.join(tmp.path, 'config.yaml')).existsSync(), isFalse);
    final stored = AppSettingsStorage.load()['profiles'] as List;
    final saved = stored.single as Map<String, dynamic>;
    // 不重新拉取：仍走本地文件转换，url 与类型原样保留
    expect(saved['type'], 'url');
    expect(saved['url'], 'https://example.com/sub');
    expect((saved['file'] as String).endsWith('.json'), isTrue);
    expect(
      File(p.join(tmp.path, 'profiles', oldProfile)).existsSync(),
      isFalse,
    );
  });

  test('keeps config.yaml marker when a profile fails to migrate', () async {
    File(p.join(tmp.path, 'config.yaml')).writeAsStringSync('mixed-port: 7890\n');
    final oldProfile = '789.yaml';
    File(p.join(tmp.path, 'profiles', oldProfile))
        .writeAsStringSync('proxies:\n  - name: p\n    type: ss\n');
    AppSettingsStorage.save({
      'profiles': [
        {
          'file': oldProfile,
          'name': 'legacy',
          'type': 'file',
          'time': '2026-08-02T00:00:00.000',
        }
      ],
    });

    await migrateLegacy(
      convert: (_) async => throw Exception('bad content'),
      validate: (_) async {},
    );

    expect(File(p.join(tmp.path, 'config.yaml')).existsSync(), isTrue);
    expect(File(p.join(tmp.path, 'config.json')).existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/migration_test.dart`
Expected: FAIL（`migrateLegacy` 未定义）。

- [ ] **Step 3: 实现**

`lib/services/migration.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:singcast/core/lib_core.dart';
import 'package:singcast/data/local/app_settings_storage.dart';
import 'package:singcast/data/local/core_config_storage.dart';
import 'package:singcast/domain/config.dart';
import 'package:singcast/domain/enums.dart';
import 'package:singcast/domain/profile.dart';
import 'package:singcast/services/subscription.dart';
import 'package:singcast/utils/constants.dart';
import 'package:singcast/utils/log_file.dart';
import 'package:yaml/yaml.dart';

/// 旧版（Clash YAML 时代）统一迁移入口。
///
/// 以 `config.yaml` 是否存在作为迁移标记：存在才执行；全部迁移成功后删除标记，
/// 任一设置/订阅迁移失败时保留标记，下次启动重试。异常不阻塞启动。
Future<void> migrateLegacy({
  Future<String> Function(String content)? convert,
  Future<void> Function(String filePath)? validate,
}) async {
  final legacyConfig = File(p.join(Constants.homeDir.path, 'config.yaml'));
  if (!legacyConfig.existsSync()) return;

  final converter = convert ?? (content) => LibCore.instance.convert(content);
  final validator = validate ?? validateConfigFile;

  var failed = false;

  // 1. 设置存储：旧 yaml → config.json
  try {
    final legacy = _loadLegacyConfig();
    if (legacy != null) {
      CoreConfigStorage.save(legacy);
    } else {
      failed = true;
    }
  } catch (e) {
    LogFileWriter.instance?.log(
      'migrate core config failed: $e',
      level: LogLevel.warning,
      name: 'migrate',
    );
    failed = true;
  }

  // 2. 订阅：URL 型与文件型统一走本地文件转换，迁移期不重新拉取
  final stored = AppSettingsStorage.load();
  final storedConfig = AppStoredConfig.fromJson(stored);
  final dir = Directory(p.join(Constants.homeDir.path, Constants.profilesDir));
  final migrated = <Profile>[];
  var changed = false;
  for (final profile in storedConfig.profiles) {
    if (!profile.file.endsWith('.yaml') && !profile.file.endsWith('.yml')) {
      migrated.add(profile);
      continue;
    }
    final path = p.join(dir.path, profile.file);
    if (!File(path).existsSync()) {
      migrated.add(profile);
      continue;
    }
    try {
      final next = await _convertLocalFile(
        dir: dir,
        profile: profile,
        converter: converter,
        validator: validator,
      );
      await File(path).delete();
      migrated.add(next);
      changed = true;
    } catch (e) {
      LogFileWriter.instance?.log(
        'legacy profile migration failed: ${profile.file}: $e',
        level: LogLevel.warning,
        name: 'migrate',
      );
      failed = true;
      migrated.add(profile);
    }
  }
  if (changed) {
    AppSettingsStorage.save(storedConfig.copyWith(profiles: migrated).toJson());
  }

  // 3. 完成标记：全部成功才删除，失败保留以便下次启动重试
  if (!failed) {
    try {
      await legacyConfig.delete();
    } catch (e) {
      LogFileWriter.instance?.log(
        'delete legacy config.yaml marker failed: $e',
        level: LogLevel.warning,
        name: 'migrate',
      );
    }
  }
}

Future<Profile> _convertLocalFile({
  required Directory dir,
  required Profile profile,
  required Future<String> Function(String content) converter,
  required Future<void> Function(String filePath) validator,
}) async {
  final content = await File(p.join(dir.path, profile.file)).readAsString();
  final jsonContent = await converter(content);
  final file = '${DateTime.now().millisecondsSinceEpoch}.json';
  await File(p.join(dir.path, file)).writeAsString(jsonContent);
  await validator(p.join(dir.path, file));
  return Profile(
    file: file,
    name: profile.name,
    type: profile.type,
    time: DateTime.now(),
    url: profile.url,
    interval: profile.interval,
    userinfo: profile.userinfo,
  );
}

SingboxConfig? _loadLegacyConfig() {
  try {
    final path = p.join(Constants.homeDir.path, 'config.yaml');
    final doc = loadYaml(File(path).readAsStringSync()) as Map;
    T? val<T>(String key) => doc[key] as T?;
    final modeStr = val<String>('mode');
    final logStr = val<String>('log-level');
    return SingboxConfig(
      mixedPort: val<int>('mixed-port'),
      allowLan: val<bool>('allow-lan'),
      mode: modeStr == null
          ? null
          : Mode.values.where((e) => e.name == modeStr).firstOrNull,
      logLevel: logStr == null
          ? null
          : LogLevel.values.where((e) => e.name == logStr).firstOrNull,
      ipv6: val<bool>('ipv6'),
      externalController: val<bool>('external-controller'),
      externalControllerAddr: val<String>('external-controller-addr'),
      portEnabled: val<bool>('port-enabled'),
      mixedSystemProxy: val<bool>('mixed-system-proxy'),
    );
  } catch (e) {
    LogFileWriter.instance?.log(
      'read legacy config.yaml failed: $e',
      level: LogLevel.warning,
      name: 'migrate',
    );
    return null;
  }
}
```

`lib/main.dart` 的 `_initApp` 中，`initCore` 的 try/catch 结束之后、`initCoreConfig()` 之前调用：

```dart
await migrateLegacy();
```

补 import：`import 'package:singcast/services/migration.dart';`。

> 时序满足：`LibCore.init` 已就绪（convert 可用），`config.yaml → config.json` 先于 `CoreConfigStorage.load()`。
> 迁移失败不抛到启动流程：内部已按 profile 记日志，设置迁移成功后即使订阅失败也保留标记，下次启动重试。
> iOS 的 convert 走 Runner 本地 FFI（Task 5），不依赖 VPN；校验仍走 RPC，VPN 未开启时校验失败会保留标记。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/migration_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/services/migration.dart test/services/migration_test.dart lib/main.dart
git commit -m "feat(migration): 启动最早阶段统一迁移旧 config.yaml 与订阅"
```

---

## Task 12: 依赖清理与文档

**Files:**
- Modify: `singcast/pubspec.yaml`
- Modify: `singcast/README.md`
- Modify: `singcast/README_zh.md`

**Interfaces:**
- Consumes: 前序任务（yaml_edit/settings_yaml 已无引用）。

- [ ] **Step 1: 清理依赖**

`pubspec.yaml` 删除 `settings_yaml` 与 `yaml_edit`（`yaml` 保留给迁移入口）。

Run: `flutter pub get`
Expected: 成功，无依赖报错。

- [ ] **Step 2: 更新 README**

`README_zh.md` 顶部标语与功能列表改为：

```markdown
支持 Clash 与 sing-box 订阅（导入后统一转换为 sing-box 配置运行）
```

`README.md` 同步英文表述。

- [ ] **Step 3: 验证**

Run: `dart analyze`
Expected: 无错误。

Run: `flutter test`
Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add pubspec.yaml pubspec.lock README.md README_zh.md
git commit -m "chore: 清理 Clash 时代依赖并更新文档"
```

---

## 最终验证

- [ ] **Step 1: Go 全量测试**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
gofmt -w translator/input.go translator/translator.go translator/translator_test.go core/service.go core/convert_test.go ipc/types.go ipc/handler.go ipc/handler_convert_test.go mobile/api.go
go test -tags 'with_clash_api,with_utls,with_quic,with_gvisor' ./translator/... ./core/... ./ipc/...
golangci-lint run ./...
```

Expected: PASS。

- [ ] **Step 2: Flutter 全量测试**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast
dart analyze
flutter test
```

Expected: PASS。

- [ ] **Step 3: 移动端绑定重生成（Task 5 前置，含 convert）**

```bash
cd /home/mapleafgo/Projects/OpenProject/singcast-cli
task mobile-all
```

将产物同步到 singcast 仓库（Android AAR 本仓库 gitignore，由 CI 从 release 下载；
iOS XCFramework 提交入库）。若本地无 gomobile/Xcode/NDK 环境，跳过并确保
singcast-cli 先发版、singcast CI 的 `CORE_VERSION` 指向新 release。

- [ ] **Step 4: 提交收尾（如有遗漏）**

```bash
git -C /home/mapleafgo/Projects/OpenProject/singcast-cli status --short
git -C /home/mapleafgo/Projects/OpenProject/singcast status --short
```

Expected: 两个仓库均无未提交变更。
