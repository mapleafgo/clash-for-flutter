import 'package:signals_flutter/signals_flutter.dart';

/// App 初始化完成信号。
///
/// `main()` 中 `_initApp()` 完成后置 true。
/// 路由层用它判断是否显示真实 shell，避免切换 router 导致过渡帧溢出。
final appReady = signal(false);
