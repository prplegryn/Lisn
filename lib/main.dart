import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lyrics.dart';
import 'music_library.dart';
import 'playback_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: LisnColors.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LisnApp());
}

class LisnApp extends StatelessWidget {
  const LisnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lisn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: LisnColors.ink,
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: LisnColors.text,
              displayColor: LisnColors.text,
            ),
      ),
      home: const HomeShell(),
    );
  }
}

class LisnColors {
  LisnColors._();

  static const Color ink = Color(0xFF0A0B0D);
  static const Color panel = Color(0xFF15181C);
  static const Color panelAlt = Color(0xFF20242A);
  static const Color text = Color(0xFFF5F7FA);
  static const Color muted = Color(0xFFA9B2BD);
  static const Color cyan = Color(0xFF00A8E8);
  static const Color magenta = Color(0xFFD81B60);
  static const Color lime = Color(0xFF7BD88F);
  static const Color amber = Color(0xFFFFB000);
  static const Color violet = Color(0xFF7C4DFF);
  static const Color orange = Color(0xFFFF5A3D);
  static const Color teal = Color(0xFF00C2A8);
}

enum LibraryMode { songs, artists, albums, folders, recent, favorites }

extension LibraryModeLabel on LibraryMode {
  String get label {
    switch (this) {
      case LibraryMode.songs:
        return '歌曲';
      case LibraryMode.artists:
        return '艺术家';
      case LibraryMode.albums:
        return '专辑';
      case LibraryMode.folders:
        return '文件夹';
      case LibraryMode.recent:
        return '最近';
      case LibraryMode.favorites:
        return '收藏';
    }
  }

  IconData get icon {
    switch (this) {
      case LibraryMode.songs:
        return Icons.library_music_rounded;
      case LibraryMode.artists:
        return Icons.mic_external_on_rounded;
      case LibraryMode.albums:
        return Icons.album_rounded;
      case LibraryMode.folders:
        return Icons.folder_rounded;
      case LibraryMode.recent:
        return Icons.history_rounded;
      case LibraryMode.favorites:
        return Icons.favorite_rounded;
    }
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  final PlaybackController _player = PlaybackController();

  int _pageIndex = 0;
  bool _searchOpen = false;
  bool _playerOpen = false;
  bool _loadingLibrary = true;
  String? _libraryError;
  String? _lastRecentTrackId;
  Timer? _saveTimer;
  List<MusicTrack> _tracks = const [];
  LibraryMode _libraryMode = LibraryMode.songs;
  final Set<String> _favoriteIds = <String>{};
  final List<String> _recentIds = <String>[];

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
    _loadSavedState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    _player.dispose();
    _saveTimer?.cancel();
    MusicLibrary.saveUserState(
      favoriteIds: _favoriteIds,
      recentIds: _recentIds,
    );
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedState() async {
    final state = await MusicLibrary.loadUserState();
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteIds
        ..clear()
        ..addAll(state.favoriteIds);
      _recentIds
        ..clear()
        ..addAll(state.recentIds);
    });
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _loadingLibrary = true;
      _libraryError = null;
    });

    try {
      final granted = await MusicLibrary.requestAudioPermission();
      if (!mounted) {
        return;
      }
      if (!granted) {
        setState(() {
          _loadingLibrary = false;
          _libraryError = '需要读取音频权限才能访问 Music 文件夹';
        });
        return;
      }

      final tracks = await MusicLibrary.scanMusic();
      if (!mounted) {
        return;
      }
      _player.setQueue(tracks);
      setState(() {
        _tracks = tracks;
        _loadingLibrary = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingLibrary = false;
        _libraryError = error.toString();
      });
    }
  }

  void _onPlayerChanged() {
    final track = _player.currentTrack;
    if (track != null && _player.isPlaying && track.id != _lastRecentTrackId) {
      _lastRecentTrackId = track.id;
      _rememberRecent(track);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _selectPage(int index) {
    if (index == 3) {
      setState(() => _searchOpen = true);
      return;
    }
    setState(() {
      _searchOpen = false;
      _pageIndex = index;
      if (index == 1) {
        _libraryMode = LibraryMode.songs;
      }
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 290),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _selectTrack(
    MusicTrack track, {
    List<MusicTrack>? queue,
  }) async {
    await _player.playTrack(track, playlist: queue ?? _tracks);
    _rememberRecent(track);
  }

  void _rememberRecent(MusicTrack track) {
    _recentIds.remove(track.id);
    _recentIds.insert(0, track.id);
    if (_recentIds.length > 50) {
      _recentIds.removeRange(50, _recentIds.length);
    }
    _scheduleSaveState();
  }

  void _toggleFavorite(MusicTrack track) {
    setState(() {
      if (_favoriteIds.contains(track.id)) {
        _favoriteIds.remove(track.id);
      } else {
        _favoriteIds.add(track.id);
      }
    });
    _scheduleSaveState();
  }

  void _scheduleSaveState() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      MusicLibrary.saveUserState(
        favoriteIds: _favoriteIds,
        recentIds: _recentIds,
      );
    });
  }

  void _openLibrary(LibraryMode mode) {
    setState(() {
      _libraryMode = mode;
      _pageIndex = 1;
      _searchOpen = false;
    });
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 290),
      curve: Curves.easeOutCubic,
    );
  }

  List<MusicTrack> get _recentTracks {
    final byId = {for (final track in _tracks) track.id: track};
    return [
      for (final id in _recentIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  List<MusicTrack> get _favoriteTracks {
    return _tracks.where((track) => _favoriteIds.contains(track.id)).toList();
  }

  int get _artistCount => _tracks.map((track) => track.artist).toSet().length;

  int get _albumCount =>
      _tracks.map((track) => track.displayAlbum).toSet().length;

  int get _folderCount =>
      _tracks.map((track) => track.folderName).toSet().length;

  List<MusicTrack> _tracksForMode(LibraryMode mode) {
    switch (mode) {
      case LibraryMode.songs:
        return _tracks;
      case LibraryMode.artists:
        return List<MusicTrack>.of(_tracks)
          ..sort((a, b) {
            final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
            return byArtist == 0
                ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
                : byArtist;
          });
      case LibraryMode.albums:
        return List<MusicTrack>.of(_tracks)
          ..sort((a, b) {
            final byAlbum = a.displayAlbum.toLowerCase().compareTo(b.displayAlbum.toLowerCase());
            return byAlbum == 0
                ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
                : byAlbum;
          });
      case LibraryMode.folders:
        return List<MusicTrack>.of(_tracks)
          ..sort((a, b) {
            final byFolder = a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase());
            return byFolder == 0
                ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
                : byFolder;
          });
      case LibraryMode.recent:
        return _recentTracks;
      case LibraryMode.favorites:
        return _favoriteTracks;
    }
  }

  void _handleBackGesture(bool didPop) {
    if (didPop) {
      return;
    }
    if (_searchOpen) {
      setState(() => _searchOpen = false);
      return;
    }
    if (_playerOpen) {
      setState(() => _playerOpen = false);
      return;
    }
    if (_pageIndex != 0) {
      _selectPage(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _player.currentTrack ?? DemoTracks.placeholder;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final reservedBottom = 78 + 64 + bottomInset;

    return PopScope(
      canPop: !_searchOpen && !_playerOpen && _pageIndex == 0,
      onPopInvokedWithResult: (didPop, result) => _handleBackGesture(didPop),
      child: Scaffold(
        body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _pageIndex = index;
                      _searchOpen = false;
                    });
                  },
                  children: [
                    HomePage(
                      tracks: _tracks,
                      recentTracks: _recentTracks,
                      currentTrack: current,
                      isPlaying: _player.isPlaying,
                      progress: _player.progress,
                      isLoading: _loadingLibrary,
                      error: _libraryError,
                      artistCount: _artistCount,
                      albumCount: _albumCount,
                      folderCount: _folderCount,
                      favoriteCount: _favoriteTracks.length,
                      onTrackSelected: (track) => _selectTrack(track),
                      onOpenLibrary: _openLibrary,
                    ),
                    LibraryPage(
                      mode: _libraryMode,
                      tracks: _tracksForMode(_libraryMode),
                      songCount: _tracks.length,
                      artistCount: _artistCount,
                      albumCount: _albumCount,
                      folderCount: _folderCount,
                      recentCount: _recentTracks.length,
                      favoriteCount: _favoriteTracks.length,
                      isLoading: _loadingLibrary,
                      error: _libraryError,
                      favoriteIds: _favoriteIds,
                      currentTrackId: _player.currentTrack?.id,
                      onModeChanged: (mode) => setState(() => _libraryMode = mode),
                      onTrackSelected: (track) => _selectTrack(
                        track,
                        queue: _tracksForMode(_libraryMode),
                      ),
                      onToggleFavorite: _toggleFavorite,
                    ),
                    ProfilePage(
                      trackCount: _tracks.length,
                      artistCount: _artistCount,
                      albumCount: _albumCount,
                      folderCount: _folderCount,
                      favoriteCount: _favoriteTracks.length,
                      recentCount: _recentTracks.length,
                      currentTrack: current,
                    ),
                  ],
                ),
              ),
              MiniPlayer(
                track: current,
                isPlaying: _player.isPlaying,
                progress: _player.progress,
                onTap: () => setState(() => _playerOpen = true),
                onTogglePlay: _player.togglePlay,
                onNext: _player.next,
              ),
              BottomTileNav(
                selectedIndex: _pageIndex,
                searchOpen: _searchOpen,
                bottomInset: bottomInset,
                onTap: _selectPage,
              ),
            ],
          ),
          SearchPanel(
            open: _searchOpen,
            controller: _searchController,
            tracks: _tracks,
            favoriteIds: _favoriteIds,
            bottomReserved: reservedBottom,
            onClose: () => setState(() => _searchOpen = false),
            onTrackSelected: (track) {
              _selectTrack(track);
              setState(() => _searchOpen = false);
            },
            onToggleFavorite: _toggleFavorite,
          ),
          if (_playerOpen)
            FullPlayerOverlay(
              player: _player,
              track: current,
              isFavorite: _favoriteIds.contains(current.id),
              onToggleFavorite: () => _toggleFavorite(current),
              onClosed: () => setState(() => _playerOpen = false),
            ),
        ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.tracks,
    required this.recentTracks,
    required this.currentTrack,
    required this.isPlaying,
    required this.progress,
    required this.isLoading,
    required this.error,
    required this.artistCount,
    required this.albumCount,
    required this.folderCount,
    required this.favoriteCount,
    required this.onTrackSelected,
    required this.onOpenLibrary,
    super.key,
  });

  final List<MusicTrack> tracks;
  final List<MusicTrack> recentTracks;
  final MusicTrack currentTrack;
  final bool isPlaying;
  final double progress;
  final bool isLoading;
  final String? error;
  final int artistCount;
  final int albumCount;
  final int folderCount;
  final int favoriteCount;
  final ValueChanged<MusicTrack> onTrackSelected;
  final ValueChanged<LibraryMode> onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final visibleTracks = recentTracks.isEmpty ? tracks.take(8).toList() : recentTracks.take(8).toList();

    return ColoredBox(
      color: LisnColors.ink,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: top)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 202,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TileBlock(
                      color: LisnColors.cyan,
                      child: InkWell(
                        onTap: tracks.isEmpty ? null : () => onTrackSelected(currentTrack),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Text(
                                'Lisn',
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                currentTrack.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isPlaying ? '正在播放 · ${currentTrack.artist}' : currentTrack.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xDFFFFFFF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  color: LisnColors.ink,
                                  backgroundColor: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: TileBlock(
                            color: LisnColors.magenta,
                            child: StatTile(
                              label: '曲目',
                              value: isLoading ? '...' : '${tracks.length}',
                            ),
                          ),
                        ),
                        Expanded(
                          child: TileButton(
                            color: LisnColors.amber,
                            foreground: LisnColors.ink,
                            icon: Icons.favorite_rounded,
                            label: '收藏 $favoriteCount',
                            onTap: () => onOpenLibrary(LibraryMode.favorites),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: Row(
                children: [
                  Expanded(
                    child: TileButton(
                      color: LisnColors.panelAlt,
                      icon: Icons.library_music_rounded,
                      label: '歌曲',
                      onTap: () => onOpenLibrary(LibraryMode.songs),
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.violet,
                      icon: Icons.mic_external_on_rounded,
                      label: '艺术家 $artistCount',
                      onTap: () => onOpenLibrary(LibraryMode.artists),
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.lime,
                      foreground: LisnColors.ink,
                      icon: Icons.album_rounded,
                      label: '专辑 $albumCount',
                      onTap: () => onOpenLibrary(LibraryMode.albums),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 108,
              child: Row(
                children: [
                  Expanded(
                    child: TileButton(
                      color: LisnColors.teal,
                      icon: Icons.folder_rounded,
                      label: '文件夹 $folderCount',
                      onTap: () => onOpenLibrary(LibraryMode.folders),
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.orange,
                      icon: Icons.history_rounded,
                      label: '最近',
                      onTap: () => onOpenLibrary(LibraryMode.recent),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (visibleTracks.isEmpty && !isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyLibrary(error: error),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = visibleTracks[index];
                  return TrackTile(
                    track: track,
                    accent: LisnPalette.byIndex(index),
                    current: track.id == currentTrack.id && isPlaying,
                    isFavorite: false,
                    onTap: () => onTrackSelected(track),
                    onToggleFavorite: null,
                  );
                },
                childCount: visibleTracks.length,
              ),
            ),
        ],
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    required this.mode,
    required this.tracks,
    required this.songCount,
    required this.artistCount,
    required this.albumCount,
    required this.folderCount,
    required this.recentCount,
    required this.favoriteCount,
    required this.isLoading,
    required this.error,
    required this.favoriteIds,
    required this.currentTrackId,
    required this.onModeChanged,
    required this.onTrackSelected,
    required this.onToggleFavorite,
    super.key,
  });

  final LibraryMode mode;
  final List<MusicTrack> tracks;
  final int songCount;
  final int artistCount;
  final int albumCount;
  final int folderCount;
  final int recentCount;
  final int favoriteCount;
  final bool isLoading;
  final String? error;
  final Set<String> favoriteIds;
  final String? currentTrackId;
  final ValueChanged<LibraryMode> onModeChanged;
  final ValueChanged<MusicTrack> onTrackSelected;
  final ValueChanged<MusicTrack> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ColoredBox(
      color: LisnColors.ink,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: top),
              child: TileBlock(
                color: LisnColors.panel,
                child: SizedBox(
                  height: 116,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        mode.label,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 164,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: ModeTile(
                            mode: LibraryMode.songs,
                            selected: mode == LibraryMode.songs,
                            count: songCount,
                            onTap: onModeChanged,
                          ),
                        ),
                        Expanded(
                          child: ModeTile(
                            mode: LibraryMode.artists,
                            selected: mode == LibraryMode.artists,
                            count: artistCount,
                            onTap: onModeChanged,
                          ),
                        ),
                        Expanded(
                          child: ModeTile(
                            mode: LibraryMode.albums,
                            selected: mode == LibraryMode.albums,
                            count: albumCount,
                            onTap: onModeChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: ModeTile(
                            mode: LibraryMode.folders,
                            selected: mode == LibraryMode.folders,
                            count: folderCount,
                            onTap: onModeChanged,
                          ),
                        ),
                        Expanded(
                          child: ModeTile(
                            mode: LibraryMode.recent,
                            selected: mode == LibraryMode.recent,
                            count: recentCount,
                            onTap: onModeChanged,
                          ),
                        ),
                        Expanded(
                          child: ModeTile(
                            mode: LibraryMode.favorites,
                            selected: mode == LibraryMode.favorites,
                            count: favoriteCount,
                            onTap: onModeChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty && !isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyLibrary(
                error: mode == LibraryMode.songs ? error : '${mode.label}列表为空',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    accent: LisnPalette.byIndex(index),
                    current: track.id == currentTrackId,
                    isFavorite: favoriteIds.contains(track.id),
                    secondaryText: _secondaryForMode(track),
                    onTap: () => onTrackSelected(track),
                    onToggleFavorite: () => onToggleFavorite(track),
                  );
                },
                childCount: tracks.length,
              ),
            ),
        ],
      ),
    );
  }

  String _secondaryForMode(MusicTrack track) {
    switch (mode) {
      case LibraryMode.artists:
        return '${track.artist} · ${track.displayAlbum}';
      case LibraryMode.albums:
        return '${track.displayAlbum} · ${track.artist}';
      case LibraryMode.folders:
        return '${track.folderName} · ${track.artist}';
      case LibraryMode.songs:
      case LibraryMode.recent:
      case LibraryMode.favorites:
        return track.artist;
    }
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.trackCount,
    required this.artistCount,
    required this.albumCount,
    required this.folderCount,
    required this.favoriteCount,
    required this.recentCount,
    required this.currentTrack,
    super.key,
  });

  final int trackCount;
  final int artistCount;
  final int albumCount;
  final int folderCount;
  final int favoriteCount;
  final int recentCount;
  final MusicTrack currentTrack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return ColoredBox(
      color: LisnColors.ink,
      child: ListView(
        padding: EdgeInsets.only(top: top),
        children: [
          SizedBox(
            height: 168,
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: TileBlock(
                    color: LisnColors.magenta,
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          '我的',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.panel,
                    child: StatTile(label: '本地', value: '$trackCount'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 132,
            child: Row(
              children: [
                Expanded(
                  child: TileBlock(
                    color: LisnColors.amber,
                    child: StatTile(
                      label: '艺术家',
                      value: '$artistCount',
                      darkText: true,
                    ),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.violet,
                    child: StatTile(label: '专辑', value: '$albumCount'),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.panelAlt,
                    child: StatTile(label: '文件夹', value: '$folderCount'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 132,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TileBlock(
                    color: LisnColors.panelAlt,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentTrack.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentTrack.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: LisnColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.lime,
                    child: StatTile(
                      label: '收藏',
                      value: '$favoriteCount',
                      darkText: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: Row(
              children: [
                Expanded(
                  child: TileBlock(
                    color: LisnColors.teal,
                    child: StatTile(label: '最近', value: '$recentCount'),
                  ),
                ),
                const Expanded(
                  child: TileBlock(
                    color: LisnColors.panel,
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          '本地音乐',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SearchPanel extends StatefulWidget {
  const SearchPanel({
    required this.open,
    required this.controller,
    required this.tracks,
    required this.favoriteIds,
    required this.bottomReserved,
    required this.onClose,
    required this.onTrackSelected,
    required this.onToggleFavorite,
    super.key,
  });

  final bool open;
  final TextEditingController controller;
  final List<MusicTrack> tracks;
  final Set<String> favoriteIds;
  final double bottomReserved;
  final VoidCallback onClose;
  final ValueChanged<MusicTrack> onTrackSelected;
  final ValueChanged<MusicTrack> onToggleFavorite;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onQueryChanged);
      widget.controller.addListener(_onQueryChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onQueryChanged);
    super.dispose();
  }

  void _onQueryChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final availableHeight =
        math.max(220.0, MediaQuery.of(context).size.height - widget.bottomReserved);
    final height = math.min(availableHeight, 620.0);
    final query = widget.controller.text.trim().toLowerCase();
    final results = query.isEmpty
        ? widget.tracks.take(12).toList()
        : widget.tracks.where((track) {
            return track.title.toLowerCase().contains(query) ||
                track.artist.toLowerCase().contains(query) ||
                track.fileName.toLowerCase().contains(query);
          }).take(40).toList();

    return IgnorePointer(
      ignoring: !widget.open,
      child: Stack(
        children: [
          Positioned.fill(
            bottom: widget.bottomReserved,
            child: AnimatedOpacity(
              opacity: widget.open ? 0.62 : 0,
              duration: const Duration(milliseconds: 220),
              child: GestureDetector(
                onTap: widget.onClose,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 330),
            curve: Curves.easeOutCubic,
            top: widget.open ? 0 : -height,
            left: 0,
            right: 0,
            height: height,
            child: Material(
              color: LisnColors.panel,
              child: Column(
                children: [
                  SizedBox(height: topInset),
                  SizedBox(
                    height: 58,
                    child: TextField(
                      controller: widget.controller,
                      autofocus: widget.open,
                      cursorColor: LisnColors.cyan,
                      style: const TextStyle(
                        color: LisnColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: LisnColors.text,
                        hintText: '搜索 Music 文件夹',
                        hintStyle: const TextStyle(color: Color(0xFF5C6670)),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: LisnColors.ink,
                        ),
                        suffixIcon: IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: LisnColors.ink,
                          ),
                        ),
                        border: InputBorder.none,
                      ),
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(
                            child: Text(
                              '没有匹配曲目',
                              style: TextStyle(color: LisnColors.muted),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final track = results[index];
                              return TrackTile(
                                track: track,
                                accent: LisnPalette.byIndex(index),
                                current: false,
                                isFavorite: widget.favoriteIds.contains(track.id),
                                onTap: () => widget.onTrackSelected(track),
                                onToggleFavorite: () => widget.onToggleFavorite(track),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.track,
    required this.isPlaying,
    required this.progress,
    required this.onTap,
    required this.onTogglePlay,
    required this.onNext,
    super.key,
  });

  final MusicTrack track;
  final bool isPlaying;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LisnColors.panel,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 78,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    AlbumTile(track: track, size: 78),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: LisnColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SquareIconButton(
                      icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      label: isPlaying ? '暂停' : '播放',
                      onTap: onTogglePlay,
                    ),
                    SquareIconButton(
                      icon: Icons.skip_next_rounded,
                      label: '下一曲',
                      onTap: onNext,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 78,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: LisnColors.cyan,
                  backgroundColor: LisnColors.panelAlt,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BottomTileNav extends StatelessWidget {
  const BottomTileNav({
    required this.selectedIndex,
    required this.searchOpen,
    required this.bottomInset,
    required this.onTap,
    super.key,
  });

  final int selectedIndex;
  final bool searchOpen;
  final double bottomInset;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LisnColors.ink,
      child: SizedBox(
        height: 64 + bottomInset,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Row(
            children: [
              _NavTile(
                label: '主页',
                icon: Icons.home_rounded,
                selected: selectedIndex == 0 && !searchOpen,
                color: LisnColors.cyan,
                onTap: () => onTap(0),
              ),
              _NavTile(
                label: '库',
                icon: Icons.library_music_rounded,
                selected: selectedIndex == 1 && !searchOpen,
                color: LisnColors.magenta,
                onTap: () => onTap(1),
              ),
              _NavTile(
                label: '我的',
                icon: Icons.person_rounded,
                selected: selectedIndex == 2 && !searchOpen,
                color: LisnColors.violet,
                onTap: () => onTap(2),
              ),
              _NavTile(
                label: '搜索',
                icon: Icons.search_rounded,
                selected: searchOpen,
                color: LisnColors.amber,
                darkSelected: true,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
    this.darkSelected = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool darkSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected && darkSelected ? LisnColors.ink : LisnColors.text;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? color : LisnColors.panelAlt,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 24),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FullPlayerOverlay extends StatefulWidget {
  const FullPlayerOverlay({
    required this.player,
    required this.track,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onClosed,
    super.key,
  });

  final PlaybackController player;
  final MusicTrack track;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onClosed;

  @override
  State<FullPlayerOverlay> createState() => _FullPlayerOverlayState();
}

class _FullPlayerOverlayState extends State<FullPlayerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _closing = false;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 360),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    await _controller.reverse();
    if (mounted) {
      widget.onClosed();
    }
  }

  double _interval(double start, double end, Curve curve) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: curve),
    ).value;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final topInset = MediaQuery.of(context).padding.top;

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, widget.player]),
        builder: (context, child) {
          final backdrop = Curves.easeOut.transform(_controller.value);
          final volume = _interval(0.00, 0.46, Curves.easeOutCubic);
          final controls = _interval(0.08, 0.58, Curves.easeOutCubic);
          final progress = _interval(0.16, 0.68, Curves.easeOutCubic);
          final title = _interval(0.12, 0.72, Curves.easeOutQuart);
          final cover = _interval(0.02, 0.88, Curves.easeOutBack);
          final topBand = topInset + 54;
          final bottomStack = 84 + 92 + 82 + bottomInset;
          final artTop = topBand;
          final artBottom = bottomStack + 92;
          final artHeight = math.max(150.0, size.height - artTop - artBottom);

          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: backdrop,
                  child: const PlayerMosaicBackground(),
                ),
              ),
              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                height: 54,
                child: Transform.translate(
                  offset: Offset(0, -48 * (1 - backdrop)),
                  child: Row(
                    children: [
                      SquareIconButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        label: '收起播放器',
                        onTap: _close,
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            '正在播放',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                      SquareIconButton(
                        icon: _showLyrics
                            ? Icons.image_rounded
                            : Icons.lyrics_rounded,
                        label: _showLyrics ? '显示封面' : '显示歌词',
                        onTap: () => setState(() => _showLyrics = !_showLyrics),
                      ),
                      SquareIconButton(
                        icon: widget.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: widget.isFavorite ? '取消收藏' : '收藏',
                        onTap: widget.onToggleFavorite,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: artTop,
                height: artHeight,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -260) {
                      _close();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(-size.width * (1 - cover), 0),
                    child: PlayerVisual(
                      track: widget.track,
                      lines: widget.player.lyrics,
                      currentIndex: widget.player.currentLyricIndex(),
                      error: widget.player.lyricsError,
                      showLyrics: _showLyrics,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomStack,
                height: 92,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -260) {
                      _close();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(-size.width * (1 - title), 0),
                    child: PlayerTitleBand(track: widget.track),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 176 + bottomInset,
                height: 82,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 260) {
                      _close();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, 140 * (1 - progress)),
                    child: PlayerProgress(
                      position: widget.player.position,
                      duration: widget.player.duration,
                      onSeek: widget.player.seekTo,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 84 + bottomInset,
                height: 92,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 260) {
                      _close();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, 160 * (1 - controls)),
                    child: PlayerControlBand(
                      isPlaying: widget.player.isPlaying,
                      onPrevious: widget.player.previous,
                      onTogglePlay: widget.player.togglePlay,
                      onNext: widget.player.next,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 84 + bottomInset,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 260) {
                      _close();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, 140 * (1 - volume)),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: PlayerVolumeBand(
                        volume: widget.player.volume,
                        onChanged: widget.player.setVolume,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PlayerMosaicBackground extends StatelessWidget {
  const PlayerMosaicBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: LisnColors.ink,
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(flex: 3, child: ColoredBox(color: LisnColors.panel)),
                Expanded(child: ColoredBox(color: LisnColors.violet)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(child: ColoredBox(color: LisnColors.magenta)),
                Expanded(flex: 2, child: ColoredBox(color: LisnColors.panelAlt)),
                Expanded(child: ColoredBox(color: LisnColors.cyan)),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 2, child: ColoredBox(color: LisnColors.amber)),
                Expanded(child: ColoredBox(color: LisnColors.lime)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerVisual extends StatelessWidget {
  const PlayerVisual({
    required this.track,
    required this.lines,
    required this.currentIndex,
    required this.error,
    required this.showLyrics,
    super.key,
  });

  final MusicTrack track;
  final List<LyricLine> lines;
  final int currentIndex;
  final String? error;
  final bool showLyrics;

  @override
  Widget build(BuildContext context) {
    if (showLyrics) {
      return LyricsBand(
        track: track,
        lines: lines,
        currentIndex: currentIndex,
        error: error,
      );
    }
    return PlayerCover(track: track);
  }
}

class PlayerCover extends StatelessWidget {
  const PlayerCover({required this.track, super.key});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    final color = LisnPalette.fromText(track.title);
    final letter = track.title.isEmpty
        ? 'L'
        : String.fromCharCodes(track.title.runes.take(1)).toUpperCase();
    final foreground = color.computeLuminance() > 0.45 ? LisnColors.ink : Colors.white;
    return CoverArt(
      track: track,
      fit: BoxFit.cover,
      fallback: ColoredBox(
        color: color,
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 18,
              child: Icon(Icons.album_rounded, color: foreground, size: 54),
            ),
            Positioned(
              right: -28,
              bottom: -32,
              child: Text(
                letter,
                style: TextStyle(
                  color: foreground.withOpacity(0.22),
                  fontSize: 220,
                  fontWeight: FontWeight.w900,
                  height: 0.8,
                  letterSpacing: 0,
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Text(
                track.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground.withOpacity(0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoverArt extends StatelessWidget {
  CoverArt({
    required this.track,
    required this.fallback,
    this.fit = BoxFit.cover,
    super.key,
  });

  static final Map<String, Future<Uint8List?>> _cache = {};

  final MusicTrack track;
  final Widget fallback;
  final BoxFit fit;

  Future<Uint8List?> _load() {
    return _cache.putIfAbsent(track.path, () => MusicLibrary.readCoverArt(track.path));
  }

  @override
  Widget build(BuildContext context) {
    if (track.path.isEmpty) {
      return fallback;
    }

    return FutureBuilder<Uint8List?>(
      future: _load(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return fallback;
        }
        return Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}

class AlbumTile extends StatelessWidget {
  const AlbumTile({
    required this.track,
    required this.size,
    this.fallbackColor,
    super.key,
  });

  final MusicTrack track;
  final double size;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final color = fallbackColor ?? LisnPalette.fromText(track.title);
    return SizedBox.square(
      dimension: size,
      child: CoverArt(
        track: track,
        fallback: ColoredBox(
          color: color,
          child: Icon(
            Icons.album_rounded,
            color: color.computeLuminance() > 0.45
                ? LisnColors.ink
                : Colors.white,
            size: size * 0.42,
          ),
        ),
      ),
    );
  }
}

class PlayerTitleBand extends StatelessWidget {
  const PlayerTitleBand({required this.track, super.key});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LisnColors.text,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LisnColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              track.durationLabel,
              style: const TextStyle(
                color: LisnColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LyricsBand extends StatelessWidget {
  const LyricsBand({
    required this.track,
    required this.lines,
    required this.currentIndex,
    required this.error,
    super.key,
  });

  final MusicTrack track;
  final List<LyricLine> lines;
  final int currentIndex;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (track.lyricsPath == null || track.lyricsPath!.isEmpty) {
      return const ColoredBox(
        color: LisnColors.panel,
        child: Center(
          child: Text('未找到同名 LRC 歌词', style: TextStyle(color: LisnColors.muted)),
        ),
      );
    }

    if (lines.isEmpty) {
      return ColoredBox(
        color: LisnColors.panel,
        child: Center(
          child: Text(
            error ?? '歌词加载中',
            style: const TextStyle(color: LisnColors.muted),
          ),
        ),
      );
    }

    final start = math.max(0, currentIndex - 3);
    final end = math.min(lines.length, currentIndex + 4);
    final visible = lines.sublist(start, end);

    return ColoredBox(
      color: LisnColors.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < visible.length; i++)
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    visible[i].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: start + i == currentIndex ? LisnColors.text : LisnColors.muted,
                      fontSize: start + i == currentIndex ? 18 : 13,
                      fontWeight: start + i == currentIndex ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PlayerProgress extends StatelessWidget {
  const PlayerProgress({
    required this.position,
    required this.duration,
    required this.onSeek,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final maxMs = math.max(1, duration.inMilliseconds);
    final value = position.inMilliseconds.clamp(0, maxMs).toDouble();
    return ColoredBox(
      color: LisnColors.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(
                  formatDuration(position),
                  style: const TextStyle(color: LisnColors.muted, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  duration == Duration.zero ? '--:--' : formatDuration(duration),
                  style: const TextStyle(color: LisnColors.muted, fontSize: 12),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: LisnColors.cyan,
                inactiveTrackColor: LisnColors.panelAlt,
                thumbColor: LisnColors.text,
                overlayColor: LisnColors.cyan.withOpacity(0.16),
                trackHeight: 8,
              ),
              child: Slider(
                value: value,
                min: 0,
                max: maxMs.toDouble(),
                onChanged: (next) => onSeek(Duration(milliseconds: next.round())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerControlBand extends StatelessWidget {
  const PlayerControlBand({
    required this.isPlaying,
    required this.onPrevious,
    required this.onTogglePlay,
    required this.onNext,
    super.key,
  });

  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LisnColors.panelAlt,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LargeControlButton(
            icon: Icons.skip_previous_rounded,
            label: '上一曲',
            onTap: onPrevious,
          ),
          LargeControlButton(
            icon: isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            label: isPlaying ? '暂停' : '播放',
            onTap: onTogglePlay,
            hero: true,
          ),
          LargeControlButton(
            icon: Icons.skip_next_rounded,
            label: '下一曲',
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class PlayerVolumeBand extends StatelessWidget {
  const PlayerVolumeBand({
    required this.volume,
    required this.onChanged,
    super.key,
  });

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LisnColors.cyan,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            const Icon(Icons.volume_down_rounded, color: LisnColors.ink),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: LisnColors.ink,
                  inactiveTrackColor: Colors.white70,
                  thumbColor: LisnColors.ink,
                  overlayColor: LisnColors.ink.withOpacity(0.12),
                  trackHeight: 7,
                ),
                child: Slider(
                  value: volume.clamp(0, 1).toDouble(),
                  onChanged: onChanged,
                ),
              ),
            ),
            const Icon(Icons.volume_up_rounded, color: LisnColors.ink),
          ],
        ),
      ),
    );
  }
}

class LargeControlButton extends StatelessWidget {
  const LargeControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hero = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: hero ? 104 : 82,
          height: 92,
          child: Icon(icon, size: hero ? 58 : 40),
        ),
      ),
    );
  }
}

class TileBlock extends StatelessWidget {
  const TileBlock({
    required this.color,
    required this.child,
    super.key,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: color, child: child);
  }
}

class TileButton extends StatelessWidget {
  const TileButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
    this.foreground = LisnColors.text,
    super.key,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: color,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground, size: 28),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ModeTile extends StatelessWidget {
  const ModeTile({
    required this.mode,
    required this.selected,
    required this.count,
    required this.onTap,
    super.key,
  });

  final LibraryMode mode;
  final bool selected;
  final int count;
  final ValueChanged<LibraryMode> onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? LisnColors.cyan : LisnColors.panelAlt;
    final foreground = selected ? LisnColors.ink : LisnColors.text;
    return Material(
      color: color,
      child: InkWell(
        onTap: () => onTap(mode),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mode.icon, color: foreground, size: 22),
              const SizedBox(height: 3),
              Text(
                '${mode.label} $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.darkText = false,
    super.key,
  });

  final String label;
  final String value;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final color = darkText ? LisnColors.ink : LisnColors.text;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.withOpacity(0.78),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({
    this.error,
    super.key,
  });

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.music_off_rounded, size: 42, color: LisnColors.muted),
        const SizedBox(height: 12),
        Text(
          error == null ? 'Music 文件夹里还没有可读取的音频' : error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: LisnColors.muted),
        ),
      ],
    );
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.track,
    required this.accent,
    required this.current,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.secondaryText,
    super.key,
  });

  final MusicTrack track;
  final Color accent;
  final bool current;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final String? secondaryText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: current ? LisnColors.panelAlt : LisnColors.panel,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              ColoredBox(
                color: accent,
                child: AlbumTile(track: track, size: 74, fallbackColor: accent),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        secondaryText ?? track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LisnColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                track.durationLabel,
                style: const TextStyle(color: LisnColors.muted, fontSize: 12),
              ),
              if (onToggleFavorite != null)
                SizedBox(
                  width: 50,
                  height: 74,
                  child: IconButton(
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFavorite ? LisnColors.magenta : LisnColors.muted,
                    ),
                  ),
                )
              else
                const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(icon, size: 30),
        ),
      ),
    );
  }
}

class LisnPalette {
  LisnPalette._();

  static const List<Color> accents = [
    LisnColors.cyan,
    LisnColors.magenta,
    LisnColors.violet,
    LisnColors.amber,
    LisnColors.lime,
    LisnColors.orange,
    LisnColors.teal,
  ];

  static Color byIndex(int index) => accents[index % accents.length];

  static Color fromText(String text) {
    if (text.isEmpty) {
      return accents.first;
    }
    final value = text.codeUnits.fold<int>(0, (sum, code) => sum + code);
    return byIndex(value);
  }
}

class DemoTracks {
  DemoTracks._();

  static const placeholder = MusicTrack(
    id: 'placeholder',
    path: '',
    title: '等待 Music 文件夹',
    artist: 'Lisn',
  );
}
