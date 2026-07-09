import 'package:flutter_lyric/core/lyric_model.dart' as fl;
import '../models/music_models.dart' as models;

/// 将项目内部的 [models.LyricLine] 列表转换为 flutter_lyric 的 [fl.LyricModel]。
///
/// [showTranslation] 控制是否显示翻译文本。
/// [showRomanization] 控制是否显示音译文本（优先级低于翻译）。
fl.LyricModel convertToFlutterLyricModel(
  List<models.LyricLine> lyrics, {
  bool showTranslation = true,
  bool showRomanization = false,
}) {
  final lines = <fl.LyricLine>[];

  for (var i = 0; i < lyrics.length; i++) {
    final line = lyrics[i];
    final start = line.time;
    // 结束时间取下一行的开始时间，最后一行给 5 秒余量
    final end = i + 1 < lyrics.length
        ? lyrics[i + 1].time
        : start + const Duration(seconds: 5);

    // 转换逐字信息
    List<fl.LyricWord>? words;
    if (line.words.isNotEmpty) {
      words = line.words.map((w) {
        final wordStart = w.time;
        final wordEnd = w.time + w.duration;
        return fl.LyricWord(
          text: w.text,
          start: wordStart,
          end: wordEnd,
        );
      }).toList();
    }

    // 根据显示模式决定翻译文本
    String? translationText;
    if (showTranslation && line.translation != null && line.translation!.isNotEmpty) {
      translationText = line.translation;
    } else if (showRomanization && line.romanization != null && line.romanization!.isNotEmpty) {
      translationText = line.romanization;
    }

    lines.add(fl.LyricLine(
      start: start,
      end: end,
      text: line.text,
      translation: translationText,
      words: words,
    ));
  }

  return fl.LyricModel(lines: lines);
}
