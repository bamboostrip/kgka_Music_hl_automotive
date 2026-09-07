import 'package:flutter/material.dart';

import '../design_tokens.dart' show AppSpacing;

/// 统一的空状态视图：图标 + 标题 + 副文案 + 可选操作。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.all(32),
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 将底层异常转换为面向用户的友好文案，避免把 ApiException / URL / 堆栈
/// 直接透出到页面（排行榜、电台无网络时曾直接展示 gateway.kugou.com 等内部细节）。
///
/// 规则：
/// - 命中网络/超时信号 -> 返回可行动的网络提示；
/// - 其余一律返回通用服务提示，不回显原始 [error] 文本。
String friendlyServiceErrorMessage(Object error) {
  final raw = error.toString().toLowerCase();
  // 超时优先：(408) / timeout / 超时（Rust 侧超时已被包装为 408 ApiException）。
  // 用 '(408)' 而非裸 '408'，避免把端口号/ID（如 4808）误判为超时。
  if (raw.contains('(408)') ||
      raw.contains('timeout') ||
      raw.contains('timed out') ||
      raw.contains('超时')) {
    return '请求超时，请检查网络后重试';
  }
  // 无网络 / 上游不可达：Socket、DNS、连接被拒/重置、Rust reqwest 的
  // "error sending request"（会被包装成 ApiException(500): Upstream API error）
  // 以及网关 502/503/504 等。本分支刻意不回显 URL 与原始异常。
  const networkSignals = [
    'socket',
    'failed host lookup',
    'no address associated',
    'network is unreachable',
    'no route to host',
    'connection refused',
    'connection reset',
    'connection closed',
    'broken pipe',
    'handshake',
    'clientexception',
    'error sending request',
    '发送失败',
    'upstream',
    'gateway',
    'rcmd_list',
    'kugou.com',
    'https://',
    'http://',
    '502',
    '503',
    '504',
    'offline',
    'unreachable',
    'dns',
    'network',
    'connection',
  ];
  if (networkSignals.any(raw.contains)) {
    return '网络连接失败，请检查网络设置后重试';
  }
  return '服务暂时不可用，请稍后重试';
}

/// 统一的错误视图：图标 + 标题 + 错误信息 + 可选重试。
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = '加载失败',
    this.icon = Icons.error_outline_rounded,
    this.padding = const EdgeInsets.all(24),
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
