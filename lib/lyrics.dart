class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
  });

  final Duration time;
  final String text;
}

class LyricsParser {
  LyricsParser._();

  static final RegExp _timeTagPattern = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]',
  );

  static List<LyricLine> parse(String content) {
    final lines = <LyricLine>[];
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final matches = _timeTagPattern.allMatches(rawLine).toList();
      if (matches.isEmpty) {
        continue;
      }

      final text = rawLine.substring(matches.last.end).trim();
      if (text.isEmpty) {
        continue;
      }

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fraction = match.group(3) ?? '0';
        final milliseconds = _fractionToMilliseconds(fraction);
        lines.add(
          LyricLine(
            time: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: milliseconds,
            ),
            text: text,
          ),
        );
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  static int currentIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) {
      return -1;
    }

    var low = 0;
    var high = lines.length - 1;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      if (lines[mid].time <= position) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (high < 0) {
      return 0;
    }
    if (high >= lines.length) {
      return lines.length - 1;
    }
    return high;
  }

  static int _fractionToMilliseconds(String value) {
    if (value.length == 1) {
      return (int.tryParse(value) ?? 0) * 100;
    }
    if (value.length == 2) {
      return (int.tryParse(value) ?? 0) * 10;
    }
    return int.tryParse(value.substring(0, 3)) ?? 0;
  }
}

String formatDuration(Duration duration) {
  if (duration.isNegative) {
    duration = Duration.zero;
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
