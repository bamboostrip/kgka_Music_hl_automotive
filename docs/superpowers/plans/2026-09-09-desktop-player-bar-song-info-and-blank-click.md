# Desktop Player Bar Song Info and Blank Click Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the desktop bottom player bar's left section to match QQ Music (cover + single-line auto-scrolling `Title - Artist` + action row with `[Like] [Comment] [More···]`), and enable clicking any blank area of the bottom bar to open the full player page.

**Architecture:**
- `MarqueeText` in `lib/ui/widgets/marquee_text.dart`: measures text width against constraints. If text fits, renders static text; if text overflows, smoothly scrolls with a pause at boundaries.
- `_SongMoreButton` uses `anchorAbove(context)` with `showDesktopAnchoredMenu` to present the actions menu (Next Play, Add to Playlist, Download, View Artist, Copy Info).
- `DesktopPlayerBar` wraps its content in a `GestureDetector(behavior: HitTestBehavior.translucent)` and `MouseRegion(cursor: ...)` so clicking non-button blank areas triggers `_openPlayerPage(context)`. All buttons and sliders use `HitTestBehavior.opaque` to ensure events are not bubbled.

**Tech Stack:** Flutter 3.x, Dart, `CustomPainter`, `showDesktopAnchoredMenu`, `AnimationController`.

## Global Constraints
- Functional buttons/controls (Play, Pause, Next, Prev, Sliders, Like, Comment, More, Audio Quality, Lyrics, Queue) must NOT trigger `_openPlayerPage`.
- MarqueeText must produce 0 animation overhead when text does not overflow.
- All existing tests must remain passing.

---

### Task 1: `MarqueeText` Component

**Files:**
- Create: `lib/ui/widgets/marquee_text.dart`
- Test: `test/ui/widgets/marquee_text_test.dart`

**Interfaces:**
- `MarqueeText({super.key, required this.textSpan, this.style, this.velocity = 30.0, this.pauseDuration = const Duration(seconds: 2)})`

- [ ] **Step 1: Write tests for `MarqueeText`**
- [ ] **Step 2: Run test to observe failure**
- [ ] **Step 3: Implement `MarqueeText`**
- [ ] **Step 4: Run test to verify pass**
- [ ] **Step 5: Commit**

---

### Task 2: Restructure Left Section to Single-Line `Title - Artist` + Action Row

**Files:**
- Modify: `lib/ui/desktop/desktop_player_bar.dart`
- Test: `test/ui/desktop/desktop_player_bar_test.dart`

**Interfaces:**
- Left section renders:
  - Cover with `ExpandDetailIcon`
  - Right of cover (Column):
    - Row 1: `MarqueeText` with `Title - Artist`
    - Row 2: `_LikeButton`, `_CommentButton`, `_SongMoreButton` (`···`)
    - Clicking `···` opens menu via `showDesktopAnchoredMenu` (or `showSongActionSheet` on desktop)

- [ ] **Step 1: Write test for new left section layout and More menu**
- [ ] **Step 2: Run test to observe failure**
- [ ] **Step 3: Implement new left section structure**
- [ ] **Step 4: Run test to verify pass**
- [ ] **Step 5: Commit**

---

### Task 3: Blank Area Click to Open Full Player Page

**Files:**
- Modify: `lib/ui/desktop/desktop_player_bar.dart`
- Test: `test/ui/desktop/desktop_player_bar_test.dart`

**Interfaces:**
- Clicking on non-button regions triggers `onOpenPlayerPage` or `PlayerPageRoute.open(context)`.
- Interactive buttons (Play/Pause, Slider, More, Like, etc.) only trigger their own callbacks and do NOT trigger `PlayerPageRoute.open`.

- [ ] **Step 1: Write tests for blank click vs button click**
- [ ] **Step 2: Run test to observe failure**
- [ ] **Step 3: Implement blank area click on `DesktopPlayerBar`**
- [ ] **Step 4: Run test to verify pass**
- [ ] **Step 5: Commit**

---

### Task 4: Full Verification & Code Review

- [ ] **Step 1: Run `flutter test test/ui/desktop/` and `flutter test test/ui/widgets/marquee_text_test.dart`**
- [ ] **Step 2: Run `flutter analyze lib/ui/desktop/ test/ui/desktop/ lib/ui/widgets/marquee_text.dart`**
- [ ] **Step 3: Commit all changes**
