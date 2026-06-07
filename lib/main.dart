import 'dart:async';
import 'dart:math' as math;

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

enum LibraryMode { all, recent, favorites, lyrics }

extension LibraryModeLabel on LibraryMode {
  String get label {
    switch (this) {
      case LibraryMode.all:
        return '全部';
      case LibraryMode.recent:
        return '最近';
      case LibraryMode.favorites:
        return '收藏';
      case LibraryMode.lyrics:
        return '歌词';
    }
  }

  IconData get icon {
    switch (this) {
      case LibraryMode.all:
        return Icons.library_music_rounded;
      case LibraryMode.recent:
        return Icons.history_rounded;
      case LibraryMode.favorites:
        return Icons.favorite_rounded;
      case LibraryMode.lyrics:
        return Icons.lyrics_rounded;
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
  bool _hasAllFilesAccess = true;
  String? _libraryError;
  String? _lastRecentTrackId;
  Timer? _saveTimer;
  List<MusicTrack> _tracks = const [];
  LibraryMode _libraryMode = LibraryMode.all;
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
      final allFiles = await MusicLibrary.hasAllFilesAccess();
      if (!mounted) {
        return;
      }
      if (!granted) {
        setState(() {
          _loadingLibrary = false;
          _hasAllFilesAccess = allFiles;
          _libraryError = '需要读取音频权限才能扫描 Music 文件夹';
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
        _hasAllFilesAccess = allFiles;
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
        _libraryMode = LibraryMode.all;
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

  Future<void> _openAllFilesSettings() async {
    await MusicLibrary.openAllFilesSettings();
    final access = await MusicLibrary.hasAllFilesAccess();
    if (mounted) {
      setState(() => _hasAllFilesAccess = access);
    }
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

  List<MusicTrack> _tracksForMode(LibraryMode mode) {
    switch (mode) {
      case LibraryMode.all:
        return _tracks;
      case LibraryMode.recent:
        return _recentTracks;
      case LibraryMode.favorites:
        return _favoriteTracks;
      case LibraryMode.lyrics:
        return _tracks
            .where((track) => track.lyricsPath != null && track.lyricsPath!.isNotEmpty)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _player.currentTrack ?? DemoTracks.placeholder;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
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
                      hasAllFilesAccess: _hasAllFilesAccess,
                      onRefresh: _loadLibrary,
                      onTrackSelected: (track) => _selectTrack(track),
                      onOpenLibrary: _openLibrary,
                    ),
                    LibraryPage(
                      mode: _libraryMode,
                      tracks: _tracksForMode(_libraryMode),
                      allCount: _tracks.length,
                      recentCount: _recentTracks.length,
                      favoriteCount: _favoriteTracks.length,
                      lyricsCount: _tracksForMode(LibraryMode.lyrics).length,
                      isLoading: _loadingLibrary,
                      error: _libraryError,
                      favoriteIds: _favoriteIds,
                      currentTrackId: _player.currentTrack?.id,
                      onModeChanged: (mode) => setState(() => _libraryMode = mode),
                      onRefresh: _loadLibrary,
                      onTrackSelected: (track) => _selectTrack(
                        track,
                        queue: _tracksForMode(_libraryMode),
                      ),
                      onToggleFavorite: _toggleFavorite,
                    ),
                    ProfilePage(
                      trackCount: _tracks.length,
                      favoriteCount: _favoriteTracks.length,
                      lyricsCount: _tracksForMode(LibraryMode.lyrics).length,
                      recentCount: _recentTracks.length,
                      currentTrack: current,
                      hasAllFilesAccess: _hasAllFilesAccess,
                      onOpenAllFilesSettings: _openAllFilesSettings,
                      onRefresh: _loadLibrary,
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
    required this.hasAllFilesAccess,
    required this.onRefresh,
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
  final bool hasAllFilesAccess;
  final VoidCallback onRefresh;
  final ValueChanged<MusicTrack> onTrackSelected;
  final ValueChanged<LibraryMode> onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final visibleTracks = recentTracks.isEmpty ? tracks.take(8).toList() : recentTracks.take(8).toList();
    final lyricsCount = tracks.where((track) => track.lyricsPath != null && track.lyricsPath!.isNotEmpty).length;

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
                            icon: Icons.sync_rounded,
                            label: '扫描',
                            onTap: onRefresh,
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
                      icon: Icons.history_rounded,
                      label: '最近',
                      onTap: () => onOpenLibrary(LibraryMode.recent),
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.violet,
                      icon: Icons.library_music_rounded,
                      label: '本地',
                      onTap: () => onOpenLibrary(LibraryMode.all),
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.lime,
                      foreground: LisnColors.ink,
                      icon: Icons.lyrics_rounded,
                      label: '$lyricsCount 词',
                      onTap: () => onOpenLibrary(LibraryMode.lyrics),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: StatusStrip(
              isLoading: isLoading,
              error: error,
              trackCount: tracks.length,
              hasAllFilesAccess: hasAllFilesAccess,
            ),
          ),
          if (visibleTracks.isEmpty && !isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyLibrary(onRefresh: onRefresh, error: error),
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
    required this.allCount,
    required this.recentCount,
    required this.favoriteCount,
    required this.lyricsCount,
    required this.isLoading,
    required this.error,
    required this.favoriteIds,
    required this.currentTrackId,
    required this.onModeChanged,
    required this.onRefresh,
    required this.onTrackSelected,
    required this.onToggleFavorite,
    super.key,
  });

  final LibraryMode mode;
  final List<MusicTrack> tracks;
  final int allCount;
  final int recentCount;
  final int favoriteCount;
  final int lyricsCount;
  final bool isLoading;
  final String? error;
  final Set<String> favoriteIds;
  final String? currentTrackId;
  final ValueChanged<LibraryMode> onModeChanged;
  final VoidCallback onRefresh;
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
              child: SizedBox(
                height: 132,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TileBlock(
                        color: LisnColors.panel,
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
                    Expanded(
                      child: TileButton(
                        color: LisnColors.cyan,
                        icon: Icons.refresh_rounded,
                        label: '刷新',
                        onTap: onRefresh,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 82,
              child: Row(
                children: [
                  Expanded(
                    child: ModeTile(
                      mode: LibraryMode.all,
                      selected: mode == LibraryMode.all,
                      count: allCount,
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
                  Expanded(
                    child: ModeTile(
                      mode: LibraryMode.lyrics,
                      selected: mode == LibraryMode.lyrics,
                      count: lyricsCount,
                      onTap: onModeChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: StatusStrip(
              isLoading: isLoading,
              error: error,
              trackCount: allCount,
              hasAllFilesAccess: true,
            ),
          ),
          if (tracks.isEmpty && !isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyLibrary(
                onRefresh: onRefresh,
                error: mode == LibraryMode.all ? error : '${mode.label}列表为空',
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
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.trackCount,
    required this.favoriteCount,
    required this.lyricsCount,
    required this.recentCount,
    required this.currentTrack,
    required this.hasAllFilesAccess,
    required this.onOpenAllFilesSettings,
    required this.onRefresh,
    super.key,
  });

  final int trackCount;
  final int favoriteCount;
  final int lyricsCount;
  final int recentCount;
  final MusicTrack currentTrack;
  final bool hasAllFilesAccess;
  final VoidCallback onOpenAllFilesSettings;
  final VoidCallback onRefresh;

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
                      label: '收藏',
                      value: '$favoriteCount',
                      darkText: true,
                    ),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.violet,
                    child: StatTile(label: '歌词', value: '$lyricsCount'),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.panelAlt,
                    child: StatTile(label: '最近', value: '$recentCount'),
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
                  child: TileButton(
                    color: hasAllFilesAccess ? LisnColors.lime : LisnColors.orange,
                    foreground: hasAllFilesAccess ? LisnColors.ink : LisnColors.text,
                    icon: hasAllFilesAccess
                        ? Icons.folder_open_rounded
                        : Icons.admin_panel_settings_rounded,
                    label: hasAllFilesAccess ? '歌词权限' : '授权歌词',
                    onTap: hasAllFilesAccess ? onRefresh : onOpenAllFilesSettings,
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
    required this.onClose,
    required this.onTrackSelected,
    required this.onToggleFavorite,
    super.key,
  });

  final bool open;
  final TextEditingController controller;
  final List<MusicTrack> tracks;
  final Set<String> favoriteIds;
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
    final height = math.min(MediaQuery.of(context).size.height * 0.72, 580.0);
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
          AnimatedOpacity(
            opacity: widget.open ? 0.62 : 0,
            duration: const Duration(milliseconds: 220),
            child: GestureDetector(
              onTap: widget.onClose,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 330),
            curve: Curves.easeOutCubic,
            top: widget.open ? 0 : -height - topInset,
            left: 0,
            right: 0,
            height: height + topInset,
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
          final artBottom = bottomStack + 150;
          final artHeight = math.max(150.0, size.height - artTop - artBottom);
          final lyricsHeight = math.min(148.0, math.max(96.0, size.height * 0.18));

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
                    child: PlayerCover(track: widget.track),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomStack + lyricsHeight,
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
                bottom: bottomStack,
                height: lyricsHeight,
                child: Transform.translate(
                  offset: Offset(-size.width * 0.42 * (1 - title), 0),
                  child: LyricsBand(
                    track: widget.track,
                    lines: widget.player.lyrics,
                    currentIndex: widget.player.currentLyricIndex(),
                    error: widget.player.lyricsError,
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
    return ColoredBox(
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

    final start = math.max(0, currentIndex - 1);
    final end = math.min(lines.length, currentIndex + 2);
    final visible = lines.sublist(start, end);

    return ColoredBox(
      color: LisnColors.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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

class StatusStrip extends StatelessWidget {
  const StatusStrip({
    required this.isLoading,
    required this.error,
    required this.trackCount,
    required this.hasAllFilesAccess,
    super.key,
  });

  final bool isLoading;
  final String? error;
  final int trackCount;
  final bool hasAllFilesAccess;

  @override
  Widget build(BuildContext context) {
    final message = isLoading
        ? '正在扫描 Music 文件夹'
        : error != null
            ? error!
            : hasAllFilesAccess
                ? '已读取 Music 文件夹及子文件夹，共 $trackCount 首'
                : '已读取音频；如歌词缺失，请在“我的”中授权歌词文件访问';
    return ColoredBox(
      color: error == null ? LisnColors.panel : LisnColors.magenta,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: LisnColors.text,
                  ),
                )
              else
                Icon(
                  error == null ? Icons.folder_open_rounded : Icons.error_outline_rounded,
                  size: 18,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({
    required this.onRefresh,
    this.error,
    super.key,
  });

  final VoidCallback onRefresh;
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
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新扫描'),
          ),
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
    super.key,
  });

  final MusicTrack track;
  final Color accent;
  final bool current;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;

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
                child: SizedBox(
                  width: 74,
                  height: 74,
                  child: Icon(
                    current ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                    color: Colors.white,
                  ),
                ),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: LisnColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (track.lyricsPath != null && track.lyricsPath!.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.lyrics_rounded, color: LisnColors.cyan, size: 16),
                            ),
                        ],
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

class AlbumTile extends StatelessWidget {
  const AlbumTile({
    required this.track,
    required this.size,
    super.key,
  });

  final MusicTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = LisnPalette.fromText(track.title);
    return ColoredBox(
      color: color,
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.album_rounded,
          color: color.computeLuminance() > 0.45 ? LisnColors.ink : Colors.white,
          size: size * 0.42,
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
