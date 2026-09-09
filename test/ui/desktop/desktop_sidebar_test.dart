import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/desktop/desktop_sidebar.dart';

void main() {
  const items = [
    DesktopNavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: '推荐'),
    DesktopNavItem(icon: Icons.leaderboard_outlined, activeIcon: Icons.leaderboard_rounded, label: '排行榜'),
    DesktopNavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
      showDividerAbove: true,
    ),
  ];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('点击条目回调对应下标', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(wrap(DesktopSidebar(
      items: items,
      selectedIndex: 0,
      onSelect: selected.add,
    )));

    await tester.tap(find.text('排行榜'));
    expect(selected, [1]);
  });

  testWidgets('侧栏无搜索入口（搜索已上移顶栏），导航项正常渲染', (tester) async {
    await tester.pumpWidget(wrap(const DesktopSidebar(
      items: items,
      selectedIndex: 2,
      onSelect: _noop,
    )));

    // QQ 音乐 PC 式：搜索不在侧栏。
    expect(find.text('搜索音乐'), findsNothing);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('排行榜'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  group('键盘可达性', () {
    testWidgets('Tab 自上而下可达导航项，Enter 激活', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(wrap(DesktopSidebar(
        items: items,
        selectedIndex: -1,
        onSelect: selected.add,
      )));

      // 第 1 次 Tab → 第一个导航项（推荐）；Enter 激活。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, [0]);

      // 继续自上而下：排行榜。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, [0, 1]);
    });

    testWidgets('空格同样可激活聚焦的导航项', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(wrap(DesktopSidebar(
        items: items,
        selectedIndex: -1,
        onSelect: selected.add,
      )));

      // Tab ×1：第一个导航项（推荐）。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(selected, [0]);
    });

    testWidgets('聚焦的导航项显示焦点环', (tester) async {
      await tester.pumpWidget(wrap(const DesktopSidebar(
        items: items,
        selectedIndex: -1,
        onSelect: _noop,
      )));

      BoxDecoration ringOf(String label) {
        final container = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ).first,
        );
        return container.foregroundDecoration! as BoxDecoration;
      }

      // 未聚焦：焦点环不可见（透明）。
      expect(ringOf('排行榜').border!.top.color.a, 0);

      // Tab 遍历顺序自上而下：推荐 → 排行榜。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final primary = FocusManager.instance.primaryFocus!;
      final tileText = find.text('排行榜');
      expect(
        find.descendant(
          of: find.byWidget(primary.context!.widget),
          matching: tileText,
        ),
        findsOneWidget,
      );
      expect(ringOf('排行榜').border!.top.color.a, greaterThan(0));
    });
  });
}

void _noop(int _) {}
