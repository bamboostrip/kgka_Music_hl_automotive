# Desktop Player Bar Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the desktop player bar by constraining progress bar width to max 440px, repositioning volume control next to Next button, implementing a non-blocking vertical volume popover with mute toggle and slider, and updating the album cover hover expand icon to the QQ-style diagonal bracket design.

**Architecture:** 
- Visual components are split cleanly between `desktop_player_bar.dart` (layout assembly) and `player_bar_widgets.dart` (modular widgets).
- `ExpandDetailIcon` is rendered via a crisp `CustomPainter` with two diagonal corners (top-right `┐` and bottom-left `└`).
- `VolumePopoverButton` uses Flutter's `TapRegion` and `OverlayPortal` with `CompositedTransformTarget` / `CompositedTransformFollower` to achieve an anchored popover with a beak pointer that does not block outside clicks (clicks outside both dismiss the popover and naturally trigger target actions).
- `_ProgressBar` is constrained by `ConstrainedBox(constraints: BoxConstraints(maxWidth: 440))` centered horizontally.

**Tech Stack:** Flutter 3.x, Dart, `TapRegion`, `OverlayPortal`, `SliderTheme`, `CustomPainter`.

## Global Constraints
- Non-blocking outside dismiss: Clicking anywhere outside the volume popover MUST dismiss the popover without consuming/swallowing the pointer event.
- Preserve existing volume state management (`PlayerController.volume`, `PlayerController.setVolume`, `toggleMute`, `applyVolumeWheel`).
- Windows shell: pwsh7; uv for python, fnm for node, pnpm global.

---

### Task 1: Cover Hover Expand Icon (`ExpandDetailIcon`)

**Files:**
- Modify: `lib/ui/desktop/player_bar_widgets.dart`
- Modify: `lib/ui/desktop/desktop_player_bar.dart:280-295`
- Test: `test/ui/desktop/player_bar_widgets_test.dart`

**Interfaces:**
- Produces: `ExpandDetailIcon({super.key, this.size = 18, this.color = Colors.white, this.strokeWidth = 2.0})`
- Consumes: Flutter standard `CustomPainter`

- [ ] **Step 1: Write failing unit test for `ExpandDetailIcon`**

In `test/ui/desktop/player_bar_widgets_test.dart`:
```dart
  group('ExpandDetailIcon', () {
    testWidgets('renders CustomPaint with corner bracket painter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: ExpandDetailIcon(size: 20, color: Colors.white),
          ),
        ),
      );
      expect(find.byType(ExpandDetailIcon), findsOneWidget);
      expect(find.byType(CustomPaint), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/desktop/player_bar_widgets_test.dart`
Expected: FAIL with "ExpandDetailIcon is not defined".

- [ ] **Step 3: Implement `ExpandDetailIcon` and update `_SongInfo`**

In `lib/ui/desktop/player_bar_widgets.dart`:
```dart
/// 封面悬停时展示的对角直角展开图标（截图 3 风格：右上角 ┐ + 左下角 └）。
class ExpandDetailIcon extends StatelessWidget {
  const ExpandDetailIcon({
    super.key,
    this.size = 18,
    this.color = Colors.white,
    this.strokeWidth = 2.0,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ExpandDetailPainter(
        color: color,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _ExpandDetailPainter extends CustomPainter {
  const _ExpandDetailPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final arm = w * 0.42;

    // 左下角 └
    final pathBottomLeft = Path()
      ..moveTo(0, h - arm)
      ..lineTo(0, h)
      ..lineTo(arm, h);
    canvas.drawPath(pathBottomLeft, paint);

    // 右上角 ┐
    final pathTopRight = Path()
      ..moveTo(w - arm, 0)
      ..lineTo(w, 0)
      ..lineTo(w, arm);
    canvas.drawPath(pathTopRight, paint);
  }

  @override
  bool shouldRepaint(covariant _ExpandDetailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
```

In `lib/ui/desktop/desktop_player_bar.dart` (`_SongInfo`):
Replace `Icons.open_in_full_rounded` with `ExpandDetailIcon(size: 20)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/desktop/player_bar_widgets_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/desktop/player_bar_widgets.dart lib/ui/desktop/desktop_player_bar.dart test/ui/desktop/player_bar_widgets_test.dart
git commit -m "feat(desktop): add QQ-style ExpandDetailIcon on cover hover"
```

---

### Task 2: Constrain Progress Bar Width

**Files:**
- Modify: `lib/ui/desktop/desktop_player_bar.dart:167-171`
- Test: `test/ui/desktop/desktop_player_bar_test.dart`

**Interfaces:**
- Constrains `_ProgressBar` to `maxWidth: 440` and centers it within the column.

- [ ] **Step 1: Write test verifying progress bar is constrained to max width 440**

In `test/ui/desktop/desktop_player_bar_test.dart`:
```dart
    testWidgets('进度条最大宽度约束在 440px 居中', (tester) async {
      final player = _FakePlayerController()
        ..currentSong = _song
        ..duration = const Duration(minutes: 3);
      await _pumpBar(tester, player);

      final progressFinder = find.byType(SliderTheme);
      expect(progressFinder, findsOneWidget);
      final size = tester.getSize(progressFinder);
      expect(size.width, lessThanOrEqualTo(440));
    });
```

- [ ] **Step 2: Run test to observe behavior**

Run: `flutter test test/ui/desktop/desktop_player_bar_test.dart`
Expected: FAIL because current width on 1400px window is > 500px.

- [ ] **Step 3: Update `desktop_player_bar.dart` layout**

Wrap `_ProgressBar` in a centered `ConstrainedBox`:
```dart
if (song != null) ...[
  Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: _ProgressBar(player: player),
    ),
  ),
],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/desktop/desktop_player_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/desktop/desktop_player_bar.dart test/ui/desktop/desktop_player_bar_test.dart
git commit -m "feat(desktop): constrain progress bar max width to 440px"
```

---

### Task 3: Vertical Volume Popover with Non-blocking Outside Dismiss & Relocate to Controls Row

**Files:**
- Create/Modify: `lib/ui/desktop/player_bar_widgets.dart` (`VolumePopoverButton`, `_VolumePopoverCard`, `_BeakClipper`)
- Modify: `lib/ui/desktop/desktop_player_bar.dart` (Add to controls row, remove old horizontal volume slider from right section)
- Test: `test/ui/desktop/desktop_player_bar_test.dart`

**Interfaces:**
- Produces: `VolumePopoverButton({super.key, required this.player, this.iconSize = 22})`
- Features:
  - `OverlayPortal` + `TapRegion(groupId: 'desktop_volume_popover')`
  - Vertical slider (0.0 to 1.0, RotatedBox quarterTurns: 3)
  - Percentage label (`${(volume * 100).round()}%`)
  - Bottom mute button calling `toggleMute`
  - Pointer wheel on button or card adjusts volume by ±5%
  - Trigger button in bottom bar is highlighted with `colorScheme.primary` while open
  - Tapping outside dismisses popover WITHOUT swallowing the click event

- [ ] **Step 1: Write tests for `VolumePopoverButton`**

In `test/ui/desktop/desktop_player_bar_test.dart`:
```dart
  group('音量弹层 VolumePopoverButton', () {
    testWidgets('下一首右侧渲染音量入口，点击弹出音量卡片，再次点击收起', (tester) async {
      final player = _FakePlayerController()..volume = 0.7;
      await _pumpBar(tester, player);

      // 验证在控制行渲染音量入口
      final popoverButton = find.byKey(const ValueKey('desktop_volume_popover_button'));
      expect(popoverButton, findsOneWidget);

      // 初始未弹出
      expect(find.text('70%'), findsNothing);

      // 点击打开
      await tester.tap(popoverButton);
      await tester.pump();

      expect(find.text('70%'), findsOneWidget);
      expect(find.byKey(const ValueKey('volume_popover_mute_button')), findsOneWidget);

      // 再次点击收起
      await tester.tap(popoverButton);
      await tester.pump();
      expect(find.text('70%'), findsNothing);
    });

    testWidgets('弹层中点击静音按钮静音并记忆音量，再次点击恢复', (tester) async {
      final player = _FakePlayerController()..volume = 0.7;
      await _pumpBar(tester, player);

      final popoverButton = find.byKey(const ValueKey('desktop_volume_popover_button'));
      await tester.tap(popoverButton);
      await tester.pump();

      // 点击弹层底部的静音按钮
      final muteBtn = find.byKey(const ValueKey('volume_popover_mute_button'));
      await tester.tap(muteBtn);
      await tester.pump();

      expect(player.volume, 0.0);
      expect(find.text('0%'), findsOneWidget);

      // 再次点击恢复 70%
      await tester.tap(muteBtn);
      await tester.pump();

      expect(player.volume, 0.7);
      expect(find.text('70%'), findsOneWidget);
    });

    testWidgets('非阻塞关闭：弹层打开时点击下一首，下一首正常触发且弹层收起', (tester) async {
      final player = _FakePlayerController()..currentSong = _song..volume = 0.7;
      await _pumpBar(tester, player);

      final popoverButton = find.byKey(const ValueKey('desktop_volume_popover_button'));
      await tester.tap(popoverButton);
      await tester.pump();
      expect(find.text('70%'), findsOneWidget);

      // 点击外部的“上一首”按钮（或其它区域）
      final prevBtn = find.byTooltip('上一首');
      await tester.tap(prevBtn);
      await tester.pump();

      // 弹层已收起
      expect(find.text('70%'), findsNothing);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/desktop/desktop_player_bar_test.dart`
Expected: FAIL ("desktop_volume_popover_button not found").

- [ ] **Step 3: Implement `VolumePopoverButton` in `player_bar_widgets.dart`**

Implement `VolumePopoverButton` with:
- `OverlayPortalController`
- `CompositedTransformTarget` & `CompositedTransformFollower`
- `TapRegion(groupId: 'desktop_volume_popover', onTapOutside: ...)`
- Vertical layout with top vertical Slider (`RotatedBox(quarterTurns: 3)`), percentage `Text`, and bottom `VolumeIconButton` or mute toggle `IconButton`.
- Downward beak pointer on the bottom of the card pointing to the volume icon.

- [ ] **Step 4: Update `DesktopPlayerBar` in `desktop_player_bar.dart`**

- In controls row:
```dart
IconButton(
  tooltip: '下一首',
  onPressed: song == null ? null : player.next,
  icon: const Icon(Icons.skip_next_rounded, size: 28),
  color: colorScheme.onSurface,
),
const SizedBox(width: 20),
VolumePopoverButton(player: player),
```
- In right section: remove `_VolumeControl`.

- [ ] **Step 5: Run tests to verify all tests pass**

Run: `flutter test test/ui/desktop/`
Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/desktop/player_bar_widgets.dart lib/ui/desktop/desktop_player_bar.dart test/ui/desktop/desktop_player_bar_test.dart
git commit -m "feat(desktop): add VolumePopoverButton next to next song and remove horizontal volume bar"
```

---

### Task 4: Complete Verification & Code Hygiene

- [ ] **Step 1: Run full test suite**

Run: `flutter test test/ui/desktop/`
Expected: 100% tests pass.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/ui/desktop/ test/ui/desktop/`
Expected: No issues found.

- [ ] **Step 3: Commit all changes**

```bash
git commit -m "chore(desktop): finalize desktop player bar refinements"
```
