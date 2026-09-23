import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_state.dart';
import 'artwork_image.dart';
import 'lyrics_parser.dart';
import 'm3e_beat_stage.dart';
import 'models.dart';
import 'lyric_colors.dart';

// Keep album hue in the glyphs while reserving luminance for readability.
Color _albumLyricInk(List<Color> palette, bool dark) {
  final source = palette.isEmpty
      ? HSLColor.fromColor(Colors.grey)
      : palette
            .map(HSLColor.fromColor)
            .reduce((a, b) => a.saturation >= b.saturation ? a : b);
  return source
      .withSaturation(
        source.saturation <= .02
            ? 0
            : (source.saturation * .85).clamp(.24, .72),
      )
      .withLightness(dark ? .95 : .12)
      .toColor();
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final PageController controller;
  int selectedPage = 0;
  int? targetPage;

  @override
  void initState() {
    super.initState();
    controller = PageController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void selectPage(int index) {
    if (index == selectedPage) return;
    targetPage = index;
    setState(() => selectedPage = index);
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(index);
    } else {
      controller.animateToPage(
        index,
        duration: Duration(
          milliseconds: (index - (controller.page ?? index)).abs() > 1
              ? 340
              : 260,
        ),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void pageChanged(int index) {
    if (targetPage != null) {
      if (index == targetPage) targetPage = null;
      return;
    }
    if (index != selectedPage) setState(() => selectedPage = index);
  }

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    const pages = [HomeScreen(), ExploreScreen(), LibraryScreen()];
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final content = SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                // The solid mini player floats over the full scroll viewport.
                // Scroll content supplies trailing space, not an opaque strip.
                bottom: 0,
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (event) {
                    if (event.depth == 0 && controller.hasClients) {
                      final settled = controller.page!.round();
                      targetPage = null;
                      if (selectedPage != settled) {
                        setState(() => selectedPage = settled);
                      }
                    }
                    return false;
                  },
                  child: PageView(
                    controller: controller,
                    onPageChanged: pageChanged,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      for (var index = 0; index < pages.length; index++)
                        TickerMode(
                          enabled: selectedPage == index,
                          // Do not cache an entire tab as a GPU texture. Rapid
                          // tab changes can retain multiple full-screen layers
                          // on some Android Vulkan drivers.
                          child: pages[index],
                        ),
                    ],
                  ),
                ),
              ),
              if (state.hasCurrent)
                Positioned(
                  left: wide ? 12 : 0,
                  right: wide ? 12 : 0,
                  bottom: wide ? 16 + systemBottom : 10,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: wide ? 720 : double.infinity,
                      ),
                      child: MiniPlayerHero(state: state),
                    ),
                  ),
                ),
            ],
          ),
        );
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: _GlassSurface(
                    enabled: false,
                    borderRadius: BorderRadius.zero,
                    child: NavigationRail(
                      selectedIndex: selectedPage,
                      onDestinationSelected: selectPage,
                      labelType: NavigationRailLabelType.all,
                      groupAlignment: -.55,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: Text('首页'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.explore_outlined),
                          selectedIcon: Icon(Icons.explore_rounded),
                          label: Text('探索'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.person_outline_rounded),
                          selectedIcon: Icon(Icons.person_rounded),
                          label: Text('我的'),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          body: content,
          bottomNavigationBar: _GlassSurface(
            enabled: false,
            borderRadius: BorderRadius.zero,
            child: NavigationBar(
              selectedIndex: selectedPage,
              onDestinationSelected: selectPage,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: '探索',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: '我的',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required bool enabled,
    required BorderRadius borderRadius,
    required this.child,
    double surfaceAlpha = .58,
    double blurSigma = 24,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

double _shellBottomClearance(BuildContext context, MelodyState state) {
  final systemBottom = MediaQuery.paddingOf(context).bottom;
  if (MediaQuery.sizeOf(context).width >= 840) {
    return state.hasCurrent ? 112 + systemBottom : 28 + systemBottom;
  }
  return state.hasCurrent ? 106 : 16;
}

class PageTitle extends StatelessWidget {
  const PageTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: MelodyScope.of(context).emphasisWeight,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    final continueTracks = state.recent.isEmpty ? state.queue : state.recent;
    final now = DateTime.now();
    final hour = now.hour;
    final greetings = hour < 5
        ? const ['夜深了，听点轻柔的？', '还没睡吗，放首歌吧']
        : hour < 9
        ? const ['早上好，听点什么？', '新的一天，从音乐开始']
        : hour < 11
        ? const ['上午好，听点什么？', '今天感觉如何？']
        : hour < 13
        ? const ['中午好，歇一会儿吧', '午间时光，听点什么？']
        : hour < 17
        ? const ['午后好，听点什么？', '给下午一点旋律']
        : hour < 19
        ? const ['傍晚好，放松一下吧', '下班路上，来点音乐？']
        : hour < 23
        ? const ['晚上好，听点什么？', '今晚，让音乐陪你']
        : const ['夜深了，听点轻柔的？', '用音乐为今天收尾吧'];
    final greeting = greetings[now.day % greetings.length];
    return CustomScrollView(
      key: const PageStorageKey('home-scroll'),
      slivers: [
        SliverToBoxAdapter(child: PageTitle(greeting, subtitle: 'SONORYNTH')),
        SliverToBoxAdapter(
          child: SectionHeader(
            '继续聆听',
            action: continueTracks.isEmpty ? null : '播放全部',
            onTap: continueTracks.isEmpty
                ? null
                : () => state.playTrack(
                    continueTracks.first,
                    from: continueTracks,
                  ),
          ),
        ),
        if (continueTracks.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text('播放歌曲后会在这里继续上次的聆听。'),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: HorizontalTracks(
                tracks: continueTracks.take(8).toList(),
                shapeId: 'continue_listening',
                shapeTitle: '继续聆听整组形状',
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SectionHeader('你的音乐概览')),
        SliverToBoxAdapter(
          child: AdaptiveM3Grid(
            preferredHeight: 148,
            children: [
              StatTile(
                icon: Icons.favorite_rounded,
                value: '${state.likedTrackIds.length}',
                label: '喜欢的歌曲',
                tone: 0,
                shape: M3ContentShape.values[state.cardShape('liked', 0)],
                onTap: () {
                  if (state.cloudPlaylists.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistScreen(
                          playlist: state.cloudPlaylists.first,
                        ),
                      ),
                    );
                  } else {
                    _openTrackCollection(
                      context,
                      title: '喜欢的歌曲',
                      tracks: _knownLikedTracks(state),
                      emptyMessage: '暂时没有可显示的喜欢歌曲',
                    );
                  }
                },
                onLongPress: () =>
                    _editOverviewCardShape(context, state, 'liked'),
              ),
              StatTile(
                icon: Icons.queue_music_rounded,
                value: '${state.allPlaylists.length}',
                label: '创建的歌单',
                tone: 1,
                shape: M3ContentShape.values[state.cardShape('playlists', 1)],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PlaylistCollectionScreen(playlists: state.allPlaylists),
                  ),
                ),
                onLongPress: () =>
                    _editOverviewCardShape(context, state, 'playlists'),
              ),
              StatTile(
                icon: Icons.history_rounded,
                value: '${state.recent.length}',
                label: '最近播放',
                tone: 2,
                shape: M3ContentShape.values[state.cardShape('recent', 2)],
                onTap: () => _openTrackCollection(
                  context,
                  title: '最近播放',
                  tracks: state.recent,
                  emptyMessage: '还没有播放历史',
                ),
                onLongPress: () =>
                    _editOverviewCardShape(context, state, 'recent'),
              ),
              StatTile(
                icon: Icons.high_quality_rounded,
                value: state.quality.label,
                label: '当前音质',
                tone: 3,
                shape: M3ContentShape.values[state.cardShape('quality', 3)],
                onTap: () => _qualitySheet(context),
                onLongPress: () =>
                    _editOverviewCardShape(context, state, 'quality'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(child: WeeklyListeningCard(state: state)),
        SliverToBoxAdapter(
          child: SizedBox(height: _shellBottomClearance(context, state)),
        ),
      ],
    );
  }
}

class WeeklyListeningCard extends StatelessWidget {
  const WeeklyListeningCard({super.key, required this.state});
  final MelodyState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = M3ContentShape.values[state.cardShape('weekly_listening', 4)];
    final border = _m3ContentBorder(shape);
    final week = state.stats.currentWeek;
    final maxSeconds = week.fold<int>(
      1,
      (value, day) => day.seconds > value ? day.seconds : value,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Card(
        color: scheme.surfaceContainerLow,
        shape: border,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: border,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ListeningStatsScreen()),
          ),
          onLongPress: () => _editCardShape(
            context,
            state,
            'weekly_listening',
            title: '本周聆听形状',
          ),
          child: Padding(
            padding: _m3ShapeSafePadding(shape, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.equalizer_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '本周聆听',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '${state.stats.streakDays} 天连续',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    state.stats.weekLabel,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '今天 ${state.stats.todayLabel} · ${state.stats.todayPlays} 次播放',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 72,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final day in week)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutCubic,
                                width: 12,
                                height: 6 + 42 * day.seconds / maxSeconds,
                                decoration: BoxDecoration(
                                  color: day.isToday
                                      ? scheme.primary
                                      : scheme.secondary.withValues(alpha: .58),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                day.label,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: day.isToday
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '本周 ${state.stats.weekPlays} 次播放 · 累计 ${state.stats.totalPlays} 次',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return CustomScrollView(
      key: const PageStorageKey('explore-scroll'),
      slivers: [
        const SliverToBoxAdapter(child: PageTitle('探索', subtitle: '发现下一首喜欢')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SearchBar(
              controller: controller,
              hintText: '搜索歌曲或歌手',
              elevation: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused) ? 3 : 0,
              ),
              shadowColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.shadow.withValues(alpha: .24),
              ),
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      controller.clear();
                      state.search('');
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: state.search,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: SegmentedButton<MusicSearchSource>(
              style: ButtonStyle(
                side: const WidgetStatePropertyAll(BorderSide.none),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                ),
              ),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: MusicSearchSource.all,
                  icon: Icon(Icons.library_music_rounded),
                  label: Text('全部'),
                ),
                ButtonSegment(
                  value: MusicSearchSource.netease,
                  icon: Icon(Icons.cloud_rounded),
                  label: Text('网易云'),
                ),
                ButtonSegment(
                  value: MusicSearchSource.kuwo,
                  icon: Icon(Icons.graphic_eq_rounded),
                  label: Text('酷我'),
                ),
              ],
              selected: {state.searchSource},
              onSelectionChanged: (selection) =>
                  state.setSearchSource(selection.first),
            ),
          ),
        ),
        if (state.hotSearches.isNotEmpty && state.searchResults.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: state.hotSearches.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ActionChip(
                  side: BorderSide.none,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerLow,
                  label: Text(state.hotSearches[index]),
                  onPressed: () {
                    controller.text = state.hotSearches[index];
                    state.search(controller.text);
                  },
                ),
              ),
            ),
          ),
        if (state.searching)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: MorphingLoadingIndicator()),
            ),
          )
        else if (state.searchResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              '搜索结果',
              action: '${state.searchResults.length} 首',
            ),
          ),
          TrackSliver(tracks: state.searchResults, showSource: true),
        ] else ...[
          const SliverToBoxAdapter(
            child: SectionHeader('为你精选', action: '每日更新'),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 210,
              child: HorizontalTracks(
                tracks: state.recommendations,
                shapeId: 'featured_tracks',
                shapeTitle: '为你精选整组形状',
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SectionHeader('推荐歌单', action: '个性推荐'),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 196,
              child: HorizontalPlaylists(
                playlists: state.recommendedPlaylists,
                shapeId: 'recommended_playlists',
                shapeTitle: '推荐歌单整组形状',
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader('此刻适合')),
          SliverToBoxAdapter(
            child: AdaptiveM3Grid(
              preferredHeight: 104,
              minCardWidth: 190,
              children: [
                for (final item in const [
                  ('专注', Icons.blur_on_rounded, 0),
                  ('通勤', Icons.directions_subway_rounded, 1),
                  ('运动', Icons.directions_run_rounded, 2),
                  ('睡眠', Icons.dark_mode_rounded, 1),
                ])
                  MoodCard(
                    item.$1,
                    item.$2,
                    item.$3,
                    shape:
                        M3ContentShape.values[state.cardShape('mood_group', 3)],
                    onTap: () {
                      controller.text = '${item.$1} 音乐';
                      state.search(controller.text);
                    },
                    onLongPress: () => _editCardShape(
                      context,
                      state,
                      'mood_group',
                      title: '此刻适合整组形状',
                    ),
                  ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader('最近流行')),
          TrackSliver(tracks: state.recommendations.reversed.toList()),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: _shellBottomClearance(context, state)),
        ),
      ],
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: PageTitle(
            '我的',
            subtitle: '你的音乐空间',
            actions: [
              IconButton(
                tooltip: '同步音乐资料',
                onPressed: state.refreshing ? null : state.refreshAll,
                icon: state.refreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: MorphingLoadingIndicator(size: 20),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
              IconButton.filledTonal(
                tooltip: '设置',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings_rounded),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Card(
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: ArtworkAvatar(
                  url: state.avatarUrl,
                  diameter: 44,
                  fallback: const Icon(Icons.person_rounded, size: 30),
                ),
                title: Text(
                  state.loggedIn ? state.nickname : '登录网易云音乐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                  ),
                ),
                subtitle: Text(
                  state.loggedIn ? '歌单与推荐已同步' : '同步收藏、歌单与个性推荐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: state.loggedIn
                    ? () => _accountSheet(context)
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            '我的歌单',
            action: '新建',
            onTap: () => _createPlaylist(context),
          ),
        ),
        SliverList.builder(
          itemCount: state.allPlaylists.length,
          itemBuilder: (context, index) {
            final playlist = state.allPlaylists[index];
            return PlaylistTile(
              playlist: playlist,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistScreen(playlist: playlist),
                ),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SectionHeader('快捷入口')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverList.list(
            children: [
              ShortcutTile(
                icon: Icons.history_rounded,
                title: '最近播放',
                subtitle: '${state.recent.length} 首歌曲',
                onTap: () => _openTrackCollection(
                  context,
                  title: '最近播放',
                  tracks: state.recent,
                  emptyMessage: '还没有播放历史',
                ),
              ),
              ShortcutTile(
                icon: Icons.bar_chart_rounded,
                title: '听歌统计',
                subtitle: '本周 ${state.stats.weekLabel}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ListeningStatsScreen(),
                  ),
                ),
              ),
              ShortcutTile(
                icon: Icons.settings_rounded,
                title: '设置',
                subtitle: '播放、歌词、音源与隐私',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: _shellBottomClearance(context, state)),
        ),
      ],
    );
  }
}

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, required this.state, this.preview = false});
  final MelodyState state;
  final bool preview;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class MiniPlayerHero extends StatelessWidget {
  const MiniPlayerHero({super.key, required this.state});
  final MelodyState state;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: MiniPlayer(state: state),
  );
}

class _MiniPlayerState extends State<MiniPlayer> {
  final surfaceKey = GlobalKey();
  bool opening = false;
  double openingDrag = 0;
  _NowPlayingDrawerRoute? interactiveRoute;

  Rect get sourceRect {
    final box = surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    if (box == null || !box.hasSize) {
      return Rect.fromLTWH(12, screen.height - 160, screen.width - 24, 70);
    }
    final origin = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      origin.dx,
      origin.dy.clamp(120, screen.height - 70),
      box.size.width,
      box.size.height,
    );
  }

  _NowPlayingDrawerRoute pushPlayer({required bool interactive}) {
    final route = _NowPlayingDrawerRoute(
      sourceRect: sourceRect,
      interactiveOpening: interactive,
    );
    opening = true;
    Navigator.push(context, route).whenComplete(() {
      if (mounted) {
        opening = false;
        interactiveRoute = null;
      }
    });
    return route;
  }

  void openPlayer() {
    if (opening) return;
    pushPlayer(interactive: false);
  }

  void updateOpening(DragUpdateDetails details) {
    if (opening) return;
    // Pushing during a drag cancels the source route's active pointers.
    // Recognise the swipe first, then start the normal opening transition.
    openingDrag = math.max(0, openingDrag - details.delta.dy);
  }

  void endOpening(DragEndDetails details) {
    final shouldOpen =
        openingDrag >= 28 || (details.primaryVelocity ?? 0) < -350;
    openingDrag = 0;
    if (shouldOpen) openPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onSurface;
    return Padding(
      padding: widget.preview
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => openingDrag = 0,
        onVerticalDragCancel: () => openingDrag = 0,
        onVerticalDragUpdate: updateOpening,
        onVerticalDragEnd: endOpening,
        child: SizedBox(
          key: surfaceKey,
          child: _GlassSurface(
            enabled: false,
            borderRadius: BorderRadius.circular(24),
            child: Material(
              color: scheme.surfaceContainerHigh,
              elevation: 1,
              shadowColor: scheme.shadow.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: openPlayer,
                child: SizedBox(
                  height: 70,
                  child: Stack(
                    children: [
                      if (state.gradientPlayerBackground &&
                          state.singleColorPlayerBackground)
                        Positioned.fill(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: AlbumBackground.gradientColors(
                                  state.coverPalette,
                                  scheme.brightness == Brightness.dark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            Cover(track: state.current, size: 54, radius: 16),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.current.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontWeight: MelodyScope.of(
                                        context,
                                      ).emphasisWeight,
                                    ),
                                  ),
                                  Text(
                                    state.current.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: foreground.withValues(
                                            alpha: .74,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            ExpressiveIconButton(
                              tooltip: state.playing ? '暂停' : '播放',
                              onPressed: state.togglePlay,
                              selected: state.playing,
                              icon: Icon(
                                state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: '下一首',
                              onPressed: () => state.skip(1),
                              color: foreground,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                            IconButton(
                              tooltip: '播放队列',
                              onPressed: () => _showQueue(context),
                              color: foreground,
                              icon: const Icon(Icons.queue_music_rounded),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 3,
                        child: state.preparingPlayback
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  color: foreground,
                                  backgroundColor: foreground.withValues(
                                    alpha: .18,
                                  ),
                                  semanticsLabel: '正在准备播放',
                                  // Flutter exposes the current Material
                                  // appearance through this compatibility flag.
                                  // ignore: deprecated_member_use
                                  year2023: false,
                                ),
                              )
                            : _PlaybackTimelineBuilder(
                                state: state,
                                builder: (context, timeline) =>
                                    _MiniPlaybackProgress(
                                      color: foreground,
                                      value:
                                          timeline.duration.inMilliseconds <= 0
                                          ? 0
                                          : (timeline.position.inMilliseconds /
                                                    timeline
                                                        .duration
                                                        .inMilliseconds)
                                                .clamp(0, 1),
                                    ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Route<void> _lyricsRoute() =>
    MaterialPageRoute<void>(builder: (context) => const LyricsScreen());

class _NowPlayingDrawerRoute extends PageRoute<void> {
  _NowPlayingDrawerRoute({
    required this.sourceRect,
    required this.interactiveOpening,
  }) : directGestureProgress = interactiveOpening;

  final Rect sourceRect;
  final bool interactiveOpening;
  AnimationController? drawerController;
  bool removing = false;
  bool directGestureProgress;

  static const double _snapThreshold = .5;
  static const double _flingThreshold = 650;
  double get dragDistance => sourceRect.top.clamp(240, 900);

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => '关闭播放器';

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 420);

  @override
  AnimationController createAnimationController() {
    drawerController = super.createAnimationController();
    return drawerController!;
  }

  @override
  TickerFuture didPush() {
    final transition = super.didPush();
    if (!interactiveOpening) return transition;
    // Navigator installs the route controller during push. Freeze it here,
    // before the first frame, so the opening progress belongs to the finger
    // rather than to the route's automatic forward animation.
    drawerController!
      ..stop()
      ..value = 0;
    return TickerFuture.complete();
  }

  void updateInteractiveOpening(DragUpdateDetails details) {
    final controller = drawerController;
    if (controller == null || removing) return;
    controller.stop();
    controller.value = (controller.value - details.delta.dy / dragDistance)
        .clamp(0, 1);
  }

  Future<void> endInteractiveOpening(DragEndDetails details) async {
    final controller = drawerController;
    if (controller == null || removing) return;
    await _settleAfterDrag(details);
  }

  void updateInteractiveClosing(DragUpdateDetails details) {
    final controller = drawerController;
    if (controller == null || removing) return;
    directGestureProgress = true;
    controller.stop();
    controller.value = (controller.value - details.delta.dy / dragDistance)
        .clamp(0, 1);
  }

  Future<void> endInteractiveClosing(DragEndDetails details) async {
    final controller = drawerController;
    if (controller == null || removing) return;
    await _settleAfterDrag(details);
  }

  Future<void> _settleAfterDrag(DragEndDetails details) async {
    final controller = drawerController;
    if (controller == null || removing) return;
    final velocity = details.primaryVelocity ?? 0;
    final hasFling = velocity.abs() >= _flingThreshold;
    final shouldOpen = hasFling
        ? velocity < 0
        : controller.value >= _snapThreshold;
    final normalizedVelocity = (-velocity / dragDistance).clamp(-4.0, 4.0);
    final settleVelocity = shouldOpen
        ? math.max(1.15, normalizedVelocity)
        : math.min(-1.15, normalizedVelocity);

    // Keep progress linear while the critically damped spring completes the
    // remaining distance. This preserves continuity with the user's finger.
    directGestureProgress = true;
    removing = !shouldOpen;
    await controller.fling(
      velocity: settleVelocity,
      springDescription: SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 460,
        ratio: 1,
      ),
    );
    if (shouldOpen) {
      directGestureProgress = false;
      changedInternalState();
    } else {
      navigator?.removeRoute(this);
    }
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _SwipeDownDismiss(route: this, child: const _NowPlayingHost());

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animation.status == AnimationStatus.completed &&
        !directGestureProgress) {
      return child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = directGestureProgress
            ? animation.value
            : animation.status == AnimationStatus.reverse
            ? const Cubic(.3, 0, .8, .15).transform(animation.value)
            : const Cubic(.05, .7, .1, 1).transform(animation.value);
        final screen = MediaQuery.sizeOf(context);
        final bounds = Rect.lerp(sourceRect, Offset.zero & screen, value)!;
        final radius = 24 * (1 - value);
        final contentOpacity = const Interval(
          .30,
          .72,
          curve: Curves.easeOutCubic,
        ).transform(value);
        final miniContentOpacity =
            1 -
            const Interval(
              .02,
              .28,
              curve: Curves.easeOutCubic,
            ).transform(value);
        final scheme = Theme.of(context).colorScheme;
        final state = MelodyScope.of(context);
        final singleColor =
            state.gradientPlayerBackground && state.singleColorPlayerBackground;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .16 * value),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: bounds,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      scheme.surfaceContainerHigh,
                      scheme.surfaceContainer,
                      value,
                    ),
                    gradient: singleColor
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: AlbumBackground.gradientColors(
                              state.coverPalette,
                              scheme.brightness == Brightness.dark,
                            ),
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      OverflowBox(
                        alignment: Alignment.topCenter,
                        minWidth: screen.width,
                        maxWidth: screen.width,
                        minHeight: screen.height,
                        maxHeight: screen.height,
                        child: Opacity(opacity: contentOpacity, child: child),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 70,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: miniContentOpacity,
                            child: const ClipRect(
                              child: _NowPlayingTransitionPreview(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NowPlayingTransitionPreview extends StatelessWidget {
  const _NowPlayingTransitionPreview();

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return MiniPlayer(state: state, preview: true);
  }
}

class _SwipeDownDismiss extends StatelessWidget {
  const _SwipeDownDismiss({required this.route, required this.child});

  final _NowPlayingDrawerRoute route;
  final Widget child;

  @override
  Widget build(BuildContext context) => _NowPlayingDismissScope(
    onUpdate: route.updateInteractiveClosing,
    onEnd: route.endInteractiveClosing,
    child: Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 84,
          right: 84,
          height: MediaQuery.paddingOf(context).top + 70,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: route.updateInteractiveClosing,
            onVerticalDragEnd: route.endInteractiveClosing,
          ),
        ),
      ],
    ),
  );
}

class _NowPlayingDismissScope extends InheritedWidget {
  const _NowPlayingDismissScope({
    required this.onUpdate,
    required this.onEnd,
    required super.child,
  });

  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  static _NowPlayingDismissScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NowPlayingDismissScope>()!;

  @override
  bool updateShouldNotify(_NowPlayingDismissScope oldWidget) => false;
}

class _NowPlayingHost extends StatelessWidget {
  const _NowPlayingHost();

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => const PlayerScreen(),
    ),
  );
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return _buildPlayer(context);
  }

  Widget _buildPlayer(BuildContext context) {
    final state = MelodyScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final coverShape =
        M3ContentShape.values[state.cardShape('player_cover', 4)];
    final coverBorder = _m3ContentBorder(coverShape);
    final dismiss = _NowPlayingDismissScope.of(context);
    if (MediaQuery.sizeOf(context).width >= 840) {
      return _TabletPlayerScreen(dismiss: dismiss);
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: dismiss.onUpdate,
      onVerticalDragEnd: dismiss.onEnd,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainer,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          leading: IconButton(
            tooltip: '收起播放器',
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          title: Column(
            children: [
              Text('正在播放', style: Theme.of(context).textTheme.labelMedium),
              Text(
                state.current.album,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () => _trackActions(context, state.current),
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (state.gradientPlayerBackground)
              Positioned.fill(
                child: AlbumBackground(
                  singleColor: state.singleColorPlayerBackground,
                  colors: state.coverPalette,
                  trackId: state.current.id,
                  coverUrl: state.current.coverUrl,
                  lowPower: state.efficientRendering,
                  animate: state.playing,
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Hero(
                          tag: 'now-cover',
                          child: GestureDetector(
                            onTap: () =>
                                Navigator.push(context, _lyricsRoute()),
                            onLongPress: () => _editCardShape(
                              context,
                              state,
                              'player_cover',
                              title: '播放页封面形状',
                            ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Material(
                                shape: coverBorder,
                                clipBehavior: Clip.antiAlias,
                                child: Cover(
                                  track: state.current,
                                  size: 500,
                                  radius: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.current.title,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: MelodyScope.of(
                                        context,
                                      ).emphasisWeight,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.current.artist,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        ExpressiveIconButton(
                          onPressed: () => state.toggleLike(state.current),
                          selected: state.isLiked(state.current),
                          tonal: true,
                          icon: Icon(
                            state.isLiked(state.current)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                        ),
                      ],
                    ),
                    if (state.message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          state.message!,
                          style: TextStyle(color: scheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 12),
                    _PlaybackTimelineBuilder(
                      state: state,
                      builder: (context, timeline) => Column(
                        children: [
                          M3EWavyProgressIndicator(
                            indeterminate: state.preparingPlayback,
                            value: timeline.duration.inMilliseconds == 0
                                ? 0
                                : (timeline.position.inMilliseconds /
                                          timeline.duration.inMilliseconds)
                                      .clamp(0, 1),
                            onChanged: state.preparingPlayback
                                ? null
                                : (v) => state.seek(
                                    Duration(
                                      milliseconds:
                                          (timeline.duration.inMilliseconds * v)
                                              .round(),
                                    ),
                                  ),
                            animate: state.playing || state.preparingPlayback,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_duration(timeline.position)),
                              Text(
                                '-${_duration(timeline.duration - timeline.position)}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PlayerTransportControls(state: state),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _PlayerAction(
                          icon: Icons.lyrics_rounded,
                          label: '歌词',
                          onTap: () => Navigator.push(context, _lyricsRoute()),
                        ),
                        _PlayerAction(
                          icon: Icons.high_quality_rounded,
                          label: state.quality.label,
                          onTap: () => _qualitySheet(context),
                        ),
                        _PlayerAction(
                          icon: Icons.queue_music_rounded,
                          label: '队列',
                          onTap: () => _showQueue(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletPlayerScreen extends StatelessWidget {
  const _TabletPlayerScreen({required this.dismiss});

  final _NowPlayingDismissScope dismiss;

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final shape = M3ContentShape.values[state.cardShape('player_cover', 4)];
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: dismiss.onUpdate,
      onVerticalDragEnd: dismiss.onEnd,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainer,
        body: Stack(
          children: [
            if (state.gradientPlayerBackground)
              Positioned.fill(
                child: AlbumBackground(
                  singleColor: state.singleColorPlayerBackground,
                  colors: state.coverPalette,
                  trackId: state.current.id,
                  coverUrl: state.current.coverUrl,
                  lowPower: state.efficientRendering,
                  animate: state.playing,
                ),
              ),
            SafeArea(
              child: Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(36, 20, 36, 28),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: '收起播放器',
                                onPressed: () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () =>
                                    _trackActions(context, state.current),
                                icon: const Icon(Icons.more_vert_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                  maxHeight: 520,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Material(
                                    shape: _m3ContentBorder(shape),
                                    clipBehavior: Clip.antiAlias,
                                    child: Cover(
                                      track: state.current,
                                      size: 620,
                                      radius: 0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.current.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: state.emphasisWeight,
                                          ),
                                    ),
                                    Text(
                                      state.current.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              ExpressiveIconButton(
                                onPressed: () =>
                                    state.toggleLike(state.current),
                                selected: state.isLiked(state.current),
                                tonal: true,
                                icon: Icon(
                                  state.isLiked(state.current)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _PlaybackTimelineBuilder(
                            state: state,
                            builder: (context, timeline) => Column(
                              children: [
                                M3EWavyProgressIndicator(
                                  indeterminate: state.preparingPlayback,
                                  value: timeline.duration.inMilliseconds == 0
                                      ? 0
                                      : (timeline.position.inMilliseconds /
                                                timeline
                                                    .duration
                                                    .inMilliseconds)
                                            .clamp(0, 1),
                                  onChanged: state.preparingPlayback
                                      ? null
                                      : (value) => state.seek(
                                          Duration(
                                            milliseconds:
                                                (timeline
                                                            .duration
                                                            .inMilliseconds *
                                                        value)
                                                    .round(),
                                          ),
                                        ),
                                  animate:
                                      state.playing || state.preparingPlayback,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_duration(timeline.position)),
                                    Text(_duration(timeline.duration)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PlayerTransportControls(state: state),
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: scheme.outlineVariant.withValues(alpha: .55),
                  ),
                  const Expanded(flex: 9, child: _TabletLyricsPane()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletLyricsPane extends StatefulWidget {
  const _TabletLyricsPane();

  @override
  State<_TabletLyricsPane> createState() => _TabletLyricsPaneState();
}

class _LyricLineMotion {
  const _LyricLineMotion({
    required this.serial,
    required this.offset,
    required this.activeIndex,
    required this.mass,
    required this.stiffness,
    required this.damping,
    this.cancel = false,
  });

  const _LyricLineMotion.idle()
    : serial = 0,
      offset = 0,
      activeIndex = -1,
      mass = 1,
      stiffness = 210,
      damping = 25,
      cancel = false;

  final int serial;
  final double offset;
  final int activeIndex;
  final double mass;
  final double stiffness;
  final double damping;
  final bool cancel;
}

class _LyricLineSpringShift extends StatefulWidget {
  const _LyricLineSpringShift({
    required this.motion,
    required this.index,
    required this.child,
  });

  final ValueListenable<_LyricLineMotion> motion;
  final int index;
  final Widget child;

  @override
  State<_LyricLineSpringShift> createState() => _LyricLineSpringShiftState();
}

class _LyricLineSpringShiftState extends State<_LyricLineSpringShift>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController.unbounded(
    vsync: this,
  );
  Timer? delayTimer;
  int lastSerial = 0;

  @override
  void initState() {
    super.initState();
    widget.motion.addListener(_handleMotion);
  }

  @override
  void didUpdateWidget(covariant _LyricLineSpringShift oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion == widget.motion) return;
    oldWidget.motion.removeListener(_handleMotion);
    widget.motion.addListener(_handleMotion);
  }

  void _handleMotion() {
    final motion = widget.motion.value;
    if (motion.serial <= lastSerial) return;
    lastSerial = motion.serial;
    delayTimer?.cancel();
    if (motion.cancel) {
      controller
        ..stop()
        ..value = 0;
      return;
    }
    final previousVelocity = controller.isAnimating ? controller.velocity : 0.0;
    final start = controller.value + motion.offset;
    controller
      ..stop()
      ..value = start;
    if (start.abs() < .25) {
      controller.value = 0;
      return;
    }
    final distance = (widget.index - motion.activeIndex).abs().clamp(0, 8);
    final delayMs = (distance * 9).clamp(0, 64);
    delayTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || lastSerial != motion.serial) return;
      controller.animateWith(
        SpringSimulation(
          SpringDescription(
            mass: motion.mass,
            stiffness: motion.stiffness,
            damping: motion.damping,
          ),
          controller.value,
          0,
          previousVelocity,
        ),
      );
    });
  }

  @override
  void dispose() {
    delayTimer?.cancel();
    widget.motion.removeListener(_handleMotion);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) =>
        Transform.translate(offset: Offset(0, controller.value), child: child),
  );
}

class _TabletLyricsPaneState extends State<_TabletLyricsPane> {
  final ScrollController controller = ScrollController();
  final ValueNotifier<_LyricLineMotion> lineMotion = ValueNotifier(
    const _LyricLineMotion.idle(),
  );
  int motionSerial = 0;
  int previous = -1;

  void moveLinesTo(double target, MelodyState state, int activeIndex) {
    final position = controller.position;
    final end = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final delta = end - position.pixels;
    if (delta.abs() < .25) return;
    position.jumpTo(end);
    lineMotion.value = _LyricLineMotion(
      serial: ++motionSerial,
      offset: delta,
      activeIndex: activeIndex,
      mass: state.lyricScrollMass,
      stiffness: state.lyricScrollStiffness,
      damping: state.lyricScrollDamping,
    );
  }

  @override
  void dispose() {
    lineMotion.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final lyricInk = _albumLyricInk(state.coverPalette, isDark);
    final contrastBase = isDark ? Colors.black : Colors.white;
    return ValueListenableBuilder<PlaybackTimeline>(
      valueListenable: state.playbackTimeline,
      builder: (context, timeline, _) {
        final lyricPosition =
            timeline.position - Duration(milliseconds: state.lyricDelayMs);
        final active = LyricsParser.activeLine(state.lyrics, lyricPosition);
        if (active >= 0 && active != previous && controller.hasClients) {
          previous = active;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !controller.hasClients) return;
            moveLinesTo(
              (active * 88.0 - controller.position.viewportDimension * .36)
                  .clamp(0.0, controller.position.maxScrollExtent)
                  .toDouble(),
              state,
              active,
            );
          });
        }
        return ColoredBox(
          color: contrastBase.withValues(alpha: isDark ? .14 : .16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 34, 34, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '歌词',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: lyricInk),
                          ),
                          Text(
                            '${state.lyricDelayMs >= 0 ? '+' : ''}${state.lyricDelayMs} ms',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: lyricInk.withValues(alpha: .72),
                                ),
                          ),
                        ],
                      ),
                    ),
                    ExpressiveIconButton(
                      size: 44,
                      tooltip: state.showTranslation ? '隐藏翻译' : '显示翻译',
                      tonal: true,
                      selected: state.showTranslation,
                      onPressed: () => state.setSetting(
                        'showTranslation',
                        !state.showTranslation,
                      ),
                      icon: const Icon(Icons.translate_rounded),
                    ),
                    const SizedBox(width: 8),
                    ExpressiveIconButton(
                      size: 44,
                      tooltip: '歌词与时间',
                      tonal: true,
                      onPressed: () => _lyricPickerSheet(context),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: state.loadingLyrics
                      ? const Center(child: MorphingLoadingIndicator())
                      : state.instrumentalLyrics
                      ? InstrumentalLyricStage(
                          playing: state.playing,
                          compact: true,
                        )
                      : state.lyrics.isEmpty
                      ? const Center(child: Text('暂未找到歌词'))
                      : ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(vertical: 120),
                          itemCount: state.lyrics.length,
                          itemBuilder: (context, index) {
                            final line = state.lyrics[index];
                            final selected = index == active;
                            final completed = lyricPosition >= line.end;
                            final rowOpacity = selected
                                ? 1.0
                                : index == active - 1
                                ? .94
                                : index == active + 1
                                ? .62
                                : completed
                                ? .86
                                : .46;
                            final cadenceMs = index + 1 < state.lyrics.length
                                ? math.max(
                                    1,
                                    (state.lyrics[index + 1].start - line.start)
                                        .inMilliseconds,
                                  )
                                : math.max(
                                    1,
                                    (line.end - line.start).inMilliseconds,
                                  );
                            final enterMs = (cadenceMs * .20).round().clamp(
                              75,
                              245,
                            );
                            final exitMs = (cadenceMs * .29).round().clamp(
                              120,
                              360,
                            );
                            final accent = albumLyricRoleColor(
                              state.coverPalette,
                              isDark,
                              line.alignRight ? 1 : 0,
                            );
                            return _LyricLineSpringShift(
                              motion: lineMotion,
                              index: index,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 260),
                                opacity: rowOpacity,
                                child: _LyricSpringPulse(
                                  active: selected,
                                  enterDuration: Duration(
                                    milliseconds: enterMs,
                                  ),
                                  exitDuration: Duration(milliseconds: exitMs),
                                  child: AnimatedScale(
                                    duration: const Duration(milliseconds: 320),
                                    curve: const Cubic(.05, .7, .1, 1),
                                    alignment: line.alignRight
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    scale: selected ? 1 : .90,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => state.seek(
                                        line.start +
                                            Duration(
                                              milliseconds: state.lyricDelayMs,
                                            ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              line.isInterlude
                                                  ? '♪  ♫  ♪'
                                                  : line.text,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: selected
                                                        ? state.emphasisWeight
                                                        : state.normalWeight,
                                                    color: selected || completed
                                                        ? accent
                                                        : lyricInk,
                                                    shadows: selected && isDark
                                                        ? [
                                                            Shadow(
                                                              color: accent
                                                                  .withValues(
                                                                    alpha: .30,
                                                                  ),
                                                              blurRadius: 12,
                                                            ),
                                                          ]
                                                        : const [],
                                                  ),
                                            ),
                                            if (line
                                                    .backgroundText
                                                    ?.isNotEmpty ==
                                                true)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Text(
                                                  line.backgroundText!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color:
                                                            selected ||
                                                                completed
                                                            ? albumLyricRoleColor(
                                                                state
                                                                    .coverPalette,
                                                                isDark,
                                                                2,
                                                              )
                                                            : lyricInk
                                                                  .withValues(
                                                                    alpha: .56,
                                                                  ),
                                                      ),
                                                ),
                                              ),
                                            if (state.showTranslation &&
                                                line.translation?.isNotEmpty ==
                                                    true)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 5,
                                                ),
                                                child: Text(
                                                  line.translation!,
                                                  style: TextStyle(
                                                    color: lyricInk.withValues(
                                                      alpha: .80,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerTransportControls extends StatefulWidget {
  const _PlayerTransportControls({required this.state});
  final MelodyState state;

  @override
  State<_PlayerTransportControls> createState() =>
      _PlayerTransportControlsState();
}

class _PlayerTransportControlsState extends State<_PlayerTransportControls> {
  int pressed = -1;

  Widget item(int index, Widget child) => AnimatedScale(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutBack,
    scale: pressed < 0
        ? 1
        : pressed == index
        ? .90
        : (pressed - index).abs() == 1
        ? .96
        : .985,
    child: Listener(
      onPointerDown: (_) => setState(() => pressed = index),
      onPointerUp: (_) => setState(() => pressed = -1),
      onPointerCancel: (_) => setState(() => pressed = -1),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final repeatOne = state.repeatMode == PlaybackRepeatMode.one;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        item(
          0,
          ExpressiveIconButton(
            tooltip: state.shuffleEnabled ? '随机播放已开启' : '开启随机播放',
            onPressed: state.toggleShuffle,
            selected: state.shuffleEnabled,
            tonal: true,
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ),
        item(
          1,
          IconButton(
            iconSize: 42,
            onPressed: () => state.skip(-1),
            icon: const Icon(Icons.skip_previous_rounded),
          ),
        ),
        item(
          2,
          ExpressiveIconButton(
            size: 82,
            iconSize: 46,
            onPressed: state.togglePlay,
            selected: state.playing,
            icon: Icon(
              state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        item(
          3,
          IconButton(
            iconSize: 42,
            onPressed: () => state.skip(1),
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ),
        item(
          4,
          ExpressiveIconButton(
            tooltip: repeatOne ? '单曲循环' : '列表循环',
            onPressed: state.cycleRepeatMode,
            selected: repeatOne,
            tonal: true,
            icon: Icon(
              repeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key});
  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen>
    with SingleTickerProviderStateMixin {
  static const estimatedLyricExtent = 116.0;
  final controller = ScrollController();
  final Map<String, GlobalKey> lyricItemKeys = {};
  late final Ticker lyricTicker;
  final ValueNotifier<_LyricLineMotion> lineMotion = ValueNotifier(
    const _LyricLineMotion.idle(),
  );
  late final ValueNotifier<Duration> lyricClock;
  MelodyState? melodyState;
  Duration nextLyricFrame = Duration.zero;
  int liveActive = -1;
  String liveTrackId = '';
  String keyedTrackId = '';
  int lastIndex = -1;
  int scrollRequest = 0;
  int motionSerial = 0;
  bool userScrolling = false;
  Timer? resumeTimer;
  @override
  void initState() {
    super.initState();
    lyricClock = ValueNotifier(Duration.zero);
    lyricTicker = createTicker((elapsed) {
      // The player's general position stream may update only every 200 ms on
      // long tracks. Lyrics need a local high-frequency clock so very short
      // lines and karaoke words still become visible without rebuilding the
      // whole application at frame rate.
      // Follow display vsync while honoring the user's lyric-only frame cap.
      // 30 FPS is the default balance; line transitions remain implicit and
      // therefore still interpolate smoothly between clock samples.
      final fps = melodyState?.lyricFrameRate ?? 30;
      final frameInterval = Duration(microseconds: (1000000 / fps).round());
      if (elapsed < nextLyricFrame) return;
      nextLyricFrame += frameInterval;
      if (elapsed - nextLyricFrame > frameInterval) {
        nextLyricFrame = elapsed + frameInterval;
      }
      // Only karaoke words listen to this clock. The whole page rebuilds only
      // when the active line changes, preserving implicit animations.
      final state = melodyState;
      if (!mounted || state?.playing != true) return;
      final position =
          state!.player.position - Duration(milliseconds: state.lyricDelayMs);
      lyricClock.value = position;
      final nextActive = LyricsParser.activeLine(state.lyrics, position);
      if (nextActive != liveActive || liveTrackId != state.current.id) {
        liveActive = nextActive;
        liveTrackId = state.current.id;
        setState(() {});
      }
    })..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    melodyState = MelodyScope.of(context);
    final state = melodyState!;
    final position =
        state.player.position - Duration(milliseconds: state.lyricDelayMs);
    lyricClock.value = position;
    liveActive = LyricsParser.activeLine(state.lyrics, position);
    liveTrackId = state.current.id;
  }

  @override
  void dispose() {
    resumeTimer?.cancel();
    lyricTicker.dispose();
    lineMotion.dispose();
    lyricClock.dispose();
    controller.dispose();
    super.dispose();
  }

  GlobalKey lyricItemKey(String trackId, LyricLine line, int index) {
    if (keyedTrackId != trackId) {
      keyedTrackId = trackId;
      lyricItemKeys.clear();
    }
    final id = '${line.start.inMicroseconds}-$index';
    return lyricItemKeys.putIfAbsent(id, GlobalKey.new);
  }

  void moveLinesTo(double target, int activeIndex) {
    final state = melodyState;
    if (state == null || !controller.hasClients) return;
    final position = controller.position;
    final end = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final delta = end - position.pixels;
    if (delta.abs() < .25) return;
    position.jumpTo(end);
    lineMotion.value = _LyricLineMotion(
      serial: ++motionSerial,
      offset: delta,
      activeIndex: activeIndex,
      mass: state.lyricScrollMass,
      stiffness: state.lyricScrollStiffness,
      damping: state.lyricScrollDamping,
    );
  }

  void cancelLineMotion() {
    lineMotion.value = _LyricLineMotion(
      serial: ++motionSerial,
      offset: 0,
      activeIndex: liveActive,
      mass: 1,
      stiffness: 210,
      damping: 25,
      cancel: true,
    );
  }

  void autoScroll(
    int index,
    List<LyricLine> lyrics,
    String trackId,
    double topInset, [
    int materializeAttempt = 0,
  ]) {
    if (index < 0 ||
        index >= lyrics.length ||
        index == lastIndex ||
        userScrolling ||
        !controller.hasClients) {
      return;
    }
    final request = ++scrollRequest;
    final previousIndex = lastIndex;
    lastIndex = index;
    final itemContext = lyricItemKey(
      trackId,
      lyrics[index],
      index,
    ).currentContext;
    if (itemContext == null) {
      lastIndex = previousIndex;
      if (materializeAttempt >= 2) return;
      // A variable-height ListView lazily builds children. During dense lyrics
      // the active index may outrun that range, so first move to an estimated
      // offset to materialize it, then refine with its real RenderObject.
      final estimatedTarget =
          topInset +
          index * estimatedLyricExtent -
          controller.position.viewportDimension * .34;
      cancelLineMotion();
      controller.jumpTo(
        estimatedTarget.clamp(0, controller.position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == scrollRequest && liveActive == index) {
          autoScroll(index, lyrics, trackId, topInset, materializeAttempt + 1);
        }
      });
      return;
    }
    final renderObject = itemContext.findRenderObject();
    if (renderObject == null) return;
    final viewport = RenderAbstractViewport.of(renderObject);
    final target = viewport.getOffsetToReveal(renderObject, .34).offset;
    moveLinesTo(target, index);
  }

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    lyricTicker.muted = !state.playing;
    final lyricsViewportTop =
        MediaQuery.paddingOf(context).top + kToolbarHeight;
    const lyricsListTopPadding = 34.0;
    final lyricPosition = lyricClock.value;
    final active = liveActive;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => autoScroll(
        active,
        state.lyrics,
        state.current.id,
        lyricsListTopPadding,
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final lyricInk = _albumLyricInk(state.coverPalette, isDark);
    final contrastBase = isDark ? Colors.black : Colors.white;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Let the album-derived lyric background continue behind the status
        // bar and toolbar. A translucent vertical scrim keeps the title
        // readable without introducing the hard colour seam of an opaque bar.
        backgroundColor: Colors.transparent,
        foregroundColor: lyricInk,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        flexibleSpace: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  contrastBase.withValues(alpha: isDark ? .58 : .48),
                  contrastBase.withValues(alpha: isDark ? .24 : .18),
                  contrastBase.withValues(alpha: 0),
                ],
                stops: const [0, .58, 1],
              ),
            ),
          ),
        ),
        title: Column(
          children: [
            Text(
              state.current.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: MelodyScope.of(context).emphasisWeight,
                color: lyricInk,
              ),
            ),
            Text(
              state.current.artist,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: lyricInk.withValues(alpha: .72),
              ),
            ),
          ],
        ),
        centerTitle: true,
        // Balance the leading back button without adding a visible action, so
        // long song titles remain centered against the whole screen.
        actions: const [SizedBox(width: 56)],
      ),
      body: Stack(
        children: [
          if (state.gradientPlayerBackground)
            Positioned.fill(
              child: AlbumBackground(
                singleColor: state.singleColorPlayerBackground,
                colors: state.coverPalette,
                trackId: state.current.id,
                coverUrl: state.current.coverUrl,
                lowPower: state.efficientRendering,
                animate: state.playing,
              ),
            ),
          if (state.gradientPlayerBackground)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: contrastBase.withValues(alpha: isDark ? .26 : 0),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: lyricsViewportTop,
            bottom: 88 + MediaQuery.paddingOf(context).bottom,
            child: ClipRect(
              child: NotificationListener<ScrollNotification>(
                onNotification: (event) {
                  if (event is ScrollStartNotification &&
                      event.dragDetails != null) {
                    userScrolling = true;
                    cancelLineMotion();
                    resumeTimer?.cancel();
                  }
                  if (event is ScrollEndNotification && userScrolling) {
                    resumeTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) {
                        setState(() {
                          userScrolling = false;
                          lastIndex = -1;
                        });
                      }
                    });
                  }
                  return false;
                },
                child: state.loadingLyrics
                    ? const Center(child: MorphingLoadingIndicator())
                    : state.instrumentalLyrics
                    ? InstrumentalLyricStage(playing: state.playing)
                    : state.lyrics.isEmpty
                    ? const Center(child: Text('暂未找到歌词，可从右下角选择其他匹配'))
                    : ListView.builder(
                        controller: controller,
                        // Keeping five screens of animated lyric rows alive was
                        // expensive on older GPUs. A little over one screen still
                        // makes fast scrolling feel immediate without heating the
                        // device through off-screen karaoke repaints.
                        cacheExtent: MediaQuery.sizeOf(context).height * 1.35,
                        padding: const EdgeInsets.fromLTRB(
                          28,
                          lyricsListTopPadding,
                          28,
                          220,
                        ),
                        itemCount: state.lyrics.length,
                        itemBuilder: (context, index) {
                          final line = state.lyrics[index];
                          final lineDurationMs = math.max(
                            1,
                            (line.end - line.start).inMilliseconds,
                          );
                          final cadenceMs = index + 1 < state.lyrics.length
                              ? math.max(
                                  1,
                                  (state.lyrics[index + 1].start - line.start)
                                      .inMilliseconds,
                                )
                              : lineDurationMs;
                          final scaleDuration = Duration(
                            milliseconds: (lineDurationMs * .42).round().clamp(
                              180,
                              420,
                            ),
                          );
                          final selected =
                              lyricPosition >= line.start &&
                              lyricPosition < line.end;
                          final completed =
                              !line.isInterlude && lyricPosition >= line.end;
                          final adjacent =
                              active >= 0 && (index - active).abs() == 1;
                          // Dense lyrics enter quickly enough to keep up, while
                          // long phrases retain a calm transition. The incoming
                          // row is deliberately a little faster than the row
                          // being released.
                          final enterMs = (cadenceMs * .20).round().clamp(
                            75,
                            245,
                          );
                          final exitMs = (cadenceMs * .29).round().clamp(
                            120,
                            360,
                          );
                          final opacityDuration = Duration(
                            milliseconds: (lineDurationMs * .28).round().clamp(
                              120,
                              220,
                            ),
                          );
                          final lineAccent = albumLyricRoleColor(
                            state.coverPalette,
                            isDark,
                            line.alignRight ? 1 : 0,
                          );
                          final harmonyAccent = albumLyricRoleColor(
                            state.coverPalette,
                            isDark,
                            2,
                          );
                          final rowOpacity = selected
                              ? 1.0
                              : index == active - 1
                              ? .94
                              : index == active + 1
                              ? .76
                              : completed
                              ? .86
                              : .56;
                          return Container(
                            key: lyricItemKey(state.current.id, line, index),
                            constraints: const BoxConstraints(minHeight: 94),
                            // Reserve space on the side the active scale grows
                            // toward. The animation remains unchanged while its
                            // painted bounds stay inside the screen.
                            padding: EdgeInsets.only(
                              top: 10,
                              bottom: 10,
                              left: line.alignRight ? 36 : 0,
                              right: line.alignRight ? 0 : 36,
                            ),
                            child: _LyricLineSpringShift(
                              motion: lineMotion,
                              index: index,
                              child: _LyricSpringPulse(
                                active: selected,
                                enterDuration: Duration(milliseconds: enterMs),
                                exitDuration: Duration(milliseconds: exitMs),
                                child: AnimatedScale(
                                  scale: selected
                                      ? 1.10
                                      : adjacent
                                      ? .90
                                      : .75,
                                  alignment: line.alignRight
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  duration: scaleDuration,
                                  curve: const Cubic(.05, .7, .1, 1),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => state.seek(
                                      line.start +
                                          Duration(
                                            milliseconds: state.lyricDelayMs,
                                          ),
                                    ),
                                    child: AnimatedOpacity(
                                      duration: opacityDuration,
                                      curve: Curves.easeOutCubic,
                                      opacity: rowOpacity,
                                      child: Column(
                                        crossAxisAlignment: line.alignRight
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (line.isInterlude)
                                            InterludeWait(
                                              active: selected,
                                              playing: state.playing,
                                            )
                                          else if ((selected ||
                                                  index == active - 1) &&
                                              line.words.isNotEmpty &&
                                              state.karaokeLyrics)
                                            KaraokeWords(
                                              words: line.words,
                                              positionListenable: lyricClock,
                                              tracking: selected,
                                              alignment: line.alignRight
                                                  ? WrapAlignment.end
                                                  : WrapAlignment.start,
                                              accentColor: lineAccent,
                                              inkColor: lyricInk,
                                            )
                                          else
                                            Text(
                                              line.text,
                                              textAlign: line.alignRight
                                                  ? TextAlign.right
                                                  : TextAlign.left,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: selected
                                                        ? MelodyScope.of(
                                                            context,
                                                          ).emphasisWeight
                                                        : MelodyScope.of(
                                                            context,
                                                          ).normalWeight,
                                                    color: selected || completed
                                                        ? lineAccent
                                                        : lyricInk,
                                                    shadows: selected && isDark
                                                        ? [
                                                            Shadow(
                                                              color: lineAccent
                                                                  .withValues(
                                                                    alpha: .30,
                                                                  ),
                                                              blurRadius: 12,
                                                            ),
                                                          ]
                                                        : const [],
                                                    height: 1.25,
                                                  ),
                                            ),
                                          if (!line.isInterlude &&
                                              line.backgroundText != null &&
                                              line.backgroundText!.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child:
                                                  (selected ||
                                                          index ==
                                                              active - 1) &&
                                                      line
                                                          .backgroundWords
                                                          .isNotEmpty &&
                                                      state.karaokeLyrics
                                                  ? KaraokeWords(
                                                      words:
                                                          line.backgroundWords,
                                                      positionListenable:
                                                          lyricClock,
                                                      tracking: selected,
                                                      alignment: line.alignRight
                                                          ? WrapAlignment.end
                                                          : WrapAlignment.start,
                                                      runSpacing: 2,
                                                      background: true,
                                                      accentColor:
                                                          harmonyAccent,
                                                      inkColor: lyricInk,
                                                    )
                                                  : Text(
                                                      line.backgroundText!,
                                                      textAlign: line.alignRight
                                                          ? TextAlign.right
                                                          : TextAlign.left,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            color:
                                                                (selected ||
                                                                            completed
                                                                        ? harmonyAccent
                                                                        : lyricInk)
                                                                    .withValues(
                                                                      alpha:
                                                                          .82,
                                                                    ),
                                                            fontWeight:
                                                                MelodyScope.of(
                                                                  context,
                                                                ).normalWeight,
                                                          ),
                                                    ),
                                            ),
                                          if (!line.isInterlude &&
                                              state.showTranslation &&
                                              line.translation != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 5,
                                              ),
                                              child: Text(
                                                line.translation!,
                                                textAlign: line.alignRight
                                                    ? TextAlign.right
                                                    : TextAlign.left,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: lyricInk
                                                          .withValues(
                                                            alpha: .80,
                                                          ),
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: _GlassSurface(
              enabled: false,
              borderRadius: BorderRadius.circular(28),
              surfaceAlpha: .36,
              blurSigma: 14,
              child: Material(
                color: Color.lerp(
                  isDark ? Colors.black : Colors.white,
                  lyricInk,
                  .08,
                ),
                elevation: 2,
                shadowColor: scheme.shadow.withValues(alpha: .24),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Cover(track: state.current, size: 48, radius: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PlaybackTimelineBuilder(
                          state: state,
                          builder: (context, timeline) =>
                              M3EWavyProgressIndicator(
                                indeterminate: state.preparingPlayback,
                                value: timeline.duration.inMilliseconds == 0
                                    ? 0
                                    : (timeline.position.inMilliseconds /
                                              timeline.duration.inMilliseconds)
                                          .clamp(0, 1),
                                onChanged: state.preparingPlayback
                                    ? null
                                    : (v) => state.seek(
                                        Duration(
                                          milliseconds:
                                              (timeline
                                                          .duration
                                                          .inMilliseconds *
                                                      v)
                                                  .round(),
                                        ),
                                      ),
                                animate:
                                    state.playing || state.preparingPlayback,
                                trackColor: Color.lerp(
                                  isDark ? Colors.black : Colors.white,
                                  lyricInk,
                                  .24,
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      ExpressiveIconButton(
                        onPressed: () => _lyricPickerSheet(context),
                        tooltip: '选择歌词',
                        tonal: true,
                        backgroundColor: lyricInk.withValues(alpha: .12),
                        foregroundColor: lyricInk,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                      ExpressiveIconButton(
                        onPressed: state.togglePlay,
                        selected: state.playing,
                        backgroundColor: lyricInk,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        icon: Icon(
                          state.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackTimelineBuilder extends StatelessWidget {
  const _PlaybackTimelineBuilder({required this.state, required this.builder});

  final MelodyState state;
  final Widget Function(BuildContext context, PlaybackTimeline timeline)
  builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PlaybackTimeline>(
        valueListenable: state.playbackTimeline,
        builder: (context, timeline, _) => builder(context, timeline),
      );
}

class _MiniPlaybackProgress extends StatelessWidget {
  const _MiniPlaybackProgress({required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = color ?? scheme.primary;
    return Semantics(
      label: '播放进度',
      value: '${(value * 100).round()}%',
      child: SizedBox(
        height: 9,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final markerLeft = (constraints.maxWidth * value - 1)
                .clamp(0.0, constraints.maxWidth - 2)
                .toDouble();
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: foreground,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                if (value > 0)
                  Positioned(
                    left: markerLeft,
                    child: Container(
                      width: 2,
                      height: 9,
                      decoration: BoxDecoration(
                        color: foreground,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Adds a restrained, transient lyric-line pulse without changing the line's
/// scale, alignment, or final position. Entering is intentionally quicker
/// than releasing, but both paths settle exactly at Offset.zero.
class _LyricSpringPulse extends StatefulWidget {
  const _LyricSpringPulse({
    required this.active,
    required this.enterDuration,
    required this.exitDuration,
    required this.child,
  });

  final bool active;
  final Duration enterDuration;
  final Duration exitDuration;
  final Widget child;

  @override
  State<_LyricSpringPulse> createState() => _LyricSpringPulseState();
}

class _LyricSpringPulseState extends State<_LyricSpringPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  double _amplitude = 0;

  @override
  void didUpdateWidget(covariant _LyricSpringPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    _amplitude = widget.active ? 1.8 : .65;
    _controller.duration = widget.active
        ? widget.enterDuration
        : widget.exitDuration;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(_controller.value);
      final damping = 1 - progress * .18;
      return Transform.translate(
        offset: Offset(0, -_amplitude * math.sin(math.pi * progress) * damping),
        child: child,
      );
    },
  );
}

class KaraokeWords extends StatelessWidget {
  const KaraokeWords({
    super.key,
    required this.words,
    required this.positionListenable,
    required this.alignment,
    this.background = false,
    this.tracking = true,
    this.accentColor,
    this.inkColor,
    this.runSpacing = 3,
  });
  final List<LyricWord> words;
  final ValueListenable<Duration> positionListenable;
  final WrapAlignment alignment;
  final bool background;
  final bool tracking;
  final Color? accentColor;
  final Color? inkColor;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => Wrap(
    clipBehavior: Clip.none,
    runSpacing: runSpacing,
    alignment: alignment,
    children: words
        .map(
          (word) => _KaraokeWordFrame(
            word: word,
            positionListenable: positionListenable,
            tracking: tracking,
            background: background,
            accentColor: accentColor,
            inkColor: inkColor,
          ),
        )
        .toList(growable: false),
  );
}

class _KaraokeWordFrame extends StatefulWidget {
  const _KaraokeWordFrame({
    required this.word,
    required this.positionListenable,
    required this.tracking,
    required this.background,
    required this.accentColor,
    required this.inkColor,
  });
  final LyricWord word;
  final ValueListenable<Duration> positionListenable;
  final bool tracking;
  final bool background;
  final Color? accentColor;
  final Color? inkColor;

  @override
  State<_KaraokeWordFrame> createState() => _KaraokeWordFrameState();
}

class _KaraokeWordFrameState extends State<_KaraokeWordFrame> {
  static final Matrix4 _restTransform = Matrix4.identity();
  static final Matrix4 _liftTransform = Matrix4.translationValues(0, -3.5, 0);
  bool active = false;
  bool lifted = false;
  bool played = false;

  @override
  void initState() {
    super.initState();
    if (widget.tracking) {
      widget.positionListenable.addListener(_syncPlaybackPhase);
    }
    _syncPlaybackPhase(notify: false);
  }

  @override
  void didUpdateWidget(covariant _KaraokeWordFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionListenable != widget.positionListenable ||
        oldWidget.tracking != widget.tracking) {
      if (oldWidget.tracking) {
        oldWidget.positionListenable.removeListener(_syncPlaybackPhase);
      }
      if (widget.tracking) {
        widget.positionListenable.addListener(_syncPlaybackPhase);
      }
    }
    if (oldWidget.word != widget.word ||
        oldWidget.positionListenable != widget.positionListenable ||
        oldWidget.tracking != widget.tracking) {
      _syncPlaybackPhase(notify: false);
    }
  }

  void _syncPlaybackPhase({bool notify = true}) {
    final now = widget.positionListenable.value.inMilliseconds;
    final start = widget.word.start.inMilliseconds;
    final end = widget.word.end.inMilliseconds;
    final nextActive = now >= start && now < end;
    final nextLifted = nextActive && now - start < 2000;
    final nextPlayed = now >= end;
    if (nextActive == active && nextLifted == lifted && nextPlayed == played) {
      return;
    }
    void update() {
      active = nextActive;
      lifted = nextLifted;
      played = nextPlayed;
    }

    if (notify && mounted) {
      setState(update);
    } else {
      update();
    }
  }

  @override
  void dispose() {
    if (widget.tracking) {
      widget.positionListenable.removeListener(_syncPlaybackPhase);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.word.start.inMilliseconds;
    final end = widget.word.end.inMilliseconds;
    final wordDurationMs = math.max(1, end - start);
    final overlongActive = active && !lifted;
    final scheme = Theme.of(context).colorScheme;
    final style =
        (widget.background
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge)!
            .copyWith(height: 1.25);
    final accent =
        widget.accentColor ??
        (widget.background ? scheme.tertiary : scheme.primary);
    final ink = widget.inkColor ?? scheme.onSurface;
    final color = active || played
        ? accent
        : ink.withValues(alpha: widget.background ? .48 : .56);
    final activationDuration = Duration(
      milliseconds: (wordDurationMs * .45).round().clamp(40, 180),
    );
    final settleDuration = overlongActive
        ? const Duration(milliseconds: 560)
        : Duration(milliseconds: (wordDurationMs * .8).round().clamp(90, 280));
    return AnimatedContainer(
      duration: lifted ? activationDuration : settleDuration,
      curve: lifted ? Curves.easeOutCubic : const Cubic(.2, 0, 0, 1),
      transform: lifted ? _liftTransform : _restTransform,
      transformAlignment: Alignment.center,
      child: Text(
        widget.word.text,
        style: style.copyWith(
          color: color,
          fontWeight: active || played
              ? MelodyScope.of(context).emphasisWeight
              : MelodyScope.of(context).normalWeight,
          // Restore the active-word halo without restoring the old per-frame
          // whole-row rebuild. At most the currently active word paints blur.
          shadows: active && ink.computeLuminance() > .5
              ? [
                  Shadow(
                    color: accent.withValues(
                      alpha: widget.background ? .22 : .40,
                    ),
                    blurRadius: widget.background ? 7 : 10,
                  ),
                  Shadow(
                    color: accent.withValues(
                      alpha: widget.background ? .10 : .17,
                    ),
                    blurRadius: widget.background ? 14 : 22,
                  ),
                ]
              : const [],
        ),
      ),
    );
  }
}

class MorphingLoadingIndicator extends StatefulWidget {
  const MorphingLoadingIndicator({super.key, this.size = 48});

  final double size;

  @override
  State<MorphingLoadingIndicator> createState() =>
      _MorphingLoadingIndicatorState();
}

class _MorphingLoadingIndicatorState extends State<MorphingLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _MorphingLoadingPainter(
          repaint: controller,
          progress: controller,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

class _MorphingLoadingPainter extends CustomPainter {
  _MorphingLoadingPainter({
    required Listenable repaint,
    required this.progress,
    required this.color,
  }) : super(repaint: repaint);

  final Animation<double> progress;
  final Color color;

  static const _profiles = <List<double>>[
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [.72, .82, 1, .82, .72, .82, 1, .82, .72, .82, 1, .82],
    [1, .72, .82, 1, .72, .82, 1, .72, .82, 1, .72, .82],
    [.68, 1, .74, .88, 1, .72, .68, 1, .74, .88, 1, .72],
    [1, .78, .70, .78, 1, .78, .70, .78, 1, .78, .70, .78],
    [.74, .86, 1, .86, .74, .68, .74, .86, 1, .86, .74, .68],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scaled = progress.value * _profiles.length;
    final current = scaled.floor() % _profiles.length;
    final next = (current + 1) % _profiles.length;
    final local = Curves.easeInOutCubic.transform(scaled - scaled.floor());
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .43;
    final points = <Offset>[];
    for (var i = 0; i < 12; i++) {
      final factor =
          _profiles[current][i] +
          (_profiles[next][i] - _profiles[current][i]) * local;
      final angle =
          -math.pi / 2 + i * math.pi * 2 / 12 + progress.value * math.pi * 2;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * factor;
      points.add(point);
    }
    final path = Path();
    final firstMid = Offset.lerp(points.last, points.first, .5)!;
    path.moveTo(firstMid.dx, firstMid.dy);
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final next = points[(i + 1) % points.length];
      final midpoint = Offset.lerp(point, next, .5)!;
      path.quadraticBezierTo(point.dx, point.dy, midpoint.dx, midpoint.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _MorphingLoadingPainter oldDelegate) =>
      oldDelegate.color != color;
}

class ExpressiveIconButton extends StatefulWidget {
  const ExpressiveIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.tonal = false,
    this.size = 48,
    this.iconSize = 24,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final bool selected;
  final bool tonal;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  State<ExpressiveIconButton> createState() => _ExpressiveIconButtonState();
}

class _ExpressiveIconButtonState extends State<ExpressiveIconButton> {
  bool pressed = false;

  void setPressed(bool value) {
    if (pressed == value || widget.onPressed == null) return;
    setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        widget.backgroundColor ??
        (widget.tonal ? scheme.secondaryContainer : scheme.primary);
    final foreground =
        widget.foregroundColor ??
        (widget.tonal ? scheme.onSecondaryContainer : scheme.onPrimary);
    final radius = pressed
        ? widget.size * .22
        : widget.selected
        ? widget.size * .3
        : widget.size / 2;
    final button = AnimatedContainer(
      width: widget.size,
      height: widget.size,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: pressed ? 100 : 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: widget.onPressed == null
            ? background.withValues(alpha: .38)
            : background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: widget.onPressed,
          onTapDown: (_) => setPressed(true),
          onTapUp: (_) => setPressed(false),
          onTapCancel: () => setPressed(false),
          child: IconTheme(
            data: IconThemeData(color: foreground, size: widget.iconSize),
            child: Center(child: widget.icon),
          ),
        ),
      ),
    );
    final elasticButton = AnimatedScale(
      scale: pressed ? .96 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: pressed ? 100 : 260),
      curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,
      child: button,
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onPressed != null,
      label: widget.tooltip,
      child: widget.tooltip == null
          ? elasticButton
          : Tooltip(message: widget.tooltip!, child: elasticButton),
    );
  }
}

enum SettingsSection {
  playback('播放与音质', '默认音质与播放偏好', Icons.play_circle_outline_rounded),
  lyrics('歌词与动画', '逐字、翻译、校准与换行弹簧', Icons.lyrics_outlined),
  appearance('外观与主题', '主题、封面取色与字重', Icons.palette_outlined),
  performance('性能与存储', '高效渲染与本地存储说明', Icons.speed_rounded),
  account('账号与服务', '登录、同步与授权音源', Icons.account_circle_outlined),
  records('记录与关于', '聆听记录、隐私与版本信息', Icons.history_rounded);

  const SettingsSection(this.title, this.summary, this.icon);
  final String title;
  final String summary;
  final IconData icon;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.section});
  final SettingsSection? section;
  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    if (section == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            SettingsGroup('聆听体验', [
              for (final item in SettingsSection.values.take(3))
                _category(context, item),
            ]),
            SettingsGroup('应用与资料', [
              for (final item in SettingsSection.values.skip(3))
                _category(context, item),
            ]),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(section!.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (section == SettingsSection.account)
            SettingsGroup('账号与服务', [
              SettingsAction(
                icon: Icons.account_circle_rounded,
                title: state.loggedIn ? state.nickname : '网易云音乐登录',
                subtitle: state.loggedIn ? '已连接' : '扫码登录并同步资料',
                onTap: state.loggedIn
                    ? () => _accountSheet(context)
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
              ),
              SettingsAction(
                icon: Icons.dns_rounded,
                title: '内置网易云服务',
                subtitle: '应用内加密请求 · 无需外部 API',
                onTap: () => _info(
                  context,
                  '内置网易云服务',
                  '搜索、推荐、歌单、歌词和登录请求由应用本地完成，不经过用户配置的中转服务器。',
                ),
              ),
              SettingsAction(
                icon: Icons.hub_rounded,
                title: '授权音源适配器',
                subtitle: state.adapterEndpoint.isEmpty
                    ? '未配置'
                    : state.adapterEndpoint,
                onTap: () => _serviceDialog(context),
              ),
            ]),
          if (section == SettingsSection.playback) ...[
            RadioGroup<AudioQuality>(
              groupValue: state.quality,
              onChanged: (value) {
                if (value != null && value != state.quality) {
                  state.setQuality(value);
                }
              },
              child: SettingsGroup('默认音质', [
                for (final quality in AudioQuality.values)
                  RadioListTile<AudioQuality>(
                    value: quality,
                    selected: state.quality == quality,
                    title: Text(quality.label),
                    subtitle: Text(switch (quality) {
                      AudioQuality.standard => '128 kbps · 更节省流量',
                      AudioQuality.higher => '192 kbps · 日常聆听',
                      AudioQuality.exhigh => '320 kbps · 更丰富的细节',
                      AudioQuality.lossless => '保留无损细节 · 流量占用较高',
                      AudioQuality.hires => '高解析度音频 · 流量占用较高',
                    }),
                  ),
              ]),
            ),
            const _SettingsNote(
              '选择优先请求的音质；实际可用音质取决于歌曲来源和账号权益。这里不会显示当前歌曲的实际码率。',
            ),
          ],
          if (section == SettingsSection.lyrics)
            SettingsGroup('歌词显示', [
              SettingsSwitch(
                icon: Icons.auto_awesome_rounded,
                title: '逐字歌词',
                subtitle: '随演唱进度逐字高亮',
                value: state.karaokeLyrics,
                onChanged: (v) {
                  state.setSetting('karaokeLyrics', v);
                  state.loadLyrics();
                },
              ),
              SettingsSwitch(
                icon: Icons.translate_rounded,
                title: '显示翻译',
                subtitle: '有翻译时显示第二行',
                value: state.showTranslation,
                onChanged: (v) => state.setSetting('showTranslation', v),
              ),
              SettingsAction(
                icon: Icons.sort_rounded,
                title: '歌词来源排序',
                subtitle: state.lyricSourceOrderLabel,
                onTap: () => _lyricSourceOrderSheet(context),
              ),
              SettingsAction(
                icon: Icons.sync_rounded,
                title: '歌词校准',
                subtitle:
                    '${state.lyricDelayMs >= 0 ? '+' : ''}${state.lyricDelayMs} ms · 全局',
                onTap: () => _lyricPickerSheet(context),
              ),
            ]),
          if (section == SettingsSection.lyrics)
            SettingsGroup('动画与换行', [
              SettingsAction(
                icon: Icons.swap_vert_circle_rounded,
                title: '换行弹簧',
                subtitle: '${state.lyricScrollPreset.label} · 仅影响纵向换行',
                onTap: () => _lyricScrollMotionSheet(context),
              ),
              SettingsAction(
                icon: Icons.speed_rounded,
                title: '歌词动画帧率',
                subtitle: '${state.lyricFrameRate} FPS · 仅影响歌词动画',
                onTap: () => _lyricFrameRateSheet(context),
              ),
            ]),
          if (section == SettingsSection.performance) ...[
            SettingsGroup('性能', [
              SettingsSwitch(
                icon: Icons.battery_saver_rounded,
                title: '高效渲染',
                subtitle: '降低波形与动态背景的刷新频率',
                value: state.efficientRendering,
                onChanged: (v) => state.setSetting('efficientRendering', v),
              ),
            ]),
            SettingsGroup('本地存储', const [
              Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('内存与文件缓存'),
                    SizedBox(height: 8),
                    Text('应用会使用运行时内存和本地文件缓存；两者不是同一项容量。'),
                    SizedBox(height: 12),
                    Text('缓存容量查看与清理功能尚未开放。此处仅作说明，不会清除歌曲、账号或播放记录。'),
                  ],
                ),
              ),
            ]),
          ],
          if (section == SettingsSection.appearance)
            SettingsGroup('外观', [
              SettingsSwitch(
                icon: Icons.gradient_rounded,
                title: '专辑背景',
                subtitle: '在播放与歌词页显示封面取色背景',
                value: state.gradientPlayerBackground,
                onChanged: (v) =>
                    state.setSetting('gradientPlayerBackground', v),
              ),
              if (state.gradientPlayerBackground)
                SettingsSwitch(
                  icon: Icons.format_color_fill_rounded,
                  title: 'Spotify 式单色渐变',
                  subtitle: '开启：同色系上暗下亮，无持续动画；关闭：动态流光',
                  value: state.singleColorPlayerBackground,
                  onChanged: (v) =>
                      state.setSetting('singleColorPlayerBackground', v),
                ),
              SettingsSwitch(
                icon: Icons.palette_rounded,
                title: '封面动态取色',
                subtitle: '播放器与全局主题随当前封面变化',
                value: state.dynamicColor,
                onChanged: (v) => state.setSetting('dynamicColor', v),
              ),
              if (state.dynamicColor)
                SettingsAction(
                  icon: Icons.color_lens_rounded,
                  title: '取色方案',
                  subtitle: state.coverColorStyle.label,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CoverColorStyleScreen(),
                    ),
                  ),
                ),
              SettingsAction(
                icon: Icons.dark_mode_rounded,
                title: '主题模式',
                subtitle: state.themeModeLabel,
                onTap: () => _themeModeSheet(context),
              ),
              SettingsAction(
                icon: Icons.format_bold_rounded,
                title: '全局字重',
                subtitle: state.fontWeightLabel,
                onTap: () => _fontWeightSheet(context),
              ),
            ]),
          if (section == SettingsSection.records)
            SettingsGroup('记录与统计', [
              SettingsAction(
                icon: Icons.history_rounded,
                title: '最近播放',
                subtitle: '${state.recent.length} 首歌曲',
                onTap: () => _openTrackCollection(
                  context,
                  title: '最近播放',
                  tracks: state.recent,
                  emptyMessage: '还没有播放历史',
                ),
              ),
              SettingsAction(
                icon: Icons.bar_chart_rounded,
                title: '听歌统计',
                subtitle: '本周 ${state.stats.weekLabel}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ListeningStatsScreen(),
                  ),
                ),
              ),
            ]),
          if (section == SettingsSection.records)
            SettingsGroup('隐私与其他', [
              SettingsSwitch(
                icon: Icons.visibility_off_rounded,
                title: '私人聆听',
                subtitle: '不计入听歌统计',
                value: state.privateMode,
                onChanged: (v) => state.setSetting('privateMode', v),
              ),
              SettingsAction(
                icon: Icons.privacy_tip_rounded,
                title: '数据与隐私',
                subtitle: '本地数据、Cookie 与授权',
                onTap: () => _info(
                  context,
                  '数据与隐私',
                  '登录 Cookie 仅保存在设备本地，并只发送到你配置的服务地址。',
                ),
              ),
              SettingsAction(
                icon: Icons.info_rounded,
                title: '关于 Sonorynth',
                subtitle: '1.10.12 · Flutter / Material 3 Expressive',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Sonorynth',
                  applicationVersion: '1.10.12',
                  applicationLegalese: 'Independent implementation.',
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

Widget _category(BuildContext context, SettingsSection section) {
  final state = MelodyScope.of(context);
  final summary = switch (section) {
    SettingsSection.playback => '默认 ${state.quality.label} · 按歌曲与权益提供',
    SettingsSection.lyrics =>
      '${state.karaokeLyrics ? '逐字开启' : '逐字关闭'} · ${state.lyricScrollPreset.label} · ${state.lyricFrameRate} FPS',
    SettingsSection.appearance =>
      '${state.themeModeLabel} · ${state.dynamicColor ? '封面取色' : '固定主题色'}',
    SettingsSection.performance =>
      '高效渲染${state.efficientRendering ? '开启' : '关闭'} · 存储说明',
    SettingsSection.account =>
      state.loggedIn ? '已登录 · ${state.nickname}' : '未登录 · 账号与授权音源',
    SettingsSection.records =>
      '${state.privateMode ? '私人聆听开启' : '私人聆听关闭'} · 记录与隐私',
  };
  return SettingsAction(
    icon: section.icon,
    title: section.title,
    subtitle: summary,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(section: section)),
    ),
  );
}

class _SettingsNote extends StatelessWidget {
  const _SettingsNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class CoverColorStyleScreen extends StatelessWidget {
  const CoverColorStyleScreen({super.key});

  static const descriptions = <CoverColorStyle, String>{
    CoverColorStyle.analogous: '锁定封面占比最高的主色，只在相邻色相内延展。与封面联系最稳定，可减少无关颜色。',
    CoverColorStyle.vibrant: '优先封面中的高饱和区域，提高强调色张力与控件对比，适合色彩明快的专辑封面。',
    CoverColorStyle.bright: '保留封面色相并整体抬高明度，界面更通透柔和，适合白天与浅色模式。',
    CoverColorStyle.balanced: '综合颜色占比、饱和度和明度，保留主色也适度引入辅助色，适合大多数封面。',
    CoverColorStyle.diverse: '从封面中选择色相差异明显的颜色，让不同控件分层更丰富，适合多色插画封面。',
  };

  static const previews = <CoverColorStyle, List<Color>>{
    CoverColorStyle.analogous: [
      Color(0xff7267a8),
      Color(0xff8b78b0),
      Color(0xffa58db8),
      Color(0xffd5cce3),
    ],
    CoverColorStyle.vibrant: [
      Color(0xff6750d8),
      Color(0xffd63a72),
      Color(0xffff8a2a),
      Color(0xff25a9a0),
    ],
    CoverColorStyle.bright: [
      Color(0xff9e9be8),
      Color(0xfff1a9ca),
      Color(0xffffd39b),
      Color(0xffb7dfd8),
    ],
    CoverColorStyle.balanced: [
      Color(0xff6f72a7),
      Color(0xffa06f8e),
      Color(0xffbf8b62),
      Color(0xffd7d1df),
    ],
    CoverColorStyle.diverse: [
      Color(0xff6256a8),
      Color(0xffc85a78),
      Color(0xffd5a13c),
      Color(0xff3e9b8a),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('取色方案')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
            child: Text(
              '颜色仍来自当前封面，方案只决定优先保留哪些颜色以及如何调整明度与饱和度。',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          for (final style in CoverColorStyle.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ColorStyleCard(
                style: style,
                description: descriptions[style]!,
                colors: previews[style]!,
                selected: state.coverColorStyle == style,
                onTap: () => state.setCoverColorStyle(style),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorStyleCard extends StatefulWidget {
  const _ColorStyleCard({
    required this.style,
    required this.description,
    required this.colors,
    required this.selected,
    required this.onTap,
  });
  final CoverColorStyle style;
  final String description;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ColorStyleCard> createState() => _ColorStyleCardState();
}

class _ColorStyleCardState extends State<_ColorStyleCard> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = pressed
        ? 14.0
        : widget.selected
        ? 22.0
        : 32.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      decoration: BoxDecoration(
        color: widget.selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: widget.selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => pressed = true),
          onTapUp: (_) => setState(() => pressed = false),
          onTapCancel: () => setState(() => pressed = false),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PaletteDots(colors: widget.colors),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.style.label,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: MelodyScope.of(
                                      context,
                                    ).emphasisWeight,
                                  ),
                            ),
                          ),
                          if (widget.selected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: scheme.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
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

class _PaletteDots extends StatelessWidget {
  const _PaletteDots({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    height: 78,
    child: Stack(
      children: [
        _dot(context, 0, 4, 4, 48),
        _dot(context, 1, 34, 2, 36),
        _dot(context, 2, 30, 34, 42),
        _dot(context, 3, 4, 48, 28),
      ],
    ),
  );

  Widget _dot(
    BuildContext context,
    int index,
    double left,
    double top,
    double size,
  ) => Positioned(
    left: left,
    top: top,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors[index],
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 3,
        ),
      ),
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final countryController = TextEditingController(text: '86');
  final phoneController = TextEditingController();
  final captchaController = TextEditingController();
  String? qrUrl;
  String? key;
  String status = '准备二维码';
  bool busy = false;
  bool phoneMode = false;
  int captchaSeconds = 0;
  Timer? timer;
  Timer? captchaTimer;

  @override
  void dispose() {
    timer?.cancel();
    captchaTimer?.cancel();
    countryController.dispose();
    phoneController.dispose();
    captchaController.dispose();
    super.dispose();
  }

  void selectMode(bool value) {
    timer?.cancel();
    setState(() {
      phoneMode = value;
      busy = false;
      status = value ? '使用网易云绑定手机号登录' : '准备二维码';
    });
  }

  Future<void> create() async {
    final state = MelodyScope.of(context);
    setState(() {
      busy = true;
      status = '正在获取二维码…';
    });
    try {
      final session = await state.api.createQrLogin();
      if (!mounted) return;
      setState(() {
        qrUrl = session.url;
        key = session.key;
        busy = false;
        status = '请用网易云音乐扫码';
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    } catch (error) {
      if (mounted) {
        setState(() {
          busy = false;
          status = '获取失败：$error';
        });
      }
    }
  }

  Future<void> check() async {
    if (key == null) return;
    final state = MelodyScope.of(context);
    try {
      final result = await state.api.checkQr(key!);
      if (!mounted) return;
      setState(
        () => status = result.message.isEmpty
            ? '状态 ${result.code}'
            : result.message,
      );
      if (result.code == 803) {
        timer?.cancel();
        await state.finishLogin(result.cookie ?? '');
        if (mounted) Navigator.pop(context);
      } else if (result.code == 800) {
        timer?.cancel();
        setState(() => status = '二维码已过期，请刷新');
      }
    } catch (_) {}
  }

  Future<void> sendCaptcha() async {
    final phone = phoneController.text.trim();
    final countryCode = countryController.text.trim();
    if (!RegExp(r'^\d{5,15}$').hasMatch(phone) ||
        !RegExp(r'^\d{1,4}$').hasMatch(countryCode)) {
      setState(() => status = '请检查国家区号和手机号');
      return;
    }
    setState(() {
      busy = true;
      status = '正在发送短信验证码…';
    });
    try {
      await MelodyScope.of(
        context,
      ).api.sendPhoneCaptcha(phone, countryCode: countryCode);
      if (!mounted) return;
      captchaTimer?.cancel();
      setState(() {
        busy = false;
        captchaSeconds = 60;
        status = '验证码已发送';
      });
      captchaTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => captchaSeconds--);
        if (captchaSeconds <= 0) timer.cancel();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          busy = false;
          status = '发送失败：$error';
        });
      }
    }
  }

  Future<void> phoneLogin() async {
    final phone = phoneController.text.trim();
    final captcha = captchaController.text.trim();
    final countryCode = countryController.text.trim();
    if (!RegExp(r'^\d{5,15}$').hasMatch(phone) ||
        !RegExp(r'^\d{4,8}$').hasMatch(captcha)) {
      setState(() => status = '请填写有效的手机号和验证码');
      return;
    }
    setState(() {
      busy = true;
      status = '正在登录…';
    });
    try {
      final state = MelodyScope.of(context);
      await state.api.loginWithPhoneCaptcha(
        phone,
        captcha,
        countryCode: countryCode,
      );
      await state.finishLogin('');
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          busy = false;
          status = '登录失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录网易云音乐')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.qr_code_2_rounded),
                    label: Text('扫码'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.phone_android_rounded),
                    label: Text('手机号'),
                  ),
                ],
                selected: {phoneMode},
                onSelectionChanged: (value) => selectMode(value.first),
              ),
              const SizedBox(height: 30),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: const Cubic(.05, .7, .1, 1),
                switchOutCurve: const Cubic(.3, 0, .8, .15),
                child: phoneMode ? _phoneLoginForm() : _qrLoginPanel(context),
              ),
              const SizedBox(height: 24),
              Text(
                status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: MelodyScope.of(context).emphasisWeight,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '登录凭据使用 Android 加密存储，仅由应用内网易云请求引擎读取。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qrLoginPanel(BuildContext context) => Column(
    key: const ValueKey('qr-login'),
    children: [
      Container(
        width: 260,
        height: 260,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
        ),
        child: qrUrl == null
            ? Icon(
                Icons.qr_code_2_rounded,
                size: 130,
                color: Theme.of(context).colorScheme.primary,
              )
            : QrImageView(data: qrUrl!, size: 220),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: busy ? null : create,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: MorphingLoadingIndicator(size: 18),
              )
            : const Icon(Icons.refresh_rounded),
        label: Text(qrUrl == null ? '生成二维码' : '刷新二维码'),
      ),
    ],
  );

  Widget _phoneLoginForm() => ConstrainedBox(
    key: const ValueKey('phone-login'),
    constraints: const BoxConstraints(maxWidth: 420),
    child: Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 94,
              child: TextField(
                controller: countryController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '区号',
                  prefixText: '+',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: '手机号',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: captchaController,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: InputDecoration(
            labelText: '短信验证码',
            border: const OutlineInputBorder(),
            suffixIcon: TextButton(
              onPressed: busy || captchaSeconds > 0 ? null : sendCaptcha,
              child: Text(captchaSeconds > 0 ? '${captchaSeconds}s' : '获取验证码'),
            ),
          ),
          onSubmitted: (_) => busy ? null : phoneLogin(),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: busy ? null : phoneLogin,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: MorphingLoadingIndicator(size: 18),
                )
              : const Icon(Icons.login_rounded),
          label: const Text('登录'),
        ),
      ],
    ),
  );
}

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist});
  final MusicPlaylist playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  Future<MusicPlaylist>? detail;
  MusicPlaylist? latest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    detail ??= MelodyScope.of(context).loadPlaylist(widget.playlist);
  }

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return FutureBuilder<MusicPlaylist>(
      future: detail,
      builder: (context, snapshot) {
        if (snapshot.hasData) latest = snapshot.data;
        final playlist = snapshot.data ?? latest ?? widget.playlist;
        final systemBottom = MediaQuery.paddingOf(context).bottom;
        return Scaffold(
          extendBody: false,
          body: Stack(
            children: [
              Positioned.fill(
                bottom: 0,
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar.large(
                      title: Text(playlist.name),
                      actions: [
                        if (state.cloudPlaylists.any(
                          (item) => item.id == playlist.id,
                        ))
                          IconButton(
                            tooltip: '一键导入本地歌单',
                            onPressed: () async {
                              final imported = await state
                                  .importPlaylistToLocal(playlist);
                              if (!context.mounted || imported == null) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已导入“${imported.name}”'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.download_done_rounded),
                          ),
                        IconButton(
                          onPressed: () => setState(() {
                            detail = state.loadPlaylist(
                              latest ?? widget.playlist,
                              forceRefresh: true,
                            );
                          }),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: MorphingLoadingIndicator()),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        child: Row(
                          children: [
                            PlaylistCover(playlist: playlist, size: 110),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    playlist.description.isEmpty
                                        ? playlist.id.startsWith('local-')
                                              ? '本地歌单'
                                              : '网易云音乐歌单'
                                        : playlist.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('${playlist.displayTrackCount} 首歌曲'),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    onPressed: playlist.tracks.isEmpty
                                        ? null
                                        : () => state.playTrack(
                                            playlist.tracks.first,
                                            from: playlist.tracks,
                                          ),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('播放'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (snapshot.hasError)
                      SliverFillRemaining(
                        child: Center(child: Text('加载失败：${snapshot.error}')),
                      )
                    else if (playlist.tracks.isEmpty &&
                        snapshot.connectionState != ConnectionState.waiting)
                      const SliverFillRemaining(
                        child: Center(child: Text('歌单还是空的')),
                      )
                    else
                      TrackSliver(tracks: playlist.tracks),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: state.hasCurrent
                            ? 108 + systemBottom
                            : 24 + systemBottom,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.hasCurrent)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12 + systemBottom,
                  child: MiniPlayerHero(state: state),
                ),
            ],
          ),
        );
      },
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: MelodyScope.of(context).emphasisWeight,
            ),
          ),
        ),
        if (action != null)
          if (onTap != null)
            TextButton(onPressed: onTap, child: Text(action!))
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(
                action!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      ],
    ),
  );
}

/// Keeps expressive cards compact on phones, tablets and landscape windows.
/// The cards gain columns instead of stretching vertically with the viewport.
class AdaptiveM3Grid extends StatelessWidget {
  const AdaptiveM3Grid({
    super.key,
    required this.children,
    required this.preferredHeight,
    this.minCardWidth = 210,
  });

  final List<Widget> children;
  final double preferredHeight;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth - 32;
      final columns = math
          .max(2, math.min(4, ((available + 10) / (minCardWidth + 10)).floor()))
          .clamp(1, children.length)
          .toInt();
      final cardWidth = (available - (columns - 1) * 10) / columns;
      // Accommodate accessibility text scaling without shrinking labels.
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final cardHeight = preferredHeight + math.max(0, textScale - 1) * 64;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cardWidth / cardHeight,
        children: children,
      );
    },
  );
}

List<Track> _knownLikedTracks(MelodyState state) {
  final byId = <String, Track>{};
  for (final track in <Track>[
    ...state.recent,
    ...state.queue,
    ...state.recommendations,
    ...state.cloudHistory,
    for (final playlist in state.allPlaylists) ...playlist.tracks,
  ]) {
    if (state.likedTrackIds.contains(track.id)) byId[track.id] = track;
  }
  return byId.values.toList();
}

void _openTrackCollection(
  BuildContext context, {
  required String title,
  required List<Track> tracks,
  required String emptyMessage,
}) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TrackCollectionScreen(
      title: title,
      tracks: tracks,
      emptyMessage: emptyMessage,
    ),
  ),
);

class TrackCollectionScreen extends StatelessWidget {
  const TrackCollectionScreen({
    super.key,
    required this.title,
    required this.tracks,
    required this.emptyMessage,
  });

  final String title;
  final List<Track> tracks;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton.filledTonal(
            tooltip: '播放全部',
            onPressed: tracks.isEmpty
                ? null
                : () => state.playTrack(tracks.first, from: tracks),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: tracks.isEmpty
          ? Center(child: Text(emptyMessage))
          : CustomScrollView(slivers: [TrackSliver(tracks: tracks)]),
    );
  }
}

class PlaylistCollectionScreen extends StatelessWidget {
  const PlaylistCollectionScreen({super.key, required this.playlists});
  final List<MusicPlaylist> playlists;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('创建的歌单')),
    body: playlists.isEmpty
        ? const Center(child: Text('还没有创建歌单'))
        : ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return PlaylistTile(
                playlist: playlist,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlaylistScreen(playlist: playlist),
                  ),
                ),
              );
            },
          ),
  );
}

class ListeningStatsScreen extends StatelessWidget {
  const ListeningStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final week = state.stats.currentWeek;
    final maxSeconds = week.fold<int>(
      1,
      (current, day) => math.max(current, day.seconds),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('听歌统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          AdaptiveM3Grid(
            preferredHeight: 132,
            minCardWidth: 180,
            children: [
              StatTile(
                icon: Icons.today_rounded,
                value: state.stats.todayLabel,
                label: '今日聆听',
                shape: M3ContentShape.softSquare,
                valueFontSize: 24,
              ),
              StatTile(
                icon: Icons.calendar_view_week_rounded,
                value: state.stats.weekLabel,
                label: '本周聆听',
                tone: 1,
                shape: M3ContentShape.softSquare,
                valueFontSize: 24,
              ),
              StatTile(
                icon: Icons.play_circle_rounded,
                value: '${state.stats.totalPlays}',
                label: '累计播放',
                tone: 2,
                shape: M3ContentShape.softSquare,
                valueFontSize: 24,
              ),
              StatTile(
                icon: Icons.local_fire_department_rounded,
                value: '${state.stats.streakDays} 天',
                label: '连续聆听',
                shape: M3ContentShape.softSquare,
                valueFontSize: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.surfaceContainerHigh,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(32),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本周趋势',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: state.emphasisWeight,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height:
                        180 +
                        math.max(
                              0,
                              MediaQuery.textScalerOf(context).scale(14) / 14 -
                                  1,
                            ) *
                            100,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final day in week)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  _compactListeningTime(day.seconds),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 7),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutCubic,
                                  width: 22,
                                  height: 12 + 112 * day.seconds / maxSeconds,
                                  decoration: BoxDecoration(
                                    color: day.isToday
                                        ? scheme.primary
                                        : scheme.secondary,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(day.label),
                              ],
                            ),
                          ),
                      ],
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

String _compactListeningTime(int seconds) {
  if (seconds < 60) return '$seconds秒';
  final minutes = seconds ~/ 60;
  return minutes < 60 ? '$minutes分' : '${minutes ~/ 60}时';
}

class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.track,
    required this.size,
    required this.radius,
  });
  final Track track;
  final double size;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(track.seedColor).withValues(alpha: .2),
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: Clip.antiAlias,
    child: track.coverUrl.isEmpty
        ? Icon(Icons.music_note_rounded, size: size * .42)
        : ArtworkImage(
            url: track.coverUrl,
            size: (size * 2).round(),
            fit: BoxFit.cover,
            fallback: Icon(Icons.album_rounded, size: size * .48),
          ),
  );
}

class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, required this.size});
  final MusicPlaylist playlist;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .24),
    child: SizedBox.square(
      dimension: size,
      child: playlist.coverUrl.isEmpty
          ? ColoredBox(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Icon(Icons.queue_music_rounded),
            )
          : ArtworkImage(
              url: playlist.coverUrl,
              size: (size * 2).round(),
              fit: BoxFit.cover,
              fallback: ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const Icon(Icons.queue_music_rounded),
              ),
            ),
    ),
  );
}

class HorizontalTracks extends StatelessWidget {
  const HorizontalTracks({
    super.key,
    required this.tracks,
    this.shapeId,
    this.shapeTitle = '歌曲卡片整组形状',
  });
  final List<Track> tracks;
  final String? shapeId;
  final String shapeTitle;
  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    final shape =
        M3ContentShape.values[state.cardShape(shapeId ?? 'track_cards', 0)];
    final border = _m3ContentBorder(shape);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final track = tracks[i];
        return SizedBox(
          width: 138,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => state.playTrack(track, from: tracks),
            onLongPress: shapeId == null
                ? null
                : () => _editCardShape(
                    context,
                    state,
                    shapeId!,
                    title: shapeTitle,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  shape: border,
                  clipBehavior: Clip.antiAlias,
                  child: Cover(track: track, size: 138, radius: 0),
                ),
                const SizedBox(height: 8),
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                  ),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HorizontalPlaylists extends StatelessWidget {
  const HorizontalPlaylists({
    super.key,
    required this.playlists,
    this.shapeId,
    this.shapeTitle = '歌单卡片整组形状',
  });
  final List<MusicPlaylist> playlists;
  final String? shapeId;
  final String shapeTitle;

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    final shape =
        M3ContentShape.values[state.cardShape(shapeId ?? 'playlist_cards', 4)];
    final border = _m3ContentBorder(shape);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: playlists.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return SizedBox(
          width: 138,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlaylistScreen(playlist: playlist),
              ),
            ),
            onLongPress: shapeId == null
                ? null
                : () => _editCardShape(
                    context,
                    state,
                    shapeId!,
                    title: shapeTitle,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 138,
                  child: Material(
                    shape: border,
                    clipBehavior: Clip.antiAlias,
                    child: playlist.coverUrl.isEmpty
                        ? ColoredBox(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            child: const Icon(Icons.queue_music_rounded),
                          )
                        : ArtworkImage(
                            url: playlist.coverUrl,
                            size: 300,
                            fit: BoxFit.cover,
                            fallback: ColoredBox(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              child: const Icon(Icons.queue_music_rounded),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TrackSliver extends StatelessWidget {
  const TrackSliver({super.key, required this.tracks, this.showSource = false});
  final List<Track> tracks;
  final bool showSource;
  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.of(context);
    return SliverList.builder(
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 4,
          ),
          leading: Cover(track: track, size: 54, radius: 16),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: MelodyScope.of(context).emphasisWeight,
            ),
          ),
          subtitle: Text(
            [
              track.artist,
              if (track.album.isNotEmpty) track.album,
              if (showSource) track.sourceLabel,
            ].where((value) => value.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            onPressed: () => _trackActions(context, track),
            icon: const Icon(Icons.more_vert_rounded),
          ),
          onTap: () => state.playTrack(track, from: tracks),
        );
      },
    );
  }
}

class PlaylistTile extends StatelessWidget {
  const PlaylistTile({super.key, required this.playlist, this.onTap});
  final MusicPlaylist playlist;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    leading: SizedBox.square(
      dimension: 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: playlist.coverUrl.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const Icon(Icons.queue_music_rounded),
              )
            : ArtworkImage(
                url: playlist.coverUrl,
                size: 160,
                fit: BoxFit.cover,
                fallback: ColoredBox(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const Icon(Icons.queue_music_rounded),
                ),
              ),
      ),
    ),
    title: Text(
      playlist.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontWeight: MelodyScope.of(context).emphasisWeight),
    ),
    subtitle: Text(
      '${playlist.displayTrackCount} 首歌曲 · '
      '${playlist.id.startsWith('local-') ? '本地' : '网易云'}',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

enum M3ContentShape {
  square,
  slanted,
  gem,
  pill,
  softSquare,
  oval,
  diamond,
  hexagon,
  pentagon,
  cookie4,
  cookie6,
  clover,
  burst,
  flower,
}

ShapeBorder _m3ContentBorder(M3ContentShape shape) => switch (shape) {
  M3ContentShape.square => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(24),
  ),
  M3ContentShape.softSquare => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(40),
  ),
  M3ContentShape.pill => const StadiumBorder(),
  M3ContentShape.oval => const OvalBorder(),
  _ => M3PolygonBorder(shape),
};

EdgeInsets _m3ShapeSafePadding(M3ContentShape shape, {double vertical = 16}) =>
    switch (shape) {
      M3ContentShape.gem || M3ContentShape.diamond => EdgeInsets.symmetric(
        horizontal: 32,
        vertical: vertical + 5,
      ),
      M3ContentShape.slanted || M3ContentShape.pentagon => EdgeInsets.symmetric(
        horizontal: 27,
        vertical: vertical + 2,
      ),
      M3ContentShape.cookie4 ||
      M3ContentShape.cookie6 ||
      M3ContentShape.clover ||
      M3ContentShape.burst ||
      M3ContentShape.flower => EdgeInsets.symmetric(
        horizontal: 25,
        vertical: vertical + 3,
      ),
      M3ContentShape.pill || M3ContentShape.oval => EdgeInsets.symmetric(
        horizontal: 23,
        vertical: vertical,
      ),
      _ => EdgeInsets.symmetric(horizontal: 18, vertical: vertical),
    };

Future<void> _editCardShape(
  BuildContext context,
  MelodyState state,
  String cardId, {
  String title = '编辑卡片形状',
  List<String> groupIds = const [],
  String groupLabel = '整组',
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheetContext) {
    const labels = [
      '柔方',
      '斜切',
      '宝石',
      '胶囊',
      '超柔方',
      '椭圆',
      '菱形',
      '六边形',
      '五边形',
      '四瓣曲奇',
      '六瓣曲奇',
      '四叶草',
      '星芒',
      '花冠',
    ];
    const icons = [
      Icons.crop_square_rounded,
      Icons.change_history_rounded,
      Icons.hexagon_outlined,
      Icons.toggle_on_outlined,
      Icons.rounded_corner_rounded,
      Icons.circle_outlined,
      Icons.diamond_outlined,
      Icons.hexagon_rounded,
      Icons.pentagon_outlined,
      Icons.cookie_outlined,
      Icons.cookie_rounded,
      Icons.filter_vintage_rounded,
      Icons.flare_rounded,
      Icons.local_florist_rounded,
    ];
    var applyToGroup = groupIds.isNotEmpty;
    return StatefulBuilder(
      builder: (context, setSheetState) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: MelodyScope.of(sheetContext).emphasisWeight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '选择 Material 3 Expressive 形状，内容会自动避开切角与收窄区域。',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              if (groupIds.isNotEmpty) ...[
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, label: Text('当前卡片')),
                    ButtonSegment(value: true, label: Text(groupLabel)),
                  ],
                  selected: {applyToGroup},
                  onSelectionChanged: (selection) =>
                      setSheetState(() => applyToGroup = selection.first),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.7,
                  ),
                  itemCount: M3ContentShape.values.length,
                  itemBuilder: (context, index) {
                    final shape = M3ContentShape.values[index];
                    final isSelected = state.cardShape(cardId, 0) == index;
                    final border = _m3ContentBorder(shape);
                    return AnimatedScale(
                      scale: isSelected ? 1 : .96,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutBack,
                      child: Material(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                        shape: border,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: border,
                          onTap: () {
                            state.setCardShapes(
                              applyToGroup ? groupIds : [cardId],
                              index,
                            );
                            Navigator.pop(sheetContext);
                          },
                          child: Padding(
                            padding: _m3ShapeSafePadding(shape, vertical: 10),
                            child: Row(
                              children: [
                                Icon(icons[index], size: 21),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    labels[index],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 19,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

Future<void> _editOverviewCardShape(
  BuildContext context,
  MelodyState state,
  String cardId,
) => _editCardShape(
  context,
  state,
  cardId,
  title: '音乐概览形状',
  groupIds: const ['liked', 'playlists', 'recent', 'quality'],
  groupLabel: '音乐概览整组',
);

class M3PolygonBorder extends ShapeBorder {
  const M3PolygonBorder(this.shape);
  final M3ContentShape shape;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(1), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final points = switch (shape) {
      M3ContentShape.slanted => <Offset>[
        Offset(rect.left + rect.height * .20, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right - rect.height * .20, rect.bottom),
        Offset(rect.left, rect.bottom),
      ],
      M3ContentShape.gem => <Offset>[
        Offset(rect.left + rect.width * .28, rect.top),
        Offset(rect.right - rect.width * .18, rect.top),
        Offset(rect.right, rect.top + rect.height * .42),
        Offset(rect.right - rect.width * .28, rect.bottom),
        Offset(rect.left + rect.width * .18, rect.bottom),
        Offset(rect.left, rect.top + rect.height * .58),
      ],
      M3ContentShape.diamond => <Offset>[
        Offset(rect.center.dx, rect.top),
        Offset(rect.right, rect.center.dy),
        Offset(rect.center.dx, rect.bottom),
        Offset(rect.left, rect.center.dy),
      ],
      M3ContentShape.hexagon => <Offset>[
        Offset(rect.left + rect.width * .24, rect.top),
        Offset(rect.right - rect.width * .24, rect.top),
        Offset(rect.right, rect.center.dy),
        Offset(rect.right - rect.width * .24, rect.bottom),
        Offset(rect.left + rect.width * .24, rect.bottom),
        Offset(rect.left, rect.center.dy),
      ],
      M3ContentShape.pentagon => _radialPoints(rect, 5),
      M3ContentShape.cookie4 => _radialPoints(rect, 8, alternatingRadius: .82),
      M3ContentShape.cookie6 => _radialPoints(rect, 12, alternatingRadius: .84),
      M3ContentShape.clover => _radialPoints(rect, 8, alternatingRadius: .58),
      M3ContentShape.burst => _radialPoints(rect, 24, alternatingRadius: .70),
      M3ContentShape.flower => _radialPoints(rect, 16, alternatingRadius: .83),
      _ => <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ],
    };
    final radius = switch (shape) {
      M3ContentShape.burst => 5.0,
      M3ContentShape.cookie6 || M3ContentShape.flower => 8.0,
      M3ContentShape.cookie4 || M3ContentShape.clover => 10.0,
      M3ContentShape.gem => 15.0,
      _ => 18.0,
    };
    return _roundedPolygon(points, radius);
  }

  List<Offset> _radialPoints(
    Rect rect,
    int count, {
    double alternatingRadius = 1,
  }) {
    final radiusX = rect.width / 2;
    final radiusY = rect.height / 2;
    return List<Offset>.generate(count, (index) {
      final scale = index.isEven ? 1.0 : alternatingRadius;
      final angle = -math.pi / 2 + math.pi * 2 * index / count;
      return Offset(
        rect.center.dx + math.cos(angle) * radiusX * scale,
        rect.center.dy + math.sin(angle) * radiusY * scale,
      );
    });
  }

  Path _roundedPolygon(List<Offset> points, double radius) {
    final incoming = <Offset>[];
    final outgoing = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final inLength = (current - previous).distance;
      final outLength = (next - current).distance;
      final cut = math.min(radius, math.min(inLength, outLength) * .28);
      incoming.add(current + (previous - current) / inLength * cut);
      outgoing.add(current + (next - current) / outLength * cut);
    }
    final path = Path()..moveTo(outgoing.first.dx, outgoing.first.dy);
    for (var i = 1; i <= points.length; i++) {
      final index = i % points.length;
      path
        ..lineTo(incoming[index].dx, incoming[index].dy)
        ..quadraticBezierTo(
          points[index].dx,
          points[index].dy,
          outgoing[index].dx,
          outgoing[index].dy,
        );
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

// Large dark-mode surfaces use tonal emphasis, not the near-white primary
// intended for small buttons. Keep the matching foreground with each role.
({Color background, Color foreground}) overviewColors(
  ColorScheme scheme,
  int tone,
) {
  if (scheme.brightness == Brightness.dark && (tone == 0 || tone == 2)) {
    return (
      background: Color.alphaBlend(
        (tone == 0 ? scheme.primary : scheme.tertiary).withValues(
          alpha: tone == 0 ? .22 : .12,
        ),
        scheme.surfaceContainerHigh,
      ),
      foreground: scheme.onSurface,
    );
  }
  return switch (tone) {
    0 => (background: scheme.primary, foreground: scheme.onPrimary),
    1 => (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    ),
    2 => (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    ),
    _ => (
      background: scheme.surfaceContainerHigh,
      foreground: scheme.onSurface,
    ),
  };
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.tone = 0,
    this.shape = M3ContentShape.square,
    this.onTap,
    this.onLongPress,
    this.valueFontSize,
  });
  final IconData icon;
  final String value;
  final String label;
  final int tone;
  final M3ContentShape shape;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? valueFontSize;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = overviewColors(scheme, tone);
    final background = colors.background;
    final foreground = colors.foreground;
    final cardShape = _m3ContentBorder(shape);
    return Card(
      margin: EdgeInsets.zero,
      color: background,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: cardShape,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: _m3ShapeSafePadding(shape, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: foreground, size: 22),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_outward_rounded,
                      color: foreground,
                      size: 16,
                    ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: foreground,
                    height: 1.05,
                    fontSize: valueFontSize,
                    letterSpacing: -1,
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MoodCard extends StatelessWidget {
  const MoodCard(
    this.label,
    this.icon,
    this.tone, {
    super.key,
    this.shape = M3ContentShape.pill,
    this.onTap,
    this.onLongPress,
  });
  final String label;
  final IconData icon;
  final int tone;
  final M3ContentShape shape;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = switch (tone) {
      1 => scheme.secondaryContainer,
      2 => scheme.tertiaryContainer,
      _ => scheme.primaryContainer,
    };
    final foreground = switch (tone) {
      1 => scheme.onSecondaryContainer,
      2 => scheme.onTertiaryContainer,
      _ => scheme.onPrimaryContainer,
    };
    final border = _m3ContentBorder(shape);
    return Card(
      color: background,
      shape: border,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: border,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: _m3ShapeSafePadding(shape, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                    fontSize: 17,
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

class ShortcutTile extends StatelessWidget {
  const ShortcutTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: MelodyScope.of(context).emphasisWeight),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup(this.title, this.children, {super.key});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: MelodyScope.of(context).emphasisWeight,
            ),
          ),
        ),
        for (var index = 0; index < children.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(index == 0 ? 24 : 4),
                bottom: Radius.circular(index == children.length - 1 ? 24 : 4),
              ),
              clipBehavior: Clip.antiAlias,
              child: children[index],
            ),
          ),
      ],
    ),
  );
}

class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(
      title,
      style: TextStyle(fontWeight: MelodyScope.of(context).emphasisWeight),
    ),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Icon(icon),
    title: Text(
      title,
      style: TextStyle(fontWeight: MelodyScope.of(context).emphasisWeight),
    ),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
}

String _duration(Duration value) {
  final safe = value.isNegative ? Duration.zero : value;
  final m = safe.inMinutes;
  final s = safe.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

Future<void> _createPlaylist(
  BuildContext context, {
  bool localOnly = false,
}) async {
  final controller = TextEditingController();
  final state = MelodyScope.of(context);
  var local = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('新建歌单'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '歌单名称',
                  border: OutlineInputBorder(),
                ),
              ),
              if (state.loggedIn && !localOnly) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.phone_android_rounded),
                        label: Text('本地歌单'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.cloud_rounded),
                        label: Text('网易云歌单'),
                      ),
                    ],
                    selected: {local},
                    onSelectionChanged: (selection) =>
                        setDialogState(() => local = selection.first),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    state.createPlaylist(controller.text, local: localOnly || local);
  }
  controller.dispose();
}

Future<void> _fontWeightSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final state = MelodyScope.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('全局字重', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '同时调整标题、正文、歌词和导航标签。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('轻盈')),
                      ButtonSegment(value: 1, label: Text('标准')),
                      ButtonSegment(value: 2, label: Text('清晰')),
                    ],
                    selected: {state.fontWeightLevel},
                    onSelectionChanged: (selection) {
                      state.setFontWeightLevel(selection.first);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

Future<void> _themeModeSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final state = MelodyScope.of(context);
        const modes = <(ThemeMode, String, IconData)>[
          (ThemeMode.system, '跟随系统', Icons.brightness_auto_rounded),
          (ThemeMode.light, '浅色', Icons.light_mode_rounded),
          (ThemeMode.dark, '深色', Icons.dark_mode_rounded),
        ];
        return SafeArea(
          child: RadioGroup<ThemeMode>(
            groupValue: state.themeMode,
            onChanged: (value) {
              if (value == null) return;
              state.setThemeMode(value);
              Navigator.pop(context);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in modes)
                  RadioListTile<ThemeMode>(
                    value: item.$1,
                    secondary: Icon(item.$3),
                    title: Text(item.$2),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

Future<void> _qualitySheet(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (context) {
    final state = MelodyScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '音质',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: MelodyScope.of(context).emphasisWeight,
              ),
            ),
            RadioGroup<AudioQuality>(
              groupValue: state.quality,
              onChanged: (value) {
                if (value != null) state.setQuality(value);
                Navigator.pop(context);
              },
              child: Column(
                children: AudioQuality.values
                    .map(
                      (q) => RadioListTile<AudioQuality>(
                        title: Text(q.label),
                        subtitle: Text(
                          q == AudioQuality.lossless || q == AudioQuality.hires
                              ? '无损音频 · 取决于账号权益与来源'
                              : '${q.kbps} kbps',
                        ),
                        value: q,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

Future<void> _showQueue(BuildContext context) {
  var positionedAtCurrent = false;
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final state = MelodyScope.of(context);
      final currentIndex = state.queue.indexWhere(
        (track) => track.id == state.current.id,
      );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (context, controller) {
          if (!positionedAtCurrent && currentIndex > 0) {
            positionedAtCurrent = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!controller.hasClients) return;
              const itemExtent = 70.0;
              controller.jumpTo(
                (currentIndex * itemExtent).clamp(
                  0.0,
                  controller.position.maxScrollExtent,
                ),
              );
            });
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '播放队列',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: MelodyScope.of(
                                    context,
                                  ).emphasisWeight,
                                ),
                          ),
                          Text(
                            '${state.queue.length} 首 · 长按拖动调整顺序',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: state.queue.length <= 1
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  icon: const Icon(
                                    Icons.playlist_remove_rounded,
                                  ),
                                  title: const Text('清空接下来播放？'),
                                  content: const Text('正在播放的歌曲会保留。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('清空'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) state.clearUpcomingQueue();
                            },
                      icon: const Icon(Icons.playlist_remove_rounded),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ),
              if (state.queue.isEmpty)
                const Expanded(child: Center(child: Text('队列为空，去选一首歌吧')))
              else
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: controller,
                    itemExtent: 70,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    buildDefaultDragHandles: false,
                    itemCount: state.queue.length,
                    onReorder: state.reorderQueue,
                    proxyDecorator: (child, index, animation) =>
                        AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) => Material(
                            elevation: 3 * animation.value,
                            color: Colors.transparent,
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(
                                28 - 8 * animation.value,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: child,
                          ),
                          child: child,
                        ),
                    itemBuilder: (context, i) {
                      final track = state.queue[i];
                      final isCurrent = track.id == state.current.id;
                      return Padding(
                        key: ValueKey(track.id),
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Colors.transparent,
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(
                              isCurrent ? 20 : 28,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: Cover(track: track, size: 48, radius: 14),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              isCurrent
                                  ? '正在播放 · ${track.artist}'
                                  : track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              state.playTrack(track, from: state.queue);
                              Navigator.pop(context);
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: isCurrent ? '正在播放' : '从队列移除',
                                  onPressed: isCurrent
                                      ? null
                                      : () => state.removeFromQueue(track),
                                  icon: Icon(
                                    isCurrent
                                        ? Icons.graphic_eq_rounded
                                        : Icons.remove_circle_outline_rounded,
                                  ),
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Icon(Icons.drag_handle_rounded),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _trackActions(BuildContext context, Track track) =>
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Cover(track: track, size: 52, radius: 14),
                title: Text(
                  track.title,
                  style: TextStyle(
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                  ),
                ),
                subtitle: Text(track.artist),
              ),
              ListTile(
                leading: const Icon(Icons.queue_play_next_rounded),
                title: const Text('下一首播放'),
                onTap: () {
                  MelodyScope.of(context).enqueueNext(track);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('添加到歌单'),
                onTap: () {
                  Navigator.pop(context);
                  _choosePlaylist(context, track);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

Future<void> _lyricFrameRateSheet(BuildContext context) async {
  final state = MelodyScope.of(context);
  const choices = [15, 24, 30, 45, 60];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('歌词动画帧率', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '只限制逐字高亮更新；换行弹簧独立运行。较低帧率更省电，较高帧率更紧跟快歌。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final fps in choices)
                  ChoiceChip(
                    avatar: fps == 30
                        ? const Icon(Icons.auto_awesome_rounded, size: 18)
                        : null,
                    label: Text('$fps FPS'),
                    selected: state.lyricFrameRate == fps,
                    onSelected: (_) {
                      state.setLyricFrameRate(fps);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '30 FPS 在功耗和流畅度之间更平衡，并且是默认值。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _lyricScrollMotionSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final state = MelodyScope.of(context);
      final scheme = Theme.of(context).colorScheme;
      Widget parameterSlider({
        required String title,
        required String description,
        required double value,
        required double min,
        required double max,
        required int divisions,
        required ValueChanged<double> onChanged,
      }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(color: scheme.primary),
              ),
            ],
          ),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
            onChangeEnd: (_) => state.saveLyricScrollMotion(),
          ),
        ],
      );

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('换行弹簧', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text('仅调整歌词换行时的纵向跟随；逐字高亮、字号缩放和强调动画不会改变。'),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in LyricScrollPreset.values.where(
                    (item) => item != LyricScrollPreset.custom,
                  ))
                    ChoiceChip(
                      avatar: preset == LyricScrollPreset.balanced
                          ? const Icon(Icons.auto_awesome_rounded, size: 18)
                          : preset == LyricScrollPreset.efficient
                          ? const Icon(Icons.battery_saver_rounded, size: 18)
                          : null,
                      label: Text(preset.label),
                      selected: state.lyricScrollPreset == preset,
                      onSelected: (_) => state.setLyricScrollPreset(preset),
                    ),
                  if (state.lyricScrollPreset == LyricScrollPreset.custom)
                    const Chip(label: Text('自定义')),
                ],
              ),
              const SizedBox(height: 22),
              parameterSlider(
                title: '响应速度',
                description: '数值越高，当前歌词越快追上目标位置。',
                value: state.lyricScrollStiffness,
                min: 80,
                max: 420,
                divisions: 68,
                onChanged: (value) =>
                    state.previewLyricScrollMotion(stiffness: value),
              ),
              parameterSlider(
                title: '阻尼',
                description: '数值越高越稳，越低则回弹和惯性更明显。',
                value: state.lyricScrollDamping,
                min: 8,
                max: 48,
                divisions: 40,
                onChanged: (value) =>
                    state.previewLyricScrollMotion(damping: value),
              ),
              parameterSlider(
                title: '质量',
                description: '数值越高越有重量感，停止所需时间也会增加。',
                value: state.lyricScrollMass,
                min: .5,
                max: 2,
                divisions: 30,
                onChanged: (value) =>
                    state.previewLyricScrollMotion(mass: value),
              ),
              const SizedBox(height: 6),
              Text(
                '“自然”接近 AMLL 的克制弹性；老旧设备建议选择“省电”并配合 24 FPS。参数会从下一次换行开始生效。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _lyricSourceOrderSheet(BuildContext context) async {
  final state = MelodyScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('歌词来源排序', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('使用箭头调整搜索结果顺序。开启逐字歌词时，逐字结果优先。'),
              const SizedBox(height: 12),
              for (
                var index = 0;
                index < state.lyricSourceOrder.length;
                index++
              )
                ListTile(
                  leading: CircleAvatar(child: Text((index + 1).toString())),
                  title: Text(state.lyricSourceOrder[index].label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上移',
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        onPressed: index == 0
                            ? null
                            : () => state.moveLyricSource(index, index - 1),
                      ),
                      IconButton(
                        tooltip: '下移',
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        onPressed: index == state.lyricSourceOrder.length - 1
                            ? null
                            : () => state.moveLyricSource(index, index + 1),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _lyricPickerSheet(BuildContext context) async {
  final state = MelodyScope.of(context);
  final controller = TextEditingController(
    text: '${state.current.title} ${state.current.artist}'.trim(),
  );
  if (state.lyricChoices.isEmpty ||
      state.lyricChoicesTrackId != state.current.id) {
    if (!state.hasCachedCurrentLyrics) {
      unawaited(state.searchLyrics(controller.text));
    }
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final live = MelodyScope.of(context);
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('歌词与时间', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.translate_rounded),
                        title: const Text('显示翻译'),
                        subtitle: const Text('有翻译时显示在原文下方'),
                        value: live.showTranslation,
                        onChanged: (value) =>
                            live.setSetting('showTranslation', value),
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.graphic_eq_rounded),
                        title: const Text('逐字歌词优先'),
                        subtitle: const Text('优先选择带逐字时间轴的结果'),
                        value: live.karaokeLyrics,
                        onChanged: (value) {
                          live.setSetting('karaokeLyrics', value);
                          live.loadLyrics();
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.sort_rounded),
                        title: const Text('歌词来源排序'),
                        subtitle: Text(live.lyricSourceOrderLabel),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _lyricSourceOrderSheet(context),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.swap_vert_circle_rounded),
                        title: const Text('换行弹簧'),
                        subtitle: Text(
                          '${live.lyricScrollPreset.label} · 响应 ${live.lyricScrollStiffness.round()} · 阻尼 ${live.lyricScrollDamping.round()}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _lyricScrollMotionSheet(context),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.speed_rounded),
                        title: const Text('歌词动画帧率'),
                        subtitle: Text(
                          '${live.lyricFrameRate} FPS · 默认 30 FPS',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _lyricFrameRateSheet(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: live.searchLyrics,
                  decoration: InputDecoration(
                    hintText: '模糊搜索歌曲、歌手或专辑',
                    prefixIcon: const Icon(Icons.manage_search_rounded),
                    suffixIcon: IconButton.filledTonal(
                      onPressed: () => live.searchLyrics(controller.text),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.timelapse_rounded),
                    const SizedBox(width: 10),
                    const Text('全局歌词延迟'),
                    const Spacer(),
                    Text(
                      '${live.lyricDelayMs >= 0 ? '+' : ''}${live.lyricDelayMs} ms',
                      style: TextStyle(color: scheme.primary),
                    ),
                  ],
                ),
                Slider(
                  value: live.lyricDelayMs.toDouble(),
                  min: -5000,
                  max: 5000,
                  divisions: 40,
                  label: '${live.lyricDelayMs} ms',
                  onChanged: (value) => live.setLyricDelay(value.round()),
                ),
                Text(
                  '正数让歌词稍后出现，设置会对所有歌曲保存。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: live.searchingLyrics
                      ? const Center(child: MorphingLoadingIndicator())
                      : live.lyricChoices.isEmpty
                      ? Center(
                          child: Text(
                            live.hasCachedCurrentLyrics
                                ? '当前歌词已从本地缓存恢复\n需要更换时点击上方搜索按钮'
                                : '没有找到可用歌词',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: live.lyricChoices.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final choice = live.lyricChoices[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              leading: Cover(
                                track: choice.track,
                                size: 52,
                                radius: 16,
                              ),
                              title: Text(choice.track.title),
                              subtitle: Text(
                                '${choice.source} · ${choice.track.artist}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Chip(
                                avatar: Icon(
                                  choice.isWordSynced
                                      ? Icons.graphic_eq_rounded
                                      : Icons.subject_rounded,
                                  size: 18,
                                ),
                                label: Text(choice.isWordSynced ? '逐字' : '普通'),
                              ),
                              onTap: () {
                                live.selectLyrics(choice);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  controller.dispose();
}

Future<void> _serviceDialog(BuildContext context) async {
  final state = MelodyScope.of(context);
  final adapter = TextEditingController(text: state.adapterEndpoint);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('授权音源适配器'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: adapter,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '授权音源适配器（可选）',
                hintText: '仅填写你有权使用的服务',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '应用不会绕过付费、地区限制或 DRM。请仅配置你部署或获准使用的服务。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await state.updateSourceEndpoint(adapter.text);
  }
  adapter.dispose();
}

Future<void> _choosePlaylist(BuildContext context, Track track) async {
  final state = MelodyScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '添加到歌单',
                style: TextStyle(
                  fontWeight: MelodyScope.of(context).emphasisWeight,
                ),
              ),
              subtitle: Text('${track.sourceLabel} · 本地歌单支持所有音源'),
              trailing: IconButton.filledTonal(
                tooltip: '新建本地歌单',
                onPressed: () {
                  Navigator.pop(context);
                  _createPlaylist(context, localOnly: true);
                },
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    leading: Icon(Icons.phone_android_rounded),
                    title: Text('本地歌单'),
                  ),
                  if (state.playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(56, 4, 20, 16),
                      child: Text('还没有本地歌单，可点击右上角新建'),
                    ),
                  for (final playlist in state.playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(playlist.name),
                      subtitle: Text('${playlist.displayTrackCount} 首 · 本地'),
                      onTap: () async {
                        Navigator.pop(context);
                        await state.addToPlaylist(track, playlist);
                      },
                    ),
                  if (state.cloudPlaylists.isNotEmpty) ...[
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.cloud_rounded),
                      title: Text('网易云歌单'),
                    ),
                    for (final playlist in state.cloudPlaylists)
                      ListTile(
                        enabled: RegExp(r'^\d+$').hasMatch(track.id),
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(playlist.name),
                        subtitle: Text(
                          !RegExp(r'^\d+$').hasMatch(track.id)
                              ? '其他音源歌曲不能写入网易云'
                              : '${playlist.displayTrackCount} 首 · 网易云',
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          await state.addToPlaylist(track, playlist);
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _accountSheet(BuildContext context) async {
  final state = MelodyScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ArtworkAvatar(
              url: state.avatarUrl,
              diameter: 40,
              fallback: const Icon(Icons.person_rounded),
            ),
            title: Text(
              state.nickname,
              style: TextStyle(
                fontWeight: MelodyScope.of(context).emphasisWeight,
              ),
            ),
            subtitle: Text('网易云 UID ${state.userId}'),
          ),
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('立即同步'),
            onTap: () {
              Navigator.pop(context);
              state.refreshAll();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.logout_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '退出登录',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              Navigator.pop(context);
              await state.logout();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class InstrumentalLyricStage extends StatelessWidget {
  const InstrumentalLyricStage({
    super.key,
    required this.playing,
    this.compact = false,
  });

  final bool playing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '纯音乐',
      child: Align(
        alignment: compact
            ? const Alignment(-1, -.18)
            : const Alignment(-1, -.30),
        child: Padding(
          padding: EdgeInsets.only(
            left: compact ? 12 : 48,
            right: compact ? 12 : 36,
          ),
          child: Transform.scale(
            scale: 1.11,
            alignment: Alignment.centerLeft,
            child: InterludeWait(active: true, playing: playing),
          ),
        ),
      ),
    );
  }
}

class InterludeWait extends StatefulWidget {
  const InterludeWait({super.key, required this.active, required this.playing});

  final bool active;
  final bool playing;

  @override
  State<InterludeWait> createState() => _InterludeWaitState();
}

class _InterludeWaitState extends State<InterludeWait>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant InterludeWait oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.active && widget.playing) {
      if (!controller.isAnimating) controller.repeat();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [scheme.primary, scheme.secondary, scheme.tertiary];
    return Semantics(
      label: '间奏',
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = controller.value * math.pi * 2 - index * .72;
            final offset = widget.active ? math.sin(phase) * 5.5 : 0.0;
            return Padding(
              padding: const EdgeInsets.only(right: 11),
              child: Transform.translate(
                offset: Offset(0, -offset),
                child: Text(
                  index == 1 ? '♫' : '♪',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors[index],
                    fontWeight: MelodyScope.of(context).emphasisWeight,
                    shadows: widget.active
                        ? [
                            Shadow(
                              color: colors[index].withValues(alpha: .38),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class M3EWavyProgressIndicator extends StatefulWidget {
  const M3EWavyProgressIndicator({
    super.key,
    required this.value,
    this.onChanged,
    this.height = 28,
    this.animate = true,
    this.indeterminate = false,
    this.color,
    this.trackColor,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double height;
  final bool animate;
  final bool indeterminate;
  final Color? color;
  final Color? trackColor;

  @override
  State<M3EWavyProgressIndicator> createState() =>
      _M3EWavyProgressIndicatorState();
}

class _M3EWavyProgressIndicatorState extends State<M3EWavyProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  final ValueNotifier<double> sampledPhase = ValueNotifier(0);
  Duration nextSample = Duration.zero;
  bool efficientRendering = true;

  @override
  void initState() {
    super.initState();
    phase.addListener(_samplePhase);
    if (widget.animate || widget.indeterminate) phase.repeat();
  }

  void _samplePhase() {
    final elapsed = phase.lastElapsedDuration ?? Duration.zero;
    final interval = efficientRendering
        ? const Duration(microseconds: 33333)
        : const Duration(microseconds: 16667);
    if (elapsed < nextSample) return;
    nextSample = elapsed + interval;
    sampledPhase.value = phase.value;
  }

  @override
  void didUpdateWidget(covariant M3EWavyProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.animate || widget.indeterminate) && !phase.isAnimating) {
      phase.repeat();
    } else if (!widget.animate && !widget.indeterminate && phase.isAnimating) {
      phase.stop();
    }
  }

  @override
  void dispose() {
    phase.removeListener(_samplePhase);
    phase.dispose();
    sampledPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    efficientRendering = MelodyScope.read(context).efficientRendering;
    final value = widget.value.clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    void update(double x, double width) {
      widget.onChanged?.call((x / width).clamp(0.0, 1.0));
    }

    return Semantics(
      slider: widget.onChanged != null && !widget.indeterminate,
      label: widget.indeterminate ? '正在准备播放' : '播放进度',
      value: widget.indeterminate ? null : '${(value * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: widget.onChanged == null
              ? null
              : (details) =>
                    update(details.localPosition.dx, constraints.maxWidth),
          onHorizontalDragUpdate: widget.onChanged == null
              ? null
              : (details) =>
                    update(details.localPosition.dx, constraints.maxWidth),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WavyProgressPainter(
                value: value,
                phase: sampledPhase,
                indeterminate: widget.indeterminate,
                color: widget.color ?? scheme.primary,
                trackColor:
                    widget.trackColor ??
                    Color.lerp(
                      scheme.secondaryContainer,
                      scheme.onSecondaryContainer,
                      .22,
                    )!,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  _WavyProgressPainter({
    required this.value,
    required this.phase,
    required this.indeterminate,
    required this.color,
    required this.trackColor,
  }) : super(repaint: phase);

  final double value;
  final ValueListenable<double> phase;
  final bool indeterminate;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Material 3 Expressive linear indicator tokens.
    const stroke = 4.0;
    const wavelength = 40.0;
    const amplitude = 3.0;
    const gap = 4.0;
    const stopSize = 4.0;
    final centerY = size.height / 2;
    final progressX = size.width * value;
    final activeEnd = progressX;
    final trackStart = math.min(size.width, progressX + gap + stroke);
    final stopDiameter = math.min(
      stopSize,
      math.max(0.0, size.width - progressX),
    );
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    if (indeterminate) {
      final trackEnd = size.width - stopSize - gap - stroke / 2;
      strokePaint.color = trackColor;
      canvas.drawLine(
        Offset(stroke / 2, centerY),
        Offset(trackEnd, centerY),
        strokePaint,
      );
      canvas.drawCircle(
        Offset(size.width - stopSize / 2, centerY),
        stopSize / 2,
        Paint()..color = trackColor,
      );

      final segment = size.width * .28;
      final travel = Curves.easeInOutCubic.transform(phase.value);
      final head = -segment + (size.width + segment * 2) * travel;
      final activeStart = (head - segment).clamp(0.0, size.width);
      final activeEnd = head.clamp(0.0, size.width);
      if (activeEnd > activeStart) {
        final path = Path();
        for (var x = activeStart; x <= activeEnd; x += 1.4) {
          final leading = ((x - activeStart) / 8).clamp(0.0, 1.0);
          final trailing = ((activeEnd - x) / 8).clamp(0.0, 1.0);
          final envelope = math.min(leading, trailing);
          final y =
              centerY +
              math.sin(
                    x / wavelength * math.pi * 2 - phase.value * math.pi * 2,
                  ) *
                  amplitude *
                  envelope;
          if (x == activeStart) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.lineTo(activeEnd, centerY);
        strokePaint.color = color;
        canvas.drawPath(path, strokePaint);
      }
      return;
    }

    final trackEnd = size.width - stopSize - gap - stroke / 2;
    if (trackStart < trackEnd) {
      strokePaint.color = trackColor;
      canvas.drawLine(
        Offset(trackStart, centerY),
        Offset(trackEnd, centerY),
        strokePaint,
      );
    }
    if (stopDiameter > 0) {
      canvas.drawCircle(
        Offset(size.width - stopDiameter / 2, centerY),
        stopDiameter / 2,
        Paint()..color = trackColor,
      );
    }

    if (activeEnd <= 0) return;
    final waveAmplitude = value <= .1 || value >= .95 ? 0.0 : amplitude;
    final path = Path();
    for (var x = 0.0; x < activeEnd; x += 1.4) {
      final trailingEnvelope = ((activeEnd - x) / 8).clamp(0.0, 1.0);
      final y =
          centerY +
          math.sin(x / wavelength * math.pi * 2 - phase.value * math.pi * 2) *
              waveAmplitude *
              trailingEnvelope;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    // Material's active indicator joins the gap on its center line. Appending
    // this fixed point prevents the animated phase from bobbing at the end.
    path.lineTo(activeEnd, centerY);
    strokePaint.color = color;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter oldDelegate) =>
      value != oldDelegate.value ||
      indeterminate != oldDelegate.indeterminate ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor;
}

void _info(BuildContext context, String title, String body) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(body),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);
