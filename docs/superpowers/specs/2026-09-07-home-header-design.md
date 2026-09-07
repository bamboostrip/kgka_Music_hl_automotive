# 首页顶部布局重构与双击回顶刷新设计规范

**日期**：2026-09-07  
**状态**：已由用户确认选择方案 1（SliverPersistentHeader 吸顶折叠 + QQ 音乐灵动胶囊标签）

---

## 1. 背景与目标

当前时音移动端首页顶栏布局存在以下不足：
1. 顶栏上方为「推荐 / 排行榜 / 电台」分段切换器，下方才是搜索框，与主流移动端（如 QQ 音乐）的布局习惯相反；
2. 页面向下滚动时，顶栏整组直接滑出屏幕，无法在浏览过程中快速发起搜索或切换页面；
3. 缺少移动端主流的「双击底部首页 Tab 平滑回顶并刷新」交互。

### 核心目标
1. **搜索置顶**：将搜索框移至顶栏最上方，占位文案保持规范的「搜索歌曲、歌手、专辑」，右侧与整体视觉贴合当前主题色设计。
2. **标签居下**：将「推荐」、「排行榜」、「电台」置于搜索框下方，采用 QQ 音乐式灵动胶囊设计（选中项主色高亮胶囊 + 加粗字，未选中项柔和灰字）。
3. **向下滑动渐隐折叠与标签吸顶**：
   - 随页面向下滚动（浏览内容时），搜索框平滑淡出（Opacity 1.0 $\to$ 0.0）并高度收起；
   - 「推荐 / 排行榜 / 电台」标签栏平滑上移，紧贴状态栏安全区下方吸顶（Pinned）；
   - 向上滑动或回顶时，搜索框平滑展开恢复；
   - 吸顶背景根据当前主题自适应（深色/浅色/半透明背景），附带细微边框与层次阴影，确保下方滚动内容不产生视觉混杂。
4. **双击首页回顶并刷新**：
   - 用户双击底栏「首页」（350ms 内连续点击），页面以缓动曲线平滑滚动回顶部（offset 0.0），搜索框随之展开，同时自动触发数据重载刷新。
5. **多端与既有能力兼容**：
   - 桌面端（Windows/macOS/Linux）：保留页头刷新按钮与桌面端交互；
   - 车机端（Car Mode）：车机横屏模式继续由车机独立顶栏接管，不受移动端 SliverHeader 影响；
   - 保证既有自动化测试用例（`home_desktop_refresh_test.dart` 等）全部通过。

---

## 2. 详细交互与视觉设计

### 2.1 顶部 Sliver 吸顶结构（`HomeCollapsibleHeader`）
采用自定义 `SliverPersistentHeaderDelegate` 实现：
- **最大高度（maxExtent）**：
  $$\text{maxExtent} = \text{topSafeArea} + \text{searchBarHeight}(44) + \text{spacing}(10) + \text{tabBarHeight}(42) + \text{bottomPadding}(8)$$
- **最小高度（minExtent）**：
  $$\text{minExtent} = \text{topSafeArea} + \text{tabBarHeight}(42) + \text{bottomPadding}(8)$$
- **收折进度计算**：
  $$\text{progress} = \left(\frac{\text{shrinkOffset}}{\text{maxExtent} - \text{minExtent}}\right).\text{clamp}(0.0, 1.0)$$
- **搜索框渐隐**：
  - 渐隐透明度：`opacity = (1.0 - progress * 1.6).clamp(0.0, 1.0)`
  - 物理高度缩放/偏移：在 progress 接近 1.0 时搜索框平滑滑出并由 `IgnorePointer` 禁用点击。
- **标签栏平移动画**：
  - 标签栏随收折平滑上升至 `topSafeArea` 下方，始终保持完全可见与可交互。
- **吸顶背景与边框**：
  - 未吸顶（progress == 0）：与页面背景无缝融合；
  - 吸顶中（progress > 0）：背景过渡至 `scaffoldBackgroundColor`（或适配自定义半透明背景的主题表面色），并在底缘显示 `outlineVariant.withValues(alpha: 0.5)` 的细微分割线。

### 2.2 QQ 音乐式灵动胶囊标签
- **布局**：横向排列三个标签「推荐」、「排行榜」、「电台」（桌面端可并列放置刷新按钮）。
- **选中项**：
  - 背景：`colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12)` 或柔和高光圆角胶囊；
  - 文字/图标：`colorScheme.primary`，字重 `FontWeight.w800`，字号 15；
  - 边框：`colorScheme.primary.withValues(alpha: 0.2)`。
- **未选中项**：
  - 文字/图标：`colorScheme.onSurfaceVariant.withValues(alpha: 0.85)`，字重 `FontWeight.w600`，字号 14。
- **动效**：标签切换时带有 200ms `Curves.easeOutCubic` 平滑过渡。

### 2.3 双击底栏回顶刷新机制
- 在 `_FloatingBottomBar` 中为「首页」导航项提供双击检测：
  - 记录上次点击时间戳 `_lastHomeTapTime`；
  - 若在 350ms 内再次点击首页：
    1. 调用首页 `scrollToTopAndRefresh()`；
    2. 执行 `_scrollController.animateTo(0, duration: Duration(milliseconds: 350), curve: Curves.easeOutCubic)`；
    3. 调用 `_refresh()` 异步刷新数据。

---

## 3. 代码模块规划

1. **新建组件**：`lib/ui/widgets/home_collapsible_header.dart`
   - `HomeCollapsibleHeaderDelegate`：SliverPersistentHeaderDelegate 核心实现；
   - `HomeSearchBar`：搜索胶囊组件；
   - `HomeCapsuleTabBar`：QQ 音乐风格胶囊标签栏。
2. **改造页面**：`lib/ui/pages/home_page.dart`
   - 在 `CustomScrollView` 中引入 `SliverPersistentHeader(pinned: true, delegate: ...)`；
   - 保留车机横屏适配分支；
   - 添加 `ScrollController` 并暴露 `scrollToTopAndRefresh()`；
   - 将 `_FeatureShelf`（猜你喜欢）合理放置在推荐内容流中。
3. **改造外壳**：`lib/ui/pages/app_shell.dart`
   - 为 `HomePage` 提供控制通道（`GlobalKey<HomePageState>`），在 `_FloatingBottomBar` 首页双击时调用 `scrollToTopAndRefresh()`。
4. **自动化与回归测试**：
   - 新增 `test/ui/widgets/home_collapsible_header_test.dart`；
   - 验证 `test/ui/pages/home_desktop_refresh_test.dart` 等既有测试全部通过。
