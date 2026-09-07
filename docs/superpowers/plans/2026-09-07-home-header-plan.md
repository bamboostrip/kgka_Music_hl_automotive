# 首页顶部布局重构与双击回顶刷新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构移动端首页顶部布局为搜索置顶、下接 QQ 音乐灵动胶囊标签栏，实现随滑动平滑渐隐折叠与标签吸顶，并在底部导航栏支持双击首页平滑回顶与刷新。

**Architecture:** 使用自定义 `SliverPersistentHeaderDelegate` 实现高性能 Sliver 吸顶折叠，将搜索框和标签栏分别独立为可复用组件。在 `HomePage` 中引入 `ScrollController` 与公共 `scrollToTopAndRefresh()` 接口，在 `AppShell` 的 `_FloatingBottomBar` 中建立双击回顶触发展开与刷新的通道。

**Tech Stack:** Flutter / Dart, CustomScrollView, SliverPersistentHeader, ColorScheme / AppTheme, flutter_test.

## Global Constraints

- 搜索框固定占位文案为「搜索歌曲、歌手、专辑」，点击跳转至 `SearchPage`。
- 标签项包含「推荐」、「排行榜」、「电台」，选中项采用灵动胶囊风格（主色调高光底色 + 加粗文字），未选中项为中性柔和文字。
- 向下滑动时搜索框平滑淡出（透明度降为 0）并收折，标签栏紧贴状态栏下方常驻吸顶。向上滑动时搜索框平滑展开。
- 桌面端（Windows/macOS/Linux）保留页头刷新按钮，且不破坏现有 `home_desktop_refresh_test.dart`。
- 车机横屏模式（Car Mode）继续使用原车机专属顶栏，不受移动端顶部折叠影响。
- 双击底栏首页（350ms 连续点击）触发 350ms 平滑回顶并刷新首页数据。

---

### Task 1: 创建 `HomeCollapsibleHeader` 组件及单元测试

**Files:**
- Create: `lib/ui/widgets/home_collapsible_header.dart`
- Test: `test/ui/widgets/home_collapsible_header_test.dart`

**Interfaces:**
- Produces:
  - `class HomeCollapsibleHeaderDelegate extends SliverPersistentHeaderDelegate`
  - `class HomeSearchBar extends StatelessWidget`
  - `class HomeCapsuleTabBar extends StatelessWidget`
- Consumes:
  - `MusicApi`, `AuthController`, `PlayerController`
  - `SearchPage`

- [ ] **Step 1: 编写 `home_collapsible_header_test.dart` 测试用例**
测试包含：
1. 搜索框在展开状态时可见，包含「搜索歌曲、歌手、专辑」文字，点击能导航；
2. 标签栏包含「推荐」、「排行榜」、「电台」，点击能触发 `onSectionChanged`；
3. 吸顶折叠计算：`minExtent` 小于 `maxExtent`。

- [ ] **Step 2: 运行测试验证失败**
Run: `flutter test test/ui/widgets/home_collapsible_header_test.dart`
Expected: FAIL（文件尚未实现）。

- [ ] **Step 3: 实现 `lib/ui/widgets/home_collapsible_header.dart`**
实现带平滑渐隐、高度收折计算的 `HomeCollapsibleHeaderDelegate`，以及灵动胶囊样式的 `HomeCapsuleTabBar` 和 `HomeSearchBar`。

- [ ] **Step 4: 运行测试验证通过**
Run: `flutter test test/ui/widgets/home_collapsible_header_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交 Task 1 代码**
```bash
git add lib/ui/widgets/home_collapsible_header.dart test/ui/widgets/home_collapsible_header_test.dart
git commit -m "feat: add HomeCollapsibleHeader widget and tests"
```

---

### Task 2: 将 `HomeCollapsibleHeader` 集成至 `HomePage` 并支持回顶刷新

**Files:**
- Modify: `lib/ui/pages/home_page.dart`
- Test: `test/ui/pages/home_desktop_refresh_test.dart`

**Interfaces:**
- Consumes:
  - `HomeCollapsibleHeaderDelegate` from `lib/ui/widgets/home_collapsible_header.dart`
- Produces:
  - `HomePageState.scrollToTopAndRefresh()`
  - 将 `HomePage` 的 `_HomePageState` 开放或通过 GlobalKey / 静态方法让外部调用回顶刷新。

- [ ] **Step 1: 检查 `home_page.dart` 滚动控制器与 Sliver 结构**
添加 `final ScrollController _scrollController = ScrollController();`。
在移动端模式下使用 `SliverPersistentHeader(pinned: true, delegate: HomeCollapsibleHeaderDelegate(...))` 替代旧有的 `_RecommendHeader` 中的搜索与顶部标签。
为 `_HomePageState` 提供 `Future<void> scrollToTopAndRefresh()`。

- [ ] **Step 2: 运行现有桌面端测试以确保向后兼容**
Run: `flutter test test/ui/pages/home_desktop_refresh_test.dart`
Expected: PASS。

- [ ] **Step 3: 提交 Task 2 代码**
```bash
git add lib/ui/pages/home_page.dart
git commit -m "feat: integrate HomeCollapsibleHeader into HomePage with scrollToTopAndRefresh"
```

---

### Task 3: 在 `AppShell` 底栏中实现双击首页回顶刷新

**Files:**
- Modify: `lib/ui/pages/app_shell.dart`
- Test: `test/ui/pages/home_scroll_to_top_test.dart`

**Interfaces:**
- Consumes:
  - `HomePage` / `GlobalKey<HomePageState>`
- Produces:
  - `_FloatingBottomBar` 中首页双击检测及回顶刷新触发。

- [ ] **Step 1: 编写底栏双击首页回顶刷新的 widget 测试**
编写 `test/ui/pages/home_scroll_to_top_test.dart` 模拟连续两次点击首页底栏，验证回顶动画和刷新调用。

- [ ] **Step 2: 运行测试验证失败**
Run: `flutter test test/ui/pages/home_scroll_to_top_test.dart`
Expected: FAIL。

- [ ] **Step 3: 修改 `app_shell.dart`**
在 `_AppShellState` 中维护 `_homeKey = GlobalKey<HomePageState>()`，在 `_BottomNavItem` 的首页项中加入时间戳双击判定（< 350ms）或 `onDoubleTap`，触发 `_homeKey.currentState?.scrollToTopAndRefresh()`。

- [ ] **Step 4: 运行测试验证通过**
Run: `flutter test test/ui/pages/home_scroll_to_top_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交 Task 3 代码**
```bash
git add lib/ui/pages/app_shell.dart test/ui/pages/home_scroll_to_top_test.dart
git commit -m "feat: implement double-tap home bottom tab to scroll to top and refresh"
```

---

### Task 4: 全局回归测试与视觉效果复核

**Files:**
- Test: 全量涉及测试集

- [ ] **Step 1: 运行全量相关 UI 自动化测试**
Run: `flutter test test/ui/pages/home_desktop_refresh_test.dart test/ui/widgets/home_collapsible_header_test.dart test/ui/pages/home_scroll_to_top_test.dart`
Expected: 全部测试通过（All tests passed）。

- [ ] **Step 2: 检查代码格式与 lint**
Run: `flutter analyze lib/ui/widgets/home_collapsible_header.dart lib/ui/pages/home_page.dart lib/ui/pages/app_shell.dart`
Expected: 0 errors / 0 warnings。

- [ ] **Step 3: 最终整理提交**
```bash
git commit --allow-empty -m "chore: complete home header revamp verification"
```
