import 'package:flutter/material.dart';

/// 自适应布局工具类。
///
/// 平板检测基于 Material Design 的 breakpoint：
/// - 最小边 < 600dp → 手机
/// - 最小边 ≥ 600dp → 平板
///
/// 手机横屏时最小边仍为宽度（一般 ≤ 430dp），不会被误判为平板。
class AdaptiveLayout {
  const AdaptiveLayout._();

  /// 平板模式下内容区域的最大宽度。
  static const double contentMaxWidth = 680;

  /// 是否为平板设备。
  ///
  /// 使用 [MediaQuery.sizeOf] 获取屏幕逻辑像素，
  /// `shortestSide >= 600` 即判定为平板（Material Design 标准）。
  static bool isTablet(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= 600;
  }
}

/// 自适应内容内边距。
///
/// 手机端：不施加任何约束，子组件直接渲染。
/// 平板端：将内容居中并限制最大宽度为 [AdaptiveLayout.contentMaxWidth]，
/// 避免在宽屏平板上内容横向拉伸到难以阅读的宽度。
class AdaptiveContentPadding extends StatelessWidget {
  const AdaptiveContentPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AdaptiveLayout.isTablet(context)) {
      return child;
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AdaptiveLayout.contentMaxWidth,
        ),
        child: child,
      ),
    );
  }
}
