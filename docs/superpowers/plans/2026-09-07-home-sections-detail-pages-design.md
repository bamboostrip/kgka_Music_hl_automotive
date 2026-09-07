# 推荐歌单与新歌速递二级流页面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为首页「推荐歌单」和「新歌速递」标题添加跳转箭头，并新增对应的二级卡片流详情页（参考 QQ 音乐设计）。推荐歌单页展示双列大卡片歌单网格；新歌速递页展示双列新歌卡片并提供顶部「▶ 播放全部」按钮。

**Architecture:** 
- 在 `lib/ui/pages/recommended_playlists_page.dart` 中实现「推荐歌单」二级页：暗色氛围沉浸顶、大标题、双列歌单网格卡片、分页加载与下拉刷新。
- 在 `lib/ui/pages/top_songs_page.dart` 中实现「新歌速递」二级页：暗色沉浸顶、居中「▶ 播放全部」药丸按钮、双列歌曲大卡片网格、点击切歌与播放队列设置。
- 在 `lib/ui/pages/home_page.dart` 与 `lib/ui/widgets/app_section.dart` 中为 `_SectionHeader` / `AppSectionHeader` 增加 `onTap` 箭头导航交互。
- 编写 Widget 测试并运行 `flutter analyze` 验证。

**Tech Stack:** Flutter, Dart, GridView / CustomScrollView, MusicApi, PlayerController, AuthController.

## Global Constraints

- 「推荐歌单」页坚决不放「播放全部」按钮，避免拉取海量歌单歌曲导致内存和 API 崩溃。
- 「新歌速递」页提供「▶ 播放全部」按钮，仅对已加载的新歌进行整队播放。
- 页面风格与项目既有深浅色主题、圆角（8~12px）和微阴影体系严格保持一致。
- 零 analyze 警告，零单元测试破坏。

---

### Task 1: 首页板块标题跳转箭头（_SectionHeader / AppSectionHeader）

**Files:**
- Modify: `lib/ui/pages/home_page.dart`
- Modify: `lib/ui/widgets/app_section.dart`

- [ ] **Step 1: 升级 _SectionHeader 支持 onTap 与右侧箭头**
  - 在 `_SectionHeader` 中增加 `onTap` 可选回调。
  - 当 `onTap != null` 时，标题右侧展示 `Icons.chevron_right_rounded` 图标。
  - 点击标题区域即可触发 `onTap`。

- [ ] **Step 2: 升级 AppSectionHeader 支持 onTap 与右侧箭头**
  - 在 `AppSectionHeader` 中支持 `onTap` 与 `chevron_right_rounded`。

- [ ] **Step 3: 绑定推荐歌单与新歌速递的跳转逻辑**
  - 在 `_PlaylistRail` 中传入 `onTapTitle`，打开 `RecommendedPlaylistsPage`。
  - 在 `_TopSongRail` 中传入 `onTapTitle`，打开 `TopSongsPage`。

---

### Task 2: 实现「推荐歌单」二级流页面（RecommendedPlaylistsPage）

**Files:**
- Create: `lib/ui/pages/recommended_playlists_page.dart`

- [ ] **Step 1: 构建页面框架与沉浸式头部**
  - 顶部导航栏：返回按钮 `←`。
  - 暗色背景渐变层 + 居中大标题「推荐歌单」。
  - 顶部圆角主卡片容器。

- [ ] **Step 2: 构建双列歌单网格卡片流**
  - 使用 `GridView.builder`，根据宽度自适应（移动端 2 列，宽屏 3~4 列）。
  - 单张卡片渲染：正方形封面（带圆角与微边框）、右下角播放量角标、标题（14px 粗体）、副标题（12px 浅灰）。
  - 点击歌单卡片：`Navigator.push` 到 `PlaylistDetailPage`。

- [ ] **Step 3: 实现分页加载与下拉刷新**
  - 监听 `ScrollController` 接近底部时自动加载下一页 `page++`。
  - 使用 `RefreshIndicator` 刷新第一页。
  - 底部预留安全区域适配 MiniPlayer。

---

### Task 3: 实现「新歌速递」二级流页面（TopSongsPage）

**Files:**
- Create: `lib/ui/pages/top_songs_page.dart`

- [ ] **Step 1: 构建页面框架与沉浸式头部**
  - 顶部返回按钮 `←`。
  - 暗色背景渐变层 + 居中大标题「新歌速递」。
  - **居中药丸按钮「▶ 播放全部」**：点击一键将全页歌曲加入播放列表并从第一首播放。

- [ ] **Step 2: 构建双列歌曲卡片流**
  - 双列卡片网格，单卡展示正方形大封面、正在播放 Badge、歌名（当前播放高亮）、歌手。
  - 点击单曲卡片直接播放该歌曲，并将已加载的新歌整体赋为当前播放队列。
  - 桌面端支持 `CoverPlayOverlay` hover 播放。

- [ ] **Step 3: 实现分页与下拉刷新**
  - 分页加载 `api.topSongs(page: page)`。
  - 下拉刷新。
  - 底部预留 MiniPlayer 悬浮空间。

---

### Task 4: 编写测试并验证完整闭环

**Files:**
- Create: `test/ui/pages/recommended_playlists_page_test.dart`
- Create: `test/ui/pages/top_songs_page_test.dart`
- Modify: `test/ui/pages/home_page_tabs_swipe_test.dart` (如需)

- [ ] **Step 1: 编写页面渲染与跳转测试**
- [ ] **Step 2: 运行所有相关测试**
- [ ] **Step 3: 运行 flutter analyze 确保 0 问题**
