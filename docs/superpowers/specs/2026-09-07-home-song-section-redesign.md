# 推荐页「大家都在听」卡片化紧凑布局设计规范

## 1. 概述与目标

将推荐页原「母带音质·精选」板块全面重构为 QQ 音乐风格的「大家都在听」板块。
- 文案统一更名为「大家都在听」。
- 每列/每组展示数量由原有的 5 首改为 **3 首**。
- 单曲条目（`HomeSongRow`）尺寸轻量化与紧凑化，行高从 76px 压缩至 ~58-60px，整体板块高度大幅降低（从 380px 降至 ~180px 左右）。
- 翻页交互采用 QQ 音乐经典卡片露边轮播（`viewportFraction: 0.92`），在右侧微露下一页边缘约 8%，传递自然的横滑翻页线索，并与现有项目的 UI 视觉质感和暗色/浅色主题风格严格保持统一。

## 2. 详细设计

### 2.1 模块文案与入口
- 标题由 `母带音质·精选` 改为 `大家都在听`（移动端 Tab 0 推荐流与车机模式同步修改）。
- 保留标题右侧的圆形播放全部按钮（`_CirclePlayButton`），点击播放该模块全部歌曲并将队列传入播放器。

### 2.2 歌曲单行（HomeSongRow）紧凑化规格
- **封面尺寸**：
  - 移动端/车机端由 58px 调整为 **48px**（桌面端调整为 44px）。
  - 圆角统一保持 8px（桌面端 6px）。
  - 封面角标 `NowPlayingBadge` 尺寸由 13px 微调为 12px。
- **行高与内边距**：
  - 垂直 padding 由 9px 调整为 **5px**，水平 padding 保持 8px。
  - 单行实际渲染高度约 58px（48 + 5*2），较原 76px 缩减 23.7%。
- **文字排版与间距**：
  - 封面与文字的水平间距由 12px 调整为 **10px**。
  - 歌名字号：移动端 15px (FontWeight.w600/w700)，桌面端 14px。
  - 歌手字号：移动端 12.5px (FontWeight.w500)，桌面端 12px。
  - 歌名与歌手垂直间距由 4px 调整为 **3px**。
- **操作按钮紧凑化**：
  - 收藏（爱心）图标大小由 27px（桌面 22px）调整为 **22px**（桌面 20px）。
  - 更多（`...`）图标大小由 24px（桌面 20px）调整为 **20px**（桌面 18px）。
  - 按钮间的间距与 `visualDensity` 保持紧凑，避免在窄屏挤占歌名空间。

### 2.3 卡片露边横滑布局（QQ 音乐风格）
- `_SongSectionState` 中的 `PageController` 调整为 `PageController(viewportFraction: 0.92)`。
- 轮播高度：`3 * 60.0 = 180.0px`（原为 `rowCount * 76.0 = 380.0px`）。
- 每页歌曲项计算：
  - 窄屏/移动端：`crossAxisCount = 1`，`itemsPerPage = 3`（原为 5）。
  - 宽屏响应式：
    - `maxWidth >= 1050`：`crossAxisCount = 3`，`itemsPerPage = 9`（3 列 × 每列 3 首）。
    - `maxWidth >= 650`：`crossAxisCount = 2`，`itemsPerPage = 6`（2 列 × 每列 3 首）。
    - 其他：`crossAxisCount = 1`，`itemsPerPage = 3`。
- 卡片间隙：每页子卡片增加左右 4~6px padding/margin，确保与露出的下一页卡片有清晰自然的呼吸感。
- 支持桌面平台横向滚轮适配组件 `HorizontalWheelPageScroll`。

## 3. 测试与验证
- 单元与 Widget 测试：
  - 更新 `test/ui/pages/home_page_tabs_swipe_test.dart` 中对标题的查找断言（`大家都在听`）。
  - 运行 `flutter test` 确保全绿。
  - 运行 `flutter analyze` 确保 0 errors, 0 warnings。
