import Flutter

/// 响度均衡 MethodChannel(iOS 端)。
///
/// 仅处理 `analyzeLoudness`(LUFS 分析)。
/// `configureLoudnessGain`/`releaseLoudnessGain` 在 iOS 走 notImplemented——
/// iOS 端增益应用由 Dart 侧用 [AudioPlayer.setVolume] 衰减完成。
enum LoudnessChannel {
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
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let r = try LoudnessAnalyzer.analyze(
                            url: url,
                            maxDurationMs: maxDurationMs
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
                            result(FlutterError(
                                code: "analyze_failed",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        }
                    }
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
