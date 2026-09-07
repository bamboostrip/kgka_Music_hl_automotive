# 推荐页「大家都在听」紧凑卡片化改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构推荐页原「母带音质·精选」板块为「大家都在听」，学习 QQ 音乐风格将一列 5 首改为一次展示 3 首紧凑卡片，缩小尺寸并采用露边轮播布局，同时与项目原有 UI 风格保持统一。

**Architecture:** 
- 修改 `lib/ui/widgets/home_song_row.dart`，对单行尺寸、间距、字号和图标进行轻量化缩减，使其单行高度从 76px 降至 ~58-60px。
- 修改 `lib/ui/pages/home_page.dart`，将「母带音质·精选」重命名为「大家都在听」，调整 `_SongSection` 内的 `PageView` 视口比例（`viewportFraction: 0.92`）、高度（182px）及每列/每页 3 首的计算规则。
- 更新测试文件 `test/ui/pages/home_page_tabs_swipe_test.dart`，确保测试全绿并通过 `flutter analyze`。

**Tech Stack:** Flutter, Dart, NestedScrollView / PageView, Widget Testing.

## Global Constraints

- 保持项目原有 UI 风格、主题色搭配以及正在播放动效（`NowPlayingBadge`）不变。
- 确保桌面平台和移动/车机平台的兼容性。
- 代码必须通过 `flutter analyze` 且不引入任何 warning/error。
- 所有单元/Widget 测试必须通过。

---

### Task 1: 紧凑化单曲条目（HomeSongRow）

**Files:**
- Modify: `lib/ui/widgets/home_song_row.dart`

**Interfaces:**
- `HomeSongRow`: 保留所有原有参数与回调签名不变。

- [ ] **Step 1: 调整封面与内边距尺寸**
  - 在 `lib/ui/widgets/home_song_row.dart` 中：
    - 移动端封面尺寸 `coverSize` 由 `58.0` 改为 `48.0`（桌面端调整为 `44.0`）。
    - 移动端圆角 `coverRadius` 保持 `8.0`（桌面端保持 `6.0`）。
    - 单行垂直内边距 `vertical` padding 由 `isDesktop ? 7 : 9` 改为 `isDesktop ? 5 : 6`。
    - `NowPlayingBadge` 尺寸由 `13` 调整为 `11`，内边距由 `padding: const EdgeInsets.all(3)` 调为 `2`。

- [ ] **Step 2: 调整文字排版与操作图标尺寸**
  - 封面与文字水平间距由 `12` 调整为 `10`。
  - 歌名字号：`fontSize: isDesktop ? 14 : 15`，`fontWeight: FontWeight.w600`。
  - 歌手字号：`fontSize: isDesktop ? 12 : 12.5`。
  - 歌名与歌手垂直间距由 `4` 调整为 `3`。
  - 收藏按钮图标大小：`size: isDesktop ? 20 : 22`。
  - 更多按钮图标大小：`iconSize: isDesktop ? 18 : 20`。

---

### Task 2: 改造推荐页「大家都在听」板块（_SongSection）与文案

**Files:**
- Modify: `lib/ui/pages/home_page.dart:623,747,1189-1383`

**Interfaces:**
- `_SongSection`: 标题使用新文案「大家都在听」，内部 PageView 采用 `viewportFraction: 0.92`。

- [ ] **Step 1: 更新板块标题文案**
  - 在 `lib/ui/pages/home_page.dart` 中，将两处 `title: '母带音质·精选'`（移动端 Tab 0 推荐和车机模式 TabPane）全部修改为 `title: '大家都在听'`。

- [ ] **Step 2: 调整 PageController 与视口比例**
  - 在 `_SongSectionState.initState` 中，初始化 `_pageController = PageController(viewportFraction: 0.92)`。

- [ ] **Step 3: 调整一列 3 首的计算规则与总高度**
  - 调整 `itemsPerPage`：
    - `maxWidth >= 1050`: `crossAxisCount = 3`, `itemsPerPage = 9` (3 列 × 每列 3 首)
    - `maxWidth >= 650`: `crossAxisCount = 2`, `itemsPerPage = 6` (2 列 × 每列 3 首)
    - 其他（窄屏/移动端）: `crossAxisCount = 1`, `itemsPerPage = 3` (1 列 × 每列 3 首)
  - 调整容器高度：`height: rowCount * 60.0`（3 行 × 60.0 = 180.0px）。
  - 在 `PageView.builder` 的每个 item 外层包裹适当的边距（例如 `Padding(padding: const EdgeInsets.symmetric(horizontal: 4))`），确保当前页与右侧露出的下一页卡片有清晰自然的间隔感。

---

### Task 3: 更新测试并全面验证

**Files:**
- Modify: `test/ui/pages/home_page_tabs_swipe_test.dart`

- [ ] **Step 1: 更新测试用例中的标题匹配文本**
  - 将 `test/ui/pages/home_page_tabs_swipe_test.dart` 中所有的 `'母带音质·精选'` 替换为 `'大家都在听'`。

- [ ] **Step 2: 运行测试并确认通过**
  - 运行 `flutter test test/ui/pages/home_page_tabs_swipe_test.dart`。

- [ ] **Step 3: 执行静态分析**
  - 运行 `flutter analyze` 确保 0 issues。
