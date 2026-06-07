import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.lyricsPath,
  });

  final String id;
  final String path;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? lyricsPath;

  factory MusicTrack.fromMap(Map<dynamic, dynamic> map) {
    final path = (map['path'] as String?) ?? '';
    final title = (map['title'] as String?) ?? _titleFromPath(path);
    final artist = (map['artist'] as String?)?.trim();
    final lyricsPath = (map['lyricsPath'] as String?)?.trim();
    final duration = map['durationMs'];

    return MusicTrack(
      id: (map['id'] as String?) ?? path,
      path: path,
      title: title.trim().isEmpty ? _titleFromPath(path) : title.trim(),
      artist: artist == null || artist.isEmpty ? '未知艺术家' : artist,
      album: (map['album'] as String?)?.trim(),
      durationMs: duration is num ? duration.round() : null,
      lyricsPath: lyricsPath == null || lyricsPath.isEmpty ? null : lyricsPath,
    );
  }

  String get fileName {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  String get folderName {
    if (path.isEmpty) {
      return 'Music';
    }
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.length < 2) {
      return 'Music';
    }
    final folder = parts[parts.length - 2].trim();
    return folder.isEmpty ? 'Music' : folder;
  }

  String get displayAlbum {
    final value = album?.trim();
    if (value == null || value.isEmpty) {
      return '未知专辑';
    }
    return value;
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

class UserLibraryState {
  const UserLibraryState({
    required this.favoriteIds,
    required this.recentIds,
  });

  final Set<String> favoriteIds;
  final List<String> recentIds;

  factory UserLibraryState.fromMap(Map<dynamic, dynamic>? map) {
    return UserLibraryState(
      favoriteIds: _stringSetFromList(map?['favoriteIds']),
      recentIds: _stringListFromList(map?['recentIds']),
    );
  }

  static Set<String> _stringSetFromList(dynamic value) {
    return _stringListFromList(value).toSet();
  }

  static List<String> _stringListFromList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String && item.isNotEmpty) item,
    ];
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

  static Future<String?> readLyrics(String path) async {
    if (path.trim().isEmpty) {
      return null;
    }

    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('readLyrics', {'path': path});
      } on MissingPluginException {
        return _readLyricsFallback(path);
      }
    }

    return _readLyricsFallback(path);
  }

  static Future<Uint8List?> readCoverArt(String path) async {
    if (path.trim().isEmpty) {
      return null;
    }

    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<Uint8List>(
          'readCoverArt',
          {'path': path},
        );
      } on MissingPluginException {
        return null;
      }
    }

    return null;
  }

  static Future<UserLibraryState> loadUserState() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<dynamic>('loadUserState');
        if (result is Map) {
          return UserLibraryState.fromMap(result);
        }
      } on MissingPluginException {
        return const UserLibraryState(favoriteIds: {}, recentIds: []);
      }
    }

    return const UserLibraryState(favoriteIds: {}, recentIds: []);
  }

  static Future<void> saveUserState({
    required Iterable<String> favoriteIds,
    required Iterable<String> recentIds,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('saveUserState', {
        'favoriteIds': favoriteIds.toList(),
        'recentIds': recentIds.toList(),
      });
    } on MissingPluginException {
      return;
    }
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
              lyricsPath: await _findFallbackLyrics(entity.path),
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

  static Future<String?> _readLyricsFallback(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  static Future<String?> _findFallbackLyrics(String audioPath) async {
    final file = File(audioPath);
    final parent = file.parent;
    if (!await parent.exists()) {
      return null;
    }
    final audioName = file.uri.pathSegments.last;
    final dot = audioName.lastIndexOf('.');
    final base = dot > 0 ? audioName.substring(0, dot) : audioName;
    final normalizedBase = base.toLowerCase();
    final matches = <File>[];

    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (!name.endsWith('.lrc')) {
        continue;
      }
      final lrcBase = name.substring(0, name.length - 4);
      if (lrcBase == normalizedBase ||
          (lrcBase.startsWith(normalizedBase) &&
              _isLyricsSuffix(lrcBase.substring(normalizedBase.length)))) {
        matches.add(entity);
      }
    }

    if (matches.isEmpty) {
      return null;
    }
    matches.sort((a, b) {
      final length = a.path.length.compareTo(b.path.length);
      if (length != 0) {
        return length;
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return matches.first.path;
  }

  static bool _isLyricsSuffix(String suffix) {
    if (suffix.isEmpty) {
      return true;
    }
    return suffix.startsWith('.') ||
        suffix.startsWith('-') ||
        suffix.startsWith('_') ||
        suffix.startsWith(' ') ||
        suffix.startsWith('(') ||
        suffix.startsWith('[');
  }
}
