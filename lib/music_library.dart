import 'dart:io';

import 'package:flutter/services.dart';

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
  });

  final String id;
  final String path;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;

  factory MusicTrack.fromMap(Map<dynamic, dynamic> map) {
    final path = (map['path'] as String?) ?? '';
    final title = (map['title'] as String?) ?? _titleFromPath(path);
    final artist = (map['artist'] as String?)?.trim();

    return MusicTrack(
      id: (map['id'] as String?) ?? path,
      path: path,
      title: title.trim().isEmpty ? _titleFromPath(path) : title.trim(),
      artist: artist == null || artist.isEmpty ? '未知艺术家' : artist,
      album: (map['album'] as String?)?.trim(),
      durationMs: map['durationMs'] is int ? map['durationMs'] as int : null,
    );
  }

  String get fileName {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  String get durationLabel {
    final value = durationMs;
    if (value == null || value <= 0) {
      return '--:--';
    }
    final duration = Duration(milliseconds: value);
    final minutes = duration.inMinutes.remainder(60).toString();
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  static String _titleFromPath(String path) {
    if (path.isEmpty) {
      return '未命名曲目';
    }
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}

class MusicLibrary {
  MusicLibrary._();

  static const MethodChannel _channel = MethodChannel('lisn/music_library');
  static const Set<String> _audioExtensions = {
    '.aac',
    '.aiff',
    '.alac',
    '.amr',
    '.ape',
    '.flac',
    '.m4a',
    '.mid',
    '.midi',
    '.mp3',
    '.oga',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
  };

  static Future<bool> requestAudioPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      return await _channel.invokeMethod<bool>('requestAudioPermission') ??
          false;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<List<MusicTrack>> scanMusic() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeListMethod<dynamic>('scanMusic');
        return _tracksFromPlatformList(result);
      } on MissingPluginException {
        return _scanMusicFallback();
      }
    }

    return _scanMusicFallback();
  }

  static List<MusicTrack> _tracksFromPlatformList(List<dynamic>? result) {
    final tracks = <MusicTrack>[];
    for (final item in result ?? const []) {
      if (item is Map) {
        tracks.add(MusicTrack.fromMap(item));
      }
    }
    tracks.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return tracks;
  }

  static Future<List<MusicTrack>> _scanMusicFallback() async {
    final candidates = <Directory>[];
    if (Platform.isAndroid) {
      candidates.add(Directory('/storage/emulated/0/Music'));
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(Directory('$home/Music'));
    }

    for (final directory in candidates) {
      if (await directory.exists()) {
        final tracks = <MusicTrack>[];
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File || !_isAudioPath(entity.path)) {
            continue;
          }
          tracks.add(
            MusicTrack(
              id: entity.path,
              path: entity.path,
              title: MusicTrack._titleFromPath(entity.path),
              artist: '未知艺术家',
            ),
          );
        }
        tracks.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        return tracks;
      }
    }

    return const [];
  }

  static bool _isAudioPath(String path) {
    final lower = path.toLowerCase();
    return _audioExtensions.any(lower.endsWith);
  }
}
