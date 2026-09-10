import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 无边框窗口的标准窗口控制按钮（最小化/最大化/关闭）。
///
/// 从 desktop_title_bar.dart 提取共用：标题栏与全屏页面的控制浮层
/// 共享同一套视觉与交互。
class DesktopWindowCaptionButton extends StatefulWidget {
  const DesktopWindowCaptionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.height = 40,
    this.hoverColor,
    this.hoverIconColor,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// 按钮高度。标题栏内传标题栏全高（52），按钮贴窗口顶边——
  /// 与原生 Windows 标题栏按钮一致；浮层内用默认 40（浮层自身 40 高）。
  final double height;
  final Color? hoverColor;
  final Color? hoverIconColor;

  /// 图标默认色：默认取主题 onSurfaceVariant，深色沉浸页传白色。
  final Color? iconColor;
  final String? tooltip;

  @override
  State<DesktopWindowCaptionButton> createState() => _DesktopWindowCaptionButtonState();
}

class _DesktopWindowCaptionButtonState extends State<DesktopWindowCaptionButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final defaultIconColor =
        widget.iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final defaultHoverBg = defaultIconColor.withValues(alpha: .12);

    final bgColor = _isHovering
        ? (widget.hoverColor ?? defaultHoverBg)
        : Colors.transparent;
    final iconColor = _isHovering
        ? (widget.hoverIconColor ?? defaultIconColor)
        : defaultIconColor;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: widget.height,
          color: bgColor,
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 16, color: iconColor),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: button,
      );
    }

    return button;
  }
}

/// 桌面无边框窗口在「无标题栏页面」的顶部窗口控制浮层。
///
/// 登录页与全屏播放页不在 DesktopShell 内（登录页整体替换 home、
/// 播放页以整屏路由覆盖 shell），看不到 [DesktopTitleBar]，无边框窗口
/// 就既拖不动也没有最小化/关闭按钮。此浮层补上：
/// - 顶部 40px 透明拖拽条（拖动移动窗口，双击最大化/还原）；
/// - 右上角最小化/最大化/关闭按钮。
///
/// 仅桌面形态使用；作为 Stack 的最后一个 child 叠加在最上层。
/// 半透明命中（translucent）不会吞掉下层内容的点击。
class DesktopWindowControlsOverlay extends StatefulWidget {
  const DesktopWindowControlsOverlay({super.key, this.iconColor});

  /// 按钮图标默认色：默认取主题 onSurfaceVariant；深色沉浸页
  /// （播放页黑色封面背景）传白色。
  final Color? iconColor;

  @override
  State<DesktopWindowControlsOverlay> createState() =>
      _DesktopWindowControlsOverlayState();
}

class _DesktopWindowControlsOverlayState extends State<DesktopWindowControlsOverlay>
    with WindowListener {
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
      if (mounted) setState(() => _isMaximized = maximized);
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

  /// 与标题栏拖拽区一致的双击行为：双击切换最大化/还原。
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
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 40,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _toggleMaximize,
        child: DragToMoveArea(
          child: Row(
          children: [
            const Spacer(),
            DesktopWindowCaptionButton(
              icon: Icons.remove_rounded,
              tooltip: '最小化',
              iconColor: widget.iconColor,
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
              iconColor: widget.iconColor,
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
        ),
      ),
    );
  }
}
