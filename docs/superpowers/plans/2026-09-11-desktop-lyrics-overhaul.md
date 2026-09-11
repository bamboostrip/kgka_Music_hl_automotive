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
- [x] 完成 Task 1~7 端到端验证与静态代码检查。

---

## Phase 2: 细节优化与交互精修（用户实机走查反馈）

### Task 9: 工具栏按钮去背景/增大热区 & 双行字体大小粗细统一

**Files:**
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Requirements:**
1. 工具栏样式调整：
   - 移除 `_buildOverlayToolbar` 外层的黑色半透底色和边框装饰（去背景，纯图标浮空展示）；
   - 位置上提：由 `top: 6` 调整为更贴顶的位置；
   - 按钮尺寸增大：`_ToolbarButton` 尺寸由 26x26 扩大为 30x30，图标大小调整为 19~20，热区更大更好点；悬停单按钮时保留微弱高亮背景（`Colors.white.withValues(alpha: 0.16)`）。
2. 双行模式字号字重统一（对标截图 3 QQ 音乐）：
   - 上下两行字体大小统一（`settings.fontSize * 0.78` 或 `settings.fontSize`），字重统一为 `FontWeight.bold`，不再有大小粗细落差；
   - 仅通过已播放金黄高亮与未播放天蓝色进行状态区分。

- [x] **Step 1: Write widget test for toolbar backgroundless style and dual line font consistency**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: Implement in lyrics_overlay_window.dart**
- [x] **Step 4: Run test to verify pass**
- [x] **Step 5: Commit**

---

### Task 10: 锁定态「🔒 解锁」胶囊位置上提与防遮挡优化

**Files:**
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Requirements:**
1. 将 `LockedLyricsBody` 中解锁胶囊的垂直位置进一步上提（贴近窗口顶部，例如 `top: 2` 或 `top: 3`）；
2. 优化歌词主体在锁定状态下的垂直内边距（略微下沉 4~6px），使解锁胶囊完全位于歌词上方的负空间，彻底消除对歌词文本的任何遮挡。

- [x] **Step 1: Write test verifying unlock pill position and non-overlapping margins**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: Implement adjustments in lyrics_overlay_window.dart**
- [x] **Step 4: Run test to verify pass**
- [x] **Step 5: Commit**

---

### Task 11: 设置快捷菜单弹出方向智能自适应（向上/向下）

**Files:**
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`
- Test: `test/ui/desktop/desktop_lyrics_test.dart`

**Requirements:**
1. 展收快捷菜单时，获取悬浮窗当前的屏幕 Y 坐标（`windowManager.getPosition()`）：
   - 若上方空间充足（例如 `position.dy >= 260.0`，大部分用户放置在屏幕底部或中下部）：
     - 菜单向上弹出！悬浮窗移动到 `position.dy - 172`，高度设为 260，菜单渲染在歌词上方；
   - 若上方空间不足（靠屏幕顶部）：
     - 菜单向下弹出，悬浮窗保持当前 Y，高度设为 260，菜单渲染在歌词下方；
2. 收起菜单时：
   - 精确还原原始窗口 Y 坐标和原始 88px 高度。

- [x] **Step 1: Write test for adaptive upward/downward menu layout and coordinate restoration**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: Implement in lyrics_overlay_window.dart**
- [x] **Step 4: Run test to verify pass**
- [x] **Step 5: Commit**

---

### Task 12: 打通“更多设置”拉起主程序并跳转歌词设置页

**Files:**
- Modify: `lib/ui/desktop/desktop_shell.dart`
- Test: `test/ui/desktop/desktop_shell_lyrics_settings_test.dart`

**Requirements:**
1. 在 `DesktopShell` 中监听 `player.openLyricsSettingsRequest`；
2. 当收到请求时：
   - 唤起主窗口至前台：`windowManager.show()`, `windowManager.focus()`, 最小化时调用 `windowManager.restore()`；
   - 通过内容区导航器打开 `DesktopLyricsSettingsPage(player: widget.player)`。

- [x] **Step 1: Write widget test verifying openLyricsSettingsRequest brings window and pushes settings page**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: Implement in desktop_shell.dart**
- [x] **Step 4: Run test to verify pass**
- [x] **Step 5: Commit**

---

### Task 13: 桌面歌词设置页紧凑化与同屏实时预览优化

**Files:**
- Modify: `lib/ui/pages/desktop_lyrics_settings_page.dart`
- Test: `test/ui/pages/desktop_lyrics_settings_test.dart`

**Requirements:**
1. 紧凑化布局调整：
   - 减小大内边距，去除冗余空隙；
   - 在桌面宽度宽裕时采用左右双栏布局（左侧为紧凑设置面板，右侧为置顶实时预览卡片）；
   - 在窄屏或移动端时预览卡片置于顶部或紧凑排列，确保用户在调节上方选项时，能够同屏直观看到下方/右侧预览效果，无需反复滚动页面。

- [x] **Step 1: Write widget test for compact/split layout and responsive preview**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: Implement in desktop_lyrics_settings_page.dart**
- [x] **Step 4: Run test to verify pass**
- [x] **Step 5: Commit**

---

### Task 14: Phase 2 全量回归验证与静态分析

- [x] **Step 1: Run flutter analyze**
- [x] **Step 2: Run flutter test on all desktop & pages suites**
- [x] **Step 3: Final verification and commit**

---

## Phase 3: 双行交替高亮、对齐可配与悬浮窗几何/交互修复（用户实机走查反馈）

**背景（4 个实测问题）：**
1. 双行模式下高亮恒在上行：每换一句，"正在唱的那句"都要从下行搬到上行，观感是"文字跳行"；
2. 对齐方式只对单行生效（双行写死左右分离），用户无法为双行选择居中/左/右；
3. 悬浮窗只有 88px 高，30px 工具栏按钮（top:2 → y2~36）与双行歌词渲染区（约 y20~74）
   恒重叠约 16px，解锁胶囊同理 —— 调按钮位置无解；
4. 展开"桌面歌词设置"快捷菜单时整条歌词会闪跳一下；且点击其它软件菜单不消失
   （透明置顶窗还会继续吃掉下方点击）。

**核心决策：**
- 双行改为**交替（乒乓）高亮**：正在唱的那一行文字留在原地，另一行换成下一句；
  横向锚点不随高亮位置变化（split：上行恒居左、下行恒居右）。
  主窗只多下发一个 `activeOnBottom = (当前句下标.isOdd)`，子窗按此决定哪一行带动画进度。
- 对齐新增第 4 个取值 `split`（左右分离，设为默认）：单行下与 `center` 渲染等价，
  双行下即 QQ 音乐经典对角交错；`center/left/right` 三种为"两行同侧"。
  存量 `center` 做一次性行为等价迁移（历史版本 alignment 对双行无效）。
- 悬浮窗高度 88 → **124**（顶部 36px 工具栏专属带 + 下方 88px 歌词带）；
  所有菜单/工具栏魔数（260/172/174/92/38/180）改为由常量推导；
  存量窗口位置一次性 -36 迁移（默认停靠位置公式同步前移，歌词视觉位置不变）。
- 展开/收起不再自己推导容器高度：容器高度 == 真实窗口高度（MediaQuery），
  卡片贴底/贴顶随之自然成立；几何变更改用**一次 `windowManager.setBounds`**
  （单次 SetWindowPos），并按弹出方向选择"先改状态再改几何 / 先改几何再改状态"，
  消除中间帧错位。菜单关闭新增前台焦点轮询 + 鼠标离开窗口兜底。

**Files:**
- Modify: `lib/services/windows_desktop_lyrics_bridge.dart`（常量、协议、位置迁移）
- Modify: `lib/services/desktop_lyrics_service.dart`（`DesktopLyricsAlignment`、默认值、updateLyrics）
- Modify: `lib/controllers/player_controller.desktop.dart`（下发 activeOnBottom）
- Modify: `lib/controllers/player_controller.settings.dart` / `player_controller.dart`（对齐迁移）
- Modify: `lib/ui/desktop/lyrics_overlay_window.dart`（排版、几何、菜单时序与收起）
- Modify: `lib/ui/pages/desktop_lyrics_settings_page.dart`（第 4 项对齐、预览同步、提示文案）
- Test: `test/ui/desktop/desktop_lyrics_test.dart` / `test/ui/pages/desktop_lyrics_settings_test.dart`

### Task 15: 悬浮窗几何重构（工具栏专属带）

- [x] **Step 1: Write failing test for 124 高度与派生常量、按钮与歌词不重叠**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: 常量与布局实现（lyricsTopInset / overlayExpandedHeight / 位置迁移）**
- [x] **Step 4: Run test to verify pass**

### Task 16: 双行交替高亮 + 对齐可配

- [x] **Step 1: Write failing test for activeOnBottom 交替排版与四种对齐锚点**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: 实现 buildOverlayLyricsBody 交替排版 + alignment 分支 + 协议打通**
- [x] **Step 4: Run test to verify pass**

### Task 17: 快捷菜单不闪跳 + 点击外部消失

- [x] **Step 1: Write failing test for setBounds 原子几何、失焦自动收起、鼠标离开兜底**
- [x] **Step 2: Run test to verify failure**
- [x] **Step 3: 实现菜单时序（setBounds + 按方向排序）与关闭看门狗**
- [x] **Step 4: Run test to verify pass**

### Task 18: Phase 3 全量回归验证与静态分析

- [x] **Step 1: Run flutter analyze**
- [x] **Step 2: Run flutter test（全量）**
- [x] **Step 3: Final verification and commit**

**已知取舍：**
- 悬浮窗在非悬停态的可点击区域增高 36px（整窗本就是 opaque MouseRegion）。
  替代方案是压缩歌词带，会让双行大字号被 FittedBox 等比缩小，故不采用。
- 快捷菜单展开期间窗口是 296px 高的透明置顶窗，那一块区域会吃掉一次点击
  （标准 popover 行为）；关闭时必定还原几何（含 dispose 防御性还原）。

