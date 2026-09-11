import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'windows_desktop_lyrics_bridge.dart';

typedef DesktopLyricsVisibilityChanged =
    void Function({required bool visible, required bool userClosed});

typedef DesktopLyricsPlaybackAction = void Function(String action);

/// 子窗工具栏请求切换锁定状态（true=锁定，false=解锁）。
/// 锁定语义 = QQ 音乐式全穿透，锁定/解锁统一由主窗落盘并回推子窗。
typedef DesktopLyricsLockChanged = void Function(bool locked);

class DesktopLyricsSettings {
  // 默认 QQ 音乐式透明悬浮：无底色（透明度 0），靠文字阴影保证可读性；
  // 字号 24 在 780x88 悬浮窗内展示效果最佳。用户可在设置页调回底色。
  // 默认经典金黄（已播放 0xFFFFD700）与天蓝（未播放 0xFF00BFFF）卡拉OK双色，单行居中。
  const DesktopLyricsSettings({
    this.opacity = 0.0,
    this.locked = false,
    this.passthrough = false,
    int? textColor,
    this.backgroundColor = 0xFF1A1A2E,
    this.fontSize = 24.0,
    this.singleLine = true,
    this.alignment = 'center',
    this.textOpacity = 1.0,
    this.playedTextColor = 0xFFFFD700,
    int? unplayedTextColor,
  }) : unplayedTextColor = unplayedTextColor ?? textColor ?? 0xFF00BFFF;

  final double opacity;
  final bool locked;
  final bool passthrough;
  final int backgroundColor;
  final double fontSize;
  final bool singleLine;
  final String alignment;
  final double textOpacity;
  final int playedTextColor;
  final int unplayedTextColor;

  /// 向下兼容别名，映射至 [unplayedTextColor]
  int get textColor => unplayedTextColor;

  DesktopLyricsSettings copyWith({
    double? opacity,
    bool? locked,
    bool? passthrough,
    int? textColor,
    int? backgroundColor,
    double? fontSize,
    bool? singleLine,
    String? alignment,
    double? textOpacity,
    int? playedTextColor,
    int? unplayedTextColor,
  }) {
    return DesktopLyricsSettings(
      opacity: opacity ?? this.opacity,
      locked: locked ?? this.locked,
      passthrough: passthrough ?? this.passthrough,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
      singleLine: singleLine ?? this.singleLine,
      alignment: alignment ?? this.alignment,
      textOpacity: textOpacity ?? this.textOpacity,
      playedTextColor: playedTextColor ?? this.playedTextColor,
      unplayedTextColor:
          unplayedTextColor ?? textColor ?? this.unplayedTextColor,
    );
  }

  Map<String, dynamic> toMap() => {
    'opacity': opacity,
    'locked': locked,
    'passthrough': passthrough,
    'textColor': unplayedTextColor,
    'backgroundColor': backgroundColor,
    'fontSize': fontSize,
    'singleLine': singleLine,
    'alignment': alignment,
    'textOpacity': textOpacity,
    'playedTextColor': playedTextColor,
    'unplayedTextColor': unplayedTextColor,
  };

  @override
  bool operator ==(Object other) =>
      other is DesktopLyricsSettings &&
      other.opacity == opacity &&
      other.locked == locked &&
      other.passthrough == passthrough &&
      other.backgroundColor == backgroundColor &&
      other.fontSize == fontSize &&
      other.singleLine == singleLine &&
      other.alignment == alignment &&
      other.textOpacity == textOpacity &&
      other.playedTextColor == playedTextColor &&
      other.unplayedTextColor == unplayedTextColor;

  @override
  int get hashCode => Object.hash(
    opacity,
    locked,
    passthrough,
    backgroundColor,
    fontSize,
    singleLine,
    alignment,
    textOpacity,
    playedTextColor,
    unplayedTextColor,
  );

  factory DesktopLyricsSettings.fromMap(Map<String, dynamic> map) {
    return DesktopLyricsSettings(
      opacity: (map['opacity'] as num?)?.toDouble() ?? 0.0,
      locked: map['locked'] as bool? ?? false,
      passthrough: map['passthrough'] as bool? ?? false,
      backgroundColor: (map['backgroundColor'] as num?)?.toInt() ?? 0xFF1A1A2E,
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 24.0,
      singleLine: map['singleLine'] as bool? ?? true,
      alignment: map['alignment'] as String? ?? 'center',
      textOpacity: (map['textOpacity'] as num?)?.toDouble() ?? 1.0,
      playedTextColor:
          (map['playedTextColor'] as num?)?.toInt() ?? 0xFFFFD700,
      unplayedTextColor:
          (map['unplayedTextColor'] as num?)?.toInt() ??
          (map['textColor'] as num?)?.toInt() ??
          0xFF00BFFF,
    );
  }
}

class DesktopLyricsService {
  static const _channel = MethodChannel('shiyin_music/desktop_lyrics');
  static bool _handlerAttached = false;
  static DesktopLyricsVisibilityChanged? _visibilityChanged;
  static DesktopLyricsPlaybackAction? _playbackAction;
  static DesktopLyricsLockChanged? _lockChanged;
  static ValueChanged<DesktopLyricsSettings>? _settingsChanged;
  static VoidCallback? _openSettingsRequested;

  /// 桌面形态的悬浮窗桥接（进程级单例；Android 分支不使用）。
  /// Windows/Linux 共用（实现基于 desktop_multi_window + window_manager，
  /// 平台无关）；可见性、播控与锁定回调经静态转发交给实例级
  /// [_visibilityChanged] / [_playbackAction] / [_lockChanged] /
  /// [_settingsChanged] / [_openSettingsRequested]。
  static final WindowsDesktopLyricsBridge? _windowsBridge = _isDesktopBridge
      ? WindowsDesktopLyricsBridge(
          onVisibilityChanged: _forwardVisibilityChanged,
          onPlaybackAction: _forwardPlaybackAction,
          onLockChanged: _forwardLockChanged,
          onSettingsChanged: _forwardSettingsChanged,
          onOpenSettings: _forwardOpenSettings,
        )
      : null;

  /// 桌面分支（悬浮窗桥接）：Windows 与 Linux。两侧 runner 均已注册
  /// desktop_multi_window 子窗的 window_manager 插件
  /// （windows/runner/main.cpp 与 linux/runner/my_application.cc 的
  /// SetWindowCreatedCallback），悬浮窗的 frameless/置顶/跳过任务栏可用。
  static bool get _isDesktopBridge =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static void _forwardVisibilityChanged({
    required bool visible,
    required bool userClosed,
  }) {
    _visibilityChanged?.call(visible: visible, userClosed: userClosed);
  }

  static void _forwardPlaybackAction(String action) {
    _playbackAction?.call(action);
  }

  static void _forwardLockChanged(bool locked) {
    _lockChanged?.call(locked);
  }

  static void _forwardSettingsChanged(DesktopLyricsSettings settings) {
    _settingsChanged?.call(settings);
  }

  static void _forwardOpenSettings() {
    _openSettingsRequested?.call();
  }

  DesktopLyricsService() {
    _attachHandler();
  }

  static bool get isSupportedPlatform {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            // 桌面歌词子窗（desktop_multi_window + window_manager 组合）需要
            // runner 侧注册子窗插件（子引擎默认只注册 desktop_multi_window
            // 自身）：Windows（windows/runner/main.cpp）与 Linux
            // （linux/runner/my_application.cc）均已通过
            // SetWindowCreatedCallback 补注册 window_manager。
            // macOS runner 未配置（非发布目标），保持不支持。
            // Linux 已知限制：window_manager Linux 侧无 setIgnoreMouseEvents
            // （点击穿透）实现，锁定模式下窗口仍会接收鼠标（已 catch 降级，
            // 不影响展示与拖动）。
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
  }

  /// 主窗侧直接关闭悬浮子窗（不翻转持久化的开关状态）。
  ///
  /// 注意：应用退出不再走本方法——quitGracefully 直接终止进程，子窗引擎
  /// 随进程被内核回收（其 teardown 在 IME/UIA 环境下会崩溃，见
  /// DesktopWindow.quitGracefully 注释）。本方法保留给需要单独关闭
  /// 子窗的非退出场景。
  static Future<void> shutdown() async {
    await _windowsBridge?.hide();
  }

  void setVisibilityChangedHandler(DesktopLyricsVisibilityChanged? handler) {
    _visibilityChanged = handler;
  }

  void setPlaybackActionHandler(DesktopLyricsPlaybackAction? handler) {
    _playbackAction = handler;
  }

  void setLockChangedHandler(DesktopLyricsLockChanged? handler) {
    _lockChanged = handler;
  }

  void setSettingsChangedHandler(ValueChanged<DesktopLyricsSettings>? handler) {
    _settingsChanged = handler;
  }

  void setOpenSettingsHandler(VoidCallback? handler) {
    _openSettingsRequested = handler;
  }

  static void _attachHandler() {
    if (_handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVisibilityChanged') {
        final args = call.arguments;
        if (args is! Map) {
          return;
        }
        _visibilityChanged?.call(
          visible: args['visible'] as bool? ?? false,
          userClosed: args['userClosed'] as bool? ?? false,
        );
      } else if (call.method == 'controlPlayback') {
        final action = call.arguments?.toString();
        if (action != null && action.isNotEmpty) {
          _playbackAction?.call(action);
        }
      }
    });
  }

  Future<bool> checkPermission() async {
    if (!isSupportedPlatform) return false;
    // Windows：悬浮窗无需特殊权限。
    if (_isDesktopBridge) return true;
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission');
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> requestPermission() async {
    if (!isSupportedPlatform) return;
    // Windows：无权限流程，no-op。
    if (_isDesktopBridge) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on MissingPluginException {
      // ignore
    }
  }

  Future<bool> show({required String title, required String artist}) async {
    if (!isSupportedPlatform) return false;
    if (_isDesktopBridge) {
      return await _windowsBridge?.show(title: title, artist: artist) ?? false;
    }
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'artist': artist,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> hide() async {
    if (!isSupportedPlatform) return;
    if (_isDesktopBridge) {
      await _windowsBridge?.hide();
      return;
    }
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> updateLyrics({
    required String current,
    required String next,
  }) async {
    if (!isSupportedPlatform) return;
    if (_isDesktopBridge) {
      await _windowsBridge?.updateLyrics(current: current, next: next);
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateLyrics', {
        'current': current,
        'next': next,
      });
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> updatePlayState({required bool isPlaying}) async {
    if (!isSupportedPlatform) return;
    if (_isDesktopBridge) {
      await _windowsBridge?.updatePlayState(isPlaying: isPlaying);
      return;
    }
    try {
      await _channel.invokeMethod<void>('updatePlayState', {
        'isPlaying': isPlaying,
      });
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> updateKaraokeProgress({
    required double progress,
    required Duration? lineDuration,
    required bool isPlaying,
  }) async {
    if (!isSupportedPlatform) return;
    // Windows：v1 整行展示，不做逐字进度。
    if (_isDesktopBridge) {
      await _windowsBridge?.updateKaraokeProgress(
        progress: progress,
        lineDuration: lineDuration,
        isPlaying: isPlaying,
      );
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateKaraokeProgress', {
        'progress': progress,
        'lineDurationMs': lineDuration?.inMilliseconds ?? 0,
        'isPlaying': isPlaying,
      });
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> updateSettings(DesktopLyricsSettings settings) async {
    if (!isSupportedPlatform) return;
    if (_isDesktopBridge) {
      await _windowsBridge?.updateSettings(settings);
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateSettings', settings.toMap());
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> setAppForeground({required bool isForeground}) async {
    if (!isSupportedPlatform) return;
    if (_isDesktopBridge) {
      await _windowsBridge?.setAppForeground(isForeground: isForeground);
      return;
    }
    try {
      await _channel.invokeMethod<void>('setAppForeground', {
        'isForeground': isForeground,
      });
    } on MissingPluginException {
      // ignore
    }
  }

  Future<bool> isVisible() async {
    if (!isSupportedPlatform) return false;
    if (_isDesktopBridge) return _windowsBridge?.isVisible ?? false;
    try {
      final result = await _channel.invokeMethod<bool>('isVisible');
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
