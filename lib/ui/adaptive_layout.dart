import 'package:flutter/material.dart';

import '../controllers/theme_controller.dart';

/// 自适应布局工具类。
///
/// 平板检测基于 Material Design 的 breakpoint：
/// - 最小边 < 600dp → 手机
/// - 最小边 ≥ 600dp → 平板
///
/// 手机横屏时最小边仍为宽度（一般 ≤ 430dp），不会被误判为平板。
class AdaptiveLayout {
  const AdaptiveLayout._();

  /// 普通平板内容区域的最大宽度。
  static const double tabletMaxWidth = 800;

  /// 超宽屏内容区域的最大宽度。
  static const double wideMaxWidth = 1200;

  /// 是否为平板设备。
  ///
  /// 使用 [MediaQuery.sizeOf] 获取屏幕逻辑像素，
  /// `shortestSide >= 600` 即判定为平板（Material Design 标准）。
  static bool isTablet(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= 600;
  }

  /// 不依赖 [BuildContext] 的平板判断。
  ///
  /// 直接从 [PlatformDispatcher] 读取屏幕物理尺寸换算为逻辑像素。
  /// 适用于 [State.dispose] 等 context 已失效、无法调用
  /// [MediaQuery.sizeOf] 的场景，否则会触发
  /// `Null check operator used on a null value` 异常。
  static bool isTabletByPlatform() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final physical = view.physicalSize;
    if (physical.isEmpty) return false;
    final size = physical / view.devicePixelRatio;
    return size.shortestSide >= 600;
  }

  /// 是否为超宽屏（宽高比 ≥ 2.5 或宽度 ≥ 1600dp）。
  static bool isUltraWide(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= 1600 || (size.height > 0 && size.width / size.height >= 2.5);
  }

  /// 根据屏幕宽度计算内容区域的最大宽度。
  ///
  /// - 宽度 < 600：不限制（手机）
  /// - 600 ≤ 宽度 < 1200：限制 [tabletMaxWidth]
  /// - 宽度 ≥ 1200：限制 [wideMaxWidth]
  static double contentMaxWidthFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    if (width < 600) return double.infinity;

    // 取消宽度限制是车机横屏专属（让内容铺满宽屏）；
    // 普通横屏/平板仍按原逻辑限制内容最大宽度，避免行宽过长难读。
    final isCarLandscape =
        size.width > size.height && ThemeController.instance.carModeEnabled;
    if (isCarLandscape) {
      return double.infinity;
    }

    if (width < 1200) return tabletMaxWidth;
    return wideMaxWidth;
  }

  /// 根据屏幕宽度计算网格列数。
  ///
  /// 适用于歌单、专辑等网格布局。
  static int gridColumnsFor(BuildContext context, {double minItemWidth = 160}) {
    final maxWidth = contentMaxWidthFor(context);
    final effectiveWidth = maxWidth == double.infinity
        ? MediaQuery.sizeOf(context).width
        : maxWidth;
    return (effectiveWidth / minItemWidth).floor().clamp(2, 8);
  }
}

/// 自适应内容内边距。
///
/// 手机端：不施加任何约束，子组件直接渲染。
/// 平板/超宽端：将内容居中并限制最大宽度，避免内容横向拉伸到难以阅读的宽度。
class AdaptiveContentPadding extends StatelessWidget {
  const AdaptiveContentPadding({
    super.key,
    required this.child,
    this.maxWidth,
  });

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 600) {
      return child;
    }
    final limit = maxWidth ?? AdaptiveLayout.contentMaxWidthFor(context);
    if (limit == double.infinity) {
      return child;
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: limit),
        child: child,
      ),
    );
  }
}
