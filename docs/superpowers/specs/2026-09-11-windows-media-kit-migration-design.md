# 时音 Windows 音频后端迁移 media_kit 方案（评估稿）

> 日期：2026-09-11 · 分支：`feature/pc-desktop-adaptation`
> 状态：**已实施（阶段 0-3，见 §9 实施记录；阶段 4 gapless 未做）**。
> 本文数字均为实测（迁移前三产物基线与迁移后数字均经 `flutter clean` 干净构建复测）；
> R1/R2/R3 为**发版期决策**，尚未裁决——见 §9.3。
> 读者：评估方（技术可行性 / 许可与分发 / 回归成本三个维度）。

## 0. 结论摘要（TL;DR）

技术上可行，收益明确（删掉两处上游崩溃的 workaround + Windows 响度均衡获得放大能力），
但**有三个必须先决策的外部依赖问题**，任一不满足都会推翻方案：

| # | 问题 | 现状 |
|---|---|---|
| R1 | libmpv 二进制来源已归档停止更新 | DLL 停留在 2023-09-24，构建仓库 2024-10 归档只读 |
| R2 | 该 DLL 的分发许可未标注 | 归档仓库页面与归档内均无 LICENSE 文件 |
| R3 | 安装包体积 +15 MB（bundle 43 → 58 MB） | 已实测 |

若 R1/R2 不可接受，替代路径见 §4.3；若可接受，实施约 2 天（含真机回归）。

## 1. 现状（迁移前）

### 1.1 两个平台的音频栈不一致

| 平台 | just_audio 平台实现 | 底层引擎 | 项目内的适配补丁 |
|---|---|---|---|
| Windows | `just_audio_windows` ^0.2.3 | WinRT `MediaPlayer`（COM） | 无，但有两处 workaround |
| Linux | `just_audio_media_kit`（本地 vendored） | libmpv | 4 处（见 1.3） |

注册点：`lib/main.dart:114`，仅 Linux 分支调用 `JustAudioMediaKit.ensureInitialized()`。

### 1.2 Windows 侧的两处 workaround（都是上游后端缺陷）

1. **completed 后延迟 100 ms 才能换源** — `lib/controllers/player_controller.playback.dart:560`
   代码注释记录：WinRT `MediaPlayer` 触发 `completed` 时 native 回调仍在后台线程，
   立即 `setUrl()` 会与 COM 平台线程竞态，进程崩溃（`Lost connection to device`）。
   代价：每次自动下一首固定多 100 ms。

2. **引擎加载串行门 + 250 ms 最小间隔** — `lib/services/music_audio_handler.dart:316-370`
   （`_minEngineLoadGap`，仅 Windows 生效于 `:353-362`）
   同根源缺陷：高频 `setUrl`（快速连点切歌）崩溃。
   代价：连点切歌时每次加载最多多等 250 ms。

### 1.3 Linux 侧已有的 media_kit 补丁（迁移后 Windows 直接复用）

`packages/just_audio_media_kit`（本地 fork，版本 `2.1.0+shiyin.4`），四处补丁：
1. `load()` 清空 `_setPosition`（上游 2.1.0 跨歌残留 seek 目标）
2. 构造时 `volume-max=400`（响度放大 +12 dB 余量）
3. `error` 流 `completeError(_loadCompleter)`（上游 load 失败无人 complete，必挂 15 s 超时）
4. `buffering` 流不再把错误态掩盖回 `ready`

### 1.4 响度均衡的现状差异

`lib/services/loudness_service.dart`：

- **Windows：只能衰减，不能放大**。`AMPLIFY` 分支只在 `TargetPlatform.linux` 走
  mpv 数字放大（`:501`）；Windows 落到 `AMPLIFY_SKIP`（`:515-521`），
  轻歌保持用户音量。根因：WinRT `MediaPlayer.Volume` 只接受 `0..1`。
- Linux：mpv 音量上限被补丁抬到 400，`_linuxMaxBoostVolume = 2.0`（`:526`）允许 >1.0。

即：**当前 Windows 上"歌曲偏轻"这一类只能不做处理**。

## 2. 迁移后的收益（逐条可验证）

| # | 收益 | 验证方式 |
|---|---|---|
| B1 | 删掉 completed 的 100 ms 延迟 | 自动下一首的实际间隔（秒表/日志） |
| B2 | 删掉 250 ms 最小加载间隔 | 连点切歌 50 次的耗时与崩溃计数 |
| B3 | Windows 获得响度**放大**能力（与 Linux 一致，±6 dB 钳制） | 轻歌 A/B 听感 + 无削波 |
| B4 | 两个平台一套后端与补丁，维护面减半 | 代码 review |
| B5 | 不再依赖 WinRT COM 线程模型（两处崩溃的根源） | 崩溃场景复现测试 |
| B6 | 可选 gapless（mpv `prefetch-playlist`，官方标注实验性） | 连续曲目切换有无静音间隙 |

## 3. 改动面清单（精确到文件:行）

### 3.1 必须改

| 文件:行 | 现状 | 改为 |
|---|---|---|
| `pubspec.yaml:19` | `just_audio_windows: ^0.2.3` | 阶段 3 移除；新增 `media_kit_libs_windows_audio: ^1.0.9` |
| `lib/main.dart:114` | `if (!kIsWeb && Platform.isLinux)` | 加 `|| Platform.isWindows`；并设 `JustAudioMediaKit.title`（音量合成器显示名，当前默认 `JustAudioMediaKit`） |
| `lib/services/loudness_service.dart:501` | `defaultTargetPlatform == TargetPlatform.linux` | 纳入 windows |
| `lib/services/loudness_service.dart:529-530` | `_platformMaxVolume` 仅 Linux >1.0 | 纳入 windows |
| `lib/services/loudness_service.dart:526` | 常量名 `_linuxMaxBoostVolume` | 更名 `_mpvMaxBoostVolume`（跨平台语义） |
| `lib/controllers/player_controller.playback.dart:560` | 100 ms 延迟 | 阶段 1 删除 |
| `lib/services/music_audio_handler.dart:353-362` | Windows 最小间隔分支 | 阶段 1 删除 |

### 3.2 明确保留（与后端无关）

- **本地 HTTP 代理**（`music_audio_handler.dart:136-312`）：Range 解析、UA/Referer 注入、
  本地文件统一入口。mpv 直接吃 URL，无需改动。
- **串行加载链**（`_enqueueEngineLoad` / `_engineLoadChain`，`music_audio_handler.dart:339-350`）：
  它同时承载"同一时刻只有一个加载在跑 + 只加载最新"的语义，**不是 Windows 专属**，
  不要随 workaround 一起删。只删 `_performEngineLoad` 内的 Windows 分支。
- **`audio_service_win`（SMTC 系统媒体集成）**：`lib/services/desktop_system_media.dart:27`
  是独立插件（实现 `AudioServicePlatform`），与 just_audio 后端解耦 → 理论上不受影响，
  但列为真机必测项（R5）。

### 3.3 阶段划分（便于二分定位与回滚）

| 阶段 | 内容 | 可回滚性 |
|---|---|---|
| 0（spike，0.5 天） | 只加依赖 + 注册 Windows 分支，**保留全部 workaround**，跑通播放 | 改 1 行即可回退 |
| 1（0.5 天） | 真机回归通过后，删 100 ms 延迟与 250 ms 间隔（独立 commit） | 独立 revert |
| 2（0.5 天） | 响度平台门控合并 + 常量更名 | 独立 revert |
| 3（0.25 天） | 移除 `just_audio_windows` 依赖与注释、更新 CHANGELOG | 独立 revert |
| 4（可选） | 评估 gapless | 独立 revert |

每阶段：`flutter analyze` + 全量 `flutter test` + Windows 构建 + 真机冒烟。

## 4. 风险评估（评估重点）

### 4.1 R1：libmpv 二进制的来源与维护状态 — **高风险，需决策**

实测事实：
- `media_kit_libs_windows_audio` **1.0.9 是最新版本**（pub.dev 上发布于约 2 年前），
  它通过 CMake 在 **configure 阶段从 GitHub 下载** libmpv：
  - 归档：`mpv-dev-x86_64-20230924-git-652a1dd.7z`（**5.2 MB**，7z）
  - 来源：`https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/...`
  - 完整性：CMake 内置 MD5 校验（`cd738e16e2a19626d7cfa48801524f8c`）
- 解包后 **`libmpv-2.dll` = 15.0 MB**（audio-only 构建，无视频模块）
- **该构建仓库已于 2024-10 归档（archived / read-only）**，DLL 时间戳停留在 2023-09-24

影响：
- 无上游安全更新。libmpv 处理网络流与容器解析（本地/远程媒体解析面），
  若将来出现 CVE（如 ffmpeg 解码器漏洞），此方案**没有升级路径**（除非自建）。
- 注意：Linux 侧用的是**系统 libmpv2**（发行版维护、会收到安全更新），
  所以"Windows 用这份 2023 归档 DLL"会在安全维护性上**弱于现状的 WinRT 后端**
  （WinRT 编解码器由 Windows 自身维护）。

待评估方选择其一：
- (a) 接受并锁定：记录版本 + MD5 + 归档现状，接受无安全更新
- (b) 换 `media_kit_libs_windows_video` 1.0.11（同样 17 个月前发布且被标记 unlisted，
  体积更大，需重新实测 DLL 大小与是否含视频模块）
- (c) 自建 libmpv（`media-kit/libmpv-win32-video-cmake`、`mpv-build-lite` 路线）：
  维护成本最高，但可控版本与许可

### 4.2 R2：分发许可 — **阻塞项，需法务/决策确认**

- Dart 包自身的 `LICENSE` 是 MIT，**但这不是分发关注点**：
  真正随安装包分发的是 `libmpv-2.dll`（内含 FFmpeg 等）。
- 实测：下载并解包该归档后，**归档内只有 `include/`、`libmpv.dll.a`、`libmpv-2.dll`，
  没有任何 LICENSE / COPYING 文件**；归档仓库页面也未标注许可。
- mpv/FFmpeg 的构建可能含 GPL 组件（取决于编译开关）。若该构建为 GPL，
  闭源分发将受限（现状：本项目私有仓库，但仍建议明确）。

行动项：向评估方确认该 DLL 的 LGPL/GPL 归属；若不可确认，只能走 R1(b)/(c)。

**2026-09-11 调研补充（已证实 GPL 倾向）**：media-kit 官方仓库 issue #20
（"custom libmpv shared libraries"）明确说明默认捆绑构建为 GPL、闭源商业
应用需自建 LGPL 版 libmpv（社区通行做法是 media-autobuild_suite 关闭 GPL
组件）。本项目为私有闭源仓库且对外分发 portable.zip/setup.exe——**若按
(a) 路线发版，需要项目所有者显式接受 GPL 分发风险，或改走 (c) 自建
LGPL libmpv（`ensureInitialized(libmpv:)` 支持自定义 DLL 路径，应用侧
代码无需改动）**。R2 维持"发版阻塞项"评级。

### 4.3 R3：体积 — 已实测（干净构建复测，2026-09-11）

| 项 | 迁移前（干净基线） | 迁移后（干净构建） | 增量 |
|---|---|---|---|
| runner bundle（未压缩） | 42 MB | 57 MB | **+15 MB** |
| `portable.zip` | 18,712,804 B（17.8 MB） | 26,087,281 B（24.9 MB） | **+7.4 MB** |
| `setup.exe`（Inno，lzma2/max + solid） | 15,618,348 B（14.9 MB） | 21,184,770 B（20.2 MB） | **+5.6 MB**（落在预估 +5~7 MB 内） |

对便携版用户（解压覆盖）而言 15 MB 的增量可感知。

> ⚠️ 实测过程中的运维发现：切换依赖变体后不 `flutter clean`，旧 DLL
> （如 libmpv-2.dll / just_audio_windows_plugin.dll）会**残留**在
> `build/windows/x64/runner/Release/` 并被打进新包，产物体积与内容都会
> 失真（首测 setup.exe 仅差 70KB 即此假象）。切换变体后必须 clean 重测。

### 4.4 R4：CI 与构建流程

- CMake configure 阶段需联网访问 GitHub Releases；离线构建会失败。
- `flutter clean` 后重新下载（5.2 MB，已有 MD5 校验）。
- 需确认 CI 网络策略、代理，以及是否需要把归档预置到构建缓存。
- 现有 CI（`build-windows.yml`）已在联网环境，预期无阻塞，但需一次实际跑通验证。

### 4.5 R5：功能回归面（必须真机实测清单）

| 项 | 为什么有风险 |
|---|---|
| SMTC（媒体键 / 音量浮层 / 锁屏） | `audio_service_win` 与后端解耦，但需实测确认 audio session 归属未变 |
| 蓝牙/耳机拔插后播放 | 车机场景核心路径，`audio_session` 设备流与 mpv 输出设备交互需验证 |
| 自动下一首 / 单曲循环 / shuffle | 涉及 completed 语义与 `_handleCompleted` 守卫 |
| seek 精度与倍速、音调 | mpv 走 `scaletempo`（`JustAudioMediaKit.pitch = true`） |
| 进度平滑与歌词时间轴 | 后端切换会改变 `positionStream` 更新节奏，需验证 `_stateSub`/`_positionSub` 守卫仍成立 |
| 音量合成器显示名 | 需设 `JustAudioMediaKit.title`，否则显示为默认名 |
| 代理路径（Range / UA / Referer / 本地文件） | mpv 的 Range 与重定向行为需实测 |
| 响度均衡 | 重点验证**新获得的放大能力**无削波；同时确认衰减路径无回归 |

### 4.6 R6：已知行为差异

- mpv 音量是**数字增益**（无模拟域削波保护）：已有 ±6 dB 钳制与 ramp，
  但听感需 A/B 确认。
- mpv 的 `completed` / buffering 事件语义与 just_audio 的 `ProcessingState`
  映射由 vendored 补丁处理，需实测边界（尤其单曲循环）。

### 4.7 R7：回滚策略

- 阶段 0 只改注册分支 1 行 → 回滚成本极低。
- 阶段 1/2 各自独立 commit → `git revert` 即可。
- 阶段 3（删依赖）最后做，此前 `just_audio_windows` 一直保留 → 全程可一键回退。

## 5. 验收标准（建议写入任务定义）

1. **崩溃场景**：连点切歌 ≥50 次、completed 连续自动推进 ≥20 首，无崩溃、无卡死。
2. **响度**：轻歌放大生效（与 Android/Windows 现状对比 A/B），无削波；
   衰减路径无回归。
3. **系统集成**：SMTC 媒体键、音量浮层、锁屏信息正常；音量合成器显示"时音"。
4. **设备**：蓝牙耳机连接/断开后播放正常（车机场景）。
5. **体积**：实测 bundle / portable.zip / setup.exe 三个数字并记录。
6. **构建**：`flutter clean` 后完整 Windows 构建成功（含 libmpv 下载与 MD5 校验）。
7. **回归**：`flutter analyze` 零 issue；全量 `flutter test` 通过。

## 6. 工作量估算

| 阶段 | 时间 |
|---|---|
| 0 spike（含体积/响度/SMTC 初测） | 0.5 天 |
| 1 删 workaround | 0.25 天 + 回归 |
| 2 响度合并 | 0.25 天 + 回归 |
| 3 依赖清理 | 0.25 天 |
| 真机回归（§5 全清单） | 1 天 |
| **合计** | **约 2~2.5 天** |

不含 R1(b)/(c) 路线所需的额外工作（换包重测约 +0.5 天；自建 libmpv 属独立立项）。

## 7. 待决策问题（给评估方）

1. **R1**：接受 2023-09-24 归档 libmpv（无安全更新），还是走 (b) 换 video 包 / (c) 自建？
2. **R2**：该 DLL 的 LGPL/GPL 归属是否满足本项目的分发要求？
3. **R3**：安装包 +15 MB（未压缩）/ portable.zip 约 +6 MB 是否可接受？
4. 是否接受"Windows 用 mpv、其他平台不变"的过渡形态（阶段 0-2 期间）？
5. 是否需要保留 `just_audio_windows` 作为长期回退后路（即阶段 3 是否推迟）？

## 8. 附：本文实测数据来源

| 数据 | 获取方式 |
|---|---|
| libmpv 归档 5.2 MB | `curl -sIL` 读 `Content-Length` = 5392413 |
| libmpv-2.dll 15 MB | 下载归档后 `cmake -E tar xf` 解包，`ls -lh` = 15525902 字节 |
| 归档内容清单（无 LICENSE） | `cmake -E tar tf` 列出：`include/`、`libmpv.dll.a`、`libmpv-2.dll` |
| 现有 bundle 43 MB / portable.zip 18.6 MB | `du -sh build/windows/x64/runner/Release`、`ls -la build/dist/` |
| 依赖可解析（无版本冲突） | `flutter pub add media_kit_libs_windows_audio --dry-run` → `+ media_kit_libs_windows_audio 1.0.9` |
| 构建仓库已归档 | 归档仓库页面标注 archived 2024-10-09 |
| 包最新版本 1.0.9（约 2 年前） | pub.dev versions 页面 |

## 9. 实施记录（2026-09-11，分支 `feature/pc-desktop-adaptation`）

### 9.1 提交序列（每阶段独立可 revert）

| 提交 | 阶段 | 内容 |
|---|---|---|
| `4903878` | 0 | 加 `media_kit_libs_windows_audio` + main.dart Windows 注册 + `title='时音'` |
| `c3089e1` | 1 | 删 completed 100ms 延迟与 250ms 最小加载间隔（串行链/seq 守卫保留） |
| `fea1a23` | 2 | 响度放大门控合并（Windows 共享 mpv 数字放大，`_mpvMaxBoostVolume`）+ 设置页文案 + 新增 `test/services/loudness_amplify_test.dart`（6 用例）+ 门控断言更新 |
| `e20c5d8` | 3 | 移除 `just_audio_windows`（含 windows/flutter 生成文件同步） |

每阶段后 `flutter analyze` 零 issue + 全量 `flutter test` 通过（790 → 796 个）。

### 9.2 真机验证结果（本机 Windows，自动化部分）

| 项 | 结果 |
|---|---|
| 后端注册 | 日志确认 `media_kit_libs_windows_audio registered` |
| 播放链路 | mpv 详细日志确认 代理(audio/mpeg) → mp3 解码 → WASAPI 出声；系统音频峰值表实测非零波动 |
| completed 自动推进（B1） | 实测 `没有如果` 播完自动切到 `趁早 (2005版)`，无崩溃（无 100ms workaround） |
| 连点切歌（B2） | 8 次 130ms 间隔 Ctrl+→ 快速切歌无崩溃，播放恢复 |
| 坏源自动前进 | 失效 URL 自动跳下一首的恢复链正常 |
| SMTC | mediaItem 标题推送正常（外部 SMTC 探针全程可读） |
| mpv 非致命噪声 | `lavf: Failed to create file cache`（文件后备缓存创建失败，回退内存缓存，播放不受影响）与 `_setProperty(osc, 1) property not found`（audio-only 构建无 osc 属性）——均可忽略 |

### 9.3 发版前遗留（需人工/决策）

1. **R1/R2/R3 决策**（见 §7）：GPL 分发风险为闭源发版的硬阻塞，未裁决前不得发版。
2. 人工听感与交互回归：媒体键/锁屏/音量浮层交互、蓝牙拔插（车机）、seek 精度与倍速/音调、歌词时间轴同步、响度放大 A/B 听感（§4.5 R5/R6 清单）。
3. `update.md` 应用内更新日志条目：按 RELEASE.md 属发版动作，未随本迁移添加。
4. 阶段 4（gapless，`prefetch-playlist` 实验特性）未实施。
5. 本机网络受限提示：pub.dev/GitHub 直连不可达，依赖经 pub.flutter-io.cn 镜像解析后
   将 lockfile URL 回写为 pub.dev（lockfile 仅 8 行净增，无传递依赖搅动）；libmpv 归档
   经 ghfast.top 镜像下载并经 MD5 校验一致。CI（GitHub 托管机）无此问题。
