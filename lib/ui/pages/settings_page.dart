import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/download_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/local_music_controller.dart';
import '../../services/app_update_service.dart';
import '../../services/cache_service.dart';
import '../../services/music_api.dart';
import '../widgets/adaptive_content_padding.dart';
import 'about_page.dart';
import 'audio_interruption_settings_page.dart';
import 'desktop_lyrics_settings_page.dart';
import 'personalization_settings_page.dart';
import 'playback_history_page.dart';
import 'playback_stats_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.theme,
    required this.localMusic,
    this.cache,
    this.downloads,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final ThemeController theme;
  final LocalMusicController localMusic;
  final CacheService? cache;
  final DownloadController? downloads;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: colorScheme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: colorScheme.brightness == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: AnimatedBuilder(
          animation: Listenable.merge([auth, player, localMusic, theme, auth.vipClaim]),
          builder: (context, _) {
            return AdaptiveContentPadding(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Account section
                  _SectionHeader(title: '账号'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.sync_rounded,
                        iconColor: colorScheme.primary,
                        title: '同步个人信息',
                        subtitle: '刷新头像、昵称和歌单数据',
                        loading: auth.isLoading,
                        onTap: auth.isLoading ? null : () => auth.refreshProfile(),
                      ),
                      _SettingsDivider(),
                      _SettingsSwitchTile(
                        icon: Icons.card_giftcard_rounded,
                        iconColor: colorScheme.primary,
                        title: '自动领取VIP',
                        subtitle: auth.vipClaim.statusText(),
                        value: auth.vipClaim.autoEnabled,
                        onChanged: auth.vipClaim.setAutoEnabled,
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.redeem_rounded,
                        iconColor: colorScheme.primary,
                        title: '立即领取',
                        subtitle: auth.vipClaim.lastMessage,
                        loading: auth.vipClaim.isClaiming,
                        onTap: auth.vipClaim.isClaiming
                            ? null
                            : () => _claimVipNow(context),
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.logout_rounded,
                        iconColor: colorScheme.error,
                        title: '退出登录',
                        titleColor: colorScheme.error,
                        onTap: auth.isLoading ? null : () => _confirmLogout(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Playback section
                  _SectionHeader(title: '播放'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.high_quality_rounded,
                        iconColor: colorScheme.primary,
                        title: '默认音质',
                        subtitle: player.audioQuality.label,
                        onTap: () => _selectDefaultAudioQuality(context),
                      ),
                      _SettingsDivider(),
                      _SettingsSwitchTile(
                        icon: Icons.bar_chart_rounded,
                        iconColor: colorScheme.primary,
                        title: '增加听歌时长',
                        subtitle: '每播放 30 分钟自动同步一次',
                        value: player.addListeningTimeEnabled,
                        onChanged: player.setAddListeningTimeEnabled,
                      ),
                      if (player.isDesktopLyricsSupported) ...[
                        _SettingsDivider(),
                        _SettingsSwitchTile(
                          icon: Icons.tv_rounded,
                          iconColor: colorScheme.primary,
                          title: '桌面歌词',
                          subtitle: '在桌面/锁屏上显示歌词',
                          value: player.desktopLyricsEnabled,
                          onChanged: player.setDesktopLyricsEnabled,
                        ),
                      ],
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.timer_rounded,
                        iconColor: colorScheme.primary,
                        title: '睡眠定时器',
                        subtitle: player.sleepTimerLabel,
                        onTap: () => _selectSleepTimer(context),
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.volume_up_rounded,
                        iconColor: colorScheme.primary,
                        title: '音频中断处理',
                        subtitle: '通话音、闹钟、勿扰模式',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AudioInterruptionSettingsPage(player: player),
                          ),
                        ),
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.equalizer_rounded,
                        iconColor: colorScheme.primary,
                        title: '均衡器',
                        subtitle: player.equalizerLabel,
                        onTap: () => _showEqualizerSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Local section
                  _SectionHeader(title: '本地'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.download_rounded,
                        iconColor: colorScheme.primary,
                        title: '下载歌曲',
                        subtitle: downloads?.downloadCountLabel ?? '连接可用',
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.folder_rounded,
                        iconColor: colorScheme.primary,
                        title: '本地歌曲',
                        subtitle: localMusic.songs.isNotEmpty
                            ? '${localMusic.songs.length} 首歌曲'
                            : '扫描本地音乐文件',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LocalSongsPage(api: api, localMusic: localMusic),
                          ),
                        ),
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.downloading_rounded,
                        iconColor: colorScheme.primary,
                        title: '已下载歌曲',
                        subtitle: downloads?.downloadCountLabel ?? '暂无下载',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DownloadedSongsPage(api: api, downloads: downloads!, player: player),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Network section
                  _SectionHeader(title: '网络'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.wifi_rounded,
                        iconColor: colorScheme.primary,
                        title: '仅使用 Wi-Fi 下载',
                        subtitle: player.wifiOnlyLabel,
                        onTap: () => _toggleWifiOnly(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Cache section
                  _SectionHeader(title: '缓存'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.storage_rounded,
                        iconColor: colorScheme.primary,
                        title: '管理缓存数据',
                        subtitle: cache != null ? '${cacheSize(cache!)}' : null,
                        onTap: () => _showCacheManagementSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Personalization section
                  _SectionHeader(title: '个性化'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.palette_rounded,
                        iconColor: colorScheme.primary,
                        title: '个性化设置',
                        subtitle: '主题、配色、字体',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PersonalizationSettingsPage(theme: theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // App section
                  _SectionHeader(title: '应用'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.history_rounded,
                        iconColor: colorScheme.primary,
                        title: '播放历史',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PlaybackHistoryPage(),
                          ),
                        ),
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.bar_chart_rounded,
                        iconColor: colorScheme.primary,
                        title: '播放统计',
                        subtitle: '记录你的播放习惯',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PlaybackStatsPage(),
                          ),
                        ),
                      ),
                      _SettingsDivider(),
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        iconColor: colorScheme.primary,
                        title: '关于',
                        subtitle: '版本 2.4.0',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AboutPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _selectDefaultAudioQuality(BuildContext context) async {
    final qualities = AudioQuality.values;
    final current = player.audioQuality;

    final selected = await showModalBottomSheet<AudioQuality>(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('默认音质', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...qualities.map((quality) {
              return ListTile(
                title: Text(quality.label),
                trailing: quality == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(context).pop(quality),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );

    if (selected != null && selected != current) {
      await player.setAudioQuality(selected);
    }
  }

  Future<void> _selectSleepTimer(BuildContext context) async {
    final options = [
      (label: '关闭', duration: Duration.zero),
      (label: '15 分钟', duration: const Duration(minutes: 15)),
      (label: '30 分钟', duration: const Duration(minutes: 30)),
      (label: '45 分钟', duration: const Duration(minutes: 45)),
      (label: '60 分钟', duration: const Duration(minutes: 60)),
      (label: '当前歌曲播放完', duration: const Duration(minutes: -1)),
    ];

    final selected = await showModalBottomSheet<Duration>(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('睡眠定时器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...options.map((option) {
              return ListTile(
                title: Text(option.label),
                trailing: player.sleepTimerDuration == option.duration
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(option.duration),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );

    if (selected != null) {
      await player.setSleepTimer(selected);
    }
  }

  Future<void> _toggleWifiOnly(BuildContext context) async {
    await player.setWifiOnlyDownload(!player.wifiOnlyDownload);
  }

  Future<void> _showEqualizerSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EqualizerSheet(player: player),
    );
  }

  Future<void> _showCacheManagementSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CacheManagementSheet(cache: cache, downloads: downloads),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确定要退出当前账号吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出登录'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;
    await auth.logout();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _claimVipNow(BuildContext context) async {
    final result = await auth.vipClaim.claimNow(auth.session);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message), duration: const Duration(seconds: 3)),
    );
  }
}

// --- Shared widgets ---

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.loading = false,
    this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool loading;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: loading
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colorScheme.primary,
                      ),
                    )
                  : Icon(icon, size: 22, color: iconColor ?? colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.iconColor,
    this.subtitle,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Icon(icon, size: 22, color: iconColor ?? colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 62,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4),
    );
  }
}

/// 缓存管理 BottomSheet。
class _CacheManagementSheet extends StatefulWidget {
  const _CacheManagementSheet({this.cache, this.downloads});

  final CacheService? cache;
  final DownloadController? downloads;

  @override
  State<_CacheManagementSheet> createState() => _CacheManagementSheetState();
}

class _CacheManagementSheetState extends State<_CacheManagementSheet> {
  String? _cacheSize;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    if (widget.cache == null) return;
    final size = await widget.cache!.size();
    if (!mounted) return;
    setState(() {
      _cacheSize = cacheSize(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '缓存管理',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_cacheSize != null) ...[
            Text('缓存大小: $_cacheSize'),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: () async {
              await widget.cache?.clear();
              if (!mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('清除缓存'),
          ),
        ],
      ),
    );
  }
}

class _EqualizerSheet extends StatefulWidget {
  const _EqualizerSheet({required this.player});

  final PlayerController player;

  @override
  State<_EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<_EqualizerSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '均衡器',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('启用均衡器'),
            value: widget.player.equalizerEnabled,
            onChanged: (value) => widget.player.setEqualizerEnabled(value),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 缓存容量格式化。
String cacheSize(CacheService cache) => '';