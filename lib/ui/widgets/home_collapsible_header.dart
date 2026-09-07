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
    this.onRefresh,
    this.topPadding = 0.0,
    this.searchBarHeight = 44.0,
    this.tabBarHeight = 42.0,
    this.bottomPadding = 8.0,
    this.spacing = 10.0,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final int sectionIndex;
  final ValueChanged<int> onSectionChanged;
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
    this.height = 44.0,
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
          borderRadius: BorderRadius.circular(22),
          onTap: () => _handleTap(context),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(
                    alpha: isDark ? 0.8 : 0.6,
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
                            alpha: isDark ? 0.7 : 0.7,
                          ),
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
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
    ValueChanged<int>? onTabSelected,
    ValueChanged<int>? onSectionChanged,
    this.tabs = const ['推荐', '排行榜', '电台'],
    this.onRefresh,
    this.height = 42.0,
  })  : selectedIndex = selectedIndex ?? sectionIndex ?? 0,
        onTabSelected = onTabSelected ?? onSectionChanged ?? _dummyOnTabSelected;

  static void _dummyOnTabSelected(int _) {}

  final int selectedIndex;
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTabSelected(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: i == selectedIndex
                              ? colorScheme.primary.withValues(
                                  alpha: isDark ? 0.22 : 0.12,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: i == selectedIndex
                                ? colorScheme.primary.withValues(alpha: 0.2)
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          tabs[i],
                          style: TextStyle(
                            fontSize: i == selectedIndex ? 15 : 14,
                            fontWeight: i == selectedIndex
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == selectedIndex
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    if (i < tabs.length - 1) const SizedBox(width: 8),
                  ],
                ],
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
