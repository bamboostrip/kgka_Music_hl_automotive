import Flutter

/// 响度均衡 MethodChannel(iOS 端)。
///
/// 处理 `analyzeLoudness`(LUFS 分析,支持渐进式进度回调)与
/// `cancelLoudnessAnalysis`(切歌时取消在途分析)。
/// `configureLoudnessGain`/`releaseLoudnessGain` 在 iOS 走 notImplemented——
/// iOS 端增益应用由 Dart 侧用 [AudioPlayer.setVolume] 衰减完成。
enum LoudnessChannel {
    /// 当前在途分析的取消标志。切歌时置 true,解码循环检测到后立即结束。
    /// 用 NSLock 保护(回调在读线程,取消在主线程)。
    private static var cancelledFlag: Bool = false
    private static let lock = NSLock()

    private static func setCancelled(_ value: Bool) {
        lock.lock()
        cancelledFlag = value
        lock.unlock()
    }

    private static func isCancelled() -> Bool {
        lock.lock()
        let v = cancelledFlag
        lock.unlock()
        return v
    }

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "kgka_music_hl/audio_effects",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "analyzeLoudness":
                guard let args = call.arguments as? [String: Any],
                      let urlString = args["url"] as? String,
                      let url = URL(string: urlString)
                else {
                    result(FlutterError(
                        code: "invalid_url",
                        message: "url is null or invalid",
                        details: nil
                    ))
                    return
                }
                let maxDurationMs = (args["maxDurationMs"] as? Int) ?? 1800000
                let progressIntervalMs = (args["progressIntervalMs"] as? Int) ?? 500
                // 每次新分析重置取消标志。
                setCancelled(false)
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LoudnessAnalyzer.analyze(
                            url: url,
                            maxDurationMs: maxDurationMs,
                            progressIntervalMs: progressIntervalMs,
                            isCancelled: { isCancelled() },
                            onProgress: { lufs, analyzedMs in
                                // 反向 invokeMethod 把中途 LUFS 推给 Dart。
                                // 切到主线程(MethodChannel 要求主线程)。
                                if !isCancelled() {
                                    DispatchQueue.main.async {
                                        channel.invokeMethod(
                                            "onLoudnessProgress",
                                            arguments: [
                                                "lufs": lufs,
                                                "analyzedMs": analyzedMs,
                                            ]
                                        )
                                    }
                                }
                            }
                        )
                        DispatchQueue.main.async {
                            result([
                                "lufs": r.lufs,
                                "sampleRate": r.sampleRate,
                                "analyzedMs": r.analyzedMs,
                            ])
                        }
                    } catch {
                        DispatchQueue.main.async {
                            if isCancelled() {
                                // 取消不算失败,返回 nil 让 Dart 侧走"已丢弃"路径。
                                result(nil)
                            } else {
                                result(FlutterError(
                                    code: "analyze_failed",
                                    message: error.localizedDescription,
                                    details: nil
                                ))
                            }
                        }
                    }
                }
            case "cancelLoudnessAnalysis":
                // 切歌时调用,让正在跑的解码循环立即结束。
                setCancelled(true)
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
