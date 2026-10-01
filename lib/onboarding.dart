import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'experience_preferences.dart';
import 'models.dart';
import 'ui.dart';

class FirstLaunchGate extends StatelessWidget {
  const FirstLaunchGate({super.key, this.home = const AppShell()});
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final completed = MelodyScope.of(context).onboardingCompleted;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 350),
      switchInCurve: Curves.easeInOutCubicEmphasized,
      child: KeyedSubtree(
        key: ValueKey(completed),
        child: completed ? home : const WelcomeScreen(),
      ),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.revisit = false});
  final bool revisit;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _saving = false;
  bool _changingPage = false;
  bool _initialized = false;
  late ThemeMode _themeMode;
  late AudioQuality _quality;
  late bool _dynamicColor;
  late bool _karaokeLyrics;
  late bool _showTranslation;
  late bool _efficientRendering;
  late bool _privateMode;
  late HomeLayoutPreferences _homeLayout;
  late int _backgroundMode;
  late int _fontWeightLevel;
  late LyricScrollPreset _lyricScrollPreset;
  late int _lyricFrameRate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final state = MelodyScope.read(context);
    _themeMode = state.themeMode;
    _quality = state.quality;
    _dynamicColor = state.dynamicColor;
    _karaokeLyrics = state.karaokeLyrics;
    _showTranslation = state.showTranslation;
    _efficientRendering = state.efficientRendering;
    _privateMode = state.privateMode;
    _homeLayout = state.homeLayout;
    _backgroundMode = !state.gradientPlayerBackground
        ? 0
        : state.singleColorPlayerBackground
        ? 1
        : 2;
    _fontWeightLevel = state.fontWeightLevel;
    _lyricScrollPreset = state.lyricScrollPreset;
    _lyricFrameRate = state.lyricFrameRate;
    _initialized = true;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _goTo(int page) async {
    if (_changingPage || _saving || page == _page) return;
    setState(() => _changingPage = true);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      await _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
    if (mounted) setState(() => _changingPage = false);
  }

  Future<void> _finish({bool skip = false}) async {
    if (_saving) return;
    if (widget.revisit && skip) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await MelodyScope.read(context).completeOnboarding(
        choices: skip
            ? null
            : QuickSetupChoices(
                themeMode: _themeMode,
                quality: _quality,
                dynamicColor: _dynamicColor,
                karaokeLyrics: _karaokeLyrics,
                showTranslation: _showTranslation,
                efficientRendering: _efficientRendering,
                privateMode: _privateMode,
                homeLayout: _homeLayout,
                gradientPlayerBackground: _backgroundMode != 0,
                singleColorPlayerBackground: _backgroundMode == 1,
                fontWeightLevel: _fontWeightLevel,
                lyricScrollPresetIndex: _lyricScrollPreset.index,
                lyricFrameRate: _lyricFrameRate,
              ),
      );
      if (mounted && widget.revisit) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置暂未保存，请重试。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final brightness = switch (_themeMode) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };
    final scheme = brightness == base.brightness
        ? base.colorScheme
        : ColorScheme.fromSeed(
            seedColor: base.colorScheme.primary,
            brightness: brightness,
          );
    return AnimatedTheme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        platform: base.platform,
        pageTransitionsTheme: base.pageTransitionsTheme,
        textTheme: base.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
        iconTheme: base.iconTheme.copyWith(color: scheme.onSurface),
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubicEmphasized,
      child: Builder(
        builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: widget.revisit && _page == 0 && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _page > 0 && !_saving) _goTo(_page - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        if (_page > 0 || widget.revisit)
                          ExpressiveIconButton(
                            tooltip: '上一步',
                            tonal: true,
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: _saving || _changingPage
                                ? null
                                : () => _page > 0
                                      ? _goTo(_page - 1)
                                      : Navigator.of(context).pop(),
                          )
                        else
                          const SizedBox.square(dimension: 48),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            label: '第 ${_page + 1} 步，共 3 步',
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    AnimatedContainer(
                                      duration: reducedMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 250),
                                      curve: Curves.easeInOutCubicEmphasized,
                                      width: i == _page ? 32 : 8,
                                      height: 8,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: i == _page
                                            ? scheme.primary
                                            : scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _saving || _changingPage
                              ? null
                              : () => _finish(skip: true),
                          child: Text(widget.revisit ? '取消' : '稍后设置'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      // Explicit buttons keep partially selected settings and
                      // page indicators in sync, including rapid taps/back.
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (value) => setState(() => _page = value),
                      children: [
                        const _WelcomeIntroduction(),
                        _preferences(),
                        _homePreferences(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        M3EActionButton(
                          key: const ValueKey('welcome-next'),
                          label: _saving
                              ? '正在保存…'
                              : _page == 0
                              ? '开始快速设置'
                              : _page == 1
                              ? '选择主页内容'
                              : '开始聆听',
                          icon: _page == 2
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          onPressed: _saving || _changingPage
                              ? null
                              : () => _page == 2 ? _finish() : _goTo(_page + 1),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '所有选项都可在设置中再次调整',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
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

  Widget _preferences() => ListView(
    key: const PageStorageKey('welcome-preferences'),
    padding: const EdgeInsets.only(bottom: 16),
    children: [
      const _StepHeading('听歌，也有你的风格', '选几项常用偏好，马上就好。'),
      SettingsGroup('主题', [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in ThemeMode.values)
                ChoiceChip(
                  label: Text(switch (mode) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                  }),
                  selected: _themeMode == mode,
                  onSelected: (_) => setState(() => _themeMode = mode),
                ),
            ],
          ),
        ),
        SettingsSwitch(
          icon: Icons.palette_rounded,
          title: '封面动态取色',
          subtitle: '主题随当前专辑封面变化',
          value: _dynamicColor,
          onChanged: (v) => setState(() => _dynamicColor = v),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('界面字重'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < 3; index++)
                    ChoiceChip(
                      label: Text(const ['轻盈', '标准', '清晰'][index]),
                      selected: _fontWeightLevel == index,
                      onSelected: (_) =>
                          setState(() => _fontWeightLevel = index),
                    ),
                ],
              ),
            ],
          ),
        ),
      ]),
      SettingsGroup('默认音质', [
        Padding(
          key: const ValueKey('welcome-quality'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final quality in AudioQuality.values)
                    ChoiceChip(
                      label: Text(quality.label),
                      selected: _quality == quality,
                      onSelected: (_) => setState(() => _quality = quality),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(switch (_quality) {
                AudioQuality.standard => '节省流量 · 128 kbps',
                AudioQuality.higher => '日常聆听 · 192 kbps',
                AudioQuality.exhigh => '细节更丰富 · 320 kbps',
                AudioQuality.lossless => '无损细节 · 流量占用较高',
                AudioQuality.hires => '高解析度 · 流量占用较高',
              }),
            ],
          ),
        ),
      ]),
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Text('实际可用音质取决于歌曲来源和账号权益。'),
      ),
      SettingsGroup('歌词', [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('播放与歌词页背景'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < 3; index++)
                    ChoiceChip(
                      label: Text(const ['纯色背景', '单色渐变', '动态流光'][index]),
                      selected: _backgroundMode == index,
                      onSelected: (_) =>
                          setState(() => _backgroundMode = index),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(switch (_backgroundMode) {
                0 => '静态封面取色背景，画面更简洁。',
                1 => '同色系上暗下亮，没有持续动画。',
                _ => '封面色彩缓慢流动；系统减少动画时使用静态效果。',
              }),
            ],
          ),
        ),
        SettingsSwitch(
          icon: Icons.auto_awesome_rounded,
          title: '逐字歌词',
          subtitle: '有逐字版本时，随演唱进度高亮',
          value: _karaokeLyrics,
          onChanged: (v) => setState(() => _karaokeLyrics = v),
        ),
        SettingsSwitch(
          icon: Icons.translate_rounded,
          title: '歌词翻译',
          subtitle: '有翻译时显示第二行',
          value: _showTranslation,
          onChanged: (v) => setState(() => _showTranslation = v),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('歌词换行动效'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in LyricScrollPreset.values)
                    if (preset != LyricScrollPreset.custom ||
                        _lyricScrollPreset == LyricScrollPreset.custom)
                      ChoiceChip(
                        label: Text(preset.label),
                        selected: _lyricScrollPreset == preset,
                        onSelected: (_) =>
                            setState(() => _lyricScrollPreset = preset),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('歌词动画帧率'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fps in {
                    15,
                    30,
                    60,
                    _lyricFrameRate,
                  }.toList()..sort())
                    ChoiceChip(
                      label: Text('$fps FPS'),
                      selected: _lyricFrameRate == fps,
                      onSelected: (_) => setState(() => _lyricFrameRate = fps),
                    ),
                ],
              ),
            ],
          ),
        ),
      ]),
      SettingsGroup('轻松聆听', [
        SettingsSwitch(
          icon: Icons.battery_saver_rounded,
          title: '高效渲染',
          subtitle: '降低动态背景与波形刷新频率',
          value: _efficientRendering,
          onChanged: (v) => setState(() => _efficientRendering = v),
        ),
        SettingsSwitch(
          icon: Icons.visibility_off_rounded,
          title: '私人聆听',
          subtitle: '不计入听歌统计，仍保留最近播放',
          value: _privateMode,
          onChanged: (v) => setState(() => _privateMode = v),
        ),
      ]),
    ],
  );

  Widget _homePreferences() => ListView(
    key: const PageStorageKey('welcome-home'),
    padding: const EdgeInsets.only(bottom: 16),
    children: [
      const _StepHeading('主页，留给你喜欢的', '每个内容元素都能单独关闭，也可以全部关闭。'),
      HomeLayoutControls(
        layout: _homeLayout,
        onPresetSelected: (layout) => setState(() => _homeLayout = layout),
        onChanged: (element, visible) => setState(
          () => _homeLayout = _homeLayout.withVisibility(element, visible),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Text('关闭只会隐藏主页内容，不会删除歌单、收藏或播放记录。导航与设置入口始终可用。'),
      ),
    ],
  );
}

class _StepHeading extends StatelessWidget {
  const _StepHeading(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _WelcomeIntroduction extends StatelessWidget {
  const _WelcomeIntroduction();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Center(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: .88, end: 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                curve: const M3ESpatialCurve(),
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: SizedBox.square(
                  dimension: 160,
                  child: Material(
                    color: scheme.primaryContainer,
                    shape: const M3PolygonBorder(M3ContentShape.flower),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 76,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          '欢迎来到\nSonorynth',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '从一首歌开始，找到自己的节奏。',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        const _FeatureCard(
          icon: Icons.explore_rounded,
          title: '发现与收藏',
          description: '搜索音乐、探索推荐，用歌单收藏喜欢的声音。登录后可同步网易云资料。',
          tone: 0,
        ),
        const _FeatureCard(
          icon: Icons.lyrics_rounded,
          title: '跟着歌词唱',
          description: '点击播放页封面打开全屏歌词，支持逐字高亮、翻译与歌词来源切换。',
          tone: 1,
        ),
        const _FeatureCard(
          icon: Icons.tune_rounded,
          title: '让聆听更顺手',
          description: '管理播放队列，切换音质，设置定时关闭。主题与主页内容都由你决定。',
          tone: 2,
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.tone,
  });
  final IconData icon;
  final String title;
  final String description;
  final int tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      0 => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      1 => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.surfaceContainerHigh, scheme.onSurface),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(description, style: TextStyle(color: foreground)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expressive shape change and a brief spatial response, without a perpetual
/// ticker or whole-screen repaints. The child is a standard Material button.
class M3EActionButton extends StatefulWidget {
  const M3EActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<M3EActionButton> createState() => _M3EActionButtonState();
}

class _M3EActionButtonState extends State<M3EActionButton> {
  bool _pressed = false;
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.addListener(_updatePressed);
  }

  void _updatePressed() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  void dispose() {
    _states.removeListener(_updatePressed);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: _pressed ? .98 : 1,
      duration: reducedMotion
          ? Duration.zero
          : Duration(milliseconds: _pressed ? 100 : 250),
      curve: _pressed ? Curves.easeOutCubic : const M3ESpatialCurve(),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onPressed,
          statesController: _states,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(64, 64)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            animationDuration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            shape: WidgetStateProperty.resolveWith((states) {
              final pressed = states.contains(WidgetState.pressed);
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(pressed ? 20 : 40),
              );
            }),
          ),
          icon: Icon(widget.icon),
          label: Text(widget.label),
        ),
      ),
    );
  }
}

class M3ESpatialCurve extends Curve {
  const M3ESpatialCurve();
  static final _spring = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 400, damping: 32),
    0,
    1,
    0,
  );
  @override
  double transformInternal(double t) => _spring.x(t * .65);
}
