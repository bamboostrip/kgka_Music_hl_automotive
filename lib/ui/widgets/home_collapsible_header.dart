import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../services/music_api.dart';
import '../pages/search_page.dart';

/// 首页吸顶收折头部 Delegate。
///
/// 顶部展示搜索栏，下方展示胶囊标签栏。向下滚动时搜索栏平滑收折淡出，
/// 标签栏常驻吸顶。向上滚动时搜索栏平滑展开。
class HomeCollapsibleHeaderDelegate extends SliverPersistentHeaderDelegate {
  HomeCollapsibleHeaderDelegate({
    required this.api,
    required this.auth,
    required this.player,
    required this.sectionIndex,
    required this.onSectionChanged,
    this.pageTracker,
    this.onRefresh,
    this.topPadding = 0.0,
    this.topMargin = 8.0,
    this.searchBarHeight = 36.0,
    this.tabBarHeight = 36.0,
    this.bottomPadding = 6.0,
    this.spacing = 8.0,
    this.pinnedTopOffset = 4.0,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final int sectionIndex;
  final ValueChanged<int> onSectionChanged;

  /// 首页 PageView 的控制器：胶囊指示器直接监听它逐帧联动，
  /// 避免外部为每个像素触发整页 setState。
  final PageController? pageTracker;
  final Future<void> Function()? onRefresh;
  final double topPadding;
  final double topMargin;
  final double searchBarHeight;
  final double tabBarHeight;
  final double bottomPadding;
  final double spacing;
  final double pinnedTopOffset;

  @override
  double get minExtent =>
      topPadding + pinnedTopOffset + tabBarHeight + bottomPadding;

  @override
  double get maxExtent =>
      topPadding + topMargin + searchBarHeight + spacing + tabBarHeight + bottomPadding;

  @override
  bool shouldRebuild(covariant HomeCollapsibleHeaderDelegate oldDelegate) {
    return oldDelegate.sectionIndex != sectionIndex ||
        oldDelegate.pageTracker != pageTracker ||
        oldDelegate.topPadding != topPadding ||
        oldDelegate.topMargin != topMargin ||
        oldDelegate.pinnedTopOffset != pinnedTopOffset ||
        oldDelegate.onRefresh != onRefresh ||
        oldDelegate.searchBarHeight != searchBarHeight ||
        oldDelegate.tabBarHeight != tabBarHeight ||
        oldDelegate.bottomPadding != bottomPadding ||
        oldDelegate.spacing != spacing ||
        oldDelegate.api != api ||
        oldDelegate.auth != auth ||
        oldDelegate.player != player ||
        oldDelegate.onSectionChanged != onSectionChanged;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final progress = (maxExtent > minExtent)
        ? (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0)
        : 0.0;

    final opacity = (1.0 - progress * 1.5).clamp(0.0, 1.0);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final isTransparent =
        scaffoldBg == Colors.transparent || scaffoldBg.a == 0;
    final effectiveBgColor = isTransparent
        ? (isDark ? const Color(0xFF06070A) : Colors.white)
            .withValues(alpha: 0.85 * progress)
        : scaffoldBg;

    final effectiveOffset = shrinkOffset.clamp(0.0, maxExtent - minExtent);

    return ClipRect(
      child: Container(
        decoration: BoxDecoration(
          color: effectiveBgColor,
          border: Border(
            bottom: progress > 0
                ? BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3 * progress),
                    width: 0.5,
                  )
                : BorderSide.none,
          ),
          boxShadow: progress > 0
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05 * progress),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // 顶行：Logo品牌 + 搜索框（参考 IT 之家布局，随着滚动平滑淡出并上移）
            Positioned(
              top: topPadding + topMargin - effectiveOffset,
              left: 16,
              right: 16,
              height: searchBarHeight,
              child: Opacity(
                opacity: opacity,
                child: IgnorePointer(
                  ignoring: progress >= 0.75,
                  child: Row(
                    children: [
                      const HomeBrandHeader(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: HomeSearchBar(
                          api: api,
                          auth: auth,
                          player: player,
                          height: searchBarHeight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 胶囊标签栏：收折后紧贴 topPadding + pinnedTopOffset 常驻吸顶
            Positioned(
              top: topPadding + topMargin + searchBarHeight + spacing - effectiveOffset,
              left: 0,
              right: 0,
              height: tabBarHeight,
              child: HomeCapsuleTabBar(
                selectedIndex: sectionIndex,
                pageTracker: pageTracker,
                onTabSelected: onSectionChanged,
                onRefresh: onRefresh,
                height: tabBarHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页顶部品牌 Logo 与应用名展示组件（参考 IT 之家品牌标识区）
class HomeBrandHeader extends StatelessWidget {
  const HomeBrandHeader({
    super.key,
    this.size = 28.0,
    this.title = '时音',
  });

  final double size;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.28),
            child: Image.asset(
              'lib/assets/logo.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: colorScheme.primaryContainer,
                child: Icon(
                  Icons.music_note_rounded,
                  size: size * 0.7,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// 首页顶部搜索框组件（参考 IT 之家轻量胶囊样式）。
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({
    super.key,
    this.api,
    this.auth,
    this.player,
    this.onTap,
    this.height = 36.0,
    this.hintText = '搜索歌曲、歌手、专辑',
    this.margin,
  });

  final MusicApi? api;
  final AuthController? auth;
  final PlayerController? player;
  final VoidCallback? onTap;
  final double height;
  final String hintText;
  final EdgeInsetsGeometry? margin;

  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (api != null && auth != null && player != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SearchPage(api: api!, auth: auth!, player: player!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: () => _handleTap(context),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 16.5,
                color: colorScheme.onSurfaceVariant.withValues(
                  alpha: isDark ? 0.7 : 0.55,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: isDark ? 0.75 : 0.65,
                        ),
                        fontWeight: FontWeight.w400,
                        fontSize: 13.5,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

/// 首页灵动胶囊标签栏组件。
class HomeCapsuleTabBar extends StatelessWidget {
  const HomeCapsuleTabBar({
    super.key,
    required this.selectedIndex,
    this.pageTracker,
    required this.onTabSelected,
    this.tabs = const ['推荐', '排行榜', '电台'],
    this.onRefresh,
    this.height = 36.0,
  });

  final int selectedIndex;

  /// 首页 PageView 的控制器：胶囊/文字随滑动逐帧联动，且重建范围
  /// 局限在本组件内（外部无需为滑动逐像素 setState 整页）。为 null 时
  /// 仅按 [selectedIndex] 静态定位。
  final PageController? pageTracker;
  final ValueChanged<int> onTabSelected;
  final List<String> tabs;
  final Future<void> Function()? onRefresh;
  final double height;

  static const _labelFontSize = 14.5;
  // 单侧内边距：文字宽度 + 2×13.5 ≈ 旧版 56/70px 的视觉宽度（scale 1.0）。
  static const _labelHPadding = 13.5;
  static const _tabGap = 6.0;

  double _resolvePage() {
    final controller = pageTracker;
    if (controller != null &&
        controller.hasClients &&
        controller.position.haveDimensions) {
      return (controller.page ?? selectedIndex.toDouble())
          .clamp(0.0, (tabs.length - 1).toDouble());
    }
    return selectedIndex.toDouble();
  }

  /// 按真实文字（含系统字体缩放）测量标签宽度：任意 tab 数量都安全，
  /// 旧实现按 3 个固定宽度硬编码，多 tab 会 RangeError、大字号会溢出。
  double _measureLabel(String label, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: _labelFontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
      textScaler: textScaler,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textScaler = MediaQuery.textScalerOf(context);
    final tabWidths = <double>[
      for (final label in tabs)
        _measureLabel(label, textScaler) + _labelHPadding * 2,
    ];
    final tabOffsets = <double>[0.0];
    for (var i = 0; i < tabWidths.length - 1; i++) {
      tabOffsets.add(tabOffsets[i] + tabWidths[i] + _tabGap);
    }
    final totalWidth = tabOffsets.last + tabWidths.last;

    const capsuleHeight = 30.0;
    final topOffset = (height - capsuleHeight) / 2;

    Widget buildBar(double p) {
      // 任意相邻两 tab 之间线性插值（p 已被 clamp 在 [0, tabs.length-1]）。
      final i = p.floor().clamp(0, tabs.length - 1);
      final next = (i + 1).clamp(0, tabs.length - 1);
      final t = (p - i).clamp(0.0, 1.0);
      final currentLeft = tabOffsets[i] + (tabOffsets[next] - tabOffsets[i]) * t;
      final currentWidth = tabWidths[i] + (tabWidths[next] - tabWidths[i]) * t;

      return SizedBox(
        width: totalWidth,
        height: height,
        child: Stack(
          children: [
            // 滑动背景胶囊（与手势实时联动）
            Positioned(
              left: currentLeft,
              top: topOffset,
              width: currentWidth,
              height: capsuleHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(
                    alpha: isDark ? 0.22 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(capsuleHeight / 2),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                    width: 1.0,
                  ),
                ),
              ),
            ),
            // 标签文字
            Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTabSelected(i),
                    child: SizedBox(
                      width: tabWidths[i],
                      height: height,
                      child: Center(
                        child: Text(
                          tabs[i],
                          style: TextStyle(
                            fontSize: _labelFontSize,
                            fontWeight: (p - i).abs() < 0.5
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: Color.lerp(
                              colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.85),
                              colorScheme.primary,
                              (1.0 - (p - i).abs()).clamp(0.0, 1.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < tabs.length - 1) const SizedBox(width: _tabGap),
                ],
              ],
            ),
          ],
        ),
      );
    }

    final tracker = pageTracker;
    final Widget tabBar = tracker != null
        ? ListenableBuilder(
            listenable: tracker,
            builder: (context, _) => buildBar(_resolvePage()),
          )
        : buildBar(selectedIndex.toDouble());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: tabBar,
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
                iconSize: 20,
                color: colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                onPressed: onRefresh,
              ),
          ],
        ),
      ),
    );
  }
}
