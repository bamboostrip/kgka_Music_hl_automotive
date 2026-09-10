import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/widgets/refresh_equalizer.dart';

void main() {
  testWidgets('visible=true 时展示 5 根竖条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: true)),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('refresh_bar_$i')), findsOneWidget);
    }
  });

  testWidgets('visible=false 时收起不占位', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: false)),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('refresh_bar_$i')), findsNothing);
    }
    final box =
        tester.getSize(find.byType(RefreshEqualizer).first);
    expect(box.height, 0.0);
  });

  testWidgets('visible 切换时动画过渡且不抛错', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: false)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('refresh_bar_0')), findsOneWidget);
  });

  testWidgets('刷新极快结束时保持最短展示时长再收起', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: false)),
      ),
    );
    await tester.pump();
    // 刷新开始：竖条出现。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: true)),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('refresh_bar_0')), findsOneWidget);
    // 刷新立即结束：进入最短展示保持期，竖条不立即消失。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: false)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('refresh_bar_0')),
      findsOneWidget,
      reason: '最短展示期内保持可见',
    );
    // 越过 600ms 最短展示 + 250ms 收起过渡后收起。
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('refresh_bar_0')), findsNothing);
  });

  testWidgets('收起保持期内再次刷新：取消收起继续展示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: false)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: true)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: false)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // 保持期内新刷新到来：继续展示。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RefreshEqualizer(visible: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      find.byKey(const ValueKey('refresh_bar_0')),
      findsOneWidget,
      reason: '保持期内新刷新取消收起',
    );
  });
}
