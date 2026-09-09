# 桌面播放栏交互与视觉精细化设计

本文档定义桌面端播放栏（`DesktopPlayerBar`）的四项视觉与交互重构规范：
1. 进度条宽度收敛至居中紧凑宽度；
2. 音量控制移动到播放控制行“下一首”按钮右侧；
3. 竖向音量弹出气泡（支持垂直滑块、百分比展示、底部静音、以及非阻塞点击外部关闭）；
4. 封面悬停图标重构为截图 3 风格的对角直角括号展开图标。

---

## 1. 进度条宽度收敛（Progress Bar Layout）

### 现状与痛点
当前 `desktop_player_bar.dart` 中间列使用 `Expanded`，导致内部 `_ProgressBar` 在桌面宽屏（>1200px）时横向撑满数百像素，拖拽跨度过大且与上方居中的控制按钮视觉比例失调。

### 设计规范
- `_ProgressBar` 外层通过 `ConstrainedBox(constraints: BoxConstraints(maxWidth: 440))` 施加最大宽度限制，并在中间列保持居中对齐（`Alignment.center`）。
- 左右保留当前时间与总时长文本（使用 `tabularFigures` 等宽对齐），中间放置带有高潮标记的 Slider 与悬停时间气泡（`HoverTimeBubble`）。
- 在屏幕窗口极窄导致可用宽度不足 440px 时，进度条自适应收缩至可用宽度，不发生溢出。

---

## 2. 播放控制行重构与音量入口迁移

### 布局结构
中间播放控制行由 4 按钮扩展为 5 按钮排列，全部居中分布：
1. `PlayModeButton`（播放模式循环/随机/单曲）
2. `IconButton`（上一首）
3. `IconButton`（播放/暂停，突出尺寸）
4. `IconButton`（下一首）
5. `VolumePopoverButton`（音量调节入口）

按钮间距保持一致（`SizedBox(width: 16)` 或 `20`）。

### 右侧功能区瘦身
原右侧 `_VolumeControl`（横向滑杆 + 图标）彻底移除。右侧保留：
- `_AudioQualityButton`（音质切换）
- `_EffectsButton`（音效入口，受支持平台）
- `_DesktopLyricsButton`（桌面歌词开关，受支持平台）
- `IconButton`（播放队列）

---

## 3. 竖向音量调节弹出面板（Volume Popover）

### 视觉构造（参考截图 2）
- **定位**：通过 `OverlayPortal` + `CompositedTransformTarget` / `CompositedTransformFollower` 锚定在音量图标正上方，居中对齐，与图标保留 8px 间距。
- **气泡卡片样式**：
  - 尺寸：宽 52px，高 184px（含底部小三角尖角）。
  - 背景：浅色主题为白色 `Colors.white`，暗色主题为 `Color(0xFF262D3D)` / `colorScheme.surfaceContainer`。
  - 投影与边框：圆角 10px，微妙边框与投影（`boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]`）。
  - 底部小三角：气泡底部中心向下延伸高 6px、底宽 10px 的三角小箭头，直指下方的音量图标。
- **内部纵向元素**（由上至下）：
  1. **垂直 Slider**：使用 `RotatedBox(quarterTurns: 3)` 包裹精简版 `Slider`，高度 100px。滑动条向上滑音量增大，向下滑音量减小；滑块与激活轨使用品牌主色（`colorScheme.primary`），非激活轨使用浅灰色。
  2. **音量百分比**：`Text('${(volume * 100).round()}%')`，字号 12，加粗字体，等宽数字排版。
  3. **静音切换按钮**：底部 `IconButton`，图标随音量状态变化（静音时为静音图标，非静音为喇叭图标）。点击调用现有 `toggleMute` 逻辑，记录并恢复静音前音量。
- **滚轮支持**：在面板任意区域滚动滚轮，均触发 `applyVolumeWheel` 进行 ±5% 微调，与桌面操作习惯高度统一。

### 核心交互机制：非阻塞关闭（Non-blocking Dismiss）
- 音量卡片使用 Flutter `TapRegion`（`groupId: 'desktop_volume_popover'`）。
- 底栏上的音量按钮本体同样加入同一个 `TapRegion`。
- 当面板打开时：
  - 用户点击音量面板内部：正常调节音量或静音，面板保持开启。
  - 用户点击底栏音量按钮：触发切换，关闭面板。
  - **用户点击界面任意其他区域（空白处、播放列表、切歌按钮、页面菜单等）**：`onTapOutside` 触发关闭面板；同时**该点击事件不会被吞掉或拦截**，正常透传给目标组件执行原有动作。
- 当面板处于展开状态时，底栏上的音量图标切换为 `colorScheme.primary` 主色高亮展示，关闭后恢复常规图标色。

---

## 4. 封面悬停展开图标重构（Cover Hover Icon）

### 视觉特征（参考截图 3）
- 封面尺寸 48x48，悬停时浮出 `Colors.black.withValues(alpha: .45)` 遮罩层。
- 遮罩层中央将原先的 `Icons.open_in_full_rounded` 替换为专属绘制的对角直角括号展开图标（`_ExpandDetailIcon`）：
  - 绘制两个对角直角：
    - **左下角 `└`**：自左边中偏下垂直向下，再向右拐出水平线段。
    - **右上角 `┐`**：自上边中偏右水平向右，再向下拐出垂直线段。
  - 规格：外框 18x18，线条粗细 2.0，纯白色 `Colors.white`，端点与转角采用圆角（`StrokeCap.round`, `StrokeJoin.round`）。
- 悬停浮现 tooltip 提示“展开歌曲详情页”，点击触发 `_openPlayerPage` 进入全屏播放页，原有业务逻辑保持不变。

---

## 5. 验证标准

1. **视觉保真度**：
   - 悬停封面图标与截图 3 完全一致（左下、右上直角折线）。
   - 音量面板气泡、滑块、百分比与静音按钮与截图 2 布局与比例一致。
   - 进度条宽度适度收敛，与上方播放控制行居中和谐。
2. **交互无阻断**：
   - 音量面板弹出时，点击底栏“下一首”或空白区域，不仅面板即时收起，且“下一首”指令正常触发切歌。
   - 音量调节百分比与播放器真实音量实时同步，静音按钮能正确记忆恢复音量。
3. **自动化测试**：
   - 运行现存 `test/ui/desktop/desktop_player_bar_test.dart` 及增强针对新布局与面板行为的单元测试。
