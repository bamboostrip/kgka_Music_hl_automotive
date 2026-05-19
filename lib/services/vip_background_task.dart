import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/music_models.dart';
import 'music_api.dart';

class VipBackgroundTask {
  VipBackgroundTask(this._api);

  final MusicApi _api;

  bool _isRunning = false;
  String? _lastCompletedRunKey;

  void schedule(LoginSession? session) {
    final runKey = _buildRunKey(session);
    if (runKey == null || _isRunning || _lastCompletedRunKey == runKey) {
      return;
    }

    _isRunning = true;
    unawaited(_run(runKey));
  }

  String? _buildRunKey(LoginSession? session) {
    if (session?.isValid != true) {
      return null;
    }

    final identity =
        session?.userId ?? session?.sessionId ?? session?.token ?? '';
    if (identity.isEmpty) {
      return null;
    }

    final today = DateTime.now().toIso8601String().split('T').first;
    return '$identity@$today';
  }

  Future<void> _run(String runKey) async {
    try {
      final history = await _api.vipReceiveHistory();
      if (history.status != 1) {
        _debugLog(
          'skip, vip history status=${history.status} error=${history.errorCode}',
        );
        return;
      }

      final today = DateTime.now().toIso8601String().split('T').first;
      VipReceiveItem? todayRecord;
      for (final item in history.items) {
        if (item.day == today) {
          todayRecord = item;
          break;
        }
      }

      if (todayRecord == null) {
        final result = await _api.dailyVip();
        if (result.status != 1) {
          _debugLog('daily vip failed, error=${result.errorCode}');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        await _upgradeVipReward();
      } else if (todayRecord.vipType == 'tvip') {
        await _upgradeVipReward();
      } else {
        _debugLog('today vip already fully claimed');
      }

      _lastCompletedRunKey = runKey;
    } catch (error, stackTrace) {
      _debugLog('vip background task failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _upgradeVipReward() async {
    final result = await _api.upgradeVipReward();
    if (result.status != 1) {
      _debugLog('upgrade vip failed, error=${result.errorCode}');
    }
  }

  void _debugLog(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[KA Music][vip-task] $message');
  }
}
