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
                      onTap:
                          auth.isLoading ? null : () => auth.refreshProfile(),
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
                      onTap: auth.isLoading
                          ? null
                          : () => _confirmLogout(context),
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
                    if (player.isDesktopLyricsSupported: '增加听歌时长',\n                      subtitle: '每播放 30 分钟自动同步一次',\n                      value: player.addListeningTimeEnabled,\n                      onChanged: player.setAddListeningTimeEnabled,\n                    ),\n                    if (player.isDesktopLyricsSupported) ...[
                      _SettingsDivider(),\n                      _SettingsSwitchTile(\n                        icon: Icons.tv_rounded,\n                        iconColor: colorScheme.primary,\n                        title: '桌面歌词',\n                        subtitle: '在桌面/锁屏上显示歌词',\n                        value: player.desktopLyricsEnabled,\n                        onChanged: player.setDesktopLyricsEnabled,\n                      ),\n                    ],\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.timer_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '睡眠定时器',\n                      subtitle: player.sleepTimerLabel,\n                      onTap: () => _selectSleepTimer(context),\n                    ),\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.volume_up_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '音频中断处理',\n                      subtitle: '通话音、闹钟、勿扰模式',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => AudioInterruptionSettingsPage(\n                            player: player,\n                          ),\n                        ),\n                      ),\n                    ),\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.equalizer_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '均衡器',\n                      subtitle: player.equalizerLabel,\n                      onTap: () => _showEqualizerSheet(context),\n                    ),\n                  ],\n                ),\n                const SizedBox(height: 24),\n                // Local section\n                _SectionHeader(title: '本地'),\n                const SizedBox(height: 8),\n                _SettingsCard(\n                  children: [\n                    _SettingsTile(\n                      icon: Icons.download_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '下载歌曲',\n                      subtitle: downloads?.downloadCountLabel ?? '连接可用',\n                    ),\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.folder_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '本地歌曲',\n                      subtitle: localMusic.songs.isNotEmpty\n                          ? '${localMusic.songs.length} 首歌曲'\n                          : '扫描本地音乐文件',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => LocalSongsPage(\n                            api: api,\n                            localMusic: localMusic,\n                          ),\n                        ),\n                      ),\n                    ),\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.downloading_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '已下载歌曲',\n                      subtitle: downloads?.downloadCountLabel ?? '暂无下载',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => DownloadedSongsPage(\n                            api: api,\n                            downloads: downloads!,\n                            player: player,\n                          ),\n                        ),\n                      ),\n                    ),\n                  ],\n                ),\n                const SizedBox(height: 24),\n                // Network section\n                _SectionHeader(title: '网络'),\n                const SizedBox(height: 8),\n                _SettingsCard(\n                  children: [\n                    _SettingsTile(\n                      icon: Icons.wifi_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '仅使用 Wi-Fi 下载',\n                      subtitle: player.wifiOnlyLabel,\n                      onTap: () => _toggleWifiOnly(context),\n                    ),\n                  ],\n                ),\n                const SizedBox(height: 24),\n                // Cache section\n                _SectionHeader(title: '缓存'),\n                const SizedBox(height: 8),\n                _SettingsCard(\n                  children: [\n                    _SettingsTile(\n                      icon: Icons.storage_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '管理缓存数据',\n                      subtitle: cache != null ? '${cacheSize(cache!)}' : null,\n                      onTap: () => _showCacheManagementSheet(context),\n                    ),\n                  ],\n                ),\n                const SizedBox(height: 24),\n                // Personalization section\n                _SectionHeader(title: '个性化'),\n                const SizedBox(height: 8),\n                _SettingsCard(\n                  children: [\n                    _SettingsTile(\n                      icon: Icons.palette_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '个性化设置',\n                      subtitle: '主题、配色、字体',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => PersonalizationSettingsPage(\n                            theme: theme,\n                          ),\n                        ),\n                      ),\n                    ),\n                  ],\n                ),\n                const SizedBox(height: 24),\n                // App section\n                _SectionHeader(title: '应用'),\n                const SizedBox(height: 8),\n                _SettingsCard(\n                  children: [\n                    _SettingsTile(\n                      icon: Icons.history_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '播放历史',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => const PlaybackHistoryPage(),\n                        ),\n                      ),\n                    ),\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.bar_chart_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '播放统计',\n                      subtitle: '记录你的播放习惯',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => const PlaybackStatsPage(),\n                        ),\n                      ),\n                    ),\n                    _SettingsDivider(),\n                    _SettingsTile(\n                      icon: Icons.info_outline_rounded,\n                      iconColor: colorScheme.primary,\n                      title: '关于',\n                      subtitle: '版本 2.4.0',\n                      onTap: () => Navigator.of(context).push(\n                        MaterialPageRoute(\n                          builder: (_) => const AboutPage(),\n                        ),\n                      ),\n                    ),\n                  ],\n                ),\n              ],\n              ),\n            );\n          },\n        ),\n      ),\n    );\n  }\n\n  Future<void> _selectDefaultAudioQuality(BuildContext context) async {\n    final qualities = AudioQuality.values;\n    final current = player.audioQuality;\n\n    final selected = await showModalBottomSheet<AudioQuality>(\n      context: context,\n      builder: (context) {\n        return Column(\n          mainAxisSize: MainAxisSize.min,\n          children: [\n            const Padding(\n              padding: EdgeInsets.all(16),\n              child: Text(\n                '默认音质',\n                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),\n              ),\n            ),\n            ...qualities.map((quality) {\n              return ListTile(\n                title: Text(quality.label),\n                trailing: quality == current\n                    ? const Icon(Icons.check_rounded)\n                    : null,\n                onTap: () => Navigator.of(context).pop(quality),\n              );\n            }),\n            const SizedBox(height: 16),\n          ],\n        );\n      },\n    );\n\n    if (selected != null && selected != current) {\n      await player.setAudioQuality(selected);\n    }\n  }\n\n  Future<void> _selectSleepTimer(BuildContext context) async {\n    final options = [\n      (label: '关闭', duration: Duration.zero),\n      (label: '15 分钟', duration: const Duration(minutes: 15)),\n      (label: '30 分钟', duration: const Duration(minutes: 30)),\n      (label: '45 分钟', duration: const Duration(minutes: 45)),\n      (label: '60 分钟', duration: const Duration(minutes: 60)),\n      (label: '当前歌曲播放完', duration: const Duration(minutes: -1)),\n    ];\n\n    final selected = await showModalBottomSheet<Duration>(\n      context: context,\n      builder: (context) {\n        return Column(\n          mainAxisSize: MainAxisSize.min,\n          children: [\n            const Padding(\n              padding: EdgeInsets.all(16),\n              child: Text(\n                '睡眠定时器',\n                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),\n              ),\n            ),\n            ...options.map((option) {\n              return ListTile(\n                title: Text(option.label),\n                trailing: player.sleepTimerDuration == option.duration\n                    ? const Icon(Icons.check_rounded)\n                    : null,\n                onTap: () => Navigator.of(context).pop(option.duration),\n              );\n            }),\n            const SizedBox(height: 16),\n          ],\n        );\n      },\n    );\n\n    if (selected != null) {\n      await player.setSleepTimer(selected);\n    }\n  }\n\n  Future<void> _toggleWifiOnly(BuildContext context) async {\n    await player.setWifiOnlyDownload(!player.wifiOnlyDownload);\n  }\n\n  Future<void> _showEqualizerSheet(BuildContext context) async {\n    await showModalBottomSheet(\n      context: context,\n      isScrollControlled: true,\n      builder: (context) => _EqualizerSheet(player: player),\n    );\n  }\n\n  Future<void> _showCacheManagementSheet(BuildContext context) async {\n    await showModalBottomSheet(\n      context: context,\n      isScrollControlled: true,\n      builder: (context) => _CacheManagementSheet(\n        cache: cache,\n        downloads: downloads,\n      ),\n    );\n  }\n\n  Future<void> _confirmLogout(BuildContext context) async {\n    final confirmed = await showDialog<bool>(\n      context: context,\n      builder: (dialogContext) {\n        return AlertDialog(\n          title: const Text('退出登录'),\n          content: const Text('确定要退出当前账号吗？'),\n          actions: [\n            TextButton(\n              onPressed: () => Navigator.of(dialogContext).pop(false),\n              child: const Text('取消'),\n            ),\n            FilledButton(\n              onPressed: () => Navigator.of(dialogContext).pop(true),\n              child: const Text('退出登录'),\n            ),\n          ],\n        );\n      },\n    );\n\n    if (confirmed != true || !context.mounted) return;\n    await auth.logout();\n    if (!context.mounted) return;\n    Navigator.of(context).popUntil((route) => route.isFirst);\n  }\n\n  Future<void> _claimVipNow(BuildContext context) async {\n    final result = await auth.vipClaim.claimNow(auth.session);\n    if (!context.mounted) return;\n    ScaffoldMessenger.of(context).showSnackBar(\n      SnackBar(content: Text(result.message), duration: const Duration(seconds: 3)),\n    );\n  }\n}\n\n// --- Shared widgets ---\n\nclass _SectionHeader extends StatelessWidget {\n  const _SectionHeader({required this.title});\n\n  final String title;\n\n  @override\n  Widget build(BuildContext context) {\n    return Padding(\n      padding: const EdgeInsets.only(left: 4),\n      child: Text(\n        title,\n        style: Theme.of(context).textTheme.titleSmall?.copyWith(\n          color: Theme.of(context).colorScheme.primary,\n          fontWeight: FontWeight.w600,\n        ),\n      ),\n    );\n  }\n}\n\nclass _SettingsCard extends StatelessWidget {\n  const _SettingsCard({required this.children});\n\n  final List<Widget> children;\n\n  @override\n  Widget build(BuildContext context) {\n    return Card(\n      margin: EdgeInsets.zero,\n      child: Column(children: children),\n    );\n  }\n}\n\nclass _SettingsTile extends StatelessWidget {\n  const _SettingsTile({\n    required this.icon,\n    required this.title,\n    this.iconColor,\n    this.subtitle,\n    this.loading = false,\n    this.onTap,\n    this.titleColor,\n  });\n\n  final IconData icon;\n  final Color? iconColor;\n  final String title;\n  final String? subtitle;\n  final bool loading;\n  final VoidCallback? onTap;\n  final Color? titleColor;\n\n  @override\n  Widget build(BuildContext context) {\n    final colorScheme = Theme.of(context).colorScheme;\n    return InkWell(\n      onTap: onTap,\n      child: Padding(\n        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),\n        child: Row(\n          children: [\n            SizedBox(\n              width: 32,\n              child: loading\n                  ? SizedBox.square(\n                      dimension: 20,\n                      child: CircularProgressIndicator(\n                        strokeWidth: 2.2,\n                        color: colorScheme.primary,\n                      ),\n                    )\n                  : Icon(icon, size: 22, color: iconColor ?? colorScheme.primary),\n            ),\n            const SizedBox(width: 14),\n            Expanded(\n              child: Column(\n                crossAxisAlignment: CrossAxisAlignment.start,\n                children: [\n                  Text(\n                    title,\n                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(\n                      color: titleColor,\n                      fontWeight: FontWeight.w600,\n                    ),\n                  ),\n                  if (subtitle != null) ...[
                    const SizedBox(height: 2),\n                    Text(\n                      subtitle!,\n                      style: Theme.of(context).textTheme.bodySmall?.copyWith(\n                        color: colorScheme.onSurfaceVariant,\n                      ),\n                    ),\n                  ],\n                ],\n              ),\n            ),\n            if (onTap != null)\n              Icon(\n                Icons.chevron_right_rounded,\n                size: 20,\n                color: colorScheme.outline,\n              ),\n          ],\n        ),\n      ),\n    );\n  }\n}\n\nclass _SettingsSwitchTile extends StatelessWidget {\n  const _SettingsSwitchTile({\n    required this.icon,\n    required this.title,\n    required this.value,\n    required this.onChanged,\n    this.iconColor,\n    this.subtitle,\n  });\n\n  final IconData icon;\n  final Color? iconColor;\n  final String title;\n  final String? subtitle;\n  final bool value;\n  final ValueChanged<bool> onChanged;\n\n  @override\n  Widget build(BuildContext context) {\n    final colorScheme = Theme.of(context).colorScheme;\n    return Padding(\n      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),\n      child: Row(\n        children: [\n          SizedBox(\n            width: 32,\n            child: Icon(icon, size: 22, color: iconColor ?? colorScheme.primary),\n          ),\n          const SizedBox(width: 14),\n          Expanded(\n            child: Column(\n              crossAxisAlignment: CrossAxisAlignment.start,\n              children: [\n                Text(\n                  title,\n                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(\n                    fontWeight: FontWeight.w600,\n                  ),\n                ),\n                if (subtitle != null) ...[
                  const SizedBox(height: 2),\n                  Text(\n                    subtitle!,\n                    style: Theme.of(context).textTheme.bodySmall?.copyWith(\n                      color: colorScheme.onSurfaceVariant,\n                    ),\n                  ),\n                ],\n              ],\n            ),\n          ),\n          Switch(value: value, onChanged: onChanged),\n        ],\n      ),\n    );\n  }\n}\n\nclass _SettingsDivider extends StatelessWidget {\n  @override\n  Widget build(BuildContext context) {\n    return Divider(\n      height: 1,\n      indent: 62,\n      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4),\n    );\n  }\n}\n\n/// 缓存管理 BottomSheet。\nclass _CacheManagementSheet extends StatefulWidget {\n  const _CacheManagementSheet({this.cache, this.downloads});\n\n  final CacheService? cache;\n  final DownloadController? downloads;\n\n  @override\n  State<_CacheManagementSheet> createState() => _CacheManagementSheetState();\n}\n\nclass _CacheManagementSheetState extends State<_CacheManagementSheet> {\n  String? _cacheSize;\n\n  @override\n  void initState() {\n    super.initState();\n    _loadCacheSize();\n  }\n\n  Future<void> _loadCacheSize() async {\n    if (widget.cache == null) return;\n    final size = await widget.cache!.size();\n    if (!mounted) return;\n    setState(() {\n      _cacheSize = cacheSize(size);\n    });\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    return Padding(\n      padding: const EdgeInsets.all(16),\n      child: Column(\n        mainAxisSize: MainAxisSize.min,\n        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: [\n          const Text(\n            '缓存管理',\n            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),\n          ),\n          const SizedBox(height: 16),\n          if (_cacheSize != null) ...[\n            Text('缓存大小: $_cacheSize'),\n            const SizedBox(height: 8),\n          ],\n          FilledButton(\n            onPressed: () async {\n              await widget.cache?.clear();\n              if (!mounted) return;\n              Navigator.of(context).pop();\n            },\n            child: const Text('清除缓存'),\n          ),\n        ],\n      ),\n    );\n  }\n}\n\nclass _EqualizerSheet extends StatefulWidget {\n  const _EqualizerSheet({required this.player});\n\n  final PlayerController player;\n\n  @override\n  State<_EqualizerSheet> createState() => _EqualizerSheetState();\n}\n\nclass _EqualizerSheetState extends State<_EqualizerSheet> {\n  @override\n  Widget build(BuildContext context) {\n    return Padding(\n      padding: const EdgeInsets.all(16),\n      child: Column(\n        mainAxisSize: MainAxisSize.min,\n        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: [\n          const Text(\n            '均衡器',\n            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),\n          ),\n          const SizedBox(height: 16),\n          SwitchListTile(\n            title: const Text('启用均衡器'),\n            value: widget.player.equalizerEnabled,\n            onChanged: (value) => widget.player.setEqualizerEnabled(value),\n          ),\n          const SizedBox(height: 16),\n          FilledButton(\n            onPressed: () => Navigator.of(context).pop(),\n            child: const Text('关闭'),\n          ),\n        ],\n      ),\n    );\n  }\n}\n\n/// 缓存容量格式化。\nString cacheSize(CacheService cache) => '';\n"}]