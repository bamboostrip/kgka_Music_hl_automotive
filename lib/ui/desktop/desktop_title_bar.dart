import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_controls.dart';

/// 桌面沉浸式自定义标题栏（QQ 音乐 PC 式）。
///
/// 左侧品牌 Logo/标题（与侧栏 208 对齐），中间居中搜索胶囊（只读按钮，
/// 点击由 [onSearch] 交给内容区打开搜索页），右侧标准 Windows
/// 最小化/最大化（还原）/关闭按钮。搜索框两侧保留拖拽区，保证空白处
/// 仍可拖动窗口、双击最大化；搜索框自身在拖拽区之外，可正常点按聚焦。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key, this.player, this.onSearch});

  /// 保留参数兼容旧调用点：播放信息已由底部播放栏展示，标题栏不再重复显示。
  final Object? player;

  /// 搜索胶囊点击回调；为 null 时不展示搜索框（测试/旧调用兼容）。
  final VoidCallback? onSearch;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = maximized);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      color: colorScheme.surface,
      child: Row(
        children: [
          // 左侧品牌区（与侧栏宽度 208 对齐）
          SizedBox(
            width: 208,
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'lib/assets/logo.png',
                        width: 24,
                        height: 24,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '时音',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 中间：搜索胶囊居中（QQ 音乐 PC 式），两侧弹簧拖拽区保留窗口拖动。
          Expanded(
            child: Row(
              children: [
                Expanded(child: _TitleBarDragSpacer(key: const ValueKey('desktop_title_bar_drag_left'))),
                if (widget.onSearch != null)
                  Flexible(
                    flex: 2,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _TitleBarSearchButton(onTap: widget.onSearch!),
                      ),
                    ),
                  )
                else
                  const Expanded(
                    child: _TitleBarDragSpacer(
                      key: ValueKey('desktop_title_bar_middle'),
                    ),
                  ),
                Expanded(child: _TitleBarDragSpacer(key: const ValueKey('desktop_title_bar_drag_right'))),
              ],
            ),
          ),

          // 右侧窗口控制按钮区（与全屏页面浮层共用同一套按钮）。
          // 高度传标题栏全高：按钮贴窗口顶边，与原生 Windows 标题栏一致，
          // 否则 40 高的按钮垂直居中会在顶部留出 6px 空白。
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DesktopWindowCaptionButton(
                icon: Icons.remove_rounded,
                tooltip: '最小化',
                height: 52,
                onTap: () async {
                  try {
                    await windowManager.minimize();
                  } catch (_) {}
                },
              ),
              DesktopWindowCaptionButton(
                icon: _isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                tooltip: _isMaximized ? '还原' : '最大化',
                height: 52,
                onTap: () async {
                  try {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  } catch (_) {}
                },
              ),
              DesktopWindowCaptionButton(
                icon: Icons.close_rounded,
                tooltip: '关闭',
                height: 52,
                hoverColor: const Color(0xFFE81123),
                hoverIconColor: Colors.white,
                onTap: () async {
                  try {
                    await windowManager.close();
                  } catch (_) {}
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 标题栏空白拖拽区：填充剩余空间保证可拖动，双击切换最大化/还原。
class _TitleBarDragSpacer extends StatelessWidget {
  const _TitleBarDragSpacer({super.key});

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _toggleMaximize,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 标题栏居中搜索胶囊（只读按钮，QQ 音乐 PC 式）。
///
/// 在拖拽区之外独立响应点按，键盘 Tab 可达、Enter/Space 激活，
/// 焦点时显示主色焦点环。点击后由外层打开内容区搜索页。
class _TitleBarSearchButton extends StatefulWidget {
  const _TitleBarSearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TitleBarSearchButton> createState() => _TitleBarSearchButtonState();
}

class _TitleBarSearchButtonState extends State<_TitleBarSearchButton> {
  var _hovering = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: '搜索音乐',
      onTap: widget.onTap,
      child: InkWell(
        key: const ValueKey('desktop_title_bar_search'),
        onTap: widget.onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(17),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        mouseCursor: SystemMouseCursors.click,
        onHover: (hovering) => setState(() => _hovering = hovering),
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _hovering
                ? colorScheme.surfaceContainerHigh
                : (isDark
                    ? colorScheme.surfaceContainerHighest
                    : const Color(0xFFF3F4F6)),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: _focused
                  ? colorScheme.primary.withValues(alpha: .75)
                  : colorScheme.outlineVariant
                      .withValues(alpha: isDark ? .85 : .45),
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 16.5,
                color: colorScheme.onSurfaceVariant.withValues(
                  alpha: isDark ? .65 : .5,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '搜索音乐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurfaceVariant.withValues(
                      alpha: isDark ? .7 : .6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Ctrl+F',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: .45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
