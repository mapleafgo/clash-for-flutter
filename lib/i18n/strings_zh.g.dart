///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsZh = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zh,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$nav$zh nav = Translations$nav$zh.internal(_root);
	late final Translations$home$zh home = Translations$home$zh.internal(_root);
	late final Translations$mode$zh mode = Translations$mode$zh.internal(_root);
	late final Translations$proxies$zh proxies = Translations$proxies$zh.internal(_root);
	late final Translations$profiles$zh profiles = Translations$profiles$zh.internal(_root);
	late final Translations$settings$zh settings = Translations$settings$zh.internal(_root);
	late final Translations$about$zh about = Translations$about$zh.internal(_root);
	late final Translations$dialogs$zh dialogs = Translations$dialogs$zh.internal(_root);
	late final Translations$tray$zh tray = Translations$tray$zh.internal(_root);
	late final Translations$core$zh core = Translations$core$zh.internal(_root);
	late final Translations$deepLink$zh deepLink = Translations$deepLink$zh.internal(_root);
	late final Translations$startup$zh startup = Translations$startup$zh.internal(_root);
	late final Translations$common$zh common = Translations$common$zh.internal(_root);
}

// Path: nav
class Translations$nav$zh {
	Translations$nav$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '首页'
	String get home => '首页';

	/// zh: '代理'
	String get proxies => '代理';

	/// zh: '订阅'
	String get profiles => '订阅';

	/// zh: '设置'
	String get settings => '设置';
}

// Path: home
class Translations$home$zh {
	Translations$home$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '网速'
	String get speed => '网速';

	/// zh: '活动连接'
	String get connections => '活动连接';

	/// zh: '个连接'
	String get connectionCount => '个连接';

	/// zh: '内存占用'
	String get memory => '内存占用';

	/// zh: '累计流量'
	String get trafficTotal => '累计流量';

	/// zh: '出站模式'
	String get outboundMode => '出站模式';

	/// zh: '代理模式'
	String get proxyMode => '代理模式';

	/// zh: '系统代理'
	String get systemProxy => '系统代理';

	/// zh: '等待内核就绪'
	String get waitingCore => '等待内核就绪';

	/// zh: '请先添加配置'
	String get pleaseAddProfile => '请先添加配置';

	/// zh: '开启'
	String get enable => '开启';

	/// zh: '复制'
	String get copy => '复制';

	/// zh: 'VPN 未连接'
	String get vpnNotConnected => 'VPN 未连接';

	/// zh: '代理功能仅在 VPN 连接后可用'
	String get connectVpnHint => '代理功能仅在 VPN 连接后可用';
}

// Path: mode
class Translations$mode$zh {
	Translations$mode$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '规则'
	String get rule => '规则';

	/// zh: '全局'
	String get global => '全局';

	/// zh: '直连'
	String get direct => '直连';
}

// Path: proxies
class Translations$proxies$zh {
	Translations$proxies$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '代理'
	String get title => '代理';

	/// zh: '排序'
	String get sort => '排序';

	/// zh: '测速'
	String get speedTest => '测速';

	/// zh: '暂无代理'
	String get empty => '暂无代理';

	/// zh: '添加订阅后，节点将出现在这里'
	String get emptyHint => '添加订阅后，节点将出现在这里';

	/// zh: '排序方式'
	String get sortTitle => '排序方式';

	/// zh: '默认'
	String get sortDefault => '默认';

	/// zh: '按名称'
	String get sortByName => '按名称';

	/// zh: '按延迟'
	String get sortByDelay => '按延迟';

	/// zh: '展开分组'
	String get expandGroups => '展开分组';

	/// zh: '选择分组'
	String get selectGroup => '选择分组';

	/// zh: '切换代理失败: $error'
	String switchFailed({required Object error}) => '切换代理失败: ${error}';

	/// zh: '该分组为自动选择，不支持手动切换'
	String get autoGroupHint => '该分组为自动选择，不支持手动切换';
}

// Path: profiles
class Translations$profiles$zh {
	Translations$profiles$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '订阅'
	String get title => '订阅';

	/// zh: '添加'
	String get add => '添加';

	/// zh: '添加订阅'
	String get addSubscription => '添加订阅';

	/// zh: '从文件'
	String get fromFile => '从文件';

	/// zh: '从 URL'
	String get fromUrl => '从 URL';

	/// zh: '修改'
	String get edit => '修改';

	/// zh: '移除'
	String get remove => '移除';

	/// zh: '更新'
	String get update => '更新';

	/// zh: '更新中...'
	String get updating => '更新中...';

	/// zh: '确认删除'
	String get confirmDelete => '确认删除';

	/// zh: '确定要删除「$name」吗？'
	String confirmDeleteMessage({required Object name}) => '确定要删除「${name}」吗？';

	/// zh: '配置「$name」已存在'
	String configExists({required Object name}) => '配置「${name}」已存在';

	/// zh: '文件复制失败: $error'
	String fileCopyFailed({required Object error}) => '文件复制失败: ${error}';

	/// zh: 'URL 校验失败: $error'
	String urlValidationFailed({required Object error}) => 'URL 校验失败: ${error}';

	/// zh: '更新失败: $error'
	String updateFailed({required Object error}) => '更新失败: ${error}';

	/// zh: '导入失败: $error'
	String importFailed({required Object error}) => '导入失败: ${error}';

	/// zh: '配置校验失败: $validation'
	String configValidationFailed({required Object validation}) => '配置校验失败: ${validation}';

	/// zh: '该订阅已存在'
	String get subscriptionExists => '该订阅已存在';

	/// zh: '输入订阅 URL'
	String get inputUrl => '输入订阅 URL';

	/// zh: '请输入'
	String get pleaseInput => '请输入';

	/// zh: '名称'
	String get name => '名称';

	/// zh: '更新间隔（小时）'
	String get updateIntervalHours => '更新间隔（小时）';

	/// zh: '暂无订阅'
	String get empty => '暂无订阅';

	/// zh: '点击右下角按钮添加订阅配置'
	String get emptyHint => '点击右下角按钮添加订阅配置';

	/// zh: '复制'
	String get copy => '复制';
}

// Path: settings
class Translations$settings$zh {
	Translations$settings$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '设置'
	String get title => '设置';

	/// zh: '内核'
	String get sectionCore => '内核';

	/// zh: '代理服务'
	String get proxyService => '代理服务';

	/// zh: '开启后提供 HTTP/SOCKS5 混合代理端口'
	String get proxyServiceDesc => '开启后提供 HTTP/SOCKS5 混合代理端口';

	/// zh: '允许局域网'
	String get allowLan => '允许局域网';

	/// zh: '允许局域网内其他设备通过代理上网'
	String get allowLanDesc => '允许局域网内其他设备通过代理上网';

	/// zh: '端口号'
	String get port => '端口号';

	/// zh: '代理服务监听的本地端口号'
	String get portDesc => '代理服务监听的本地端口号';

	/// zh: '请输入 1-65535 之间的端口号'
	String get portValidationError => '请输入 1-65535 之间的端口号';

	/// zh: '未设置'
	String get notSet => '未设置';

	/// zh: 'IPv6'
	String get ipv6 => 'IPv6';

	/// zh: '代理连接支持 IPv6 网络协议'
	String get ipv6Desc => '代理连接支持 IPv6 网络协议';

	/// zh: '出站模式'
	String get outboundMode => '出站模式';

	/// zh: '控制流量路由策略'
	String get outboundModeDesc => '控制流量路由策略';

	/// zh: 'TUN 协议栈'
	String get tunStack => 'TUN 协议栈';

	/// zh: '无网络时可切换为 gvisor 试试'
	String get tunStackDesc => '无网络时可切换为 gvisor 试试';

	/// zh: 'gvisor（兼容）'
	String get tunStackGvisor => 'gvisor（兼容）';

	/// zh: 'mixed（高性能）'
	String get tunStackMixed => 'mixed（高性能）';

	/// zh: 'system（内核）'
	String get tunStackSystem => 'system（内核）';

	/// zh: 'Clash API'
	String get clashApi => 'Clash API';

	/// zh: '对外提供代理状态查询和控制接口'
	String get clashApiDesc => '对外提供代理状态查询和控制接口';

	/// zh: 'API 地址'
	String get apiAddress => 'API 地址';

	/// zh: '日志等级'
	String get logLevel => '日志等级';

	/// zh: '等级越低记录越详细，调试时可选调试'
	String get logLevelDesc => '等级越低记录越详细，调试时可选调试';

	/// zh: '调试'
	String get logDebug => '调试';

	/// zh: '信息'
	String get logInfo => '信息';

	/// zh: '警告'
	String get logWarning => '警告';

	/// zh: '错误'
	String get logError => '错误';

	/// zh: '普通'
	String get sectionGeneral => '普通';

	/// zh: '订阅 User-Agent'
	String get subUserAgent => '订阅 User-Agent';

	/// zh: '订阅 User-Agent'
	String get subUaDialogTitle => '订阅 User-Agent';

	/// zh: '更新订阅时使用的 User-Agent 标识'
	String get subUaDialogDesc => '更新订阅时使用的 User-Agent 标识';

	/// zh: '输入 User-Agent'
	String get inputUa => '输入 User-Agent';

	/// zh: '默认'
	String get defaultValue => '默认';

	/// zh: '延迟测试 Url'
	String get delayTestUrl => '延迟测试 Url';

	/// zh: '测速时请求的目标地址'
	String get delayTestUrlDesc => '测速时请求的目标地址';

	/// zh: 'Rule-Set 代理'
	String get ruleSetProxy => 'Rule-Set 代理';

	/// zh: '下载 Rule-Set 规则集时使用的代理地址'
	String get ruleSetProxyDesc => '下载 Rule-Set 规则集时使用的代理地址';

	/// zh: '启动检查更新'
	String get autoCheckUpdate => '启动检查更新';

	/// zh: '应用启动时自动检查新版本'
	String get autoCheckUpdateDesc => '应用启动时自动检查新版本';

	/// zh: '外观'
	String get sectionAppearance => '外观';

	/// zh: '开机自启'
	String get autoStart => '开机自启';

	/// zh: '开机后自动启动并连接代理'
	String get autoStartDesc => '开机后自动启动并连接代理';

	/// zh: '主题'
	String get theme => '主题';

	/// zh: '切换应用外观风格'
	String get themeDesc => '切换应用外观风格';

	/// zh: '跟随系统'
	String get themeSystem => '跟随系统';

	/// zh: '浅色'
	String get themeLight => '浅色';

	/// zh: '深色'
	String get themeDark => '深色';

	/// zh: '语言'
	String get language => '语言';

	/// zh: '切换应用显示语言'
	String get languageDesc => '切换应用显示语言';

	/// zh: '跟随系统'
	String get languageSystem => '跟随系统';

	/// zh: '其他'
	String get sectionOther => '其他';

	/// zh: '关于'
	String get about => '关于';

	/// zh: '版本信息与相关链接'
	String get aboutDesc => '版本信息与相关链接';
}

// Path: about
class Translations$about$zh {
	Translations$about$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '关于'
	String get title => '关于';

	/// zh: '官方网站'
	String get officialWebsite => '官方网站';

	/// zh: '源码仓库'
	String get sourceRepo => '源码仓库';

	/// zh: '内核版本'
	String get kernelVersion => '内核版本';

	/// zh: '加载中...'
	String get loading => '加载中...';

	/// zh: '版本'
	String get version => '版本';

	/// zh: '发现新版本'
	String get newVersionFound => '发现新版本';

	/// zh: '当前版本: $current 最新版本: $latest'
	String versionInfo({required Object current, required Object latest}) => '当前版本: ${current}\n最新版本: ${latest}';

	/// zh: '忽略'
	String get ignore => '忽略';

	/// zh: '前往下载'
	String get goDownload => '前往下载';

	/// zh: '移除提权'
	String get removeElevation => '移除提权';

	/// zh: '确认移除提权'
	String get removeElevationConfirm => '确认移除提权';

	/// zh: '将移除 TUN 模式的提权服务，内核将以内置模式重启（TUN 不可用），下次使用 TUN 时需重新提权。'
	String get removeElevationDesc => '将移除 TUN 模式的提权服务，内核将以内置模式重启（TUN 不可用），下次使用 TUN 时需重新提权。';

	/// zh: '删除 Windows 服务并切换到内置内核'
	String get removeElevationWinDesc => '删除 Windows 服务并切换到内置内核';

	/// zh: '删除提权内核并切换到内置内核'
	String get removeElevationMacDesc => '删除提权内核并切换到内置内核';

	/// zh: '提权已移除，已切换到内置内核'
	String get elevationRemoved => '提权已移除，已切换到内置内核';

	/// zh: '操作失败'
	String get operationFailed => '操作失败';

	/// zh: '导出日志'
	String get exportLog => '导出日志';

	/// zh: '日志未初始化'
	String get logNotInitialized => '日志未初始化';

	/// zh: '日志文件不存在'
	String get logFileNotExist => '日志文件不存在';

	/// zh: '日志已导出'
	String get logExported => '日志已导出';

	/// zh: '导出失败'
	String get exportFailed => '导出失败';

	/// zh: '这都被你发现了！'
	String get easterEgg => '这都被你发现了！';
}

// Path: dialogs
class Translations$dialogs$zh {
	Translations$dialogs$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '错误'
	String get error => '错误';

	/// zh: '取消'
	String get cancel => '取消';

	/// zh: '确定'
	String get confirm => '确定';

	/// zh: '删除'
	String get delete => '删除';

	/// zh: '导入'
	String get import => '导入';

	/// zh: '复制'
	String get copy => '复制';
}

// Path: tray
class Translations$tray$zh {
	Translations$tray$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '显示窗口'
	String get showWindow => '显示窗口';

	/// zh: 'TUN 模式'
	String get tunMode => 'TUN 模式';

	/// zh: '系统代理'
	String get systemProxy => '系统代理';

	/// zh: '退出'
	String get exit => '退出';
}

// Path: core
class Translations$core$zh {
	Translations$core$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '内核连接失败: $error'
	String connectionFailed({required Object error}) => '内核连接失败: ${error}';

	/// zh: '内核初始化超时'
	String get initTimeout => '内核初始化超时';

	/// zh: '内核初始化失败: $error'
	String initFailed({required Object error}) => '内核初始化失败: ${error}';

	/// zh: '重新连接内核'
	String get reconnectCore => '重新连接内核';

	/// zh: '重启内核'
	String get restartCore => '重启内核';

	/// zh: '内核当前未连接，是否尝试重新连接？'
	String get reconnectMessage => '内核当前未连接，是否尝试重新连接？';

	/// zh: '是否重启内核服务？'
	String get restartMessage => '是否重启内核服务？';

	/// zh: '重新连接'
	String get reconnect => '重新连接';

	/// zh: '重启'
	String get restart => '重启';

	/// zh: '内核状态'
	String get coreState => '内核状态';

	/// zh: '内核未连接，点击重新连接'
	String get coreDisconnected => '内核未连接，点击重新连接';

	/// zh: '切换模式失败: $error'
	String modeSwitchFailed({required Object error}) => '切换模式失败: ${error}';

	/// zh: '提权设置失败，请重试'
	String get elevationFailed => '提权设置失败，请重试';
}

// Path: deepLink
class Translations$deepLink$zh {
	Translations$deepLink$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '导入订阅'
	String get importSubscription => '导入订阅';

	/// zh: '是否导入订阅「$name」？'
	String confirmImport({required Object name}) => '是否导入订阅「${name}」？';

	/// zh: '是否导入订阅？'
	String get confirmImportNoName => '是否导入订阅？';

	/// zh: '订阅导入成功'
	String get importSuccess => '订阅导入成功';

	/// zh: '订阅导入失败: $error'
	String importFailed({required Object error}) => '订阅导入失败: ${error}';
}

// Path: startup
class Translations$startup$zh {
	Translations$startup$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '发现新版本'
	String get newVersionFound => '发现新版本';

	/// zh: '当前版本: $current 最新版本: $latest'
	String currentAndLatest({required Object current, required Object latest}) => '当前版本: ${current}\n最新版本: ${latest}';

	/// zh: '下次提醒'
	String get remindLater => '下次提醒';

	/// zh: '忽略该版本'
	String get ignoreThisVersion => '忽略该版本';

	/// zh: '前往下载'
	String get goDownload => '前往下载';
}

// Path: common
class Translations$common$zh {
	Translations$common$zh.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// zh: '关闭'
	String get close => '关闭';
}

/// The flat map containing all translations for locale <zh>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'nav.home' => '首页',
			'nav.proxies' => '代理',
			'nav.profiles' => '订阅',
			'nav.settings' => '设置',
			'home.speed' => '网速',
			'home.connections' => '活动连接',
			'home.connectionCount' => '个连接',
			'home.memory' => '内存占用',
			'home.trafficTotal' => '累计流量',
			'home.outboundMode' => '出站模式',
			'home.proxyMode' => '代理模式',
			'home.systemProxy' => '系统代理',
			'home.waitingCore' => '等待内核就绪',
			'home.pleaseAddProfile' => '请先添加配置',
			'home.enable' => '开启',
			'home.copy' => '复制',
			'home.vpnNotConnected' => 'VPN 未连接',
			'home.connectVpnHint' => '代理功能仅在 VPN 连接后可用',
			'mode.rule' => '规则',
			'mode.global' => '全局',
			'mode.direct' => '直连',
			'proxies.title' => '代理',
			'proxies.sort' => '排序',
			'proxies.speedTest' => '测速',
			'proxies.empty' => '暂无代理',
			'proxies.emptyHint' => '添加订阅后，节点将出现在这里',
			'proxies.sortTitle' => '排序方式',
			'proxies.sortDefault' => '默认',
			'proxies.sortByName' => '按名称',
			'proxies.sortByDelay' => '按延迟',
			'proxies.expandGroups' => '展开分组',
			'proxies.selectGroup' => '选择分组',
			'proxies.switchFailed' => ({required Object error}) => '切换代理失败: ${error}',
			'proxies.autoGroupHint' => '该分组为自动选择，不支持手动切换',
			'profiles.title' => '订阅',
			'profiles.add' => '添加',
			'profiles.addSubscription' => '添加订阅',
			'profiles.fromFile' => '从文件',
			'profiles.fromUrl' => '从 URL',
			'profiles.edit' => '修改',
			'profiles.remove' => '移除',
			'profiles.update' => '更新',
			'profiles.updating' => '更新中...',
			'profiles.confirmDelete' => '确认删除',
			'profiles.confirmDeleteMessage' => ({required Object name}) => '确定要删除「${name}」吗？',
			'profiles.configExists' => ({required Object name}) => '配置「${name}」已存在',
			'profiles.fileCopyFailed' => ({required Object error}) => '文件复制失败: ${error}',
			'profiles.urlValidationFailed' => ({required Object error}) => 'URL 校验失败: ${error}',
			'profiles.updateFailed' => ({required Object error}) => '更新失败: ${error}',
			'profiles.importFailed' => ({required Object error}) => '导入失败: ${error}',
			'profiles.configValidationFailed' => ({required Object validation}) => '配置校验失败: ${validation}',
			'profiles.subscriptionExists' => '该订阅已存在',
			'profiles.inputUrl' => '输入订阅 URL',
			'profiles.pleaseInput' => '请输入',
			'profiles.name' => '名称',
			'profiles.updateIntervalHours' => '更新间隔（小时）',
			'profiles.empty' => '暂无订阅',
			'profiles.emptyHint' => '点击右下角按钮添加订阅配置',
			'profiles.copy' => '复制',
			'settings.title' => '设置',
			'settings.sectionCore' => '内核',
			'settings.proxyService' => '代理服务',
			'settings.proxyServiceDesc' => '开启后提供 HTTP/SOCKS5 混合代理端口',
			'settings.allowLan' => '允许局域网',
			'settings.allowLanDesc' => '允许局域网内其他设备通过代理上网',
			'settings.port' => '端口号',
			'settings.portDesc' => '代理服务监听的本地端口号',
			'settings.portValidationError' => '请输入 1-65535 之间的端口号',
			'settings.notSet' => '未设置',
			'settings.ipv6' => 'IPv6',
			'settings.ipv6Desc' => '代理连接支持 IPv6 网络协议',
			'settings.outboundMode' => '出站模式',
			'settings.outboundModeDesc' => '控制流量路由策略',
			'settings.tunStack' => 'TUN 协议栈',
			'settings.tunStackDesc' => '无网络时可切换为 gvisor 试试',
			'settings.tunStackGvisor' => 'gvisor（兼容）',
			'settings.tunStackMixed' => 'mixed（高性能）',
			'settings.tunStackSystem' => 'system（内核）',
			'settings.clashApi' => 'Clash API',
			'settings.clashApiDesc' => '对外提供代理状态查询和控制接口',
			'settings.apiAddress' => 'API 地址',
			'settings.logLevel' => '日志等级',
			'settings.logLevelDesc' => '等级越低记录越详细，调试时可选调试',
			'settings.logDebug' => '调试',
			'settings.logInfo' => '信息',
			'settings.logWarning' => '警告',
			'settings.logError' => '错误',
			'settings.sectionGeneral' => '普通',
			'settings.subUserAgent' => '订阅 User-Agent',
			'settings.subUaDialogTitle' => '订阅 User-Agent',
			'settings.subUaDialogDesc' => '更新订阅时使用的 User-Agent 标识',
			'settings.inputUa' => '输入 User-Agent',
			'settings.defaultValue' => '默认',
			'settings.delayTestUrl' => '延迟测试 Url',
			'settings.delayTestUrlDesc' => '测速时请求的目标地址',
			'settings.ruleSetProxy' => 'Rule-Set 代理',
			'settings.ruleSetProxyDesc' => '下载 Rule-Set 规则集时使用的代理地址',
			'settings.autoCheckUpdate' => '启动检查更新',
			'settings.autoCheckUpdateDesc' => '应用启动时自动检查新版本',
			'settings.sectionAppearance' => '外观',
			'settings.autoStart' => '开机自启',
			'settings.autoStartDesc' => '开机后自动启动并连接代理',
			'settings.theme' => '主题',
			'settings.themeDesc' => '切换应用外观风格',
			'settings.themeSystem' => '跟随系统',
			'settings.themeLight' => '浅色',
			'settings.themeDark' => '深色',
			'settings.language' => '语言',
			'settings.languageDesc' => '切换应用显示语言',
			'settings.languageSystem' => '跟随系统',
			'settings.sectionOther' => '其他',
			'settings.about' => '关于',
			'settings.aboutDesc' => '版本信息与相关链接',
			'about.title' => '关于',
			'about.officialWebsite' => '官方网站',
			'about.sourceRepo' => '源码仓库',
			'about.kernelVersion' => '内核版本',
			'about.loading' => '加载中...',
			'about.version' => '版本',
			'about.newVersionFound' => '发现新版本',
			'about.versionInfo' => ({required Object current, required Object latest}) => '当前版本: ${current}\n最新版本: ${latest}',
			'about.ignore' => '忽略',
			'about.goDownload' => '前往下载',
			'about.removeElevation' => '移除提权',
			'about.removeElevationConfirm' => '确认移除提权',
			'about.removeElevationDesc' => '将移除 TUN 模式的提权服务，内核将以内置模式重启（TUN 不可用），下次使用 TUN 时需重新提权。',
			'about.removeElevationWinDesc' => '删除 Windows 服务并切换到内置内核',
			'about.removeElevationMacDesc' => '删除提权内核并切换到内置内核',
			'about.elevationRemoved' => '提权已移除，已切换到内置内核',
			'about.operationFailed' => '操作失败',
			'about.exportLog' => '导出日志',
			'about.logNotInitialized' => '日志未初始化',
			'about.logFileNotExist' => '日志文件不存在',
			'about.logExported' => '日志已导出',
			'about.exportFailed' => '导出失败',
			'about.easterEgg' => '这都被你发现了！',
			'dialogs.error' => '错误',
			'dialogs.cancel' => '取消',
			'dialogs.confirm' => '确定',
			'dialogs.delete' => '删除',
			'dialogs.import' => '导入',
			'dialogs.copy' => '复制',
			'tray.showWindow' => '显示窗口',
			'tray.tunMode' => 'TUN 模式',
			'tray.systemProxy' => '系统代理',
			'tray.exit' => '退出',
			'core.connectionFailed' => ({required Object error}) => '内核连接失败: ${error}',
			'core.initTimeout' => '内核初始化超时',
			'core.initFailed' => ({required Object error}) => '内核初始化失败: ${error}',
			'core.reconnectCore' => '重新连接内核',
			'core.restartCore' => '重启内核',
			'core.reconnectMessage' => '内核当前未连接，是否尝试重新连接？',
			'core.restartMessage' => '是否重启内核服务？',
			'core.reconnect' => '重新连接',
			'core.restart' => '重启',
			'core.coreState' => '内核状态',
			'core.coreDisconnected' => '内核未连接，点击重新连接',
			'core.modeSwitchFailed' => ({required Object error}) => '切换模式失败: ${error}',
			'core.elevationFailed' => '提权设置失败，请重试',
			'deepLink.importSubscription' => '导入订阅',
			'deepLink.confirmImport' => ({required Object name}) => '是否导入订阅「${name}」？',
			'deepLink.confirmImportNoName' => '是否导入订阅？',
			'deepLink.importSuccess' => '订阅导入成功',
			'deepLink.importFailed' => ({required Object error}) => '订阅导入失败: ${error}',
			'startup.newVersionFound' => '发现新版本',
			'startup.currentAndLatest' => ({required Object current, required Object latest}) => '当前版本: ${current}\n最新版本: ${latest}',
			'startup.remindLater' => '下次提醒',
			'startup.ignoreThisVersion' => '忽略该版本',
			'startup.goDownload' => '前往下载',
			'common.close' => '关闭',
			_ => null,
		};
	}
}
