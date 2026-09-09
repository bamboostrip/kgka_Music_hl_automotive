import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/desktop/desktop_title_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  testWidgets('renders logo and title 时音', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(),
        ),
      ),
    );

    expect(find.text('时音'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'lib/assets/logo.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('无 onSearch 时不展示搜索框（旧调用兼容）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('desktop_title_bar_search')), findsNothing);
  });

  testWidgets('有 onSearch 时居中展示搜索胶囊，点击回调', (tester) async {
    var searched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(onSearch: () => searched = true),
        ),
      ),
    );

    final search = find.byKey(const ValueKey('desktop_title_bar_search'));
    expect(search, findsOneWidget);
    expect(find.text('搜索音乐'), findsOneWidget);

    await tester.tap(search);
    await tester.pump();
    expect(searched, isTrue);
  });

  testWidgets('搜索胶囊 Tab 可达、Enter 激活', (tester) async {
    var searched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(onSearch: () => searched = true),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(searched, isTrue);
  });

  testWidgets('renders minimize, maximize/restore, and close buttons',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(),
        ),
      ),
    );

    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.crop_square_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('clicking window buttons calls windowManager', (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'isMaximized') return false;
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(calls, contains('minimize'));

    await tester.tap(find.byIcon(Icons.crop_square_rounded));
    await tester.pump();
    expect(calls, contains('maximize'));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(calls, contains('close'));
  });

  testWidgets('double clicking drag spacer toggles maximize/unmaximize',
      (tester) async {
    final calls = <String>[];
    bool isMax = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'isMaximized') return isMax;
        if (call.method == 'maximize') {
          isMax = true;
          return null;
        }
        if (call.method == 'unmaximize') {
          isMax = false;
          return null;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopTitleBar(),
        ),
      ),
    );

    // Double tap the left drag spacer
    final spacer = find.byKey(const ValueKey('desktop_title_bar_drag_left'));
    expect(spacer, findsOneWidget);

    await tester.tap(spacer);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(spacer);
    await tester.pumpAndSettle();

    expect(calls, contains('maximize'));
  });
}
