# PC 桌面歌词体验优化（对标 QQ 音乐）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 深度重构与优化 PC 桌面歌词体验，实现长歌词跑马灯平滑滚动、悬浮工具栏快捷调节菜单、锁定态靠近悬浮「🔒 解锁」胶囊、默认单行且支持双行交错排布、卡拉OK逐字变色高亮，以及对齐 QQ 音乐的详细设置页。

**Architecture:** 
1. **模型与协议层**：扩展 `DesktopLyricsSettings` 支持单双行、对齐、透明度及双色（已播放/未播放），主子窗 IPC 增加 `updateProgress`、`updateOverlaySettings`、`openLyricsSettings`；
2. **渲染层**：双层 `ClipRect` 高性能逐字染色；基于 `TextPainter` 与播放进度的长歌词跑马灯平滑位移；单行居中与双行交错排版；
3. **交互层**：悬浮工具栏内嵌快捷设置浮动卡片；锁定态通过光标区域感应淡入「🔒 解锁」胶囊并动态切换鼠标穿透；主窗口设置页提供单选、滑块与实时预览。

**Tech Stack:** Flutter / Dart, desktop_multi_window, window_manager, SharedPreferences, Provider / ChangeNotifier.

## Global Constraints
- Windows 桌面悬浮窗架构保持 `desktop_multi_window` + `window_manager`；
- 所有配置扩展必须具备向下兼容性（缺失字段取安全默认值，旧 `textColor` 映射为 `unplayedTextColor`）；
- 每次任务变更需保证 `flutter analyze` 零 issue，对应单元测试全部通过。

---

## File Structure

```
lib/
├── services/
│   ├── desktop_lyrics_service.dart          # [MODIFY] 扩展 DesktopLyricsSettings 配置项与服务接口
│   └── windows_desktop_lyrics_bridge.dart   # [MODIFY] 扩展 IPC 消息通道（updateProgress, updateOverlaySettings, openLyricsSettings）
├── controllers/
│   ├── player_controller.desktop.dart       # [MODIFY] 接入 updateProgress 推送、设置持久化与打开设置页
│   └── player_controller.dart               # [MODIFY] 暴露 openDesktopLyricsSettingsPage 路由或回调
├── ui/
│   ├── desktop/
│   │   ├── lyrics_overlay_window.dart       # [MODIFY] 悬浮窗重构：单双行排版、逐字变色、跑马灯滚动、设置面板、悬浮解锁胶囊
│   │   └── desktop_player_bar.dart          # [MODIFY] 保持与锁定态联动
│   └── pages/
│       └── desktop_lyrics_settings_page.dart# [MODIFY] 对标 QQ 音乐设置项（行数、对齐、文字透明度、双色选择与实时预览）
test/
├── ui/
│   ├── desktop/
│   │   └── desktop_lyrics_test.dart         # [MODIFY] 增加单双行、逐字变色、跑马灯与设置相关测试
│   └── pages/
│       └── desktop_lyrics_settings_test.dart# [NEW] 设置页新增配置选项与实时预览测试
```

---

## Tasks

### Task 1: 扩展 DesktopLyricsSettings 配置模型与向下兼容

**Files:**
- Modify: `lib/services/desktop_lyrics_service.dart:15-95`
- Modify: `test/ui/desktop/desktop_lyrics_test.dart:18-83`

**Interfaces:**
- `DesktopLyricsSettings`:
  - `singleLine`: `bool` (default `true`)
  - `alignment`: `String` (default `'center'`)
  - `textOpacity`: `double` (default `1.0`)
  - `playedTextColor`: `int` (default `0xFFFFD700`)
  - `unplayedTextColor`: `int` (default `0xFF00BFFF`)
  - `toMap() / fromMap() / copyWith()`

- [ ] **Step 1: Write failing unit tests for new settings fields**
  在 `test/ui/desktop/desktop_lyrics_test.dart` 中增加对 `singleLine`、`alignment`、`textOpacity`、`playedTextColor`、`unplayedTextColor` 默认值、序列化及旧配置升级兼容（旧 `textColor` 自动继承到 `unplayedTextColor`）的测试。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确认编译/断言失败。
- [ ] **Step 3: Implement settings fields in desktop_lyrics_service.dart**
  在 `DesktopLyricsSettings` 中加入新字段、构造函数默认值、`copyWith`、`toMap`、`fromMap`、`==` 与 `hashCode`。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确保测试通过。
- [ ] **Step 5: Commit**
  `git add lib/services/desktop_lyrics_service.dart test/ui/desktop/desktop_lyrics_test.dart; git commit -m "feat: extend DesktopLyricsSettings with layout and color fields"`

---

### Task 2: 扩展 IPC 通信协议（进度推送、悬浮窗调参回传与打开设置页）

**Files:**
- Modify: `lib/services/windows_desktop_lyrics_bridge.dart`
- Modify: `lib/services/desktop_lyrics_service.dart`
- Modify: `lib/controllers/player_controller.desktop.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Interfaces:**
- `WindowsDesktopLyricsBridge`:
  - `updateKaraokeProgress({required double progress, required Duration? lineDuration, required bool isPlaying})`: 向子窗发送 `updateProgress`
  - `DesktopLyricsOpenSettingsRequested`: 回调函数
  - 处理 `updateOverlaySettings` 与 `openLyricsSettings`
- `PlayerController.desktop.dart`:
  - 接收并处理子窗的设置变更与打开设置页请求

- [ ] **Step 1: Write tests for IPC bridge dispatching updateProgress and receiving overlay settings**
  在 `test/ui/desktop/desktop_lyrics_test.dart` 中增加对 `updateProgress` 桥接与 `updateOverlaySettings` 消息处理的测试。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确认失败。
- [ ] **Step 3: Implement bridge methods and message handling**
  在 `windows_desktop_lyrics_bridge.dart` 中实现 `updateKaraokeProgress` 向子窗发送 `updateProgress`；在 `_ensureMethodHandler` 中处理 `updateOverlaySettings` 并分发至 `onSettingsChanged`、处理 `openLyricsSettings` 分发至 `onOpenSettings`；在 `player_controller.desktop.dart` 中对接。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确保全部通过。
- [ ] **Step 5: Commit**
  `git commit -am "feat: implement IPC for karaoke progress and overlay settings"`

---

### Task 3: 逐字变色渲染器与长歌词跑马灯平滑滚动

**Files:**
- Create: `lib/ui/desktop/lyrics_karaoke_line.dart`
- Test: `test/ui/desktop/lyrics_karaoke_line_test.dart`

**Interfaces:**
- `LyricsKaraokeLine`:
  - `text: String`
  - `fontSize: double`
  - `playedColor: Color`
  - `unplayedColor: Color`
  - `progress: double` (0.0 ~ 1.0)
  - `availableWidth: double`
  - `alignment: TextAlign`
  - `textOpacity: double`
  - 内部自动通过 `TextPainter` 计算文本总宽。超出 `availableWidth` 时根据 `progress` 自动向左平移 `(textWidth - availableWidth + 32) * progress`。

- [ ] **Step 1: Write failing unit/widget tests for LyricsKaraokeLine**
  在 `test/ui/desktop/lyrics_karaoke_line_test.dart` 中编写：
  - 未播放时（progress=0）整行渲染未播放色；
  - 部分播放时（progress=0.5）使用 ClipRect 裁剪高亮层；
  - 正常长度时不产生滚动偏移；
  - 超长文本时根据 progress 计算正确的向左负偏移量。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/desktop/lyrics_karaoke_line_test.dart` 确认失败。
- [ ] **Step 3: Implement LyricsKaraokeLine widget**
  实现双层叠放架构：
  底层 Text（未播放色，带 3D 轮廓文字阴影）；
  顶层 Text（已播放色，带金色发光阴影），外层包装 `ClipRect` 与 `Align(alignment: Alignment.topLeft, widthFactor: progress.clamp(0.0, 1.0))`；
  若 `textWidth > availableWidth`，使用 `Transform.translate` 施加平移动画，呈现跑马灯。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/desktop/lyrics_karaoke_line_test.dart` 确保测试通过。
- [ ] **Step 5: Commit**
  `git commit -am "feat: implement LyricsKaraokeLine with progressive coloring and marquee scroll"`

---

### Task 4: 桌面歌词排版重构（默认单行居中 + QQ 音乐经典双行交错）

**Files:**
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Interfaces:**
- `buildOverlayLyricsBody`:
  - 引入 `progress` 参数；
  - 根据 `settings.singleLine` 分流为单行视图与双行交错视图；
  - 单行模式：居中展示当前句 `LyricsKaraokeLine`；
  - 双行模式：第一行居左（padding left 24）、第二行居右（padding right 24）。

- [ ] **Step 1: Write failing widget test for single and dual line layouts**
  在 `test/ui/desktop/desktop_lyrics_test.dart` 增加测试：
  - `singleLine=true` 时只渲染当前句，无下一句；
  - `singleLine=false` 时第一行左对齐、第二行右对齐。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确认失败。
- [ ] **Step 3: Implement layout refactor in lyrics_overlay_window.dart**
  重构 `buildOverlayLyricsBody`，接入 `LyricsKaraokeLine`，支持单双行模式切换与对齐配置。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确保测试通过。
- [ ] **Step 5: Commit**
  `git commit -am "feat: refactor desktop lyrics layout with single line and dual line staggered mode"`

---

### Task 5: 悬浮工具栏快捷调节菜单（字号加减、预设配色、单双行切换）

**Files:**
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Interfaces:**
- `_buildOverlayToolbar`:
  - 新增设置齿轮按钮；
  - 点击弹出 `_OverlayQuickSettingsMenu`；
  - 菜单包含：
    - 字号调节：`[-]` 当前字号 `[+]`
    - 颜色预设：6 个高频颜色圆圈色块
    - 行数切换：切换单行 / 切换双行
    - 更多设置：点击调用主窗打开设置页
  - 点击菜单外部遮罩或再次点击齿轮关闭。

- [ ] **Step 1: Write failing widget test for settings button and quick menu**
  测试点击设置图标弹出快捷调节面板，测试点击字号加减按钮与预设颜色能够触发设置回调。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确认失败。
- [ ] **Step 3: Implement quick settings menu in lyrics_overlay_window.dart**
  构建精致的半透明暗色磨砂卡片，绑定字号修改、颜色挑选、单双行切换与更多设置事件，回传主窗落盘。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确保测试通过。
- [ ] **Step 5: Commit**
  `git commit -am "feat: add quick settings popup menu to desktop lyrics overlay"`

---

### Task 6: 锁定态靠近悬浮「🔒 解锁」胶囊与鼠标动态穿透

**Files:**
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Interfaces:**
- `_LockedLyricsBody`:
  - 维持全穿透模式；
  - 80ms 定时器监听光标位置（通过 `window_manager` 查询）；
  - 当光标进入歌词窗口，顶部中央淡入 `[🔒 解锁]` 胶囊；
  - 当光标移入胶囊几何矩形，动态切换 `setIgnoreMouseEvents(false)`；
  - 用户点击胶囊触发 `onToggleLock(false)`；
  - 光标移出胶囊但留在窗口内时恢复 `setIgnoreMouseEvents(true)`；
  - 光标离开窗口后胶囊淡出。

- [ ] **Step 1: Write widget test for locked hover unlock badge**
  测试在锁定模式下，光标在窗口内时胶囊组件渲染，点击解锁胶囊触发解锁回调。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确认失败。
- [ ] **Step 3: Implement hover unlock pill and dynamic passthrough**
  在 `_LockedLyricsBody` 中加入光标感应逻辑、淡入淡出动画与胶囊按钮手势监听。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/desktop/desktop_lyrics_test.dart` 确保测试通过。
- [ ] **Step 5: Commit**
  `git commit -am "feat: implement locked hover unlock pill with dynamic mouse passthrough"`

---

### Task 7: 主程序桌面歌词设置页对标 QQ 音乐

**Files:**
- Modify: `lib/ui/pages/desktop_lyrics_settings_page.dart`
- Create: `test/ui/pages/desktop_lyrics_settings_test.dart`

**Interfaces:**
- `DesktopLyricsSettingsPage`:
  - 行数设置卡片：单选【单行显示】/【双行显示】；
  - 对齐方式卡片：单选【居中对齐】/【左对齐】/【右对齐】；
  - 字体大小与文字透明度滑块（10% ~ 100%）；
  - 颜色卡片：已播放字色、未播放字色；
  - 底部实时预览卡片：展示包含逐字变色与双行交错的真实预览效果。

- [ ] **Step 1: Write failing widget test for updated settings page**
  测试设置页渲染单选行数、对齐方式选择器、透明度滑块以及双色选择，并验证变更同步到 `PlayerController`。
- [ ] **Step 2: Run test to verify failure**
  `flutter test test/ui/pages/desktop_lyrics_settings_test.dart` 确认失败。
- [ ] **Step 3: Implement UI updates in desktop_lyrics_settings_page.dart**
  重构设置页布局，增加行数、对齐、文字透明度与双色选择器，添加带动态变色效果的实时预览组件。
- [ ] **Step 4: Run test to verify pass**
  `flutter test test/ui/pages/desktop_lyrics_settings_test.dart` 确保测试通过。
- [ ] **Step 5: Commit**
  `git commit -am "feat: align desktop lyrics settings page with QQ Music design"`

---

### Task 8: 全量端到端验证与静态检查

- [ ] **Step 1: Run flutter analyze**
  运行 `flutter analyze` 确保 0 errors、0 warnings、0 issues。
- [ ] **Step 2: Run all related unit & widget tests**
  运行 `flutter test test/ui/desktop/` 与 `flutter test test/ui/pages/` 确保所有用例 100% 绿色通过。
- [ ] **Step 3: Verification & Commit**
  整理文档与最终提交。
