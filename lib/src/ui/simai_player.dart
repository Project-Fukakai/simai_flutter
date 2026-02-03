import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../simai_flutter.dart';
import 'chart_timing_mapper.dart';
import 'simai_game.dart';
import 'fullscreen_utils.dart';

class SimaiChartInfo {
  final double totalDuration;
  final int noteCollectionCount;
  final int noteCount;
  final int timingChangeCount;

  const SimaiChartInfo({
    required this.totalDuration,
    required this.noteCollectionCount,
    required this.noteCount,
    required this.timingChangeCount,
  });
}

enum SimaiBackgroundMode {
  /// 无
  none,

  /// 判定点
  dots,

  /// 判定线 (判定点 + 判定环)
  judgeLine,

  /// 判定区 (判定点 + 判定环 + 传感分区)
  judgeZone,
}

enum SimaiMirrorMode {
  /// 无
  none,

  /// 左右反
  horizontal,

  /// 上下反
  vertical,

  /// 全反
  full,
}

class SimaiPlayerController extends ChangeNotifier {
  final MaiChart chart;
  Source? audioSource;
  ImageProvider? backgroundImageProvider;
  final double initialChartTime;
  String? title;

  VoidCallback? onToggleFullScreen;

  SimaiGame? _game;
  Timer? _pollTimer;

  double _speed = 8.0;
  bool _isPlaying = false;
  double _playbackRate = 1.0;
  double _musicVolume = 0.8;
  int _musicOffsetMs = 0;
  int _hitSoundOffsetMs = 0;
  bool _hitSoundEnabled = false;
  bool _isFullScreen = false;
  SimaiBackgroundMode _backgroundMode = SimaiBackgroundMode.judgeLine;
  SimaiMirrorMode _mirrorMode = SimaiMirrorMode.none;
  bool _rotateSlideStar = true;
  bool _pinkSlideStar = false;
  bool _standardBreakSlide = false;
  bool _highlightExNotes = false;

  double _chartTimeSnapshot = 0.0;
  double _totalDurationSnapshot = 0.0;
  bool _isDisposed = false;

  SimaiPlayerController({
    required this.chart,
    this.audioSource,
    this.backgroundImageProvider,
    this.initialChartTime = 0.0,
  }) {
    _totalDurationSnapshot = _computeTotalDuration(chart);
  }

  double get speed => _speed;
  bool get isPlaying => _isPlaying;
  double get playbackRate => _playbackRate;
  double get musicVolume => _musicVolume;
  int get musicOffsetMs => _musicOffsetMs;
  int get hitSoundOffsetMs => _hitSoundOffsetMs;
  bool get hitSoundEnabled => _hitSoundEnabled;
  bool get isFullScreen => _isFullScreen;
  SimaiBackgroundMode get backgroundMode => _backgroundMode;
  SimaiMirrorMode get mirrorMode => _mirrorMode;
  bool get rotateSlideStar => _rotateSlideStar;
  bool get pinkSlideStar => _pinkSlideStar;
  bool get standardBreakSlide => _standardBreakSlide;
  bool get highlightExNotes => _highlightExNotes;

  double get chartTime => _game?.chartTime ?? _chartTimeSnapshot;

  SimaiChartInfo get chartInfo {
    final total = _game?.totalDuration ?? _totalDurationSnapshot;
    int noteCount = 0;
    for (final collection in chart.noteCollections) {
      noteCount += collection.length;
    }
    return SimaiChartInfo(
      totalDuration: total,
      noteCollectionCount: chart.noteCollections.length,
      noteCount: noteCount,
      timingChangeCount: chart.timingChanges.length,
    );
  }

  double get approachTime {
    final safeSpeed = _speed.isFinite ? _speed : 8.0;
    final clampedSpeed = safeSpeed.clamp(3.0, 9.0).toDouble();
    return 3.6 / clampedSpeed;
  }

  double get effectiveMusicOffsetSeconds {
    return initialChartTime + _musicOffsetMs / 1000.0;
  }

  set speed(double value) {
    final safeValue = value.isFinite ? value : 8.0;
    final clamped = safeValue.clamp(3.0, 9.0).toDouble();
    final quantized = (clamped / 0.25).round() * 0.25;
    if (_speed == quantized) return;
    _speed = quantized;
    _applyToGame();
    notifyListeners();
  }

  set playbackRate(double value) {
    final safeValue = value.isFinite ? value : 1.0;
    final clamped = safeValue.clamp(0.1, 1.0).toDouble();
    if (_playbackRate == clamped) return;
    _playbackRate = clamped;
    _applyToGame();
    notifyListeners();
  }

  set musicVolume(double value) {
    final safeValue = value.isFinite ? value : 0.8;
    final clamped = safeValue.clamp(0.0, 1.0).toDouble();
    if (_musicVolume == clamped) return;
    _musicVolume = clamped;
    _applyToGame();
    notifyListeners();
  }

  set musicOffsetMs(int value) {
    final clamped = value.clamp(-2000, 2000);
    if (_musicOffsetMs == clamped) return;
    _musicOffsetMs = clamped;
    _applyToGame(resyncAudio: true);
    notifyListeners();
  }

  set hitSoundOffsetMs(int value) {
    final clamped = value.clamp(-200, 200);
    if (_hitSoundOffsetMs == clamped) return;
    _hitSoundOffsetMs = clamped;
    _applyToGame();
    notifyListeners();
  }

  set hitSoundEnabled(bool value) {
    if (_hitSoundEnabled == value) return;
    _hitSoundEnabled = value;
    _applyToGame();
    notifyListeners();
  }

  set isFullScreen(bool value) {
    if (_isFullScreen == value) return;
    _isFullScreen = value;
    notifyListeners();
  }

  set backgroundMode(SimaiBackgroundMode value) {
    if (_backgroundMode == value) return;
    _backgroundMode = value;
    _applyToGame();
    notifyListeners();
  }

  set mirrorMode(SimaiMirrorMode value) {
    if (_mirrorMode == value) return;
    _mirrorMode = value;
    _applyToGame();
    notifyListeners();
  }

  set rotateSlideStar(bool value) {
    if (_rotateSlideStar == value) return;
    _rotateSlideStar = value;
    _applyToGame();
    notifyListeners();
  }

  set pinkSlideStar(bool value) {
    if (_pinkSlideStar == value) return;
    _pinkSlideStar = value;
    _applyToGame();
    notifyListeners();
  }

  set standardBreakSlide(bool value) {
    if (_standardBreakSlide == value) return;
    _standardBreakSlide = value;
    _applyToGame();
    notifyListeners();
  }

  set highlightExNotes(bool value) {
    if (_highlightExNotes == value) return;
    _highlightExNotes = value;
    _applyToGame();
    notifyListeners();
  }

  double get totalDurationSnapshot => _totalDurationSnapshot;

  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    _applyToGame();
    notifyListeners();
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _applyToGame();
    notifyListeners();
  }

  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  Future<void> seek(double time, {bool syncAudio = true}) async {
    final total = chartInfo.totalDuration;
    final clamped = time.isFinite
        ? time.clamp(0.0, total > 0 ? total : double.infinity).toDouble()
        : 0.0;
    _chartTimeSnapshot = clamped;
    notifyListeners();
    final game = _game;
    if (game == null) return;
    await game.seek(clamped, syncAudio: syncAudio);
    _chartTimeSnapshot = game.chartTime;
    notifyListeners();
  }

  Future<void> previousMeasure() async {
    final target = computePreviousMeasureTime(chartTime);
    await seek(target, syncAudio: true);
  }

  Future<void> nextMeasure() async {
    final target = computeNextMeasureTime(chartTime);
    await seek(target, syncAudio: true);
  }

  Future<void> replayMeasure() async {
    final target = computeCurrentMeasureStartTime(chartTime);
    await seek(target, syncAudio: true);
  }

  Future<void> previousNote() async {
    final target = computePreviousNoteTime(chartTime);
    await seek(target, syncAudio: true);
  }

  Future<void> nextNote() async {
    final target = computeNextNoteTime(chartTime);
    await seek(target, syncAudio: true);
  }

  double computePreviousMeasureTime(double time) {
    return _computeMeasureTime(time, forward: false);
  }

  double computeNextMeasureTime(double time) {
    return _computeMeasureTime(time, forward: true);
  }

  double computeCurrentMeasureStartTime(double time) {
    final t = time.isFinite ? time : 0.0;
    if (chart.timingChanges.isEmpty) return t;
    final beats = ChartTimingMapper.beatsAtTime(chart, t < 0 ? 0.0 : t);
    final targetBeats = (beats / 4.0).floorToDouble() * 4.0;
    final boundaryTime = ChartTimingMapper.timeAtBeats(chart, targetBeats);
    return boundaryTime < 0 ? 0.0 : boundaryTime;
  }

  double computePreviousNoteTime(double time) {
    if (chart.noteCollections.isEmpty) return time;
    const double tolerance = 0.1;

    int lo = 0;
    int hi = chart.noteCollections.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = chart.noteCollections[mid].time;
      if (t < time - tolerance) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    if (hi < 0) return 0.0;
    return chart.noteCollections[hi].time;
  }

  double computeNextNoteTime(double time) {
    if (chart.noteCollections.isEmpty) return time;
    final epsilon = 1e-6;

    int index = _findCollectionIndex(time);
    index++;

    if (index >= chart.noteCollections.length) return time;

    if (chart.noteCollections[index].time <= time + epsilon) {
      index++;
    }

    if (index >= chart.noteCollections.length) return time;
    return chart.noteCollections[index].time;
  }

  int _findCollectionIndex(double time) {
    int lo = 0;
    int hi = chart.noteCollections.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = chart.noteCollections[mid].time;
      if (t <= time) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi;
  }

  void _attachGame(SimaiGame game) {
    if (identical(_game, game)) return;
    _pollTimer?.cancel();
    _game = game;
    _applyToGame();
    _totalDurationSnapshot = game.totalDuration;
    _chartTimeSnapshot = game.chartTime;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final g = _game;
      if (g == null) return;
      final t = g.chartTime;
      if ((_chartTimeSnapshot - t).abs() < 0.0001) return;
      _chartTimeSnapshot = t;
      notifyListeners();
    });
    // Use a microtask to notify listeners to avoid "setState during build" errors
    // when called from initState or didUpdateWidget of a child widget.
    Future.microtask(() => notifyListeners());
  }

  void _detachGame(SimaiGame game) {
    if (!identical(_game, game)) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    _game = null;
  }

  void _applyToGame({bool resyncAudio = false}) {
    final game = _game;
    if (game == null) return;
    final approach = approachTime;
    game.ringApproachTime = approach;
    game.touchApproachTime = approach;
    game.offset = effectiveMusicOffsetSeconds;
    game.hitSoundOffset = _hitSoundOffsetMs / 1000.0;
    game.hitSoundEnabled = _hitSoundEnabled;
    game.setPlaying(_isPlaying);
    game.setAudioSource(audioSource);
    game.setBackgroundImageProvider(backgroundImageProvider);
    game.setPlaybackRate(_playbackRate);
    game.setMusicVolume(_musicVolume);
    game.setBackgroundMode(_backgroundMode);
    game.setMirrorMode(_mirrorMode);
    game.rotateSlideStar = _rotateSlideStar;
    game.pinkSlideStar = _pinkSlideStar;
    game.standardBreakSlide = _standardBreakSlide;
    game.highlightExNotes = _highlightExNotes;
    if (resyncAudio) {
      game.seek(game.chartTime, syncAudio: true);
    }
  }

  double _computeMeasureTime(double time, {required bool forward}) {
    final t = time.isFinite ? time : 0.0;
    if (chart.timingChanges.isEmpty) {
      return t;
    }
    final epsilon = 1e-6;
    final clampedTime = t < 0 ? 0.0 : t;

    if (forward) {
      final beats = ChartTimingMapper.beatsAtTime(chart, clampedTime);
      double boundaryBeats = (beats / 4.0).floorToDouble() * 4.0 + 4.0;
      double boundaryTime = ChartTimingMapper.timeAtBeats(chart, boundaryBeats);
      if (boundaryTime <= clampedTime + epsilon) {
        boundaryBeats += 4.0;
        boundaryTime = ChartTimingMapper.timeAtBeats(chart, boundaryBeats);
      }
      return boundaryTime;
    } else {
      const double tolerance = 0.2;
      final beats = ChartTimingMapper.beatsAtTime(
        chart,
        (clampedTime - tolerance).clamp(0.0, double.infinity),
      );
      final targetBeats = (beats / 4.0).floorToDouble() * 4.0;
      final boundaryTime = ChartTimingMapper.timeAtBeats(chart, targetBeats);
      return boundaryTime < 0 ? 0.0 : boundaryTime;
    }
  }

  static double _computeTotalDuration(MaiChart chart) {
    if (chart.finishTiming != null) return chart.finishTiming!;
    if (chart.noteCollections.isEmpty) return 0.0;

    final lastCollection = chart.noteCollections.last;
    double maxTime = lastCollection.time;
    for (final note in lastCollection) {
      double end = lastCollection.time + (note.length ?? 0);
      if (note.type == NoteType.slide) {
        for (final slide in note.slidePaths) {
          final slideEnd = lastCollection.time + slide.delay + slide.duration;
          if (slideEnd > end) end = slideEnd;
        }
      }
      if (end > maxTime) maxTime = end;
    }
    return maxTime;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    pause();
    _pollTimer?.cancel();
    _pollTimer = null;
    _game = null;
    super.dispose();
  }
}

class SimaiPlayer extends StatefulWidget {
  final SimaiPlayerController controller;

  const SimaiPlayer({super.key, required this.controller});

  @override
  State<SimaiPlayer> createState() => _SimaiPlayerState();
}

class _SimaiPlayerState extends State<SimaiPlayer> {
  late SimaiGame _game;

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  void _initializeGame() {
    final controller = widget.controller;
    _game = SimaiGame(
      chart: controller.chart,
      isPlaying: controller.isPlaying,
      ringApproachTime: controller.approachTime,
      touchApproachTime: controller.approachTime,
      playbackRate: controller.playbackRate,
      musicVolume: controller.musicVolume,
      hitSoundOffset: controller.hitSoundOffsetMs / 1000.0,
      hitSoundEnabled: controller.hitSoundEnabled,
      backgroundMode: controller.backgroundMode,
      mirrorMode: controller.mirrorMode,
      rotateSlideStar: controller.rotateSlideStar,
      pinkSlideStar: controller.pinkSlideStar,
      standardBreakSlide: controller.standardBreakSlide,
      highlightExNotes: controller.highlightExNotes,
      initialChartTime: controller.initialChartTime,
      offset: controller.effectiveMusicOffsetSeconds,
      audioSource: controller.audioSource,
      backgroundImageProvider: controller.backgroundImageProvider,
    );
    controller._attachGame(_game);
  }

  @override
  void didUpdateWidget(SimaiPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller._detachGame(_game);
      _initializeGame();
    }
  }

  @override
  void dispose() {
    widget.controller._detachGame(_game);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget(game: _game);
  }
}

class SimaiPlayerPage extends StatefulWidget {
  final SimaiPlayerController controller;
  final String? title;
  final VoidCallback? onBack;
  final bool disposeController;

  const SimaiPlayerPage({
    super.key,
    required this.controller,
    this.title,
    this.onBack,
    this.disposeController = true,
  });

  @override
  State<SimaiPlayerPage> createState() => _SimaiPlayerPageState();
}

class _SimaiPlayerPageState extends State<SimaiPlayerPage> {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isFullScreen = false;
  bool _isLocked = false;
  bool _isManualExit = false;
  late final GlobalKey _playerKey;

  @override
  void initState() {
    super.initState();
    _playerKey = GlobalKey();
    widget.controller.onToggleFullScreen = _toggleFullScreen;
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_isFullScreen) {
      _exitFullScreen();
    }
    if (widget.disposeController) {
      widget.controller.dispose();
    }
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showControls = true;
    });
    _startHideTimer();
  }

  void _toggleFullScreen() {
    if (_isFullScreen) {
      _isManualExit = true;
      _exitFullScreen();
    } else {
      _isManualExit = false;
      _enterFullScreen();
    }
  }

  Future<void> _enterFullScreen() async {
    setState(() {
      _isFullScreen = true;
      _showControls = true;
      _isManualExit = false;
    });
    widget.controller.isFullScreen = true;
    await FullScreenUtils.enterFullScreen();
    _startHideTimer();
  }

  Future<void> _exitFullScreen() async {
    setState(() {
      _isFullScreen = false;
    });
    widget.controller.isFullScreen = false;
    await FullScreenUtils.exitFullScreen();
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final controller = widget.controller;

    // Force dark mode for the drawer
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          return Drawer(
            backgroundColor: colorScheme.surface,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
                    child: Text(
                      '设置',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (controller.title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 16, 20),
                      child: Text(
                        controller.title!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _buildSectionHeader(context, '显示设置'),
                        _buildSegmentedSetting<SimaiMirrorMode>(
                          context,
                          label: '镜像',
                          icon: Icons.flip,
                          value: controller.mirrorMode,
                          segments: const [
                            ButtonSegment(
                              value: SimaiMirrorMode.none,
                              label: Text('无'),
                            ),
                            ButtonSegment(
                              value: SimaiMirrorMode.horizontal,
                              label: Text('左右'),
                            ),
                            ButtonSegment(
                              value: SimaiMirrorMode.vertical,
                              label: Text('上下'),
                            ),
                            ButtonSegment(
                              value: SimaiMirrorMode.full,
                              label: Text('全反'),
                            ),
                          ],
                          onChanged: (v) => controller.mirrorMode = v,
                        ),
                        const SizedBox(height: 16),
                        _buildSegmentedSetting<SimaiBackgroundMode>(
                          context,
                          label: '判定线',
                          icon: Icons.blur_on,
                          value: controller.backgroundMode,
                          segments: const [
                            ButtonSegment(
                              value: SimaiBackgroundMode.none,
                              label: Text('无'),
                            ),
                            ButtonSegment(
                              value: SimaiBackgroundMode.dots,
                              label: Text('点'),
                            ),
                            ButtonSegment(
                              value: SimaiBackgroundMode.judgeLine,
                              label: Text('线'),
                            ),
                            ButtonSegment(
                              value: SimaiBackgroundMode.judgeZone,
                              label: Text('区'),
                            ),
                          ],
                          onChanged: (v) => controller.backgroundMode = v,
                        ),
                        _buildSliderSetting(
                          context,
                          label: '流速',
                          icon: Icons.speed,
                          value: controller.speed,
                          min: 3.0,
                          max: 9.0,
                          divisions: 24,
                          onChanged: (v) => controller.speed = v,
                          valueSuffix:
                              'x${controller.speed.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 16),
                        _buildSwitchSetting(
                          context,
                          label: '星星旋转',
                          icon: Icons.rotate_right,
                          value: controller.rotateSlideStar,
                          onChanged: (v) => controller.rotateSlideStar = v,
                        ),
                        _buildSwitchSetting(
                          context,
                          label: '粉色星星头',
                          icon: Icons.star,
                          value: controller.pinkSlideStar,
                          onChanged: (v) => controller.pinkSlideStar = v,
                        ),
                        _buildSwitchSetting(
                          context,
                          label: '标准色绝赞星星',
                          icon: Icons.star_border,
                          value: controller.standardBreakSlide,
                          onChanged: (v) => controller.standardBreakSlide = v,
                        ),
                        _buildSwitchSetting(
                          context,
                          label: '高亮保护套',
                          icon: Icons.brightness_high,
                          value: controller.highlightExNotes,
                          onChanged: (v) => controller.highlightExNotes = v,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Divider(),
                        ),
                        _buildSectionHeader(context, '音频设置'),
                        _buildSwitchSetting(
                          context,
                          label: '正解音播放',
                          icon: Icons.music_note,
                          value: controller.hitSoundEnabled,
                          onChanged: (v) => controller.hitSoundEnabled = v,
                        ),
                        _buildSliderSetting(
                          context,
                          label: '音乐音量',
                          icon: Icons.volume_up,
                          value: controller.musicVolume,
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          onChanged: (v) => controller.musicVolume = v,
                          valueSuffix:
                              '${(controller.musicVolume * 100).toInt()}%',
                        ),
                        _buildSliderSetting(
                          context,
                          label: '音乐偏移',
                          icon: Icons.audiotrack,
                          value: controller.musicOffsetMs.toDouble(),
                          min: -2000,
                          max: 2000,
                          divisions: 400,
                          onChanged: (v) =>
                              controller.musicOffsetMs = v.toInt(),
                          valueSuffix: '${controller.musicOffsetMs}ms',
                        ),
                        _buildSliderSetting(
                          context,
                          label: '正解音偏移',
                          icon: Icons.timer,
                          value: controller.hitSoundOffsetMs.toDouble(),
                          min: -200,
                          max: 200,
                          divisions: 40,
                          onChanged: (v) =>
                              controller.hitSoundOffsetMs = v.toInt(),
                          valueSuffix: '${controller.hitSoundOffsetMs}ms',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSegmentedSetting<T>(
    BuildContext context, {
    required String label,
    required IconData icon,
    required T value,
    required List<ButtonSegment<T>> segments,
    required ValueChanged<T> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(label, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            segments: segments,
            selected: {value},
            onSelectionChanged: (Set<T> newSelection) {
              onChanged(newSelection.first);
            },
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(label, style: theme.textTheme.bodyLarge),
      trailing: Switch(value: value, onChanged: onChanged),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    );
  }

  Widget _buildSliderSetting(
    BuildContext context, {
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? valueSuffix,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
                if (valueSuffix != null)
                  Text(
                    valueSuffix,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;

    // Auto-toggle based on orientation in mobile platforms
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (orientation == Orientation.landscape &&
            !_isFullScreen &&
            !_isManualExit) {
          _enterFullScreen();
        } else if (orientation == Orientation.portrait) {
          if (_isFullScreen) {
            _exitFullScreen();
          }
          if (_isManualExit) {
            setState(() {
              _isManualExit = false;
            });
          }
        }
      });
    }

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final player = SimaiPlayer(
          key: _playerKey,
          controller: widget.controller,
        );

        Widget body;
        PreferredSizeWidget? appBar;

        if (!_isFullScreen) {
          appBar = AppBar(
            title: Text(widget.title ?? widget.controller.title ?? ''),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: Navigator.canPop(context) || widget.onBack != null
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed:
                        widget.onBack ?? () => Navigator.of(context).pop(),
                  )
                : null,
            actions: [
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ],
          );

          body = Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(aspectRatio: 1.0, child: player),
                ),
              ),
              SafeArea(
                top: false,
                child: SimaiPlayerControls(controller: widget.controller),
              ),
            ],
          );
        } else {
          body = MouseRegion(
            onHover: (_) {
              if (!_showControls) {
                setState(() {
                  _showControls = true;
                });
              }
              _startHideTimer();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Stack(
                children: [
                  Center(child: AspectRatio(aspectRatio: 1.0, child: player)),
                  // Top Bar
                  IgnorePointer(
                    ignoring: !_showControls || _isLocked,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: (_showControls && !_isLocked) ? 1.0 : 0.0,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                            child: Row(
                              children: [
                                if (Navigator.canPop(context) ||
                                    widget.onBack != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                    ),
                                    onPressed:
                                        widget.onBack ??
                                        () => Navigator.of(context).pop(),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title ??
                                        widget.controller.title ??
                                        '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Builder(
                                  builder: (context) => IconButton(
                                    icon: const Icon(
                                      Icons.settings,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      Scaffold.of(context).openEndDrawer();
                                      _hideTimer
                                          ?.cancel(); // Don't hide while drawer is open
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom Bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !_showControls || _isLocked,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: (_showControls && !_isLocked) ? 1.0 : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 16,
                                bottom: 8,
                              ),
                              child: SimaiPlayerControls(
                                controller: widget.controller,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Lock Button
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: SafeArea(
                      left: false,
                      top: false,
                      bottom: false,
                      child: Center(
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _showControls ? 1.0 : 0.0,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.5,
                                  ),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(12),
                                ),
                                icon: Icon(
                                  _isLocked ? Icons.lock : Icons.lock_open,
                                ),
                                onPressed: _toggleLock,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_isFullScreen) {
                _exitFullScreen();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: Colors.black,
              appBar: appBar,
              endDrawer: _buildSettingsDrawer(context),
              body: body,
            ),
          ),
        );
      },
    );
  }
}
