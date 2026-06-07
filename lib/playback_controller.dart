import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lyrics.dart';
import 'music_library.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController() {
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (_) {},
    );
  }

  static const MethodChannel _channel = MethodChannel('lisn/player');
  static const EventChannel _events = EventChannel('lisn/player_events');

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _ticker;
  bool _syncing = false;

  List<MusicTrack> _playlist = const [];
  MusicTrack? _currentTrack;
  String? _preparedTrackId;
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.72;
  List<LyricLine> _lyrics = const [];
  String? _lyricsError;
  String? _playbackError;

  List<MusicTrack> get playlist => _playlist;
  MusicTrack? get currentTrack => _currentTrack;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  List<LyricLine> get lyrics => _lyrics;
  String? get lyricsError => _lyricsError;
  String? get playbackError => _playbackError;

  double get progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (_position.inMilliseconds / total).clamp(0, 1).toDouble();
  }

  bool get hasTrack => _currentTrack != null;

  void setQueue(List<MusicTrack> tracks) {
    _playlist = List<MusicTrack>.of(tracks);
    if (_playlist.isEmpty) {
      _currentTrack = null;
      _preparedTrackId = null;
      _currentIndex = -1;
      _position = Duration.zero;
      _duration = Duration.zero;
      _lyrics = const [];
      _lyricsError = null;
      _playbackError = null;
      notifyListeners();
      return;
    }

    final current = _currentTrack;
    if (current == null) {
      _currentIndex = 0;
      _currentTrack = _playlist.first;
      _duration = _durationFromTrack(_playlist.first);
      notifyListeners();
      return;
    }

    final index = _playlist.indexWhere((item) => item.id == current.id);
    if (index >= 0) {
      _currentIndex = index;
    }
    notifyListeners();
  }

  Future<void> playTrack(
    MusicTrack track, {
    required List<MusicTrack> playlist,
  }) async {
    _playlist = playlist.isEmpty ? [track] : List<MusicTrack>.of(playlist);
    final index = _playlist.indexWhere((item) => item.id == track.id);
    _currentIndex = index < 0 ? 0 : index;
    _currentTrack = track;
    _position = Duration.zero;
    _duration = _durationFromTrack(track);
    _isPlaying = true;
    _lyrics = const [];
    _lyricsError = null;
    _playbackError = null;
    notifyListeners();

    await Future.wait([
      _playNative(track),
      _loadLyrics(track),
    ]);
    _startTicker();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_currentTrack == null) {
      if (_playlist.isNotEmpty) {
        await playTrack(_playlist.first, playlist: _playlist);
      }
      return;
    }

    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    try {
      final state = await _channel.invokeMethod<dynamic>('pause');
      _applyNativeState(state);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _playbackError = error.message ?? '暂停失败';
      notifyListeners();
    }
  }

  Future<void> resume() async {
    final track = _currentTrack;
    if (track == null) {
      return;
    }
    if (_preparedTrackId != track.id) {
      await playTrack(track, playlist: _playlist);
      return;
    }
    _isPlaying = true;
    notifyListeners();
    try {
      final state = await _channel.invokeMethod<dynamic>('resume');
      _applyNativeState(state);
    } on MissingPluginException {
      _startTicker();
      return;
    } on PlatformException catch (error) {
      _isPlaying = false;
      _playbackError = error.message ?? '播放失败';
      notifyListeners();
      return;
    }
    _startTicker();
  }

  Future<void> next() async {
    if (_playlist.isEmpty) {
      return;
    }
    final nextIndex = (_currentIndex + 1) % _playlist.length;
    await playTrack(_playlist[nextIndex], playlist: _playlist);
  }

  Future<void> previous() async {
    if (_playlist.isEmpty) {
      return;
    }
    final previousIndex =
        (_currentIndex <= 0 ? _playlist.length : _currentIndex) - 1;
    await playTrack(_playlist[previousIndex], playlist: _playlist);
  }

  Future<void> seekTo(Duration position) async {
    _position = _clampPosition(position);
    notifyListeners();
    try {
      final state = await _channel.invokeMethod<dynamic>(
        'seekTo',
        {'positionMs': _position.inMilliseconds},
      );
      _applyNativeState(state);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _playbackError = error.message ?? '定位失败';
      notifyListeners();
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 1).toDouble();
    notifyListeners();
    try {
      final state = await _channel.invokeMethod<dynamic>(
        'setVolume',
        {'volume': _volume},
      );
      _applyNativeState(state);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _playbackError = error.message ?? '音量设置失败';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    _preparedTrackId = null;
    _position = Duration.zero;
    _ticker?.cancel();
    notifyListeners();
    try {
      final state = await _channel.invokeMethod<dynamic>('stop');
      _applyNativeState(state);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _playbackError = error.message ?? '停止失败';
      notifyListeners();
    }
  }

  int currentLyricIndex() {
    return LyricsParser.currentIndex(_lyrics, _position);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _playNative(MusicTrack track) async {
    try {
      final state = await _channel.invokeMethod<dynamic>(
        'play',
        {
          'path': track.path,
          'volume': _volume,
        },
      );
      _applyNativeState(state);
      _preparedTrackId = track.id;
    } on MissingPluginException {
      _duration = _durationFromTrack(track);
      _preparedTrackId = track.id;
    } on PlatformException catch (error) {
      _isPlaying = false;
      _playbackError = error.message ?? '播放失败';
    }
  }

  Future<void> _loadLyrics(MusicTrack track) async {
    final path = track.lyricsPath;
    if (path == null || path.isEmpty) {
      _lyrics = const [];
      _lyricsError = null;
      return;
    }

    try {
      final content = await MusicLibrary.readLyrics(path);
      if (content == null || content.trim().isEmpty) {
        _lyrics = const [];
        _lyricsError = '歌词文件为空';
        return;
      }
      _lyrics = LyricsParser.parse(content);
      _lyricsError = _lyrics.isEmpty ? '歌词文件没有有效时间轴' : null;
    } catch (error) {
      _lyrics = const [];
      _lyricsError = '歌词读取失败';
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _syncNativeState();
    });
  }

  Future<void> _syncNativeState() async {
    if (_syncing || (!_isPlaying && _currentTrack != null)) {
      return;
    }
    _syncing = true;
    try {
      final state = await _channel.invokeMethod<dynamic>('getState');
      _applyNativeState(state);
    } on MissingPluginException {
      if (_isPlaying) {
        _position += const Duration(milliseconds: 500);
        _position = _clampPosition(_position);
        if (_duration > Duration.zero && _position >= _duration) {
          _isPlaying = false;
        }
        notifyListeners();
      }
    } on PlatformException catch (error) {
      _playbackError = error.message ?? '播放状态同步失败';
      notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final type = event['event'] as String?;
    if (type == 'completed') {
      next();
      return;
    }
    _applyNativeState(event);
  }

  void _applyNativeState(dynamic value) {
    if (value is! Map) {
      return;
    }
    final positionMs = _readInt(value['positionMs']);
    final durationMs = _readInt(value['durationMs']);
    final isPlaying = value['isPlaying'];
    final volume = value['volume'];

    if (positionMs != null) {
      _position = Duration(milliseconds: positionMs);
    }
    if (durationMs != null && durationMs > 0) {
      _duration = Duration(milliseconds: durationMs);
    }
    if (isPlaying is bool) {
      _isPlaying = isPlaying;
    }
    if (volume is num) {
      _volume = volume.toDouble().clamp(0, 1).toDouble();
    }
    _position = _clampPosition(_position);
    notifyListeners();
  }

  Duration _durationFromTrack(MusicTrack track) {
    final value = track.durationMs;
    if (value == null || value <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: value);
  }

  Duration _clampPosition(Duration value) {
    if (value.isNegative) {
      return Duration.zero;
    }
    if (_duration > Duration.zero && value > _duration) {
      return _duration;
    }
    return value;
  }

  int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return null;
  }
}
