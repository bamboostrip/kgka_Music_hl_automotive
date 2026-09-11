import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/services/desktop_lyrics_service.dart';
import 'package:shiyin_music/services/windows_desktop_lyrics_bridge.dart';
import 'package:shiyin_music/ui/desktop/lyrics_karaoke_line.dart';
import 'package:shiyin_music/ui/desktop/lyrics_overlay_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowsDesktopLyricsBridge dimensions', () {
    test('悬浮窗尺寸更新为宽 780、高 88', () {
      expect(WindowsDesktopLyricsBridge.overlayWidth, 780);
      expect(WindowsDesktopLyricsBridge.overlayHeight, 88);
    });
  });

  group('DesktopLyricsSettings', () {
    test('默认配置为透明悬浮、标准字号与默认布局/色彩', () {
      const settings = DesktopLyricsSettings();
      expect(settings.opacity, 0.0);
      expect(settings.locked, isFalse);
      expect(settings.passthrough, isFalse);
      expect(settings.textColor, 0xFF00BFFF);
      expect(settings.unplayedTextColor, 0xFF00BFFF);
      expect(settings.playedTextColor, 0xFFFFD700);
      expect(settings.fontSize, 24.0);
      expect(settings.singleLine, isTrue);
      expect(settings.alignment, 'center');
      expect(settings.textOpacity, 1.0);
      expect(settings.backgroundColor, 0xFF1A1A2E);
    });

    test('序列化与反序列化完整保持所有新旧字段', () {
      const original = DesktopLyricsSettings(
        opacity: 0.8,
        locked: true,
        passthrough: true,
        backgroundColor: 0xFF141823,
        fontSize: 22.0,
        singleLine: false,
        alignment: 'left',
        textOpacity: 0.85,
        playedTextColor: 0xFFFF0000,
        unplayedTextColor: 0xFF00FF00,
      );

      final map = original.toMap();
      expect(map['singleLine'], isFalse);
      expect(map['alignment'], 'left');
      expect(map['textOpacity'], 0.85);
      expect(map['playedTextColor'], 0xFFFF0000);
      expect(map['unplayedTextColor'], 0xFF00FF00);
      expect(map['textColor'], 0xFF00FF00);

      final restored = DesktopLyricsSettings.fromMap(map);

      expect(restored.opacity, original.opacity);
      expect(restored.locked, original.locked);
      expect(restored.passthrough, original.passthrough);
      expect(restored.backgroundColor, original.backgroundColor);
      expect(restored.fontSize, original.fontSize);
      expect(restored.singleLine, original.singleLine);
      expect(restored.alignment, original.alignment);
      expect(restored.textOpacity, original.textOpacity);
      expect(restored.playedTextColor, original.playedTextColor);
      expect(restored.unplayedTextColor, original.unplayedTextColor);
      expect(restored.textColor, original.unplayedTextColor);
      expect(restored, original);
    });

    test('兼容旧持久化字段：passthrough 保留，缺失字段取默认值，unplayedTextColor 回退到 textColor', () {
      // 旧版本 JSON：locked + passthrough 同时存在。
      final legacy = DesktopLyricsSettings.fromMap(const {
        'opacity': 0.5,
        'locked': true,
        'passthrough': true,
        'fontSize': 20.0,
      });
      expect(legacy.locked, isTrue);
      expect(legacy.passthrough, isTrue);
      expect(legacy.opacity, 0.5);
      expect(legacy.fontSize, 20.0);
      expect(legacy.singleLine, isTrue);
      expect(legacy.alignment, 'center');
      expect(legacy.textOpacity, 1.0);
      expect(legacy.playedTextColor, 0xFFFFD700);
      expect(legacy.unplayedTextColor, 0xFF00BFFF);

      // 旧配置仅含 textColor：unplayedTextColor 自动回退并同步 textColor
      final legacyTextColor = DesktopLyricsSettings.fromMap(const {
        'textColor': 0xFF123456,
      });
      expect(legacyTextColor.unplayedTextColor, 0xFF123456);
      expect(legacyTextColor.textColor, 0xFF123456);

      // 同时包含 unplayedTextColor 与 textColor 时，unplayedTextColor 优先
      final dualColorMap = DesktopLyricsSettings.fromMap(const {
        'textColor': 0xFF111111,
        'unplayedTextColor': 0xFF222222,
      });
      expect(dualColorMap.unplayedTextColor, 0xFF222222);
      expect(dualColorMap.textColor, 0xFF222222);

      // 字段全缺失时不抛异常，逐项取默认值。
      final minimal = DesktopLyricsSettings.fromMap(const {'locked': true});
      expect(minimal.locked, isTrue);
      expect(minimal.passthrough, isFalse);
      expect(minimal.opacity, 0.0);
      expect(minimal.fontSize, 24.0);
      expect(minimal.singleLine, isTrue);
      expect(minimal.alignment, 'center');
      expect(minimal.textOpacity, 1.0);
      expect(minimal.playedTextColor, 0xFFFFD700);
      expect(minimal.unplayedTextColor, 0xFF00BFFF);
    });

    test('相等性与 copyWith 完整覆盖所有新旧字段', () {
      const base = DesktopLyricsSettings();

      // copyWith 各个新字段
      expect(base.copyWith(singleLine: false).singleLine, isFalse);
      expect(base.copyWith(alignment: 'right').alignment, 'right');
      expect(base.copyWith(textOpacity: 0.5).textOpacity, 0.5);
      expect(base.copyWith(playedTextColor: 0xFF123456).playedTextColor, 0xFF123456);
      expect(base.copyWith(unplayedTextColor: 0xFF654321).unplayedTextColor, 0xFF654321);
      expect(base.copyWith(textColor: 0xFF778899).textColor, 0xFF778899);
      expect(base.copyWith(textColor: 0xFF778899).unplayedTextColor, 0xFF778899);

      // 相等性对比
      final modifiedSingleLine = base.copyWith(singleLine: false);
      expect(modifiedSingleLine, isNot(base));
      expect(modifiedSingleLine.hashCode, isNot(base.hashCode));

      final modifiedAlignment = base.copyWith(alignment: 'left');
      expect(modifiedAlignment, isNot(base));
      expect(modifiedAlignment.hashCode, isNot(base.hashCode));

      final modifiedTextOpacity = base.copyWith(textOpacity: 0.8);
      expect(modifiedTextOpacity, isNot(base));
      expect(modifiedTextOpacity.hashCode, isNot(base.hashCode));

      final modifiedPlayedColor = base.copyWith(playedTextColor: 0xFF111111);
      expect(modifiedPlayedColor, isNot(base));
      expect(modifiedPlayedColor.hashCode, isNot(base.hashCode));

      final modifiedUnplayedColor = base.copyWith(unplayedTextColor: 0xFF222222);
      expect(modifiedUnplayedColor, isNot(base));
      expect(modifiedUnplayedColor.hashCode, isNot(base.hashCode));

      const locked = DesktopLyricsSettings(locked: true);
      expect(const DesktopLyricsSettings(locked: true), locked);
      expect(const DesktopLyricsSettings(locked: false, passthrough: true),
          isNot(locked));

      final unlocked = locked.copyWith(locked: false);
      expect(unlocked.locked, isFalse);
      expect(unlocked, const DesktopLyricsSettings());
      // passthrough 字段保留解析，但 UI 已无该开关；锁定语义吸收穿透。
      expect(locked.copyWith(locked: false).passthrough, isFalse);
    });
  });

  group('DesktopLyricsService PlaybackAction', () {
    const channel = MethodChannel('shiyin_music/desktop_lyrics');

    test('支持注册与触发 controlPlayback 播控指令', () async {
      final service = DesktopLyricsService();
      final receivedActions = <String>[];

      service.setPlaybackActionHandler((action) {
        receivedActions.add(action);
      });

      // 模拟平台通道下发播控事件
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      await binding.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('controlPlayback', 'previous')),
        (ByteData? data) {},
      );
      await binding.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('controlPlayback', 'togglePlay')),
        (ByteData? data) {},
      );
      await binding.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('controlPlayback', 'next')),
        (ByteData? data) {},
      );

      expect(receivedActions, ['previous', 'togglePlay', 'next']);

      service.setPlaybackActionHandler(null);
    });

    test('支持注册与注销 setSettingsChangedHandler 与 setOpenSettingsHandler', () {
      final service = DesktopLyricsService();
      DesktopLyricsSettings? changedSettings;
      var openSettingsCalled = false;

      service.setSettingsChangedHandler((s) => changedSettings = s);
      service.setOpenSettingsHandler(() => openSettingsCalled = true);

      service.setSettingsChangedHandler(null);
      service.setOpenSettingsHandler(null);
      expect(changedSettings, isNull);
      expect(openSettingsCalled, isFalse);
    });
  });

  group('isLyricsOverlayWindowArgs', () {
    test('正确识别 multi_window 子窗口启动参数', () {
      expect(isLyricsOverlayWindowArgs(['multi_window', '1']), isTrue);
      expect(isLyricsOverlayWindowArgs(['multi_window', '1', '{}']), isTrue);
      expect(isLyricsOverlayWindowArgs(['multi_window']), isFalse);
      expect(isLyricsOverlayWindowArgs(['main']), isFalse);
      expect(isLyricsOverlayWindowArgs([]), isFalse);
    });
  });

  group('WindowsDesktopLyricsBridge 就绪门控', () {
    // 与 desktop_multi_window 0.2.1 源码（src/channels.dart）一致：
    // - mixin.one/flutter_multi_window：窗口控制通道（createWindow/setFrame/close）。
    // - mixin.one/flutter_multi_window_channel：窗口间消息通道
    //   （主->子 invokeMethod；子->主经 setMethodHandler 分发，
    //   入站信封为 {fromWindowId, arguments}）。
    const multiWindowChannel = MethodChannel('mixin.one/flutter_multi_window');
    const windowEventChannel =
        MethodChannel('mixin.one/flutter_multi_window_channel');
    const fakeWindowId = 42;

    /// 记录主窗 -> 子窗的全部消息（即被门控的推送路径）。
    final outgoing = <MethodCall>[];

    void setUpMultiWindowMocks(TestDefaultBinaryMessengerBinding binding) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(multiWindowChannel, (call) async {
        // createWindow 返回固定窗口ID，其余窗口控制调用一律成功。
        return call.method == 'createWindow' ? fakeWindowId : null;
      });
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowEventChannel, (call) async {
        outgoing.add(call);
        return null;
      });
    }

    void clearMultiWindowMocks(TestDefaultBinaryMessengerBinding binding) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(multiWindowChannel, null);
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowEventChannel, null);
      outgoing.clear();
    }

    /// 模拟子引擎经 windowEventChannel 向主窗上报消息
    /// （desktop_multi_window 包装层从信封取 fromWindowId/arguments）。
    Future<void> simulateChildMessage(
      TestDefaultBinaryMessengerBinding binding,
      String method, [
      dynamic arguments,
    ]) async {
      const codec = StandardMethodCodec();
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        windowEventChannel.name,
        codec.encodeMethodCall(MethodCall(method, <String, dynamic>{
          'fromWindowId': fakeWindowId,
          'arguments': arguments,
        })),
        (ByteData? data) {},
      );
    }

    List<MethodCall> pushesOf(String method) =>
        outgoing.where((c) => c.method == method).toList();

    dynamic pushPayload(MethodCall call) =>
        (call.arguments as Map)['arguments'] as Map;

    test('overlayReady 之前 updateLyrics 不 invoke 通道，就绪后补发缓存歌词与设置',
        () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      final bridge = WindowsDesktopLyricsBridge();
      final shown = await bridge.show(title: '标题', artist: '歌手');
      expect(shown, isTrue);
      expect(bridge.isVisible, isTrue);

      // 冷启动窗口期（子引擎未上报 overlayReady）：推送只更新缓存，
      // 不产生任何通道调用，不再触发 MissingPluginException。
      await bridge.updateLyrics(current: '第一句', next: '第二句');
      await bridge.updatePlayState(isPlaying: true);
      await bridge.updateSettings(const DesktopLyricsSettings(fontSize: 28.0));
      expect(pushesOf('updateLyric'), isEmpty);
      expect(pushesOf('updateSettings'), isEmpty);

      // 子引擎完成初始化并注册 handler 后上报 overlayReady。
      await simulateChildMessage(binding, 'overlayReady');

      // 就绪后主窗补发缓存歌词与设置。
      final lyricPushes = pushesOf('updateLyric');
      expect(lyricPushes, hasLength(1));
      final lyricPayload = pushPayload(lyricPushes.single);
      expect(lyricPayload['current'], '第一句');
      expect(lyricPayload['next'], '第二句');
      expect(lyricPayload['isPlaying'], isTrue);

      final settingsPushes = pushesOf('updateSettings');
      expect(settingsPushes, hasLength(1));
      expect((pushPayload(settingsPushes.single)['fontSize'] as num).toDouble(),
          28.0);
    });

    test('windowClosed 复位门控，重建子窗需新一轮 overlayReady 握手', () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      final bridge = WindowsDesktopLyricsBridge();
      await bridge.show(title: '标题', artist: '歌手');

      // 首轮握手前：推送只更新缓存，不产生通道调用。
      await bridge.updateLyrics(current: 'A', next: 'B');
      expect(pushesOf('updateLyric'), isEmpty);

      // 首轮握手：补发当时缓存。
      await simulateChildMessage(binding, 'overlayReady');
      expect(pushesOf('updateLyric'), hasLength(1));
      expect(pushPayload(pushesOf('updateLyric').single)['current'], 'A');

      // 用户手动关闭子窗：就绪门控与可见性同步复位。
      await simulateChildMessage(binding, 'windowClosed');
      expect(bridge.isVisible, isFalse);

      // 重新展示（重建子窗）：新引擎握手前推送仍被门控（缓存已更新为 C）。
      final reshow = await bridge.show(title: '标题', artist: '歌手');
      expect(reshow, isTrue);
      await bridge.updateLyrics(current: 'C', next: 'D');
      expect(pushesOf('updateLyric'), hasLength(1));

      // 新一轮握手后补发最新缓存。
      await simulateChildMessage(binding, 'overlayReady');
      expect(pushesOf('updateLyric'), hasLength(2));
      final latest = pushesOf('updateLyric').last;
      expect(pushPayload(latest)['current'], 'C');
    });

    test('已展示时重复 show 复用旧窗，就绪状态不被误重置', () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      final bridge = WindowsDesktopLyricsBridge();
      await bridge.show(title: '标题', artist: '歌手');
      // 首轮握手：空缓存也照常补发一次（以此次数为基线）。
      await simulateChildMessage(binding, 'overlayReady');
      final baseline = pushesOf('updateLyric').length;
      expect(baseline, 1);

      await bridge.updateLyrics(current: '第一句', next: '第二句');
      expect(pushesOf('updateLyric').length, baseline + 1);

      // 重复 show：走复用分支并直接推送（若误重置门控，此处不会再推送）。
      final again = await bridge.show(title: '标题', artist: '歌手');
      expect(again, isTrue);
      expect(pushesOf('updateLyric').length, baseline + 2);
      expect(pushPayload(pushesOf('updateLyric').last)['current'], '第一句');
    });

    test('setLyricsLocked 转发回调；主窗处理后的 updateSettings 回推子窗',
        () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      final reported = <bool>[];
      final bridge = WindowsDesktopLyricsBridge(onLockChanged: reported.add);
      await bridge.show(title: '标题', artist: '歌手');
      await simulateChildMessage(binding, 'overlayReady');
      outgoing.clear();

      // 子窗工具栏锁定按钮上报 setLyricsLocked=true → 主窗回调。
      await simulateChildMessage(binding, 'setLyricsLocked', true);
      expect(reported, [true]);

      // 模拟主窗侧（PlayerController）处理回调：落盘 + 回推新设置，
      // 子窗不本地直改锁定状态，统一经 updateSettings 重建。
      await bridge.updateSettings(const DesktopLyricsSettings(locked: true));
      final pushes = pushesOf('updateSettings');
      expect(pushes, hasLength(1));
      expect(pushPayload(pushes.single)['locked'], isTrue);

      // 子窗请求解锁同样转发。
      await simulateChildMessage(binding, 'setLyricsLocked', false);
      expect(reported, [true, false]);
    });

    test('updateKaraokeProgress 就绪时推送 updateProgress，未就绪时缓存并由 overlayReady 补发',
        () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      final bridge = WindowsDesktopLyricsBridge();
      await bridge.show(title: '标题', artist: '歌手');

      // 未就绪时调用 updateKaraokeProgress：只更新缓存，不推送
      await bridge.updateKaraokeProgress(
        progress: 0.35,
        lineDuration: const Duration(seconds: 4),
        isPlaying: true,
      );
      expect(pushesOf('updateProgress'), isEmpty);

      // overlayReady 握手后补发缓存进度
      await simulateChildMessage(binding, 'overlayReady');
      final progressPushes = pushesOf('updateProgress');
      expect(progressPushes, hasLength(1));
      final payload = pushPayload(progressPushes.single);
      expect(payload['progress'], 0.35);
      expect(payload['isPlaying'], isTrue);

      // 就绪后再次调用：立即推送
      await bridge.updateKaraokeProgress(
        progress: 0.75,
        lineDuration: const Duration(seconds: 4),
        isPlaying: false,
      );
      expect(pushesOf('updateProgress'), hasLength(2));
      final nextPayload = pushPayload(pushesOf('updateProgress').last);
      expect(nextPayload['progress'], 0.75);
      expect(nextPayload['isPlaying'], isFalse);
    });

    test('子窗发送 updateOverlaySettings 触发 onSettingsChanged 回调且正确反序列化',
        () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      final settingsList = <DesktopLyricsSettings>[];
      final bridge = WindowsDesktopLyricsBridge(
        onSettingsChanged: settingsList.add,
      );
      await bridge.show(title: '标题', artist: '歌手');
      await simulateChildMessage(binding, 'overlayReady');

      await simulateChildMessage(
        binding,
        'updateOverlaySettings',
        <String, dynamic>{
          'fontSize': 32.0,
          'opacity': 0.6,
          'singleLine': false,
          'alignment': 'left',
          'playedTextColor': 0xFFFF0000,
          'unplayedTextColor': 0xFF00FF00,
        },
      );

      expect(settingsList, hasLength(1));
      final received = settingsList.single;
      expect(received.fontSize, 32.0);
      expect(received.opacity, 0.6);
      expect(received.singleLine, isFalse);
      expect(received.alignment, 'left');
      expect(received.playedTextColor, 0xFFFF0000);
      expect(received.unplayedTextColor, 0xFF00FF00);
    });

    test('子窗发送 openLyricsSettings 触发 onOpenSettings 回调', () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      setUpMultiWindowMocks(binding);
      addTearDown(() => clearMultiWindowMocks(binding));

      var openSettingsTriggered = false;
      final bridge = WindowsDesktopLyricsBridge(
        onOpenSettings: () {
          openSettingsTriggered = true;
        },
      );
      await bridge.show(title: '标题', artist: '歌手');
      await simulateChildMessage(binding, 'overlayReady');

      await simulateChildMessage(binding, 'openLyricsSettings');
      expect(openSettingsTriggered, isTrue);
    });
  });

  group('锁定态纯歌词子树（QQ 音乐式全穿透）', () {
    final contentKey = GlobalKey();

    Future<void> pumpContent(
      WidgetTester tester, {
      required DesktopLyricsSettings settings,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: KeyedSubtree(
            key: contentKey,
            child: DesktopLyricsOverlayContent(
              settings: settings,
              current: '第一句歌词',
              next: '第二句歌词',
              isPlaying: true,
              onControlPlayback: (_) {},
              onToggleLock: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pump();
    }

    testWidgets('锁定：只渲染歌词文字与悬浮解锁胶囊，无播控工具栏',
        (tester) async {
      await pumpContent(
        tester,
        settings: const DesktopLyricsSettings(locked: true, singleLine: false),
      );

      // 歌词文字仍在（含下一句）。
      expect(find.text('第一句歌词'), findsWidgets);
      expect(find.text('第二句歌词'), findsWidgets);

      // 无工具栏 Tooltip。
      final content = find.byKey(contentKey);
      expect(
        find.descendant(of: content, matching: find.byType(Tooltip)),
        findsNothing,
      );
      // 悬浮播控栏全部图标在锁定子树中一律不存在。
      const playbackToolbarIcons = [
        Icons.lock_open_rounded,
        Icons.close_rounded,
        Icons.play_arrow_rounded,
        Icons.pause_rounded,
        Icons.skip_previous_rounded,
        Icons.skip_next_rounded,
        Icons.settings_rounded,
      ];
      expect(
        find.descendant(
          of: content,
          matching: find.byWidgetPredicate(
            (w) => w is Icon && playbackToolbarIcons.contains(w.icon),
          ),
        ),
        findsNothing,
      );
      // 包含解锁胶囊（Icons.lock_rounded + 解锁文字），初始透明度为 0.0
      expect(find.text('解锁'), findsOneWidget);
      final opacityWidget = tester.widget<AnimatedOpacity>(
        find.descendant(of: content, matching: find.byType(AnimatedOpacity)),
      );
      expect(opacityWidget.opacity, 0.0);
    });

    testWidgets('未锁定：保留工具栏与锁按钮（悬停 UI 只属于非锁定态）',
        (tester) async {
      await pumpContent(tester, settings: const DesktopLyricsSettings());

      expect(find.text('第一句歌词'), findsWidgets);
      expect(find.byType(Tooltip), findsWidgets);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('applyDesktopLyricsPassthrough 锁定即穿透', () {
    const windowManagerChannel = MethodChannel('window_manager');

    test('locked ⇒ setIgnoreMouseEvents(true)；解锁恢复 false', () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      final ignoreCalls = <bool>[];
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, (call) async {
        if (call.method == 'setIgnoreMouseEvents') {
          final args = call.arguments as Map;
          ignoreCalls.add(args['ignore'] as bool);
        }
        return null;
      });
      addTearDown(() => binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, null));

      // 锁定即全穿透：不再受旧 passthrough 字段影响。
      await applyDesktopLyricsPassthrough(
        const DesktopLyricsSettings(locked: true, passthrough: false),
      );
      await applyDesktopLyricsPassthrough(
        const DesktopLyricsSettings(locked: true, passthrough: true),
      );
      // 解锁恢复鼠标事件。
      await applyDesktopLyricsPassthrough(
        const DesktopLyricsSettings(locked: false),
      );

      expect(ignoreCalls, [true, true, false]);
    });
  });

  group('OverlayPassthroughScheduler（穿透延迟到窗口显示后）', () {
    test('显示前只登记不施加，markShown 后 flushPending 施加最后一笔', () async {
      final applied = <bool>[];
      final scheduler = OverlayPassthroughScheduler(
        onApply: (settings) async => applied.add(settings.locked),
      );

      // 窗口隐藏期间（插件创建子窗后默认 SW_HIDE）到达的设置：
      // 只登记，绝不触碰原生层（隐藏期加 WS_EX_LAYERED 会让内容面
      // 永久空白——锁定重开后歌词消失的根因）。
      await scheduler.apply(const DesktopLyricsSettings(locked: true));
      await scheduler.apply(const DesktopLyricsSettings(locked: false));
      await scheduler.apply(const DesktopLyricsSettings(locked: true));
      expect(applied, isEmpty);

      scheduler.markShown();
      await scheduler.flushPending();
      expect(applied, [true]);
    });

    test('markShown 之后的 apply 立即施加（工具栏解锁/重锁路径）', () async {
      final applied = <bool>[];
      final scheduler = OverlayPassthroughScheduler(
        onApply: (settings) async => applied.add(settings.locked),
      );
      scheduler.markShown();

      await scheduler.apply(const DesktopLyricsSettings(locked: true));
      await scheduler.apply(const DesktopLyricsSettings(locked: false));
      expect(applied, [true, false]);

      // 无遗留 pending。
      await scheduler.flushPending();
      expect(applied, [true, false]);
    });
  });

  group('歌词主体高度自适应（防溢出黄黑条纹）', () {
    // 悬浮窗固定 780x88：系统字体缩放（make text bigger）或设置页大字号
    // （上限 48sp）下两行总高可能超过窗高。修复前 Column 直接溢出，
    // 窗口底部常驻 RenderFlex 黄黑条纹。
    Future<void> pumpOverlay(
      WidgetTester tester, {
      required DesktopLyricsSettings settings,
      double textScale = 1.0,
      double progress = 0.0,
    }) async {
      tester.view.physicalSize = const Size(
        WindowsDesktopLyricsBridge.overlayWidth,
        WindowsDesktopLyricsBridge.overlayHeight,
      );
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(
              WindowsDesktopLyricsBridge.overlayWidth,
              WindowsDesktopLyricsBridge.overlayHeight,
            ),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: DesktopLyricsOverlayContent(
              settings: settings,
              current: '当前句歌词内容',
              next: '下一句歌词内容',
              isPlaying: true,
              progress: progress,
              onControlPlayback: (_) {},
              onToggleLock: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('锁定态 textScale=$scale 不溢出', (tester) async {
        await pumpOverlay(
          tester,
          settings: const DesktopLyricsSettings(locked: true),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('锁定态设置页最大字号 48sp 不溢出', (tester) async {
      await pumpOverlay(
        tester,
        settings: const DesktopLyricsSettings(locked: true, fontSize: 48),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('当前句歌词内容'), findsWidgets);
    });

    testWidgets('未锁定态悬停卡片内同样不溢出（48sp + 1.5 倍缩放）',
        (tester) async {
      await pumpOverlay(
        tester,
        settings: const DesktopLyricsSettings(locked: false, fontSize: 48),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('锁定态歌词文字无双黄下划线（decoration 为 none 且具备 Material 祖先）',
        (tester) async {
      await pumpOverlay(
        tester,
        settings: const DesktopLyricsSettings(locked: true),
      );
      final textWidget = tester.widget<Text>(find.text('当前句歌词内容').first);
      expect(textWidget.style?.decoration, TextDecoration.none);
      expect(find.byType(Material), findsWidgets);
    });
  });

  group('桌面歌词排版（单行居中与 QQ 音乐双行交错）', () {
    Future<void> pumpCustomOverlay(
      WidgetTester tester, {
      required DesktopLyricsSettings settings,
      required String current,
      required String next,
      double progress = 0.0,
    }) async {
      tester.view.physicalSize = const Size(
        WindowsDesktopLyricsBridge.overlayWidth,
        WindowsDesktopLyricsBridge.overlayHeight,
      );
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopLyricsOverlayContent(
            settings: settings,
            current: current,
            next: next,
            isPlaying: true,
            progress: progress,
            onControlPlayback: (_) {},
            onToggleLock: (_) {},
            onClose: () {},
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('单行模式 (singleLine: true)：仅渲染当前句，不渲染下一句', (tester) async {
      await pumpCustomOverlay(
        tester,
        settings: const DesktopLyricsSettings(singleLine: true),
        current: '当前句歌词内容',
        next: '下一句歌词内容',
      );
      expect(find.text('当前句歌词内容'), findsWidgets);
      expect(find.text('下一句歌词内容'), findsNothing);

      final karaokeLines = tester.widgetList<LyricsKaraokeLine>(find.byType(LyricsKaraokeLine)).toList();
      expect(karaokeLines.length, 1);
      expect(karaokeLines.first.text, '当前句歌词内容');
      expect(karaokeLines.first.fontWeight, FontWeight.bold);
    });

    testWidgets('双行交错模式 (singleLine: false)：当前句居左交错，下一句居右交错', (tester) async {
      await pumpCustomOverlay(
        tester,
        settings: const DesktopLyricsSettings(singleLine: false),
        current: '当前句歌词内容',
        next: '下一句歌词内容',
      );
      expect(find.text('当前句歌词内容'), findsWidgets);
      expect(find.text('下一句歌词内容'), findsWidgets);

      final karaokeLines = tester.widgetList<LyricsKaraokeLine>(find.byType(LyricsKaraokeLine)).toList();
      expect(karaokeLines.length, 2);

      final currentLine = karaokeLines[0];
      final nextLine = karaokeLines[1];

      expect(currentLine.text, '当前句歌词内容');
      expect(currentLine.alignment, TextAlign.left);
      expect(currentLine.fontWeight, FontWeight.bold);

      expect(nextLine.text, '下一句歌词内容');
      expect(nextLine.alignment, TextAlign.right);
      expect(nextLine.progress, 0.0);

      final column = tester.widget<Column>(find.byType(Column));
      final line1Align = column.children[0] as Align;
      final line2Align = column.children[2] as Align;
      expect(line1Align.alignment, Alignment.centerLeft);
      expect(line2Align.alignment, Alignment.centerRight);
    });

    testWidgets('双行交错模式 (singleLine: false)：上下两行统一字号与 bold 字重', (tester) async {
      const fontSize = 24.0;
      await pumpCustomOverlay(
        tester,
        settings: const DesktopLyricsSettings(singleLine: false, fontSize: fontSize),
        current: '当前句歌词内容',
        next: '下一句歌词内容',
      );

      final karaokeLines = tester.widgetList<LyricsKaraokeLine>(find.byType(LyricsKaraokeLine)).toList();
      expect(karaokeLines.length, 2);
      final currentLine = karaokeLines[0];
      final nextLine = karaokeLines[1];

      // 上下两行字体大小统一且字重均为 bold
      expect(currentLine.fontWeight, FontWeight.bold);
      expect(nextLine.fontWeight, FontWeight.bold);
      expect(currentLine.fontSize, nextLine.fontSize);
      expect(currentLine.fontSize, closeTo(fontSize * 0.82, 0.001));
      // 上行变色高亮，下行未播天蓝色，但基础 unplayedColor 与 textOpacity 一致
      expect(currentLine.unplayedColor, nextLine.unplayedColor);
      expect(currentLine.textOpacity, nextLine.textOpacity);
    });

    testWidgets('修改 progress 更新 DesktopLyricsOverlayContent 变色进度', (tester) async {
      await pumpCustomOverlay(
        tester,
        settings: const DesktopLyricsSettings(singleLine: true),
        current: '变色测试',
        next: '',
        progress: 0.25,
      );

      var karaokeLine = tester.widget<LyricsKaraokeLine>(find.byType(LyricsKaraokeLine));
      expect(karaokeLine.progress, 0.25);

      await pumpCustomOverlay(
        tester,
        settings: const DesktopLyricsSettings(singleLine: true),
        current: '变色测试',
        next: '',
        progress: 0.75,
      );

      karaokeLine = tester.widget<LyricsKaraokeLine>(find.byType(LyricsKaraokeLine));
      expect(karaokeLine.progress, 0.75);
    });

    testWidgets('单行模式下 settings.alignment 生效', (tester) async {
      for (final alignStr in ['left', 'right', 'center']) {
        final expected = alignStr == 'left'
            ? TextAlign.left
            : (alignStr == 'right' ? TextAlign.right : TextAlign.center);
        await pumpCustomOverlay(
          tester,
          settings: DesktopLyricsSettings(singleLine: true, alignment: alignStr),
          current: '对齐测试',
          next: '',
        );
        final line = tester.widget<LyricsKaraokeLine>(find.byType(LyricsKaraokeLine));
        expect(line.alignment, expected);
      }
    });

    testWidgets('当前歌词为空时渲染“暂无歌词”', (tester) async {
      await pumpCustomOverlay(
        tester,
        settings: const DesktopLyricsSettings(singleLine: true),
        current: '',
        next: '',
      );

      expect(find.text('暂无歌词'), findsWidgets);
    });

    testWidgets('双行模式下 48sp 与 2.0 textScale 同样不溢出', (tester) async {
      tester.view.physicalSize = const Size(
        WindowsDesktopLyricsBridge.overlayWidth,
        WindowsDesktopLyricsBridge.overlayHeight,
      );
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(
              WindowsDesktopLyricsBridge.overlayWidth,
              WindowsDesktopLyricsBridge.overlayHeight,
            ),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            home: DesktopLyricsOverlayContent(
              settings: const DesktopLyricsSettings(singleLine: false, fontSize: 48),
              current: '超大字号当前句歌词内容',
              next: '超大字号下一句歌词内容',
              isPlaying: true,
              progress: 0.5,
              onControlPlayback: (_) {},
              onToggleLock: (_) {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('悬浮工具栏快捷调节菜单（字号、配色、单双行）', () {
    Future<void> pumpQuickSettings(
      WidgetTester tester, {
      required Widget child,
      Future<dynamic>? Function(MethodCall call)? windowManagerHandler,
    }) async {
      tester.view.physicalSize = const Size(
        WindowsDesktopLyricsBridge.overlayWidth,
        400,
      );
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const windowManagerChannel = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        windowManagerChannel,
        windowManagerHandler ?? (call) async => null,
      );
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Align(
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        ),
      );
      await tester.pump();

      // 悬停以唤出工具栏
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(const Offset(390, 44));
      await tester.pumpAndSettle();
    }

    testWidgets('工具栏包含设置按钮 (Icons.settings_rounded)', (tester) async {
      await pumpQuickSettings(
        tester,
        child: DesktopLyricsOverlayContent(
          settings: const DesktopLyricsSettings(locked: false),
          current: '测试歌词',
          next: '',
          isPlaying: true,
          onControlPlayback: (_) {},
          onToggleLock: (_) {},
          onClose: () {},
        ),
      );
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    });

    testWidgets('工具栏去背景装饰且位置上提，按钮尺寸扩大为 30x30 且图标尺寸为 20', (tester) async {
      await pumpQuickSettings(
        tester,
        child: DesktopLyricsOverlayContent(
          settings: const DesktopLyricsSettings(locked: false),
          current: '测试歌词',
          next: '',
          isPlaying: true,
          onControlPlayback: (_) {},
          onToggleLock: (_) {},
          onClose: () {},
        ),
      );

      // 工具栏位置 top 为 2
      final positionedToolbar = tester.widget<Positioned>(
        find.ancestor(
          of: find.byIcon(Icons.settings_rounded),
          matching: find.byType(Positioned),
        ).first,
      );
      expect(positionedToolbar.top, 2.0);

      // 工具栏在 IgnorePointer 内直接是 Padding，不再有外层 DecoratedBox 半透黑色胶囊背景
      final toolbarRow = find.ancestor(
        of: find.byIcon(Icons.settings_rounded),
        matching: find.byType(Row),
      ).first;
      final ignorePointer = find.ancestor(
        of: toolbarRow,
        matching: find.byType(IgnorePointer),
      ).first;
      final ignorePointerWidget = tester.widget<IgnorePointer>(ignorePointer);
      expect(ignorePointerWidget.child, isA<Padding>());
      expect(
        find.descendant(
          of: ignorePointer,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).borderRadius ==
                    BorderRadius.circular(10),
          ),
        ),
        findsNothing,
      );

      // 按钮尺寸扩大为 30x30
      final buttonContainers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: toolbarRow,
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(buttonContainers.isNotEmpty, isTrue);
      for (final container in buttonContainers) {
        expect(container.constraints?.maxWidth, 30.0);
        expect(container.constraints?.maxHeight, 30.0);
      }

      // 工具栏播控与设置按钮默认图标统一为 20
      final icons = tester.widgetList<Icon>(
        find.descendant(
          of: toolbarRow,
          matching: find.byType(Icon),
        ),
      );
      for (final icon in icons) {
        expect(icon.size, 20.0);
      }
    });

    testWidgets('点击设置按钮展开快捷调节菜单，再次点击或点击遮罩收起', (tester) async {
      await pumpQuickSettings(
        tester,
        child: DesktopLyricsOverlayContent(
          settings: const DesktopLyricsSettings(locked: false),
          current: '测试歌词',
          next: '',
          isPlaying: true,
          onControlPlayback: (_) {},
          onToggleLock: (_) {},
          onClose: () {},
        ),
      );

      // 初始未展开菜单
      expect(find.text('字体大小'), findsNothing);
      expect(find.text('字体颜色'), findsNothing);

      // 点击设置按钮展开
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      expect(find.text('字体大小'), findsOneWidget);
      expect(find.text('字体颜色'), findsOneWidget);
      expect(find.text('更多设置'), findsOneWidget);

      // 点击遮罩外部（如左上角）收起菜单
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('字体大小'), findsNothing);
      expect(find.text('字体颜色'), findsNothing);
    });

    testWidgets('点击 [+] 或 [-] 触发字号调节回调并钳制在 [16, 40]', (tester) async {
      DesktopLyricsSettings? updatedSettings;

      await pumpQuickSettings(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            return DesktopLyricsOverlayContent(
              settings: updatedSettings ??
                  const DesktopLyricsSettings(locked: false, fontSize: 24.0),
              current: '测试歌词',
              next: '',
              isPlaying: true,
              onControlPlayback: (_) {},
              onToggleLock: (_) {},
              onClose: () {},
              onUpdateSettings: (s) => setState(() => updatedSettings = s),
            );
          },
        ),
      );

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      // 当前字号 24
      expect(find.text('24'), findsOneWidget);

      // 点击 [+] -> 26
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(updatedSettings?.fontSize, 26.0);
      expect(find.text('26'), findsOneWidget);

      // 点击 [-] -> 24
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(updatedSettings?.fontSize, 24.0);
      expect(find.text('24'), findsOneWidget);
    });

    testWidgets('点击预设配色触发颜色变更回调', (tester) async {
      DesktopLyricsSettings? updatedSettings;

      await pumpQuickSettings(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            return DesktopLyricsOverlayContent(
              settings: updatedSettings ??
                  const DesktopLyricsSettings(
                    locked: false,
                    unplayedTextColor: 0xFF00BFFF,
                    textColor: 0xFF00BFFF,
                  ),
              current: '测试歌词',
              next: '',
              isPlaying: true,
              onControlPlayback: (_) {},
              onToggleLock: (_) {},
              onClose: () {},
              onUpdateSettings: (s) => setState(() => updatedSettings = s),
            );
          },
        ),
      );

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      // 点击金黄色预设 0xFFFFD700
      await tester.tap(find.byKey(const ValueKey(0xFFFFD700)));
      await tester.pumpAndSettle();

      expect(updatedSettings?.unplayedTextColor, 0xFFFFD700);
      expect(updatedSettings?.textColor, 0xFFFFD700);
    });

    testWidgets('点击切换单/双行触发单双行切换回调', (tester) async {
      DesktopLyricsSettings? updatedSettings;

      await pumpQuickSettings(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            return DesktopLyricsOverlayContent(
              settings: updatedSettings ??
                  const DesktopLyricsSettings(locked: false, singleLine: true),
              current: '测试歌词',
              next: '',
              isPlaying: true,
              onControlPlayback: (_) {},
              onToggleLock: (_) {},
              onClose: () {},
              onUpdateSettings: (s) => setState(() => updatedSettings = s),
            );
          },
        ),
      );

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      // 单行模式下文案为“切换双行”
      expect(find.text('切换双行'), findsOneWidget);
      await tester.tap(find.text('切换双行'));
      await tester.pumpAndSettle();

      expect(updatedSettings?.singleLine, isFalse);
      expect(find.text('切换单行'), findsOneWidget);

      // 再次点击切回单行
      await tester.tap(find.text('切换单行'));
      await tester.pumpAndSettle();
      expect(updatedSettings?.singleLine, isTrue);
    });

    testWidgets('点击更多设置触发 onOpenDetailedSettings 回调并关闭菜单', (tester) async {
      var openedDetailed = false;

      await pumpQuickSettings(
        tester,
        child: DesktopLyricsOverlayContent(
          settings: const DesktopLyricsSettings(locked: false),
          current: '测试歌词',
          next: '',
          isPlaying: true,
          onControlPlayback: (_) {},
          onToggleLock: (_) {},
          onClose: () {},
          onOpenDetailedSettings: () => openedDetailed = true,
        ),
      );

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      expect(find.text('更多设置'), findsOneWidget);
      await tester.tap(find.text('更多设置'));
      await tester.pumpAndSettle();

      expect(openedDetailed, isTrue);
      // 菜单已关闭
      expect(find.text('更多设置'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('展开快捷菜单时动态调整原生窗口高度为 260，收起或销毁时复位为 88', (tester) async {
      final windowSizes = <Size>[];

      await pumpQuickSettings(
        tester,
        windowManagerHandler: (call) async {
          if (call.method == 'setSize' || call.method == 'setBounds') {
            final args = (call.arguments as Map).cast<String, dynamic>();
            windowSizes.add(Size(
              (args['width'] as num).toDouble(),
              (args['height'] as num).toDouble(),
            ));
          }
          return null;
        },
        child: DesktopLyricsOverlayContent(
          settings: const DesktopLyricsSettings(locked: false),
          current: '测试歌词',
          next: '',
          isPlaying: true,
          onControlPlayback: (_) {},
          onToggleLock: (_) {},
          onClose: () {},
        ),
      );

      // 初始未展开菜单，未触发快捷菜单引起的 setSize
      expect(windowSizes, isEmpty);

      // 1. 点击设置按钮展开菜单 -> 窗口高度调整为 260
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(windowSizes.isNotEmpty, isTrue);
      expect(
        windowSizes.last,
        const Size(WindowsDesktopLyricsBridge.overlayWidth, 260.0),
      );

      // 2. 点击空白遮罩收起菜单 -> 窗口高度恢复为 88
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        windowSizes.last,
        const Size(
          WindowsDesktopLyricsBridge.overlayWidth,
          WindowsDesktopLyricsBridge.overlayHeight,
        ),
      );

      // 3. 再次点击设置按钮展开
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(
        windowSizes.last,
        const Size(WindowsDesktopLyricsBridge.overlayWidth, 260.0),
      );

      // 4. 菜单展开状态下组件销毁（如被移除或关闭）-> dispose 防御性重置窗口尺寸回 88
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(
        windowSizes.last,
        const Size(
          WindowsDesktopLyricsBridge.overlayWidth,
          WindowsDesktopLyricsBridge.overlayHeight,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('clampOverlayOriginToVisibleAreas（拔显示器/屏幕外位置钳制）', () {
    const primary = Rect.fromLTWH(0, 0, 1920, 1080);

    test('主屏内可见位置原样返回', () {
      final origin =
          WindowsDesktopLyricsBridge.clampOverlayOriginToVisibleAreas(
        const Offset(500, 900),
        [primary],
        fallback: const Offset(100, 100),
      );
      expect(origin, const Offset(500, 900));
    });

    test('位置在已拔掉的副屏（屏幕外）→ 钳回主屏右下可见区', () {
      final origin =
          WindowsDesktopLyricsBridge.clampOverlayOriginToVisibleAreas(
        const Offset(3840, 2000),
        [primary],
        fallback: const Offset(100, 100),
      );
      // 右/下至少留 80px 可见。
      expect(origin.dx, primary.right - 80);
      expect(origin.dy, primary.bottom - 80);
    });

    test('与主屏仅数像素交集（DPI 换算贴边残余）→ 钳回可见区', () {
      // 窗口宽 780：左沿 1915 只剩 5px 可见。
      final origin =
          WindowsDesktopLyricsBridge.clampOverlayOriginToVisibleAreas(
        const Offset(1915, 500),
        [primary],
        fallback: const Offset(100, 100),
      );
      expect(origin.dx, primary.right - 80);
      expect(origin.dy, 500);
    });

    test('无显示器信息时返回 fallback（无从钳制）', () {
      final origin =
          WindowsDesktopLyricsBridge.clampOverlayOriginToVisibleAreas(
        const Offset(-5000, -5000),
        const <Rect>[],
        fallback: const Offset(100, 100),
      );
      expect(origin, const Offset(100, 100));
    });

    test('多显示器：副屏内可见位置不误钳', () {
      const secondary = Rect.fromLTWH(1920, 0, 1920, 1080);
      final origin =
          WindowsDesktopLyricsBridge.clampOverlayOriginToVisibleAreas(
        const Offset(2500, 900),
        [primary, secondary],
        fallback: const Offset(100, 100),
      );
      expect(origin, const Offset(2500, 900));
    });
  });

  group('锁定态靠近悬浮「🔒 解锁」胶囊与鼠标动态穿透', () {
    testWidgets('光标在窗口外时胶囊不可见 (opacity 0.0)', (tester) async {
      Offset? cursorPos = const Offset(0, 0);
      const windowPos = Offset(100, 100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LockedLyricsBody(
              settings: const DesktopLyricsSettings(locked: true),
              current: '当前歌词',
              next: '下一句歌词',
              onToggleLock: (_) {},
              cursorPositionProvider: () async => cursorPos,
              windowPositionProvider: () async => windowPos,
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      // 80ms 定时轮询
      await tester.pump(const Duration(milliseconds: 80));

      final opacityFinder = find.descendant(
        of: find.byType(LockedLyricsBody),
        matching: find.byType(AnimatedOpacity),
      );
      expect(opacityFinder, findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0.0);
    });

    testWidgets('光标移入窗口内时胶囊淡入可见 (opacity 1.0)', (tester) async {
      Offset? cursorPos = const Offset(0, 0);
      const windowPos = Offset(100, 100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LockedLyricsBody(
              settings: const DesktopLyricsSettings(locked: true),
              current: '当前歌词',
              next: '下一句歌词',
              onToggleLock: (_) {},
              cursorPositionProvider: () async => cursorPos,
              windowPositionProvider: () async => windowPos,
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      await tester.pump(const Duration(milliseconds: 80));
      final opacityFinder = find.descendant(
        of: find.byType(LockedLyricsBody),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0.0);

      // 光标移入窗口内部（非胶囊区，例如 (200, 120)）
      cursorPos = const Offset(200, 120);
      await tester.pump(const Duration(milliseconds: 80));
      // 推进 AnimatedOpacity 动画 180ms
      await tester.pump(const Duration(milliseconds: 180));

      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1.0);
    });

    testWidgets('光标悬浮在胶囊上时触发 setIgnoreMouseEvents(false)', (tester) async {
      Offset? cursorPos = const Offset(200, 120);
      const windowPos = Offset(100, 100);
      final mouseEventsCalls = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LockedLyricsBody(
              settings: const DesktopLyricsSettings(locked: true),
              current: '当前歌词',
              next: '下一句歌词',
              onToggleLock: (_) {},
              cursorPositionProvider: () async => cursorPos,
              windowPositionProvider: () async => windowPos,
              ignoreMouseEventsSetter: (ignore) async => mouseEventsCalls.add(ignore),
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      await tester.pump(const Duration(milliseconds: 80));
      expect(mouseEventsCalls, isEmpty);

      // 胶囊水平居中：pillLeft = 100 + (780 - 84)/2 = 448, pillTop = 100 + 6 = 106
      // 光标移入胶囊矩形内 (450, 110)
      cursorPos = const Offset(450, 110);
      await tester.pump(const Duration(milliseconds: 80));

      expect(mouseEventsCalls, contains(false));
      expect(mouseEventsCalls.last, isFalse);
    });

    testWidgets('点击胶囊触发 onToggleLock(false)', (tester) async {
      Offset? cursorPos = const Offset(450, 110);
      const windowPos = Offset(100, 100);
      bool? toggledLock;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LockedLyricsBody(
              settings: const DesktopLyricsSettings(locked: true),
              current: '当前歌词',
              next: '下一句歌词',
              onToggleLock: (locked) => toggledLock = locked,
              cursorPositionProvider: () async => cursorPos,
              windowPositionProvider: () async => windowPos,
              ignoreMouseEventsSetter: (ignore) async {},
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 180));

      await tester.tap(find.text('解锁'));
      await tester.pump();

      expect(toggledLock, isFalse);
    });

    testWidgets('光标离开窗口时胶囊淡出且恢复 setIgnoreMouseEvents(true)', (tester) async {
      Offset? cursorPos = const Offset(450, 110);
      const windowPos = Offset(100, 100);
      final mouseEventsCalls = <bool>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LockedLyricsBody(
              settings: const DesktopLyricsSettings(locked: true),
              current: '当前歌词',
              next: '下一句歌词',
              onToggleLock: (_) {},
              cursorPositionProvider: () async => cursorPos,
              windowPositionProvider: () async => windowPos,
              ignoreMouseEventsSetter: (ignore) async => mouseEventsCalls.add(ignore),
            ),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      // 悬浮在胶囊上
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 180));
      expect(mouseEventsCalls.last, isFalse);

      final opacityFinder = find.descendant(
        of: find.byType(LockedLyricsBody),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1.0);

      // 光标移出窗口
      cursorPos = const Offset(0, 0);
      await tester.pump(const Duration(milliseconds: 80));

      expect(mouseEventsCalls.last, isTrue);

      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0.0);
    });
  });
}

