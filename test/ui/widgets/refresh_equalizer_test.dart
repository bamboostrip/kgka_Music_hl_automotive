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
}
