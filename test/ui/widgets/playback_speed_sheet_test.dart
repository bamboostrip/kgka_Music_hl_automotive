import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/ui/widgets/playback_speed_sheet.dart';

void main() {
  // 与 PlaybackSpeedScale 内部 SliderTheme 一致：
  // overlayRadius 18 / thumbRadius 10 → 轨道两端各内缩 max(18, 20/2) = 18。
  const trackInset = 18.0;

  Future<void> pumpScale(
    WidgetTester tester, {
    double value = 1.5,
    ValueChanged<double>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: PlaybackSpeedScale(
                value: value,
                onChanged: onChanged ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('每个档位标签中心都落在滑块对应值的拇指中心正下方', (tester) async {
    await pumpScale(tester, value: 1.5);

    final sliderRect = tester.getRect(find.byType(Slider));
    final trackWidth = sliderRect.width - 2 * trackInset;

    for (final step in kPlaybackSpeedSteps) {
      final t = (step - kMinPlaybackSpeed) / (kMaxPlaybackSpeed - kMinPlaybackSpeed);
      final expectedThumbCenterX = sliderRect.left + trackInset + t * trackWidth;
      final labelCenter = tester.getCenter(find.text(formatPlaybackSpeed(step)));
      expect(
        labelCenter.dx,
        moreOrLessEquals(expectedThumbCenterX, epsilon: 1.5),
        reason: '档位 $step 的标签未对齐滑块刻度',
      );
    }
  });

  testWidgets('点击档位标签直接选中该档位', (tester) async {
    final selected = <double>[];
    await pumpScale(tester, value: 1.0, onChanged: selected.add);

    await tester.tap(find.text('2x'));
    expect(selected, [2.0]);

    await tester.tap(find.text('0.75x'));
    expect(selected.last, 0.75);
  });

  testWidgets('拖动后回调值始终落在最近的档位上', (tester) async {
    final selected = <double>[];
    await pumpScale(tester, value: 1.0, onChanged: selected.add);

    final sliderRect = tester.getRect(find.byType(Slider));
    // 拖到轨道约 44% 处（介于 1.5x@40% 与 2x@60% 之间，靠 1.5x 更近）。
    final target = Offset(
      sliderRect.left + trackInset + 0.44 * (sliderRect.width - 2 * trackInset),
      sliderRect.center.dy,
    );
    final gesture = await tester.startGesture(sliderRect.center);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveTo(target);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, everyElement(isIn(kPlaybackSpeedSteps)));
    expect(selected.last, 1.5);
  });
}
