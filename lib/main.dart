import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'music_library.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      navigationBarColor: LisnColors.ink,
      navigationBarIconBrightness: Brightness.light,
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
        fontFamily: 'Roboto',
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
  static const Color muted = Color(0xFF9BA7B4);
  static const Color cyan = Color(0xFF00A8E8);
  static const Color magenta = Color(0xFFD81B60);
  static const Color lime = Color(0xFF6DD400);
  static const Color amber = Color(0xFFFFB000);
  static const Color violet = Color(0xFF7C4DFF);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _pageController = PageController();
  final TextEditingController _searchController = TextEditingController();

  int _pageIndex = 0;
  bool _searchOpen = false;
  bool _playerOpen = false;
  bool _isPlaying = false;
  bool _loadingLibrary = true;
  String? _libraryError;
  List<MusicTrack> _tracks = const [];
  MusicTrack? _currentTrack;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
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
          _libraryError = '需要读取音频权限才能扫描 Music 文件夹';
        });
        return;
      }

      final tracks = await MusicLibrary.scanMusic();
      if (!mounted) {
        return;
      }
      setState(() {
        _tracks = tracks;
        _currentTrack = tracks.isNotEmpty ? tracks.first : null;
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

  void _selectPage(int index) {
    if (index == 3) {
      setState(() => _searchOpen = true);
      return;
    }
    setState(() {
      _searchOpen = false;
      _pageIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 290),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectTrack(MusicTrack track, {bool play = true}) {
    setState(() {
      _currentTrack = track;
      _isPlaying = play;
    });
  }

  void _playNext() {
    if (_tracks.isEmpty) {
      return;
    }
    final current = _currentTrack;
    final index = current == null ? -1 : _tracks.indexOf(current);
    final next = _tracks[(index + 1) % _tracks.length];
    _selectTrack(next, play: _isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentTrack ?? DemoTracks.placeholder;
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
                      currentTrack: current,
                      isLoading: _loadingLibrary,
                      error: _libraryError,
                      onRefresh: _loadLibrary,
                      onTrackSelected: _selectTrack,
                    ),
                    LibraryPage(
                      tracks: _tracks,
                      isLoading: _loadingLibrary,
                      error: _libraryError,
                      onRefresh: _loadLibrary,
                      onTrackSelected: _selectTrack,
                    ),
                    ProfilePage(
                      trackCount: _tracks.length,
                      currentTrack: current,
                    ),
                  ],
                ),
              ),
              MiniPlayer(
                track: current,
                isPlaying: _isPlaying,
                onTap: () => setState(() => _playerOpen = true),
                onTogglePlay: () => setState(() => _isPlaying = !_isPlaying),
                onNext: _playNext,
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
            onClose: () => setState(() => _searchOpen = false),
            onTrackSelected: (track) {
              _selectTrack(track);
              setState(() => _searchOpen = false);
            },
          ),
          if (_playerOpen)
            FullPlayerOverlay(
              track: current,
              isPlaying: _isPlaying,
              onTogglePlay: () => setState(() => _isPlaying = !_isPlaying),
              onNext: _playNext,
              onPrevious: () {
                if (_tracks.isEmpty) {
                  return;
                }
                final index = _tracks.indexOf(current);
                final previous = _tracks[
                    (index <= 0 ? _tracks.length : index) - 1];
                _selectTrack(previous, play: _isPlaying);
              },
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
    required this.currentTrack,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onTrackSelected,
    super.key,
  });

  final List<MusicTrack> tracks;
  final MusicTrack currentTrack;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<MusicTrack> onTrackSelected;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final recent = tracks.take(6).toList();

    return ColoredBox(
      color: LisnColors.ink,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: top),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 192,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TileBlock(
                      color: LisnColors.cyan,
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
                                fontWeight: FontWeight.w800,
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
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              currentTrack.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xDFFFFFFF),
                                fontSize: 13,
                              ),
                            ),
                          ],
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
              height: 118,
              child: Row(
                children: [
                  Expanded(
                    child: TileButton(
                      color: LisnColors.panelAlt,
                      icon: Icons.history_rounded,
                      label: '最近播放',
                      onTap: () {},
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.violet,
                      icon: Icons.folder_rounded,
                      label: '本地音乐',
                      onTap: () {},
                    ),
                  ),
                  Expanded(
                    child: TileButton(
                      color: LisnColors.lime,
                      foreground: LisnColors.ink,
                      icon: Icons.favorite_rounded,
                      label: '收藏',
                      onTap: () {},
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
            ),
          ),
          if (recent.isEmpty && !isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyLibrary(onRefresh: onRefresh, error: error),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = recent[index];
                  return TrackTile(
                    track: track,
                    accent: LisnPalette.byIndex(index),
                    onTap: () => onTrackSelected(track),
                  );
                },
                childCount: recent.length,
              ),
            ),
        ],
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    required this.tracks,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onTrackSelected,
    super.key,
  });

  final List<MusicTrack> tracks;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<MusicTrack> onTrackSelected;

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
                height: 120,
                child: Row(
                  children: [
                    const Expanded(
                      flex: 2,
                      child: TileBlock(
                        color: LisnColors.panel,
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              '库',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
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
            child: StatusStrip(
              isLoading: isLoading,
              error: error,
              trackCount: tracks.length,
            ),
          ),
          if (tracks.isEmpty && !isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyLibrary(onRefresh: onRefresh, error: error),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = tracks[index];
                  return TrackTile(
                    track: track,
                    accent: LisnPalette.byIndex(index),
                    onTap: () => onTrackSelected(track),
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
    required this.currentTrack,
    super.key,
  });

  final int trackCount;
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
                            fontWeight: FontWeight.w800,
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
                      label: '当前',
                      value: currentTrack.durationLabel,
                      darkText: true,
                    ),
                  ),
                ),
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
                              fontWeight: FontWeight.w700,
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
              ],
            ),
          ),
          const SizedBox(
            height: 118,
            child: Row(
              children: [
                Expanded(
                  child: TileBlock(
                    color: LisnColors.violet,
                    child: Center(
                      child: Icon(Icons.equalizer_rounded, size: 32),
                    ),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.cyan,
                    child: Center(
                      child: Icon(Icons.palette_rounded, size: 32),
                    ),
                  ),
                ),
                Expanded(
                  child: TileBlock(
                    color: LisnColors.lime,
                    child: Center(
                      child: Icon(
                        Icons.offline_bolt_rounded,
                        color: LisnColors.ink,
                        size: 32,
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
    required this.onClose,
    required this.onTrackSelected,
    super.key,
  });

  final bool open;
  final TextEditingController controller;
  final List<MusicTrack> tracks;
  final VoidCallback onClose;
  final ValueChanged<MusicTrack> onTrackSelected;

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

  void _onQueryChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final height = math.min(MediaQuery.of(context).size.height * 0.72, 560.0);
    final query = widget.controller.text.trim().toLowerCase();
    final results = query.isEmpty
        ? widget.tracks.take(8).toList()
        : widget.tracks.where((track) {
            return track.title.toLowerCase().contains(query) ||
                track.artist.toLowerCase().contains(query) ||
                track.fileName.toLowerCase().contains(query);
          }).take(24).toList();

    return IgnorePointer(
      ignoring: !widget.open,
      child: Stack(
        children: [
          AnimatedOpacity(
            opacity: widget.open ? 0.6 : 0,
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
                      style: const TextStyle(fontSize: 18),
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
                                onTap: () => widget.onTrackSelected(track),
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
    required this.onTap,
    required this.onTogglePlay,
    required this.onNext,
    super.key,
  });

  final MusicTrack track;
  final bool isPlaying;
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
          height: 76,
          child: Row(
            children: [
              AlbumTile(track: track, size: 76),
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
                          fontWeight: FontWeight.w700,
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
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
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
    final foreground =
        selected && darkSelected ? LisnColors.ink : LisnColors.text;
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
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w500,
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
    required this.track,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onNext,
    required this.onPrevious,
    required this.onClosed,
    super.key,
  });

  final MusicTrack track;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
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
        animation: _controller,
        builder: (context, child) {
          final backdrop = Curves.easeOut.transform(_controller.value);
          final volume = _interval(0.00, 0.46, Curves.easeOutCubic);
          final controls = _interval(0.08, 0.58, Curves.easeOutCubic);
          final progress = _interval(0.16, 0.68, Curves.easeOutCubic);
          final title = _interval(0.12, 0.72, Curves.easeOutQuart);
          final cover = _interval(0.02, 0.88, Curves.easeOutBack);
          final topBand = topInset + 54;
          final bottomStack = 84 + 92 + 76 + bottomInset;
          final artTop = topBand;
          final artBottom = bottomStack + 92;
          final artHeight = math.max(170.0, size.height - artTop - artBottom);

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
                      const SizedBox(width: 54),
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
                height: 76,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) > 260) {
                      _close();
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, 140 * (1 - progress)),
                    child: PlayerProgress(track: widget.track),
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
                      isPlaying: widget.isPlaying,
                      onPrevious: widget.onPrevious,
                      onTogglePlay: widget.onTogglePlay,
                      onNext: widget.onNext,
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
                      child: const PlayerVolumeBand(),
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
    return ColoredBox(
      color: LisnColors.ink,
      child: Column(
        children: const [
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
    return ColoredBox(
      color: color,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 18,
            child: Icon(
              Icons.album_rounded,
              color: color.computeLuminance() > 0.45
                  ? LisnColors.ink
                  : Colors.white,
              size: 54,
            ),
          ),
          Positioned(
            right: -28,
            bottom: -32,
            child: Text(
              letter,
              style: TextStyle(
                color: (color.computeLuminance() > 0.45
                        ? LisnColors.ink
                        : Colors.white)
                    .withOpacity(0.22),
                fontSize: 220,
                fontWeight: FontWeight.w900,
                height: 0.8,
                letterSpacing: 0,
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              track.durationLabel,
              style: const TextStyle(
                color: LisnColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerProgress extends StatelessWidget {
  const PlayerProgress({required this.track, super.key});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LisnColors.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const Text(
                  '0:00',
                  style: TextStyle(color: LisnColors.muted, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  track.durationLabel,
                  style: const TextStyle(
                    color: LisnColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: LinearProgressIndicator(
                value: 0.28,
                minHeight: 8,
                color: LisnColors.cyan,
                backgroundColor: LisnColors.panelAlt,
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
  const PlayerVolumeBand({super.key});

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
                  value: 0.72,
                  onChanged: (_) {},
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
                    fontWeight: FontWeight.w800,
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
              fontWeight: FontWeight.w700,
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
    super.key,
  });

  final bool isLoading;
  final String? error;
  final int trackCount;

  @override
  Widget build(BuildContext context) {
    final message = isLoading
        ? '正在扫描 Music 文件夹'
        : error != null
            ? error!
            : '已读取 Music 文件夹及子文件夹，共 $trackCount 首';
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
                  error == null
                      ? Icons.folder_open_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
          error == null ? 'Music 文件夹里还没有可读取的音频' : '暂时无法读取 Music 文件夹',
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
    required this.onTap,
    super.key,
  });

  final MusicTrack track;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LisnColors.panel,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              ColoredBox(
                color: accent,
                child: const SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(Icons.music_note_rounded, color: Colors.white),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
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
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  track.durationLabel,
                  style: const TextStyle(
                    color: LisnColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
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
          color: color.computeLuminance() > 0.45
              ? LisnColors.ink
              : Colors.white,
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
    Color(0xFFFF5A3D),
    Color(0xFF00C2A8),
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
