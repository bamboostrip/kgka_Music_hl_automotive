# 播放状态持久化设计

## 概述

用户退出应用后，保留上一次的播放状态（歌单、当前歌曲、播放模式）。重新打开应用时恢复这些状态。结合已有的「自动播放」设置，实现打开应用自动播放上次歌曲的能力。

## 需求

1. **持久化**：退出时保存当前播放队列、当前歌曲索引、播放模式
2. **恢复**：启动时恢复上述状态（无论自动播放是否开启）
3. **自动播放改造**：自动播放从「播放每日推荐」改为「播放上次歌曲」；无保存状态时回退到每日推荐
4. **不记住播放进度**：恢复后从头播放
5. **播放失败处理**：
   - 顺序播放（playlistLoop）→ 切下一首
   - 随机播放（shuffle）→ 随机切下一首
   - 单曲循环（singleLoop）→ 报错提示，不切歌

## 技术方案

### 方案选择：PlayerController 内置持久化

在 `PlayerController` 中直接添加保存/恢复逻辑，使用 `SharedPreferences` 存储 JSON。与现有设置持久化模式（`_restoreSettings` / `setXxx`）完全一致。

### 1. 持久化数据

**SharedPreferences key**: `playback_state`

**JSON 结构**:

```json
{
  "queue": [ /* Song.toCache() 对象数组，最多 200 首 */ ],
  "currentIndex": 3,
  "playbackMode": "shuffle"
}
```

**Song 序列化**：复用现有 `Song.toCache()` / `Song.fromCache`。需在 `toCache()` 中补充 `source` 字段（当前缺失），`fromCache` 中对应恢复。此改动向后兼容——旧缓存数据无 `source` 字段时默认为 `kugou`。

### 2. 保存时机

在 PlayerController 中，以下操作后触发保存（500ms 防抖）：

| 触发点 | 说明 |
|---|---|
| `playSong()` | 切歌 / 设置新队列 |
| `next()` / `previous()` | 手动或自动切歌 |
| `cyclePlaybackMode()` | 切换播放模式 |
| `replaceQueue()` | 替换队列 |
| `addSongsToQueue()` | 添加歌曲到队列 |

**防抖实现**：使用 `Timer`，每次触发时重置 500ms 倒计时，到期后执行一次写入。Timer 在 `PlayerController.dispose()` 中取消。

**队列上限**：保存时截断为最多 200 首，防止 SharedPreferences 写入过大数据。

### 3. 启动恢复

在 `PlayerController` 初始化时，与 `_restoreSettings()` 并行执行 `_restorePlaybackState()`：

1. 从 SharedPreferences 读取 `playback_state` JSON
2. 如果存在且 queue 非空：
   - 反序列化 queue → `List<Song>`（使用 `Song.fromCache`）
   - 设置 `this.queue`
   - 设置 `currentIndex`（越界则 clamp 到有效范围）
   - 设置 `currentSong = queue[currentIndex]`（不播放，仅设置状态）
   - 设置 `playbackMode`
   - `notifyListeners()` → UI 显示上次歌曲信息
3. 如果不存在或为空：不做任何操作

**关键点**：
- 恢复后 `isPlaying = false`，`position = Duration.zero`
- 不需要网络请求，所有数据在本地 JSON 中
- 新增 `hasRestoredPlaybackState` 标志，供自动播放判断

### 4. 自动播放改造

**修改 `HomePage._checkAndAutoPlay()`**：

```
if (autoPlay 开启 && 未自动播放过):
  if (player.hasRestoredPlaybackState):
    → player.resumePlayback()  // 播放已恢复的当前歌曲
  else:
    → 回退到现有逻辑：播放每日推荐
```

**新增 `PlayerController.resumePlayback()` 方法**：

1. 如果 `currentSong == null` 或 `queue` 为空 → 返回 false
2. 尝试播放 `currentSong`（调用 `playSong`，使用已恢复的 queue）
3. 如果播放失败（`playSong` 抛出异常：URL 解析失败、歌曲不可用、网络错误等）：
   - `singleLoop` → 弹出错误提示（SnackBar），不切歌
   - `playlistLoop` → 自动切到下一首，继续尝试
   - `shuffle` → 随机切到下一首，继续尝试
4. 最多尝试 `queue.length` 次，全部失败则停止并提示

### 5. 设置页文案更新

- 当前：「打开应用时自动加载并播放推荐歌单」
- 改为：「打开应用时自动播放上次的歌曲」

## 涉及文件

| 文件 | 改动 |
|---|---|
| `lib/controllers/player_controller.dart` | 新增持久化保存/恢复逻辑、`resumePlayback()` 方法、防抖 Timer |
| `lib/models/music_models.dart` | `Song.toCache()` 补充 `source` 字段，`Song.fromCache` 对应恢复 |
| `lib/ui/pages/home_page.dart` | 修改 `_checkAndAutoPlay()` 逻辑 |
| `lib/ui/pages/settings_page.dart` | 更新自动播放开关的副标题文案 |

## 不在范围内

- 播放进度（歌曲内位置）的持久化
- 播放历史的改动（已有独立服务）
- 多设备同步
