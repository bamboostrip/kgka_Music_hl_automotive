# Windows 音频后端迁移 media_kit 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows 桌面音频后端从 `just_audio_windows`（WinRT MediaPlayer）迁移到 media_kit(libmpv)，删除两处上游崩溃 workaround，并让 Windows 获得与 Linux 一致的响度放大能力。

**Architecture:** 复用 Linux 已有的 vendored `packages/just_audio_media_kit`（上游原生支持 Windows，四处补丁直接生效）。分四个独立 commit 的阶段推进（spike → 删 workaround → 响度合并 → 删旧依赖），每阶段均可独立 revert；`just_audio_windows` 保留到最后一刻作为回退后路。

**Tech Stack:** Flutter 3.44.8 · just_audio ^0.10.4 · media_kit ^1.2.0（经 vendored 适配层）· media_kit_libs_windows_audio ^1.0.9（构建期 CMake 下载 libmpv-2.dll）

**设计文档:** `docs/superpowers/specs/2026-09-11-windows-media-kit-migration-design.md`（本计划的所有改动面均来自其 §3，行号已逐条核验一致）

## Global Constraints

- 本地 HTTP 代理（`music_audio_handler.dart` 的 `_loadViaProxy` 及路由表）**不改**——mpv 直接消费代理 URL。
- 引擎加载串行链 `_enqueueEngineLoad` / `_engineLoadChain` / `seq != _loadSeq` 守卫**保留**——它承载"串行 + 只加载最新"语义，与后端无关；只删 `_performEngineLoad` 内的 Windows 专属分支。
- `audio_service_win`（SMTC）路径不动（`desktop_system_media.dart` 与 just_audio 后端解耦）。
- 每阶段一个独立 commit，阶段结束时 `flutter analyze` 零 issue + 全量 `flutter test` 通过。
- 不修改 `update.md`（应用内更新日志按 RELEASE.md 属发版时动作，无版本号可挂；发版时补条目）。
- R1（归档 DLL 无安全更新）/ R2（GPL 许可风险，已调研证实）/ R3（+15MB）为**发版期决策**，不在本计划内解决；分支实现不发生分发。R2 证据：media-kit 官方 issue #20 确认默认构建为 GPL、社区需自建 LGPL 版。

## 评估结论（已完成）

设计文档的全部事实性声明核验一致：7 处 file:line 引用准确；vendored 包 `ensureInitialized(windows: true)` 原生支持 Windows；四处补丁在副本中齐全；`flutter pub add media_kit_libs_windows_audio --dry-run` 解析干净（"Would change 1 dependency"）；CI（build-windows.yml）在联网 windows-latest 上构建，libmpv 下载无阻塞；测试用 Fake AudioPlayer 且在 Windows 宿主运行，可直接回归 workaround 删除路径。补充发现（设计文档未列）：`lib/ui/settings/playback_settings_section.dart` 的 Windows 响度文案与 `test/ui/pages/settings_desktop_gate_test.dart` 的对应断言需随阶段 2 同步修改。

---

### Task 1: 阶段 0 — spike：依赖 + Windows 注册（保留全部 workaround）

**Files:**
- Modify: `pubspec.yaml:20-33`（依赖注释块 + 新增依赖）
- Modify: `lib/main.dart:108-116`（注册分支 + 音量合成器显示名）

**Interfaces:**
- Consumes: vendored `JustAudioMediaKit.ensureInitialized()` / `.title`（已存在）
- Produces: Windows 运行时使用 media_kit 后端；后续任务删除的 workaround 均以此为先决条件

- [ ] **Step 1: pubspec.yaml 新增依赖并修正注释**

在 `just_audio_media_kit` 注释块首段（原"仅在 main.dart 的 Platform.isLinux 分支注册，不影响 Windows 的 just_audio_windows 后端"两句已失真）替换为双平台表述，并在 `media_kit_libs_linux: ^1.2.1` 之后新增：

```yaml
  # 桌面音频后端：just_audio 官方不出 Linux 平台实现；Windows 官方实现
  # （just_audio_windows，WinRT MediaPlayer）存在高频 setUrl/completed 竞态
  # 崩溃（见 music_audio_handler 引擎加载串行门注释），统一迁移社区
  # media_kit(libmpv) 适配，在 main.dart 的 Linux/Windows 分支注册。
  # Linux 运行期依赖系统 libmpv2；Windows 二进制由
  # media_kit_libs_windows_audio 构建期提供（见下）。
```

（其余四处补丁注释不动。）新增依赖行：

```yaml
  media_kit_libs_linux: ^1.2.1
  # Windows libmpv 二进制（audio-only 构建，libmpv-2.dll 约 15MB）：构建期
  # CMake 从 media-kit/libmpv-win32-audio-build 归档（2023-09-24，MD5 校验）
  # 下载；来源仓库 2024-10 已归档、无升级路径，决策记录见
  # docs/superpowers/specs/2026-09-11-windows-media-kit-migration-design.md。
  media_kit_libs_windows_audio: ^1.0.9
```

- [ ] **Step 2: main.dart 注册 Windows 分支并设置显示名**

替换 `lib/main.dart:108-116`：

```dart
    // Linux/Windows 桌面：统一注册社区 media_kit(libmpv) 后端（见
    # pubspec.yaml 依赖注释）——Linux 无官方实现，Windows 官方实现
    # （WinRT MediaPlayer）存在高频 setUrl/completed 竞态崩溃。必须在
    # 创建首个 AudioPlayer（AudioService.init → MusicAudioHandler 字段
    # 初始化）之前调用。kIsWeb 前置：web 上访问 Platform.* 会直接 throw
    # （当前 web 构建因 dart:io 无法编译，此为防御性收敛，保持与
    # form_factor 判定同构）。
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      // Windows 音量合成器/任务管理器里的进程显示名（mpv 原生侧使用，
      # Linux 忽略）；不设则显示默认的 "JustAudioMediaKit"。
      if (Platform.isWindows) JustAudioMediaKit.title = '时音';
      JustAudioMediaKit.ensureInitialized();
    }
```

- [ ] **Step 3: 解析依赖并跑静态检查/测试**

Run: `flutter pub get && flutter analyze && flutter test`
Expected: analyze 零 issue；测试全绿（此阶段无行为断言变化）

- [ ] **Step 4: Windows 构建冒烟（首次含 libmpv 下载 5.2MB + MD5 校验）**

Run: `flutter build windows --release`
Expected: 构建成功；`build/windows/x64/runner/Release/` 出现 `libmpv-2.dll`（约 15MB）

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart
git commit -m "feat(windows): switch audio backend to media_kit (libmpv) spike

Register just_audio_media_kit on Windows (Linux unchanged) and add
media_kit_libs_windows_audio for the bundled libmpv-2.dll. Both crash
workarounds stay in place until real-machine regression passes; title
set so the volume mixer shows the app name."
```

### Task 2: 阶段 1 — 删除两处 WinRT 竞态 workaround

前置：Task 1 已 commit 且真机/构建冒烟通过（本机 = Windows 真机）。

**Files:**
- Modify: `lib/controllers/player_controller.playback.dart:555-563`（删 100ms completed 延迟）
- Modify: `lib/services/music_audio_handler.dart:314-331,336-337,353-363`（删 250ms 最小间隔与 `_lastEngineLoadAt`）

**Interfaces:**
- Consumes: Task 1 的 mpv 后端
- Produces: 无接口变化（纯删除）；`_handleCompleted` 立即切歌；`_performEngineLoad` 仅保留 seq 守卫 + setUrl + 超时

- [ ] **Step 1: 删除 completed 的 100ms 延迟块**

删除 `lib/controllers/player_controller.playback.dart:555-563` 整块（注释 + `if (Platform.isWindows) {...}`）。删除后 `_handleCompleted` 从睡眠分支直接进入 `playbackMode == PlaybackMode.singleLoop` 判断。`dart:io` 导入在库主文件 `player_controller.dart:3`，其他 part 文件仍在使用，**不要动导入**（analyzer 会兜底报 unused）。

- [ ] **Step 2: 删除引擎加载的 Windows 间隔分支**

`lib/services/music_audio_handler.dart`：
1. 替换 314-331 的段注释与常量（删 `_minEngineLoadGap`）：

```dart
  // ---- 引擎加载串行门 ----------------------------------------------------
  //
  // 桌面统一走 media_kit(libmpv) 后端后，WinRT MediaPlayer 高频 setUrl 的
  # COM 线程竞态崩溃根源已消除，最小加载间隔 workaround 已随迁移删除；
  # 但串行门本身保留——它承载的语义与后端无关：
  // 1. 串行：同一时刻至多一个 setUrl 在 native 侧执行（异步链排队）；
  // 2. 只加载最新：排队期间出现更新的 load 注册时，旧 load 直接跳过
  //    （不碰引擎），上层 playSong 的 hash 守卫会把对应的旧流程收尾。
  // 连点 N 次的净效果：队列里的旧任务瞬间跳过，只有最后一次真正进引擎。
```

2. 删除 336-337 的 `/// 上一次 setUrl 发起时刻（仅 Windows 记录）。` 与 `DateTime? _lastEngineLoadAt;`
3. `_performEngineLoad` 删除 `if (Platform.isWindows) {...}` 块（353-363），保留：

```dart
  Future<void> _performEngineLoad(int seq, String proxyUrl) async {
    if (seq != _loadSeq) return; // 已被更新的加载取代，跳过
    await audioPlayer.setUrl(proxyUrl).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception('音频加载超时，请检查网络后重试');
      },
    );
  }
```

- [ ] **Step 3: 静态检查 + 全量测试（Windows 宿主上即回归 completed 路径）**

Run: `flutter analyze && flutter test`
Expected: analyze 零 issue（若报 `dart:io` unused 则回查其他 Platform 使用）；`player_auto_advance_test` 等全绿

- [ ] **Step 4: 构建 + Commit**

Run: `flutter build windows --release` → 成功

```bash
git add lib/controllers/player_controller.playback.dart lib/services/music_audio_handler.dart
git commit -m "perf(player): drop WinRT crash workarounds now mpv is the backend

Remove the 100ms post-completed delay and the 250ms minimum engine
load gap; both existed to dodge WinRT MediaPlayer COM-thread races
that no longer apply under media_kit. Serial-load chain and seq guard
kept intact (backend-independent semantics)."
```

### Task 3: 阶段 2 — 响度放大平台门控合并（TDD）

**Files:**
- Create: `test/services/loudness_amplify_test.dart`
- Modify: `lib/services/loudness_service.dart:424-431,478-479,501-513,524-534`（门控 + 常量更名 + 注释）
- Modify: `lib/ui/settings/playback_settings_section.dart:107-118`（Windows 文案）
- Modify: `test/ui/pages/settings_desktop_gate_test.dart:190-203`（Windows 文案断言）

**Interfaces:**
- Consumes: `LoudnessService.setEnabled/applyGain`（现有公共 API，签名不变）
- Produces: Windows 放大走 mpv 数字增益（volume >1.0，钳制 2.0）；常量 `_linuxMaxBoostVolume` → `_mpvMaxBoostVolume`（私有，无外部引用）

- [ ] **Step 1: 写失败测试（锁定 Windows 放大行为）**

新建 `test/services/loudness_amplify_test.dart`：

```dart
// 响度均衡放大路径的平台矩阵：Windows 迁移 media_kit(mpv) 后获得与
// Linux 一致的数字放大能力（引擎音量 >1.0，钳制 +6dB ≈ 2.0）。
// 迁移前 Windows 落 AMPLIFY_SKIP（保持用户音量 1.0），本文件锁定迁移后
// 行为，同时锁定 macOS 等无放大能力平台仍走 SKIP。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiyin_music/services/loudness_service.dart';

class _RecordingAudioPlayer extends Fake implements AudioPlayer {
  final volumes = <double>[];
  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumes.add(volume);
  }
}

void main() {
  late _RecordingAudioPlayer player;
  late LoudnessService service;

  setUp(() async {
    player = _RecordingAudioPlayer();
    SharedPreferences.setMockInitialValues({});
    service = LoudnessService();
    await service.init();
    await service.setEnabled(enabled: true, audioPlayer: player);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> apply(double gainDb) => service.applyGain(
        audioPlayer: player,
        audioSessionId: null,
        gainDb: gainDb,
        userVolume: 1.0,
        instant: true,
      );

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('$platform 轻歌走 mpv 数字放大（+4dB → ×1.585）', () async {
      debugDefaultTargetPlatformOverride = platform;
      await apply(4.0);
      expect(player.volumes.single, closeTo(1.5849, 0.001));
    });

    test('$platform 增益钳制 +6dB（+20dB 输入 → ×1.995）', () async {
      debugDefaultTargetPlatformOverride = platform;
      await apply(20.0);
      expect(player.volumes.single, closeTo(1.9953, 0.001));
    });
  }

  test('windows 响歌衰减路径无回归（-3dB → ×0.708）', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await apply(-3.0);
    expect(player.volumes.single, closeTo(0.7079, 0.001));
  });

  test('macOS 无放大能力仍走 SKIP（保持用户音量）', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await apply(4.0);
    expect(player.volumes.single, 1.0);
  });
}
```

- [ ] **Step 2: 运行确认 windows 放大用例失败**

Run: `flutter test test/services/loudness_amplify_test.dart`
Expected: 两个 windows 放大用例 FAIL（实际 setVolume 1.0 ≠ 期望 1.585）；linux 用例与衰减/SKIP 用例 PASS

- [ ] **Step 3: 合并平台门控并更名常量**

`lib/services/loudness_service.dart`：
1. 501 行门控与 502-503 注释：

```dart
    } else if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      // mpv: just_audio volume 1.0 = mpv volume 100; 放大即 >100
      //（vendored just_audio_media_kit 已抬高 volume-max）。
```

（分支体不变，仅 506/509 行日志与 526 常量名里的 `_linuxMaxBoostVolume` 改 `_mpvMaxBoostVolume`）
2. 524-530 常量与 getter：

```dart
  /// mpv 后端放大上限（mpv 音量标量）。+6dB = 2.0；vendored 适配层把
  /// mpv volume-max 抬到 400（=4.0/+12dB），留出钳制后的安全余量。
  static const double _mpvMaxBoostVolume = 2.0;

  /// 平台音量上限（ramp 插值时的 clamp 边界）。mpv 后端（Linux/Windows）
  /// 允许 >1.0；其余后端 0..1。与上方放大门控同用 defaultTargetPlatform，
  /// 保证测试可覆写、两处判定一致。
  static double get _platformMaxVolume =>
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.windows))
      ? _mpvMaxBoostVolume
      : 1.0;
```

3. 同步失真注释：424-431 doc 注释中 Windows 行改为并入 Linux 行（"Linux/Windows(mpv 后端)：<1.0 上限被 vendored 适配层抬高，可数字放大"）；478-479 行注释改"Linux/Windows(mpv 后端)用 mpv 数字放大(>1.0)；iOS/macOS 无放大能力"；532-534 `_setVolumeRamped` doc 中"Linux 放大路径允许 >1.0"改"mpv 后端（Linux/Windows）放大路径允许 >1.0"。

- [ ] **Step 4: 运行新测试确认全绿**

Run: `flutter test test/services/loudness_amplify_test.dart`
Expected: 7 个用例全 PASS

- [ ] **Step 5: 设置页文案与既有断言同步**

`lib/ui/settings/playback_settings_section.dart`（107-118）：Windows case 从 switch 中删除（与默认文案一致），注释同步：

```dart
              // 平台差异如实标注：macOS 无分析通道（Rust 引擎未接入，
              // 见 form_factor.dart 清单）。Windows 迁移 mpv 后端后放大/
              // 衰减能力与 Linux 一致，不再需要差异化文案。
              // 移动端无需显示桌面平台专属限制提示。
              subtitle: !isDesktopFormFactor
                  ? '基于 EBU R128 LUFS 标准化，降低各首歌曲音量差异'
                  : switch (defaultTargetPlatform) {
                      TargetPlatform.macOS => 'macOS 暂不支持响度分析',
                      _ => '基于 EBU R128 LUFS 标准化，降低各首歌曲音量差异',
                    },
```

`test/ui/pages/settings_desktop_gate_test.dart`（"桌面形态在 Windows 平台上展示 Windows 限制提示"用例）：改为断言通用文案、无平台限制文案，用例名同步改为"桌面形态在 Windows 平台上不显示平台限制提示（mpv 后端已支持放大）"：

```dart
        expect(find.text('响度均衡'), findsOneWidget);
        expect(
          find.text('基于 EBU R128 LUFS 标准化，降低各首歌曲音量差异'),
          findsOneWidget,
        );
        expect(find.textContaining('仅支持压低'), findsNothing);
```

- [ ] **Step 6: 全量测试 + 构建 + Commit**

Run: `flutter analyze && flutter test && flutter build windows --release`
Expected: 全绿

```bash
git add lib/services/loudness_service.dart lib/ui/settings/playback_settings_section.dart test/services/loudness_amplify_test.dart test/ui/pages/settings_desktop_gate_test.dart
git commit -m "feat(loudness): unify amplification across mpv backends (Linux+Windows)

Windows now shares the Linux mpv digital-gain path (volume >1.0,
+6dB clamp) instead of skipping amplification; constant renamed
_linuxMaxBoostVolume -> _mpvMaxBoostVolume. Settings copy and gate
test updated to drop the Windows-only limitation note."
```

### Task 4: 阶段 3 — 移除 just_audio_windows 依赖

**Files:**
- Modify: `pubspec.yaml:18-41`（删依赖行、注释块定稿）
- Modify: `lib/main.dart`（注释里 just_audio_windows 迁移表述定稿为现状）
- Modify: `lib/services/music_audio_handler.dart`（如 Task 2 后仍有 just_audio_windows 字样的注释）

**Interfaces:**
- Consumes: Task 1-3 全部已合入且回归通过
- Produces: Windows 只剩 media_kit 一条音频后端路径

- [ ] **Step 1: 删除依赖与失真注释**

`pubspec.yaml`：删除 `just_audio_windows: ^0.2.3` 行；Task 1 的过渡注释（"Windows 官方实现存在…崩溃，统一迁移…"）定稿为：

```yaml
  # 桌面音频后端（Linux/Windows）：just_audio 官方不出桌面平台实现，
  # 统一用社区 media_kit(libmpv) 适配，在 main.dart 的 Linux/Windows 分支
  # 注册。Linux 运行期依赖系统 libmpv2（发行版维护）；Windows 二进制由
  # media_kit_libs_windows_audio 构建期提供（见下）。
```

`lib/main.dart`：注释定稿（去掉"官方实现存在崩溃"的迁移叙述，改为一句历史指引：迁移记录见 docs/superpowers/specs/…design.md）。grep 确认全仓库（lib/、test/）无残留 `just_audio_windows` 引用。

- [ ] **Step 2: 依赖解析 + 静态检查 + 全量测试 + 构建**

Run: `flutter pub get && flutter analyze && flutter test && flutter build windows --release`
Expected: 全绿；lockfile 移除 just_audio_windows

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/services/music_audio_handler.dart
git commit -m "chore(deps): remove just_audio_windows after media_kit migration

Backend fully switched on Windows; lockfile drops the WinRT plugin.
Migration record and measured bundle sizes live in
docs/superpowers/specs/2026-09-11-windows-media-kit-migration-design.md."
```

### Task 5: 全量验证、体积实测与文档收尾

**Files:**
- Modify: `docs/superpowers/specs/2026-09-11-windows-media-kit-migration-design.md`（状态与 §4.3 实测数字）

**Interfaces:**
- Consumes: Task 1-4 的构建产物
- Produces: 验收数据（设计文档 §5 第 5/6/7 条的可自动化部分）

- [ ] **Step 1: 三产物体积实测**

Run: `flutter build windows --release` 后 `du -sh build/windows/x64/runner/Release`；再按 `build_windows.ps1` 的实际产物路径实测 portable.zip 与 setup.exe（脚本产出在 `build/dist/`），记录三组数字与迁移前基线（43MB / 18.6MB / 待实测）对比。

- [ ] **Step 2: 应用冒烟**

启动 Release exe：验证进程存活（libmpv 加载不崩）；如可行用 computer-use 驱动 UI 播放一首歌验证进度推进与切歌。做不到自动播放（无账号/网络受限）则如实标注"待人工真机回归"。

- [ ] **Step 3: 更新设计文档状态**

状态行改"已实施（阶段 0-3，阶段 4 gapless 未做）"；§4.3 待实测单元格填实测值；§8 附 R2 调研结论（GPL 证实，media-kit issue #20）与发版决策提醒。

- [ ] **Step 4: Commit 文档**

```bash
git add docs/superpowers/specs/2026-09-11-windows-media-kit-migration-design.md
git commit -m "docs: record media_kit migration results and measured sizes"
```
