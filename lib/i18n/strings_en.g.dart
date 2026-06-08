///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsEn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsEn _root = this; // ignore: unused_field

	@override 
	TranslationsEn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEn(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$nav$en nav = _Translations$nav$en._(_root);
	@override late final _Translations$home$en home = _Translations$home$en._(_root);
	@override late final _Translations$mode$en mode = _Translations$mode$en._(_root);
	@override late final _Translations$proxies$en proxies = _Translations$proxies$en._(_root);
	@override late final _Translations$profiles$en profiles = _Translations$profiles$en._(_root);
	@override late final _Translations$settings$en settings = _Translations$settings$en._(_root);
	@override late final _Translations$about$en about = _Translations$about$en._(_root);
	@override late final _Translations$dialogs$en dialogs = _Translations$dialogs$en._(_root);
	@override late final _Translations$tray$en tray = _Translations$tray$en._(_root);
	@override late final _Translations$core$en core = _Translations$core$en._(_root);
	@override late final _Translations$deepLink$en deepLink = _Translations$deepLink$en._(_root);
	@override late final _Translations$startup$en startup = _Translations$startup$en._(_root);
	@override late final _Translations$common$en common = _Translations$common$en._(_root);
}

// Path: nav
class _Translations$nav$en extends Translations$nav$zh {
	_Translations$nav$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get home => 'Home';
	@override String get proxies => 'Proxies';
	@override String get profiles => 'Profiles';
	@override String get settings => 'Settings';
}

// Path: home
class _Translations$home$en extends Translations$home$zh {
	_Translations$home$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get speed => 'Speed';
	@override String get connections => 'Connections';
	@override String get connectionCount => 'connections';
	@override String get memory => 'Memory Usage';
	@override String get trafficTotal => 'Total Traffic';
	@override String get outboundMode => 'Outbound Mode';
	@override String get proxyMode => 'Proxy Mode';
	@override String get systemProxy => 'System Proxy';
	@override String get waitingCore => 'Waiting for core...';
	@override String get pleaseAddProfile => 'Add a profile first';
	@override String get enable => 'Enable';
	@override String get copy => 'Copy';
}

// Path: mode
class _Translations$mode$en extends Translations$mode$zh {
	_Translations$mode$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get rule => 'Rule';
	@override String get global => 'Global';
	@override String get direct => 'Direct';
}

// Path: proxies
class _Translations$proxies$en extends Translations$proxies$zh {
	_Translations$proxies$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Proxies';
	@override String get sort => 'Sort';
	@override String get speedTest => 'Speed Test';
	@override String get empty => 'No Proxies';
	@override String get emptyHint => 'Proxies will appear here after adding a profile';
	@override String get sortTitle => 'Sort By';
	@override String get sortDefault => 'Default';
	@override String get sortByName => 'By Name';
	@override String get sortByDelay => 'By Delay';
	@override String get expandGroups => 'Expand Groups';
	@override String get selectGroup => 'Select Group';
	@override String switchFailed({required Object error}) => 'Failed to switch proxy: ${error}';
}

// Path: profiles
class _Translations$profiles$en extends Translations$profiles$zh {
	_Translations$profiles$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profiles';
	@override String get add => 'Add';
	@override String get addSubscription => 'Add Profile';
	@override String get fromFile => 'From File';
	@override String get fromUrl => 'From URL';
	@override String get edit => 'Edit';
	@override String get remove => 'Remove';
	@override String get update => 'Update';
	@override String get updating => 'Updating...';
	@override String get confirmDelete => 'Confirm Delete';
	@override String confirmDeleteMessage({required Object name}) => 'Delete "${name}"?';
	@override String configExists({required Object name}) => 'Profile "${name}" already exists';
	@override String fileCopyFailed({required Object error}) => 'File copy failed: ${error}';
	@override String urlValidationFailed({required Object error}) => 'URL validation failed: ${error}';
	@override String updateFailed({required Object error}) => 'Update failed: ${error}';
	@override String importFailed({required Object error}) => 'Import failed: ${error}';
	@override String configValidationFailed({required Object validation}) => 'Config validation failed: ${validation}';
	@override String get subscriptionExists => 'Subscription already exists';
	@override String get inputUrl => 'Enter Profile URL';
	@override String get pleaseInput => 'Please enter';
	@override String get name => 'Name';
	@override String get updateIntervalHours => 'Update Interval (hours)';
	@override String get empty => 'No Profiles';
	@override String get emptyHint => 'Tap the button below to add a profile';
	@override String get copy => 'Copy';
}

// Path: settings
class _Translations$settings$en extends Translations$settings$zh {
	_Translations$settings$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Settings';
	@override String get sectionCore => 'Core';
	@override String get proxyService => 'Proxy Service';
	@override String get proxyServiceDesc => 'Enable HTTP/SOCKS5 mixed proxy port';
	@override String get allowLan => 'Allow LAN';
	@override String get allowLanDesc => 'Allow other LAN devices to use this proxy';
	@override String get port => 'Port';
	@override String get portDesc => 'Local port for proxy service';
	@override String get portValidationError => 'Enter a port between 1-65535';
	@override String get notSet => 'Not set';
	@override String get ipv6 => 'IPv6';
	@override String get ipv6Desc => 'Support IPv6 for proxy connections';
	@override String get outboundMode => 'Outbound Mode';
	@override String get outboundModeDesc => 'Control traffic routing strategy';
	@override String get clashApi => 'Clash API';
	@override String get clashApiDesc => 'Expose proxy status and control interface';
	@override String get apiAddress => 'API Address';
	@override String get logLevel => 'Log Level';
	@override String get logLevelDesc => 'Lower level = more detailed, use Debug for troubleshooting';
	@override String get logDebug => 'Debug';
	@override String get logInfo => 'Info';
	@override String get logWarning => 'Warning';
	@override String get logError => 'Error';
	@override String get sectionGeneral => 'General';
	@override String get subUserAgent => 'Subscription User-Agent';
	@override String get subUaDialogTitle => 'Subscription User-Agent';
	@override String get subUaDialogDesc => 'User-Agent for subscription updates';
	@override String get inputUa => 'Enter User-Agent';
	@override String get defaultValue => 'Default';
	@override String get delayTestUrl => 'Delay Test URL';
	@override String get delayTestUrlDesc => 'Target URL for latency testing';
	@override String get ruleSetProxy => 'Rule-Set Proxy';
	@override String get ruleSetProxyDesc => 'Proxy address for downloading rule-set';
	@override String get autoCheckUpdate => 'Check for Updates on Startup';
	@override String get autoCheckUpdateDesc => 'Automatically check for new versions on startup';
	@override String get sectionAppearance => 'Appearance';
	@override String get theme => 'Theme';
	@override String get themeDesc => 'Change app appearance';
	@override String get themeSystem => 'System Default';
	@override String get themeLight => 'Light';
	@override String get themeDark => 'Dark';
	@override String get language => 'Language';
	@override String get languageDesc => 'Change app display language';
	@override String get languageSystem => 'System Default';
	@override String get sectionOther => 'Other';
	@override String get about => 'About';
	@override String get aboutDesc => 'Version info and related links';
}

// Path: about
class _Translations$about$en extends Translations$about$zh {
	_Translations$about$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'About';
	@override String get officialWebsite => 'Website';
	@override String get sourceRepo => 'Source Code';
	@override String get kernelVersion => 'Kernel Version';
	@override String get loading => 'Loading...';
	@override String get version => 'Version';
	@override String get newVersionFound => 'Update Available';
	@override String versionInfo({required Object current, required Object latest}) => 'Current: ${current}\nLatest: ${latest}';
	@override String get ignore => 'Ignore';
	@override String get goDownload => 'Download';
	@override String get removeElevation => 'Remove Elevation';
	@override String get removeElevationConfirm => 'Confirm Remove Elevation';
	@override String get removeElevationDesc => 'This will remove the TUN elevation service and restart the core in built-in mode (TUN unavailable). You will need to re-elevate next time you use TUN.';
	@override String get removeElevationWinDesc => 'Remove Windows service and switch to built-in core';
	@override String get removeElevationMacDesc => 'Remove elevated core and switch to built-in core';
	@override String get elevationRemoved => 'Elevation removed, switched to built-in core';
	@override String get operationFailed => 'Operation failed';
	@override String get exportLog => 'Export Log';
	@override String get logNotInitialized => 'Log not initialized';
	@override String get logFileNotExist => 'Log file not found';
	@override String get logExported => 'Log exported';
	@override String get exportFailed => 'Export failed';
	@override String get easterEgg => 'You found me!';
}

// Path: dialogs
class _Translations$dialogs$en extends Translations$dialogs$zh {
	_Translations$dialogs$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get error => 'Error';
	@override String get cancel => 'Cancel';
	@override String get confirm => 'OK';
	@override String get delete => 'Delete';
	@override String get import => 'Import';
	@override String get copy => 'Copy';
}

// Path: tray
class _Translations$tray$en extends Translations$tray$zh {
	_Translations$tray$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get showWindow => 'Show Window';
	@override String get tunMode => 'TUN Mode';
	@override String get systemProxy => 'System Proxy';
	@override String get exit => 'Exit';
}

// Path: core
class _Translations$core$en extends Translations$core$zh {
	_Translations$core$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String connectionFailed({required Object error}) => 'Core connection failed: ${error}';
	@override String get initTimeout => 'Core initialization timed out';
	@override String initFailed({required Object error}) => 'Core initialization failed: ${error}';
	@override String get reconnectCore => 'Reconnect Core';
	@override String get restartCore => 'Restart Core';
	@override String get reconnectMessage => 'Core is disconnected. Try reconnecting?';
	@override String get restartMessage => 'Restart core service?';
	@override String get reconnect => 'Reconnect';
	@override String get restart => 'Restart';
	@override String get coreState => 'Core Status';
	@override String get coreDisconnected => 'Core disconnected, tap to reconnect';
	@override String modeSwitchFailed({required Object error}) => 'Failed to switch mode: ${error}';
	@override String get elevationFailed => 'Elevation failed, please retry';
}

// Path: deepLink
class _Translations$deepLink$en extends Translations$deepLink$zh {
	_Translations$deepLink$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get importSubscription => 'Import Profile';
	@override String confirmImport({required Object name}) => 'Import profile "${name}"?';
	@override String get confirmImportNoName => 'Import this profile?';
	@override String get importSuccess => 'Profile imported successfully';
	@override String importFailed({required Object error}) => 'Profile import failed: ${error}';
}

// Path: startup
class _Translations$startup$en extends Translations$startup$zh {
	_Translations$startup$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get newVersionFound => 'Update Available';
	@override String currentAndLatest({required Object current, required Object latest}) => 'Current: ${current}\nLatest: ${latest}';
	@override String get ignoreThisTime => 'Dismiss';
	@override String get ignoreThisVersion => 'Ignore This Version';
	@override String get goDownload => 'Download';
}

// Path: common
class _Translations$common$en extends Translations$common$zh {
	_Translations$common$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get close => 'Close';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEn {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'nav.home' => 'Home',
			'nav.proxies' => 'Proxies',
			'nav.profiles' => 'Profiles',
			'nav.settings' => 'Settings',
			'home.speed' => 'Speed',
			'home.connections' => 'Connections',
			'home.connectionCount' => 'connections',
			'home.memory' => 'Memory Usage',
			'home.trafficTotal' => 'Total Traffic',
			'home.outboundMode' => 'Outbound Mode',
			'home.proxyMode' => 'Proxy Mode',
			'home.systemProxy' => 'System Proxy',
			'home.waitingCore' => 'Waiting for core...',
			'home.pleaseAddProfile' => 'Add a profile first',
			'home.enable' => 'Enable',
			'home.copy' => 'Copy',
			'mode.rule' => 'Rule',
			'mode.global' => 'Global',
			'mode.direct' => 'Direct',
			'proxies.title' => 'Proxies',
			'proxies.sort' => 'Sort',
			'proxies.speedTest' => 'Speed Test',
			'proxies.empty' => 'No Proxies',
			'proxies.emptyHint' => 'Proxies will appear here after adding a profile',
			'proxies.sortTitle' => 'Sort By',
			'proxies.sortDefault' => 'Default',
			'proxies.sortByName' => 'By Name',
			'proxies.sortByDelay' => 'By Delay',
			'proxies.expandGroups' => 'Expand Groups',
			'proxies.selectGroup' => 'Select Group',
			'proxies.switchFailed' => ({required Object error}) => 'Failed to switch proxy: ${error}',
			'profiles.title' => 'Profiles',
			'profiles.add' => 'Add',
			'profiles.addSubscription' => 'Add Profile',
			'profiles.fromFile' => 'From File',
			'profiles.fromUrl' => 'From URL',
			'profiles.edit' => 'Edit',
			'profiles.remove' => 'Remove',
			'profiles.update' => 'Update',
			'profiles.updating' => 'Updating...',
			'profiles.confirmDelete' => 'Confirm Delete',
			'profiles.confirmDeleteMessage' => ({required Object name}) => 'Delete "${name}"?',
			'profiles.configExists' => ({required Object name}) => 'Profile "${name}" already exists',
			'profiles.fileCopyFailed' => ({required Object error}) => 'File copy failed: ${error}',
			'profiles.urlValidationFailed' => ({required Object error}) => 'URL validation failed: ${error}',
			'profiles.updateFailed' => ({required Object error}) => 'Update failed: ${error}',
			'profiles.importFailed' => ({required Object error}) => 'Import failed: ${error}',
			'profiles.configValidationFailed' => ({required Object validation}) => 'Config validation failed: ${validation}',
			'profiles.subscriptionExists' => 'Subscription already exists',
			'profiles.inputUrl' => 'Enter Profile URL',
			'profiles.pleaseInput' => 'Please enter',
			'profiles.name' => 'Name',
			'profiles.updateIntervalHours' => 'Update Interval (hours)',
			'profiles.empty' => 'No Profiles',
			'profiles.emptyHint' => 'Tap the button below to add a profile',
			'profiles.copy' => 'Copy',
			'settings.title' => 'Settings',
			'settings.sectionCore' => 'Core',
			'settings.proxyService' => 'Proxy Service',
			'settings.proxyServiceDesc' => 'Enable HTTP/SOCKS5 mixed proxy port',
			'settings.allowLan' => 'Allow LAN',
			'settings.allowLanDesc' => 'Allow other LAN devices to use this proxy',
			'settings.port' => 'Port',
			'settings.portDesc' => 'Local port for proxy service',
			'settings.portValidationError' => 'Enter a port between 1-65535',
			'settings.notSet' => 'Not set',
			'settings.ipv6' => 'IPv6',
			'settings.ipv6Desc' => 'Support IPv6 for proxy connections',
			'settings.outboundMode' => 'Outbound Mode',
			'settings.outboundModeDesc' => 'Control traffic routing strategy',
			'settings.clashApi' => 'Clash API',
			'settings.clashApiDesc' => 'Expose proxy status and control interface',
			'settings.apiAddress' => 'API Address',
			'settings.logLevel' => 'Log Level',
			'settings.logLevelDesc' => 'Lower level = more detailed, use Debug for troubleshooting',
			'settings.logDebug' => 'Debug',
			'settings.logInfo' => 'Info',
			'settings.logWarning' => 'Warning',
			'settings.logError' => 'Error',
			'settings.sectionGeneral' => 'General',
			'settings.subUserAgent' => 'Subscription User-Agent',
			'settings.subUaDialogTitle' => 'Subscription User-Agent',
			'settings.subUaDialogDesc' => 'User-Agent for subscription updates',
			'settings.inputUa' => 'Enter User-Agent',
			'settings.defaultValue' => 'Default',
			'settings.delayTestUrl' => 'Delay Test URL',
			'settings.delayTestUrlDesc' => 'Target URL for latency testing',
			'settings.ruleSetProxy' => 'Rule-Set Proxy',
			'settings.ruleSetProxyDesc' => 'Proxy address for downloading rule-set',
			'settings.autoCheckUpdate' => 'Check for Updates on Startup',
			'settings.autoCheckUpdateDesc' => 'Automatically check for new versions on startup',
			'settings.sectionAppearance' => 'Appearance',
			'settings.theme' => 'Theme',
			'settings.themeDesc' => 'Change app appearance',
			'settings.themeSystem' => 'System Default',
			'settings.themeLight' => 'Light',
			'settings.themeDark' => 'Dark',
			'settings.language' => 'Language',
			'settings.languageDesc' => 'Change app display language',
			'settings.languageSystem' => 'System Default',
			'settings.sectionOther' => 'Other',
			'settings.about' => 'About',
			'settings.aboutDesc' => 'Version info and related links',
			'about.title' => 'About',
			'about.officialWebsite' => 'Website',
			'about.sourceRepo' => 'Source Code',
			'about.kernelVersion' => 'Kernel Version',
			'about.loading' => 'Loading...',
			'about.version' => 'Version',
			'about.newVersionFound' => 'Update Available',
			'about.versionInfo' => ({required Object current, required Object latest}) => 'Current: ${current}\nLatest: ${latest}',
			'about.ignore' => 'Ignore',
			'about.goDownload' => 'Download',
			'about.removeElevation' => 'Remove Elevation',
			'about.removeElevationConfirm' => 'Confirm Remove Elevation',
			'about.removeElevationDesc' => 'This will remove the TUN elevation service and restart the core in built-in mode (TUN unavailable). You will need to re-elevate next time you use TUN.',
			'about.removeElevationWinDesc' => 'Remove Windows service and switch to built-in core',
			'about.removeElevationMacDesc' => 'Remove elevated core and switch to built-in core',
			'about.elevationRemoved' => 'Elevation removed, switched to built-in core',
			'about.operationFailed' => 'Operation failed',
			'about.exportLog' => 'Export Log',
			'about.logNotInitialized' => 'Log not initialized',
			'about.logFileNotExist' => 'Log file not found',
			'about.logExported' => 'Log exported',
			'about.exportFailed' => 'Export failed',
			'about.easterEgg' => 'You found me!',
			'dialogs.error' => 'Error',
			'dialogs.cancel' => 'Cancel',
			'dialogs.confirm' => 'OK',
			'dialogs.delete' => 'Delete',
			'dialogs.import' => 'Import',
			'dialogs.copy' => 'Copy',
			'tray.showWindow' => 'Show Window',
			'tray.tunMode' => 'TUN Mode',
			'tray.systemProxy' => 'System Proxy',
			'tray.exit' => 'Exit',
			'core.connectionFailed' => ({required Object error}) => 'Core connection failed: ${error}',
			'core.initTimeout' => 'Core initialization timed out',
			'core.initFailed' => ({required Object error}) => 'Core initialization failed: ${error}',
			'core.reconnectCore' => 'Reconnect Core',
			'core.restartCore' => 'Restart Core',
			'core.reconnectMessage' => 'Core is disconnected. Try reconnecting?',
			'core.restartMessage' => 'Restart core service?',
			'core.reconnect' => 'Reconnect',
			'core.restart' => 'Restart',
			'core.coreState' => 'Core Status',
			'core.coreDisconnected' => 'Core disconnected, tap to reconnect',
			'core.modeSwitchFailed' => ({required Object error}) => 'Failed to switch mode: ${error}',
			'core.elevationFailed' => 'Elevation failed, please retry',
			'deepLink.importSubscription' => 'Import Profile',
			'deepLink.confirmImport' => ({required Object name}) => 'Import profile "${name}"?',
			'deepLink.confirmImportNoName' => 'Import this profile?',
			'deepLink.importSuccess' => 'Profile imported successfully',
			'deepLink.importFailed' => ({required Object error}) => 'Profile import failed: ${error}',
			'startup.newVersionFound' => 'Update Available',
			'startup.currentAndLatest' => ({required Object current, required Object latest}) => 'Current: ${current}\nLatest: ${latest}',
			'startup.ignoreThisTime' => 'Dismiss',
			'startup.ignoreThisVersion' => 'Ignore This Version',
			'startup.goDownload' => 'Download',
			'common.close' => 'Close',
			_ => null,
		};
	}
}
