# PC 桌面歌词体验优化设计规范（对标 QQ 音乐）

## 1. 目标与背景

当前 Windows 桌面歌词悬浮窗已具备基础的常显、拖动、播控与锁定穿透能力，但相比成熟的桌面音乐客户端（如 QQ 音乐），在精细化交互与视觉体验上仍有差距：
1. **长歌词截断**：长句子被固定宽度和省略号（`TextOverflow.ellipsis`）截断，后半句无法看全；
2. **缺乏即时调节**：用户无法直接在悬浮窗上调节字号与颜色，必须跳转到深层设置页；
3. **锁定态缺乏直观解锁**：锁定后完全穿透，悬浮窗没有类似 QQ 音乐的光标靠近解锁胶囊；
4. **单/双行与排版单一**：默认强制双行居中，无法切换单行，双行缺乏经典交错排版；
5. **未支持卡拉OK逐字变色高亮**：整行同色，缺乏已播放/未播放字的动态视觉节奏。

本项目旨在系统性优化 PC 桌面歌词，实现长歌词跑马灯平滑滚动、悬浮工具栏快捷调节面板、锁定态靠近悬浮「🔒 解锁」胶囊、默认单行且支持双行交错排版，以及卡拉OK逐字变色高亮。

---

## 2. 核心架构与数据流

```
[ PlayerController (主进程) ]
       │
       ├─ (1) 高频推送播放进度 ──> updateProgress { progress, isPlaying } ──> [ 歌词悬浮窗 (子进程) ]
       │                                                                         │
       ├─ (2) 歌词与基础信息 ───> updateLyric { current, next, isPlaying } ──────┤
       │                                                                         ├─ 逐字变色 (ClipRect)
       ├─ (3) 设置同步 ────────> updateSettings { DesktopLyricsSettings } ───────┼─ 跑马灯平滑滚动
       │                                                                         ├─ 快捷设置悬停菜单
       │                                                                         ├─ 锁定态靠近悬浮解锁胶囊
       │                                                                         │
       │<─ (4) 快捷调参回传 ──── updateOverlaySettings { settingsMap } ──────────┘
       │<─ (5) 唤起详细设置 ──── openLyricsSettings {}
       ▼
[ DesktopLyricsSettingsPage ] & [ SharedPreferences ]
```

---

## 3. 数据模型与协议扩展

### 3.1 `DesktopLyricsSettings` 字段扩展
在 `lib/services/desktop_lyrics_service.dart` 中增加以下配置项（均带安全向下兼容与默认值）：

| 字段名 | 类型 | 默认值 | 描述 |
|---|---|---|---|
| `singleLine` | `bool` | `true` | 是否单行显示（默认 `true` 为单行，`false` 为双行） |
| `alignment` | `String` | `'center'` | 对齐方式：`'center'`（居中）、`'left'`（靠左）、`'right'`（靠右） |
| `textOpacity` | `double` | `1.0` | 文字透明度（范围 `0.2` ~ `1.0`） |
| `playedTextColor` | `int` | `0xFFFFD700` | 已播放字高亮色（默认亮金黄色） |
| `unplayedTextColor` | `int` | `0xFF00BFFF` | 未播放字颜色（默认天蓝色，兼容映射旧 `textColor`） |

原有字段保留并继续支持：
* `opacity`: 背景透明度（默认 0.0）
* `backgroundColor`: 背景颜色
* `fontSize`: 字体大小（默认 24.0）
* `locked`: 锁定状态
* `passthrough`: 兼容解析字段

### 3.2 IPC 通信协议定义
* **主窗 → 子窗**：
  * `updateProgress`: `{ 'progress': double, 'isPlaying': bool }`
    主窗 `_syncDesktopKaraokeProgress` 计算的 `progress`（0.0 ~ 1.0）下发给子窗，用于驱动逐字染色和跑马灯滚动。
  * `updateLyric`: `{ 'current': String, 'next': String, 'isPlaying': bool }`
  * `updateSettings`: `{ ...DesktopLyricsSettings.toMap() }`
* **子窗 → 主窗**：
  * `updateOverlaySettings`: 携带修改后的设置 Map。主窗统一持久化至 `SharedPreferences`，通知设置页刷新并回推子窗。
  * `openLyricsSettings`: 请求主窗将自身激活并导航到 `DesktopLyricsSettingsPage`。
  * `setLyricsLocked`: `{ 'locked': bool }`（已有协议，复用）。
  * `controlPlayback`: `{ 'action': 'previous' | 'togglePlay' | 'next' }`（已有协议，复用）。
  * `windowClosed`: 用户点击 X 关闭（已有协议，复用）。
  * `overlayReady`: 子引擎准备就绪握手（已有协议，复用）。

---

## 4. UI 与渲染设计

### 4.1 歌词排版与逐字变色（Karaoke）

#### (1) 单行排版（默认）
* 垂直居中展示当前正在播放的歌词（`current`）。
* 水平对齐由 `settings.alignment` 控制（默认居中）。

#### (2) 双行交错排版（QQ 音乐经典样式）
* 第一行：当前播放句（或上一句），靠左对齐，左侧留出 24px 内边距；
* 第二行：即将播放的下一句，靠右对齐，右侧留出 24px 内边距；
* 形成视觉上的对角交错排布，上下呼应、层次分明。

#### (3) 逐字变色高亮（双层 ClipRect 技术）
* **底层**：完整渲染整行歌词，颜色为 `unplayedTextColor`，配合 `textOpacity` 与柔和的文字阴影；
* **顶层**：相同内容与样式的歌词，颜色为 `playedTextColor`，带发光高亮阴影；
* **裁剪控制器**：顶层通过 `ClipRect` 包裹，裁剪宽度为 `textWidth * progress`。随着当前句进度从 0% 推进至 100%，高亮色从左至右逐字擦染，还原原汁原味的逐字染色。

### 4.2 超长歌词跑马灯平滑滚动（解决痛点 1）
* 使用 `TextPainter` 预先计算当前单行文本的真实排版宽度 `textWidth`。
* 比较 `textWidth` 与窗口内容可视宽度 `availableWidth`：
  * **未超出**（`textWidth <= availableWidth`）：静止展示，遵循用户选定的对齐方式；
  * **超出**（`textWidth > availableWidth`）：
    * 不缩小字号，不使用 `...` 截断；
    * 最大位移量 `maxScroll = textWidth - availableWidth + 32`；
    * 当前水平偏移量 `offset = -maxScroll * progress`；
    * 随着歌曲播放进度，整句歌词匀速从右向左滑过，使当前唱到的字始终处于视野中心，唱完时平稳滑至句末。

### 4.3 悬浮工具栏与快捷调节面板（解决痛点 2）
* **工具栏**：
  在播控按钮右侧增加设置齿轮按钮：
  `[上一曲]` `[播放/暂停]` `[下一曲]` | `[锁定]` `[设置]` `[关闭]`
* **快捷设置面板**：
  点击设置齿轮在工具栏下方弹出暗色磨砂卡片（支持点击卡片外部自动收起）：
  1. **字体大小**：`[-]` `24` `[+]` 按钮步进器（步长 2sp，范围 16~40）；
  2. **字体颜色**：预设 6 个经典配色色块（亮白、深蓝、金黄、霓虹粉、青绿、天蓝），点击高亮选中色块并实时换色；
  3. **行数切换**：提供【切换双行】或【切换单行】快捷按钮；
  4. **更多设置**：点击触发 `openLyricsSettings`，主窗口跳转至完整设置页。

### 4.4 锁定态悬浮「🔒 解锁」胶囊按钮（解决痛点 3）
* **常态**：锁定后，歌词文字常显，窗口开启穿透（`WS_EX_TRANSPARENT`），鼠标操作完全穿透到底层应用。
* **光标靠近感应**：
  * 悬浮窗内部启动 80ms 轻量光标位置检测（`GetCursorPos` / `window_manager`）；
  * 当光标位于桌面歌词窗口区域时，在歌词顶部中央平滑淡入展示 QQ 音乐同款 `[🔒 解锁]` 药丸胶囊（暗色半透明圆角卡片，带锁图标与白字）；
* **精准接收点击**：
  * 当光标移入该胶囊按钮的矩形范围时，动态调用 `windowManager.setIgnoreMouseEvents(false)`，光标切换为手型 Pointer；
  * 用户点击胶囊按钮，直接调用 `onToggleLock(false)` 完成解锁；
  * 光标离开胶囊按钮但仍在窗口内时，立即恢复 `setIgnoreMouseEvents(true)`，其余区域继续保持穿透；
  * 光标移出歌词窗口后，解锁胶囊平滑淡出隐藏。

### 4.5 主窗口详细设置页对齐 QQ 音乐
在 `DesktopLyricsSettingsPage` 中：
1. **行数选择**：Radio【单行显示】/【双行显示】；
2. **对齐方式**：Radio【居中对齐】/【左对齐】/【右对齐】；
3. **字号与透明度**：字号滑块、文字透明度滑块（10% ~ 100%）；
4. **颜色方案**：已播放字色色盘、未播放字色色盘；
5. **实时预览区**：底部展示包含逐字变色的实时渲染预览效果。

---

## 5. 测试与验证策略

1. **单元与微件测试**：
   * `DesktopLyricsSettings` 序列化/反序列化及新增字段默认值；
   * 单行与双行交错渲染的 Widget 测试；
   * 超长歌词跑马灯偏移量计算函数的纯逻辑测试；
   * 逐字变色双层文本渲染逻辑测试；
   * 快捷菜单与锁定悬浮胶囊状态切换测试。
2. **静态分析与质量保证**：
   * 运行 `flutter analyze` 确保 0 errors、0 warnings；
   * 运行全部相关测试用例确保全部 Pass。
