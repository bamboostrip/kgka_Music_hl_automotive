import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/app_theme.dart';

void main() {
  testWidgets('AppScrollBehavior safe buildScrollbar: single position builds Scrollbar',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemBuilder: (_, i) => Text('Item $i'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets(
      'AppScrollBehavior safe buildScrollbar: does not attach Scrollbar to NeverScrollable nested views',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 10,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                  itemBuilder: (_, i) => Text('Grid $i'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
