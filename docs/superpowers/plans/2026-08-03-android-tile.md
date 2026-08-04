# 安卓快速设置磁贴（VPN 快捷开关）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Android 快速设置提供磁贴，点按直接开/关 VPN（关 = 完全直连），仅图标着色区分连接态，长按进入应用。

**Architecture:** 磁贴是原生 `TileService`，直接驱动现有 `SingcastVpnService`（`VpnService`）。建连要素从既有文件读取：`cache-tun.json`（TUN 启动配置与 `ipv6`）、`settings.json`（`rule-set-proxy`），不新增 SharedPreferences 字段。

**Tech Stack:** Kotlin / Android SDK (`TileService`, `VpnService`), Flutter/Dart, JUnit, org.json, Gradle。

## Global Constraints

- `minSdkVersion 34`（Android 14）。磁贴不自动添加（不做 `requestAddTileService`），各版本均手动加入。
- 磁贴仅图标、无文字；用 `Tile.STATE_ACTIVE` / `Tile.STATE_INACTIVE` 表示 已连接 / 未连接。
- 断开 = 完全直连：走 `SingcastVpnService.disconnect`（内部 `stopCore` + `stopForeground`），**不**拉起非 VPN 代理实例。
- 建连要素来源固定：
  - `configContent` ← `context.filesDir/cache-tun.json`
  - `ipv6` ← 同一文件的 `dns.strategy == "prefer_ipv6"`
  - `ruleSetProxy` ← `context.filesDir/settings.json` 的 `rule-set-proxy`
- 不做设置页"显示磁贴"开关；不动语言持久化。
- 现有 `ruleSetProxy` 未持久化是 bug，本计划按 `subUA` 同款方式补进 `settings.json`（key 用 `rule-set-proxy`，kebab-case 对齐 `sub-ua`）。
- 代码注释、commit message 用中文；标识符用英文。

---

## File Structure

新建/修改的文件及职责：

- `lib/data/local/app_settings_storage.dart`：`AppStoredConfig` 增加 `ruleSetProxy` 字段（fromJson/toJson/copyWith）。
- `lib/services/app_config.dart`：`initAppConfig` 读回、`_save` 写入、`_startAutoSave` effect 跟踪 `ruleSetProxy`。
- `test/settings_storage_test.dart`：`ruleSetProxy` 持久化单测。
- `android/app/src/main/kotlin/cn/mapleafgo/singcast/TileConfig.kt`：`TileVpnConfig` 数据类 + `TileConfigReader`（纯 `parse` 逻辑可 JVM 单测）。
- `android/app/src/test/kotlin/cn/mapleafgo/singcast/TileConfigReaderTest.kt`：原生配置解析单测。
- `android/app/src/main/kotlin/cn/mapleafgo/singcast/TileVpnConnector.kt`：统一"读配置 → 启 `SingcastVpnService`；缺 tun 配置时不操作 VPN"。
- `android/app/src/main/kotlin/cn/mapleafgo/singcast/VpnPermissionActivity.kt`：`VpnService.prepare` 授权中转（透明、自动 finish）。
- `android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastTileService.kt`：`TileService`，点按启停 + 状态刷新。
- `android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastVpnService.kt`：新增 `ACTION_DISCONNECT_TILE`。
- `android/app/src/main/res/drawable/tile_icon.xml`：磁贴单色图标。
- `android/app/src/main/AndroidManifest.xml`：注册磁贴服务与授权 Activity。
- `android/app/src/main/res/values/strings.xml` / `values-zh/strings.xml`：磁贴 label。
- `android/app/build.gradle`：初始化 JVM 测试依赖与 test 源集。

---

### Task 1: `ruleSetProxy` 持久化（Flutter）

**Files:**
- Modify: `lib/data/local/app_settings_storage.dart`
- Modify: `lib/services/app_config.dart`
- Test: `test/settings_storage_test.dart`

**Interfaces:**
- Consumes: 既有 `AppStoredConfig`、`Defaults.ruleSetProxy`。
- Produces: `AppStoredConfig.ruleSetProxy`（`String`，默认 `Defaults.ruleSetProxy`）；`settings.json` 的 `rule-set-proxy` 键。

- [ ] **Step 1: 写失败测试**

在 `test/settings_storage_test.dart` 顶部增加 `import 'package:singcast/utils/constants.dart';`，文件末尾追加：

```dart
group('AppStoredConfig ruleSetProxy', () {
  test('fromJson 默认值取 Defaults.ruleSetProxy', () {
    final config = AppStoredConfig.fromJson({});
    expect(config.ruleSetProxy, Defaults.ruleSetProxy);
  });

  test('fromJson 正确读取 rule-set-proxy', () {
    final config = AppStoredConfig.fromJson({'rule-set-proxy': 'https://example.com'});
    expect(config.ruleSetProxy, 'https://example.com');
  });

  test('toJson 在非默认值时写入 rule-set-proxy', () {
    final config = AppStoredConfig.empty().copyWith(ruleSetProxy: 'https://example.com');
    expect(config.toJson()['rule-set-proxy'], 'https://example.com');
  });

  test('toJson 在默认值时省略 rule-set-proxy', () {
    final config = AppStoredConfig.empty();
    expect(config.toJson().containsKey('rule-set-proxy'), false);
  });

  test('copyWith 保留原值', () {
    final config = AppStoredConfig.empty().copyWith(ruleSetProxy: 'https://example.com');
    final copied = config.copyWith();
    expect(copied.ruleSetProxy, 'https://example.com');
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

```bash
flutter test test/settings_storage_test.dart
```

Expected: 因 `ruleSetProxy` 字段不存在而编译失败 / 断言失败。

- [ ] **Step 3: `AppStoredConfig` 增加字段**

在 `lib/data/local/app_settings_storage.dart` 中给 `AppStoredConfig` 增加（参照 `subUA` 同款写法）：

```dart
  final String ruleSetProxy;

  AppStoredConfig({
    this.selectedFile,
    required this.profiles,
    required this.delayTestUrl,
    this.tunIf,
    String? subUA,
    this.themeMode,
    this.ignoredVersion,
    this.autoCheckUpdate = true,
    this.locale,
    this.autoStart = false,
    this.tunStack = TunStack.mixed,
    String? ruleSetProxy,
  }) : subUA = subUA ?? Defaults.subUA,
       ruleSetProxy = ruleSetProxy ?? Defaults.ruleSetProxy;
```

`fromJson` 增加：`ruleSetProxy: json['rule-set-proxy'] as String?,`。

`toJson` 增加（参照 `subUA`）：

```dart
    if (ruleSetProxy != Defaults.ruleSetProxy) 'rule-set-proxy': ruleSetProxy,
```

`copyWith` 增加 `String? ruleSetProxy,` 参数并赋值 `ruleSetProxy: ruleSetProxy ?? this.ruleSetProxy,`。

- [ ] **Step 4: `app_config.dart` 接线**

`initAppConfig` 中（`subUA.value = stored.subUA;` 之后）增加：

```dart
  ruleSetProxy.value = stored.ruleSetProxy;
```

`_startAutoSave` 的 `effect` 依赖列表增加一行 `ruleSetProxy.value;`。

`_save()` 的 `AppStoredConfig(...)` 构造增加 `ruleSetProxy: ruleSetProxy.value,`。

- [ ] **Step 5: 跑测试确认通过**

```bash
flutter test test/settings_storage_test.dart
```

Expected: 全绿。

- [ ] **Step 6: Commit**

```bash
git add lib/data/local/app_settings_storage.dart lib/services/app_config.dart test/settings_storage_test.dart
git commit -m "fix: ruleSetProxy 持久化到 settings.json

现状 ruleSetProxy 仅存内存 signal，重启即丢用户自定义值。
按 subUA 同款方式写入 settings.json（键 rule-set-proxy），
并为安卓快速设置磁贴提供建连要素来源。"
```

---

### Task 2: 原生配置读取器 + JVM 测试基建

**Files:**
- Create: `android/app/src/main/kotlin/cn/mapleafgo/singcast/TileConfig.kt`
- Test: `android/app/src/test/kotlin/cn/mapleafgo/singcast/TileConfigReaderTest.kt`
- Modify: `android/app/build.gradle`

**Interfaces:**
- Consumes: 无（纯逻辑）。
- Produces: `data class TileVpnConfig(configContent: String?, ipv6: Boolean, ruleSetProxy: String)`；`object TileConfigReader { fun parse(mergedContent: String?, settingsJson: String?): TileVpnConfig; fun read(context: Context): TileVpnConfig }`。

- [ ] **Step 1: 加测试依赖与 test 源集**

在 `android/app/build.gradle` 的 `sourceSets` 块改为：

```groovy
  sourceSets {
    main.java.srcDirs += 'src/main/kotlin'
    test.java.srcDirs += 'src/test/kotlin'
  }
```

`dependencies` 块增加：

```groovy
  testImplementation 'junit:junit:4.13.2'
  testImplementation 'org.json:json:20240303'
```

- [ ] **Step 2: 写失败测试**

创建 `android/app/src/test/kotlin/cn/mapleafgo/singcast/TileConfigReaderTest.kt`：

```kotlin
package cn.mapleafgo.singcast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TileConfigReaderTest {
    private val mergedWithoutDns = """{"inbounds":[]}"""
    private val mergedIpv6 = """{"dns":{"strategy":"prefer_ipv6"}}"""
    private val mergedIpv4 = """{"dns":{"strategy":"ipv4_only"}}"""

    @Test
    fun noConfig_returnsBlankContent() {
        val cfg = TileConfigReader.parse(null, null)
        assertNull(cfg.configContent)
        assertFalse(cfg.ipv6)
        assertEquals("https://gh-proxy.org", cfg.ruleSetProxy)
    }

    @Test
    fun mergedContent_returnedAsIs() {
        val cfg = TileConfigReader.parse(mergedWithoutDns, null)
        assertEquals(mergedWithoutDns, cfg.configContent)
    }

    @Test
    fun preferIpv6_mapsTrue() {
        val cfg = TileConfigReader.parse(mergedIpv6, null)
        assertTrue(cfg.ipv6)
    }

    @Test
    fun ipv4Only_mapsFalse() {
        val cfg = TileConfigReader.parse(mergedIpv4, null)
        assertFalse(cfg.ipv6)
    }

    @Test
    fun missingDns_mapsFalse() {
        val cfg = TileConfigReader.parse(mergedWithoutDns, null)
        assertFalse(cfg.ipv6)
    }

    @Test
    fun ruleSetProxy_readFromSettings() {
        val cfg = TileConfigReader.parse(null, """{"rule-set-proxy":"https://example.com"}""")
        assertEquals("https://example.com", cfg.ruleSetProxy)
    }

    @Test
    fun missingRuleSetProxy_fallsBackToDefault() {
        val cfg = TileConfigReader.parse(null, """{"sub-ua":"x"}""")
        assertEquals("https://gh-proxy.org", cfg.ruleSetProxy)
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

```bash
cd android && ./gradlew :app:testDebugUnitTest --tests "cn.mapleafgo.singcast.TileConfigReaderTest"
```

Expected: FAIL（`TileConfigReader` 不存在）。

- [ ] **Step 4: 实现 `TileConfig` / `TileConfigReader`**

创建 `android/app/src/main/kotlin/cn/mapleafgo/singcast/TileConfig.kt`：

```kotlin
package cn.mapleafgo.singcast

import android.content.Context
import org.json.JSONObject
import java.io.File

/// 磁贴建连所需的三个要素。
data class TileVpnConfig(
    val configContent: String?,
    val ipv6: Boolean,
    val ruleSetProxy: String,
)

/// 从既有磁盘文件组装磁贴建连参数，不新增持久化字段。
object TileConfigReader {
    /// 与 Dart 侧 Defaults.ruleSetProxy 保持一致。
    private const val DEFAULT_RULE_SET_PROXY = "https://gh-proxy.org"

    fun read(context: Context): TileVpnConfig {
        val filesDir = context.filesDir
        val merged = File(filesDir, "cache-tun.json").takeIf { it.exists() }?.readText()
        val settings = File(filesDir, "settings.json").takeIf { it.exists() }?.readText()
        return parse(merged, settings)
    }

    /// 纯函数，便于 JVM 单测。
    fun parse(mergedContent: String?, settingsJson: String?): TileVpnConfig {
        val content = mergedContent?.trim()?.takeIf { it.isNotEmpty() }
        return TileVpnConfig(
            configContent = content,
            ipv6 = parseIpv6(content),
            ruleSetProxy = parseRuleSetProxy(settingsJson),
        )
    }

    private fun parseIpv6(content: String?): Boolean {
        if (content.isNullOrEmpty()) return false
        return try {
            val dns = JSONObject(content).optJSONObject("dns")
            dns?.optString("strategy") == "prefer_ipv6"
        } catch (e: Exception) {
            false
        }
    }

    private fun parseRuleSetProxy(settingsJson: String?): String {
        if (settingsJson.isNullOrEmpty()) return DEFAULT_RULE_SET_PROXY
        return try {
            JSONObject(settingsJson).optString("rule-set-proxy", DEFAULT_RULE_SET_PROXY)
        } catch (e: Exception) {
            DEFAULT_RULE_SET_PROXY
        }
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd android && ./gradlew :app:testDebugUnitTest --tests "cn.mapleafgo.singcast.TileConfigReaderTest"
```

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add android/app/build.gradle android/app/src/main/kotlin/cn/mapleafgo/singcast/TileConfig.kt android/app/src/test/kotlin/cn/mapleafgo/singcast/TileConfigReaderTest.kt
git commit -m "feat: 新增磁贴建连配置读取器及 JVM 测试基建

从 cache-tun.json（configContent/ipv6）与 settings.json（rule-set-proxy）
组装磁贴建连参数；parse 为纯函数，并以 org.json+JUnit 初始化原生单元测试。"
```

---

### Task 3: 磁贴启停连接器与断开 action

**Files:**
- Create: `android/app/src/main/kotlin/cn/mapleafgo/singcast/TileVpnConnector.kt`
- Modify: `android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastVpnService.kt`

**Interfaces:**
- Consumes: `TileVpnConfig` / `TileConfigReader`（Task 2）、`SingcastVpnService.ACTION_CONNECT/EXTRA_*`。
- Produces: `object TileVpnConnector { fun startVpn(context: Context) }`；`SingcastVpnService.ACTION_DISCONNECT_TILE`。

- [ ] **Step 1: 写 `TileVpnConnector`**

创建 `android/app/src/main/kotlin/cn/mapleafgo/singcast/TileVpnConnector.kt`：

```kotlin
package cn.mapleafgo.singcast

import android.content.Context
import android.content.Intent

/// 统一"读配置 → 启动 VPN 服务"；缺 tun 配置时不操作 VPN。
object TileVpnConnector {
    fun startVpn(context: Context) {
        val cfg = TileConfigReader.read(context)
        val content = cfg.configContent
        if (content.isNullOrEmpty()) {
            val launcher = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launcher != null) {
                launcher.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launcher)
            }
            return
        }
        val intent = Intent(context, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_CONNECT
            putExtra(SingcastVpnService.EXTRA_CONFIG, content)
            putExtra(SingcastVpnService.EXTRA_PROXY, cfg.ruleSetProxy)
            putExtra(SingcastVpnService.EXTRA_IPV6, cfg.ipv6)
        }
        context.startService(intent)
    }
}
```

- [ ] **Step 2: `SingcastVpnService` 增加断开 action**

在 `SingcastVpnService.kt` 的 companion 常量区（`ACTION_DISCONNECT_NOTIFY` 附近）增加：

```kotlin
        /// 磁贴主动断开的 action：断开到完全直连（不复用 ACTION_DISCONNECT_NOTIFY
        /// 那条回退非 VPN 代理的逻辑）。
        const val ACTION_DISCONNECT_TILE = "cn.mapleafgo.singcast.DISCONNECT_TILE"
```

在 `onStartCommand` 的 `when` 里、`ACTION_DISCONNECT_NOTIFY` 分支后增加：

```kotlin
            ACTION_DISCONNECT_TILE -> {
                AppLog.i(TAG, "onStartCommand: DISCONNECT (tile)")
                disconnect("tile_disconnect")
                stopSelf()
            }
```

说明：`disconnect` 内部已 `stopCore` + `stopForeground`，即"完全直连"；`reason != REASON_USER_DISCONNECT` 时其会回传 `onVpnDisconnected` 通知 Flutter 同步状态，符合预期。

- [ ] **Step 3: 编译验证**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/cn/mapleafgo/singcast/TileVpnConnector.kt android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastVpnService.kt
git commit -m "feat: 磁贴启停连接器与断开 action

新增 TileVpnConnector：读配置启 SingcastVpnService，缺 tun 配置时不操作 VPN。
SingcastVpnService 新增 ACTION_DISCONNECT_TILE，断开即完全直连，
不复用通知栏按钮回退非 VPN 代理的逻辑。"
```

---

### Task 4: TileService、授权中转 Activity 与 Manifest

**Files:**
- Create: `android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastTileService.kt`
- Create: `android/app/src/main/kotlin/cn/mapleafgo/singcast/VpnPermissionActivity.kt`
- Create: `android/app/src/main/res/drawable/tile_icon.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/res/values/strings.xml`
- Modify: `android/app/src/main/res/values-zh/strings.xml`

**Interfaces:**
- Consumes: `TileVpnConnector`、`SingcastVpnService.isServiceRunning`、`ACTION_DISCONNECT_TILE`（Task 3）。
- Produces: 注册的磁贴服务与授权 Activity；磁贴 icon/label。

- [ ] **Step 1: 写 `SingcastTileService`**

创建 `android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastTileService.kt`：

```kotlin
package cn.mapleafgo.singcast

import android.content.Intent
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class SingcastTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (SingcastVpnService.isServiceRunning) {
            toggleOff()
        } else {
            toggleOn()
        }
    }

    /// 仅图标着色：STATE_ACTIVE(已连接) / STATE_INACTIVE(未连接)。
    private fun updateTile() {
        val tile = qsTile ?: return
        val running = SingcastVpnService.isServiceRunning
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        qsTile = tile
    }

    private fun toggleOn() {
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            // 未授权：拉起透明授权 Activity，其一并在授权成功后建连并 finish。
            startActivityAndCollapse(Intent(this, VpnPermissionActivity::class.java))
        } else {
            TileVpnConnector.startVpn(this)
        }
    }

    private fun toggleOff() {
        // 完全直连：走服务自身 disconnect（内部 stopCore + stopForeground）。
        val intent = Intent(this, SingcastVpnService::class.java).apply {
            action = SingcastVpnService.ACTION_DISCONNECT_TILE
        }
        startService(intent)
    }
}
```

- [ ] **Step 2: 写 `VpnPermissionActivity`**

创建 `android/app/src/main/kotlin/cn/mapleafgo/singcast/VpnPermissionActivity.kt`：

```kotlin
package cn.mapleafgo.singcast

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

/// 磁贴首次建连时的 VPN 授权中转：透明、授权成功后建连并自动 finish，
/// 不展示 App 界面。
class VpnPermissionActivity : Activity() {
    companion object {
        private const val REQ_VPN = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivityForResult(prepare, REQ_VPN)
        } else {
            TileVpnConnector.startVpn(this)
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN && resultCode == RESULT_OK) {
            TileVpnConnector.startVpn(this)
        }
        finish()
    }
}
```

- [ ] **Step 3: 写磁贴图标**

创建 `android/app/src/main/res/drawable/tile_icon.xml`（单色电源图标）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp"
    android:height="48dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M11,2v9h2V2h-2zM13.5,5.5v2.2c2.1,0.9 3.5,2.9 3.5,5.3c0,3.1 -2.5,5.5 -5,5.5c-2.5,0 -5,-2.4 -5,-5.5c0,-2.4 1.4,-4.4 3.5,-5.3V5.5C6.8,6.5 5,9.2 5,12c0,3.9 3.1,7 7,7s7,-3.1 7,-7C19,9.2 17.2,6.5 13.5,5.5z"/>
</vector>
```

- [ ] **Step 4: Manifest 注册**

在 `android/app/src/main/AndroidManifest.xml` 中、`</application>` 之前增加：

```xml
    <service
        android:name=".SingcastTileService"
        android:label="@string/tile_label"
        android:icon="@drawable/tile_icon"
        android:exported="true"
        android:permission="android.permission.BIND_QUICK_SETTINGS_TILE">
      <intent-filter>
        <action android:name="android.service.quicksettings.action.QS_TILE" />
      </intent-filter>
    </service>

    <activity
        android:name=".VpnPermissionActivity"
        android:exported="false"
        android:excludeFromRecents="true"
        android:launchMode="singleInstance"
        android:theme="@android:style/Theme.Translucent.NoTitleBar" />
```

注意：**不要**加 `android.service.quicksettings.default_tile` meta-data（不做磁贴自动添加）。

- [ ] **Step 5: 增加 label 字符串**

`android/app/src/main/res/values/strings.xml` 增加：

```xml
    <string name="tile_label">Singcast VPN</string>
```

`android/app/src/main/res/values-zh/strings.xml` 增加：

```xml
    <string name="tile_label">Singcast VPN</string>
```

- [ ] **Step 6: 编译验证**

```bash
cd android && ./gradlew :app:compileDebugKotlin
```

Expected: BUILD SUCCESSFUL。

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/cn/mapleafgo/singcast/SingcastTileService.kt android/app/src/main/kotlin/cn/mapleafgo/singcast/VpnPermissionActivity.kt android/app/src/main/res/drawable/tile_icon.xml android/app/src/main/AndroidManifest.xml android/app/src/main/res/values/strings.xml android/app/src/main/res/values-zh/strings.xml
git commit -m "feat: 接入安卓快速设置磁贴

新增 SingcastTileService：点按启用/断开 VPN，仅图标着色区分状态，
长按进入应用；新增 VpnPermissionActivity 承接首次授权，授权后建连并自动
finish。磁贴不做自动添加。"
```

---

### Task 5: 整体验证

**Files:**
- 无新文件（验证与收尾）。

**Interfaces:**
- 无。

- [ ] **Step 1: 跑 Flutter 静态检查与测试**

```bash
flutter analyze
flutter test
```

Expected: 均通过（`flutter analyze` 无 error，`flutter test` 全绿）。

- [ ] **Step 2: 构建 Android debug APK**

```bash
flutter build apk --debug
```

Expected: BUILD SUCCESSFUL，产出 `build/app/outputs/flutter-apk/app-debug.apk`。

- [ ] **Step 3: 打包手动验收清单**

在真机/模拟器逐项人工验证：

1. 快速设置编辑页手动加入磁贴。
2. 未连接时点按 → 首次弹 VPN 授权 → 授权后建连，磁贴转"已连接"着色。
3. 再点按 → 断开到完全直连，磁贴转"未连接"着色。
4. 长按磁贴 → 进入 App 首页。
5. 无配置（删除/缺失 `cache-tun.json`）点按 → 仅提示，不操作 VPN。
6. App 内连接/断开后，磁贴下拉刷新状态与之一致。

---

## Self-Review

**Spec 覆盖：** 磁贴点按开关（Task 3/4）、仅图标着色（Task 4 Step 1）、长按进应用（依赖 Manifest 注册 + 系统默认行为，Task 4）、建连要素来源（Task 2/3）、错误处理（无配置点按仅提示不操作 VPN：Task 3 Step 1；授权拒绝即 finish：Task 4 Step 2；内核失败由 `SingcastVpnService` 兜底：Task 3 Step 2）、平台兼容不做自动添加（Task 4 Step 4）、`ruleSetProxy` 持久化修复（Task 1）、语言不动（未列入任务，符合"非目标"）。

**占位符扫描：** 无 TBD/TODO；每个代码/测试步骤均给出完整内容与可执行命令。

**类型一致性：** `TileVpnConfig/parse/read`、`TileVpnConnector.startVpn`、`ACTION_DISCONNECT_TILE`、`EXTRA_CONFIG/EXTRA_PROXY/EXTRA_IPV6` 在各任务签名一致；JSON 键 `rule-set-proxy`、`dns.strategy` 在 Task 1 与 Task 2 中保持一致。
