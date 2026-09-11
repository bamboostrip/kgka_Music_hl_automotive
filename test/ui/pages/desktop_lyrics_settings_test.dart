import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/controllers/player_controller.dart';
import 'package:shiyin_music/services/desktop_lyrics_service.dart';
import 'package:shiyin_music/ui/desktop/lyrics_karaoke_line.dart';
import 'package:shiyin_music/ui/pages/desktop_lyrics_settings_page.dart';

class _FakePlayerController extends ChangeNotifier
    implements PlayerController {
  @override
  DesktopLyricsSettings desktopLyricsSettings = const DesktopLyricsSettings();

  @override
  bool desktopLyricsEnabled = true;

  bool previewVisible = false;
  final List<DesktopLyricsSettings> updatedSettingsList = [];

  @override
  Future<void> setDesktopLyricsPreviewVisible(bool visible) async {
    previewVisible = visible;
  }

  @override
  Future<void> updateDesktopLyricsSettings(
    DesktopLyricsSettings settings,
  ) async {
    desktopLyricsSettings = settings;
    updatedSettingsList.add(settings);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlayerController player;

  setUp(() {
    player = _FakePlayerController();
  });

  Future<void> pumpSettingsPage(
    WidgetTester tester, {
    Size size = const Size(1200, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopLyricsSettingsPage(player: player),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('DesktopLyricsSettingsPage', () {
    testWidgets('preview visible is set on init and cleared on dispose', (
      tester,
    ) async {
      await pumpSettingsPage(tester);
      expect(player.previewVisible, isTrue);

      // Navigate away/dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(player.previewVisible, isFalse);
    });

    testWidgets('renders line count selection and toggles single/dual line', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      expect(find.text('单行显示'), findsOneWidget);
      expect(find.text('双行显示'), findsOneWidget);
      expect(player.desktopLyricsSettings.singleLine, isTrue);

      // Switch to dual line
      await tester.tap(find.text('双行显示'));
      await tester.pumpAndSettle();

      expect(player.desktopLyricsSettings.singleLine, isFalse);
      expect(player.updatedSettingsList.last.singleLine, isFalse);

      // Switch back to single line
      await tester.tap(find.text('单行显示'));
      await tester.pumpAndSettle();

      expect(player.desktopLyricsSettings.singleLine, isTrue);
      expect(player.updatedSettingsList.last.singleLine, isTrue);
    });

    testWidgets('renders alignment selection and updates alignment setting', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      // 四种对齐：居中/左/右 = 双行两行同侧；左右分离 = 上行居左、下行居右。
      expect(find.text('居中'), findsOneWidget);
      expect(find.text('左对齐'), findsOneWidget);
      expect(find.text('右对齐'), findsOneWidget);
      expect(find.text('左右分离'), findsOneWidget);

      // Tap left align
      await tester.tap(find.text('左对齐'));
      await tester.pumpAndSettle();
      expect(player.desktopLyricsSettings.alignment, 'left');

      // Tap right align
      await tester.tap(find.text('右对齐'));
      await tester.pumpAndSettle();
      expect(player.desktopLyricsSettings.alignment, 'right');

      // Tap center align
      await tester.tap(find.text('居中'));
      await tester.pumpAndSettle();
      expect(player.desktopLyricsSettings.alignment, 'center');

      // Tap split（左右分离）
      await tester.tap(find.text('左右分离'));
      await tester.pumpAndSettle();
      expect(
        player.desktopLyricsSettings.alignment,
        DesktopLyricsAlignment.split,
      );
    });

    testWidgets('renders text opacity slider and updates textOpacity', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      expect(find.text('文字透明度'), findsOneWidget);
      expect(find.text('100%'), findsWidgets);

      // Find the Slider for text opacity
      final textOpacityFinder = find.ancestor(
        of: find.text('文字透明度'),
        matching: find.byType(Column),
      );
      final sliderFinder = find.descendant(
        of: textOpacityFinder.first,
        matching: find.byType(Slider),
      );
      expect(sliderFinder, findsOneWidget);

      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.min, 0.2);
      expect(slider.max, 1.0);

      // Change slider value
      slider.onChanged?.call(0.6);
      await tester.pumpAndSettle();

      expect(player.desktopLyricsSettings.textOpacity, closeTo(0.6, 0.01));
      expect(find.text('60%'), findsWidgets);
    });

    testWidgets('renders played and unplayed text color pickers and updates colors', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      expect(find.text('歌词颜色'), findsOneWidget);
      expect(find.text('高亮颜色'), findsOneWidget);

      // Pick Yellow for played color (高亮颜色)
      final yellowPresetFinder = find.byKey(
        const Key('color_高亮颜色_ffffee58'),
      );
      expect(yellowPresetFinder, findsOneWidget);
      await tester.tap(yellowPresetFinder);
      await tester.pumpAndSettle();

      expect(player.desktopLyricsSettings.playedTextColor, 0xFFFFEE58);

      // Pick White for unplayed color (歌词颜色)
      final whitePresetFinder = find.byKey(
        const Key('color_歌词颜色_ffffffff'),
      );
      expect(whitePresetFinder, findsOneWidget);
      await tester.tap(whitePresetFinder);
      await tester.pumpAndSettle();

      expect(player.desktopLyricsSettings.unplayedTextColor, 0xFFFFFFFF);
      expect(player.desktopLyricsSettings.textColor, 0xFFFFFFFF);
    });

    testWidgets('renders live preview section and updates on settings change', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      // Preview section header
      expect(find.text('效果预览'), findsOneWidget);

      // Single line shows "时音 听我想听" (karaoke line renders stacked Text widgets)
      expect(find.text('时音 听我想听'), findsWidgets);
      expect(find.byType(LyricsKaraokeLine), findsOneWidget);
      expect(find.text('让音乐更自由'), findsNothing);

      // Switch to dual line mode
      await tester.tap(find.text('双行显示'));
      await tester.pumpAndSettle();

      // Dual line preview shows both lines
      expect(find.text('时音 听我想听'), findsWidgets);
      expect(find.text('让音乐更自由'), findsWidgets);
      expect(find.byType(LyricsKaraokeLine), findsNWidgets(2));
    });

    testWidgets('updates UI when player desktopLyricsSettings changes externally', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      // 默认对齐为「左右分离」(split)
      final alignmentSelector = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(alignmentSelector.selected, {DesktopLyricsAlignment.split});

      // Externally update player settings
      await player.updateDesktopLyricsSettings(
        player.desktopLyricsSettings.copyWith(
          alignment: 'right',
          singleLine: false,
        ),
      );
      await tester.pumpAndSettle();

      // Should reflect in preview with dual lines
      expect(find.byType(LyricsKaraokeLine), findsNWidgets(2));
      final updatedSelector = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(updatedSelector.selected, {'right'});
    });

    testWidgets(
      'wide layout renders 2-column split view with sticky preview on right',
      (tester) async {
        await pumpSettingsPage(tester, size: const Size(1000, 700));

        // Both appearance and preview sections exist
        final appearanceHeader = find.text('外观');
        final previewHeader = find.text('效果预览');
        expect(appearanceHeader, findsOneWidget);
        expect(previewHeader, findsOneWidget);

        // In wide layout, preview is on the right side of appearance settings
        final appearancePos = tester.getTopLeft(appearanceHeader);
        final previewPos = tester.getTopLeft(previewHeader);
        expect(previewPos.dx, greaterThan(appearancePos.dx));

        // Both are visible on screen
        expect(find.byType(LyricsKaraokeLine), findsOneWidget);

        // 1. Updating segments (行数)
        await tester.tap(find.text('双行显示'));
        await tester.pumpAndSettle();
        expect(player.desktopLyricsSettings.singleLine, isFalse);
        expect(find.byType(LyricsKaraokeLine), findsNWidgets(2));

        // 2. Updating slider (字体大小)
        final fontSizeFinder = find.ancestor(
          of: find.text('字体大小'),
          matching: find.byType(Column),
        );
        final fontSliderFinder = find.descendant(
          of: fontSizeFinder.first,
          matching: find.byType(Slider),
        );
        final fontSlider = tester.widget<Slider>(fontSliderFinder);
        fontSlider.onChanged?.call(32.0);
        await tester.pumpAndSettle();
        expect(player.desktopLyricsSettings.fontSize, closeTo(32.0, 0.01));

        // 3. Updating color
        final pinkPresetFinder = find.byKey(
          const Key('color_歌词颜色_ffff69b4'),
        );
        await tester.ensureVisible(pinkPresetFinder);
        await tester.pumpAndSettle();
        await tester.tap(pinkPresetFinder);
        await tester.pumpAndSettle();
        expect(player.desktopLyricsSettings.unplayedTextColor, 0xFFFF69B4);
      },
    );

    testWidgets(
      'narrow layout renders preview card at top before appearance section',
      (tester) async {
        await pumpSettingsPage(tester, size: const Size(400, 800));

        final appearanceHeader = find.text('外观');
        final previewHeader = find.text('效果预览');
        expect(appearanceHeader, findsOneWidget);
        expect(previewHeader, findsOneWidget);

        // In narrow layout, preview is above appearance settings
        final appearancePos = tester.getTopLeft(appearanceHeader);
        final previewPos = tester.getTopLeft(previewHeader);
        expect(previewPos.dy, lessThan(appearancePos.dy));

        // 1. Updating segments (行数)
        await tester.tap(find.text('双行显示'));
        await tester.pumpAndSettle();
        expect(player.desktopLyricsSettings.singleLine, isFalse);
        expect(find.byType(LyricsKaraokeLine), findsNWidgets(2));

        // 2. Updating slider (字体大小)
        final fontSizeFinder = find.ancestor(
          of: find.text('字体大小'),
          matching: find.byType(Column),
        );
        final fontSliderFinder = find.descendant(
          of: fontSizeFinder.first,
          matching: find.byType(Slider),
        );
        final fontSlider = tester.widget<Slider>(fontSliderFinder);
        fontSlider.onChanged?.call(30.0);
        await tester.pumpAndSettle();
        expect(player.desktopLyricsSettings.fontSize, closeTo(30.0, 0.01));

        // 3. Updating color
        final pinkPresetFinder = find.byKey(
          const Key('color_歌词颜色_ffff69b4'),
        );
        await tester.ensureVisible(pinkPresetFinder);
        await tester.pumpAndSettle();
        await tester.tap(pinkPresetFinder);
        await tester.pumpAndSettle();
        expect(player.desktopLyricsSettings.unplayedTextColor, 0xFFFF69B4);
      },
    );

    testWidgets(
      'dual line preview uses unified fontSize * 0.82 and bold weight for second line',
      (tester) async {
        await pumpSettingsPage(tester);

        await tester.tap(find.text('双行显示'));
        await tester.pumpAndSettle();

        final lines = tester
            .widgetList<LyricsKaraokeLine>(
              find.byType(LyricsKaraokeLine),
            )
            .toList();
        expect(lines.length, 2);

        final secondLine = lines[1];
        expect(secondLine.text, '让音乐更自由');
        expect(
          secondLine.fontSize,
          closeTo(player.desktopLyricsSettings.fontSize * 0.82, 0.01),
        );
        expect(secondLine.fontWeight, FontWeight.bold);
      },
    );
  });
}

