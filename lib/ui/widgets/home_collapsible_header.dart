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
    this.pageOffset,
    this.onRefresh,
    this.topPadding = 0.0,
    this.searchBarHeight = 36.0,
    this.tabBarHeight = 36.0,
    this.bottomPadding = 6.0,
    this.spacing = 8.0,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final int sectionIndex;
  final ValueChanged<int> onSectionChanged;
  final double? pageOffset;
  final Future<void> Function()? onRefresh;
  final double topPadding;
  final double searchBarHeight;
  final double tabBarHeight;
  final double bottomPadding;
  final double spacing;

  @override
  double get minExtent => topPadding + tabBarHeight + bottomPadding;

  @override
  double get maxExtent =>
      topPadding + searchBarHeight + spacing + tabBarHeight + bottomPadding;

  @override
  bool shouldRebuild(covariant HomeCollapsibleHeaderDelegate oldDelegate) {
    return oldDelegate.sectionIndex != sectionIndex ||
        oldDelegate.pageOffset != pageOffset ||
        oldDelegate.topPadding != topPadding ||
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

    final opacity = (1.0 - progress * 1.6).clamp(0.0, 1.0);
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
            // 搜索框：随着滚动平滑淡出并上移
            Positioned(
              top: topPadding - effectiveOffset,
              left: 0,
              right: 0,
              height: searchBarHeight,
              child: Opacity(
                opacity: opacity,
                child: IgnorePointer(
                  ignoring: progress >= 0.8,
                  child: HomeSearchBar(
                    api: api,
                    auth: auth,
                    player: player,
                    height: searchBarHeight,
                  ),
                ),
              ),
            ),
            // 胶囊标签栏：收折后紧贴 topPadding 常驻吸顶
            Positioned(
              top: topPadding + (searchBarHeight + spacing) - effectiveOffset,
              left: 0,
              right: 0,
              height: tabBarHeight,
              child: HomeCapsuleTabBar(
                selectedIndex: sectionIndex,
                pageOffset: pageOffset,
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

/// 首页顶部搜索框组件。
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({
    super.key,
    this.api,
    this.auth,
    this.player,
    this.onTap,
    this.height = 36.0,
    this.hintText = '搜索歌曲、歌手、专辑',
  });

  final MusicApi? api;
  final AuthController? auth;
  final PlayerController? player;
  final VoidCallback? onTap;
  final double height;
  final String hintText;

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Material(
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
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 17,
                  color: colorScheme.onSurfaceVariant.withValues(
                    alpha: isDark ? 0.7 : 0.55,
                  ),
                ),
                const SizedBox(width: 8),
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
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant.withValues(
                    alpha: isDark ? 0.5 : 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 首页灵动胶囊标签栏组件。
class HomeCapsuleTabBar extends StatelessWidget {
  const HomeCapsuleTabBar({
    super.key,
    int? selectedIndex,
    int? sectionIndex,
    this.pageOffset,
    ValueChanged<int>? onTabSelected,
    ValueChanged<int>? onSectionChanged,
    this.tabs = const ['推荐', '排行榜', '电台'],
    this.onRefresh,
    this.height = 36.0,
  })  : selectedIndex = selectedIndex ?? sectionIndex ?? 0,
        onTabSelected = onTabSelected ?? onSectionChanged ?? _dummyOnTabSelected;

  static void _dummyOnTabSelected(int _) {}

  final int selectedIndex;
  final double? pageOffset;
  final ValueChanged<int> onTabSelected;
  final List<String> tabs;
  final Future<void> Function()? onRefresh;
  final double height;

  int get sectionIndex => selectedIndex;
  ValueChanged<int> get onSectionChanged => onTabSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final p = (pageOffset ?? selectedIndex.toDouble())
        .clamp(0.0, (tabs.length - 1).toDouble());

    // 三个 Tab 的精确像素宽度与偏移（['推荐', '排行榜', '电台']）
    const tabWidths = [56.0, 70.0, 56.0];
    const tabOffsets = [0.0, 62.0, 138.0];

    double currentLeft;
    double currentWidth;
    if (p <= 1.0) {
      currentLeft = tabOffsets[0] + (tabOffsets[1] - tabOffsets[0]) * p;
      currentWidth = tabWidths[0] + (tabWidths[1] - tabWidths[0]) * p;
    } else {
      final t = p - 1.0;
      currentLeft = tabOffsets[1] + (tabOffsets[2] - tabOffsets[1]) * t;
      currentWidth = tabWidths[1] + (tabWidths[2] - tabWidths[1]) * t;
    }

    const capsuleHeight = 30.0;
    final topOffset = (height - capsuleHeight) / 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 194.0, // 138 + 56
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
                            borderRadius:
                                BorderRadius.circular(capsuleHeight / 2),
                            border: Border.all(
                              color:
                                  colorScheme.primary.withValues(alpha: 0.22),
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
                                      fontSize: 14.5,
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
                            if (i < tabs.length - 1) const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
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
