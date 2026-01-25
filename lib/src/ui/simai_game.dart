import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import '../../simai_flutter.dart';
import 'simai_colors.dart';
import 'components/note_component.dart';
import 'components/chart_status_text_component.dart';

class SimaiGame extends FlameGame {
  final MaiChart chart;
  bool isPlaying;
  double chartTime = 0.0;
  double ringApproachTime;
  double touchApproachTime;
  double playbackRate;
  double musicVolume;
  double hitSoundOffset;
  bool hitSoundEnabled;
  SimaiBackgroundMode backgroundMode;
  SimaiMirrorMode mirrorMode;
  bool rotateSlideStar;
  bool pinkSlideStar;
  bool standardBreakSlide;
  bool highlightExNotes;
  Source? audioSource;
  ImageProvider? backgroundImageProvider;
  final AudioPlayer _audioPlayer = AudioPlayer();
  double offset;
  StreamSubscription? _positionSubscription;
  bool _pendingSeekReset = false;
  String _debugLastSeekReason = '';
  double _debugNextLogTime = 0.0;
  int _debugSeekCalls = 0;
  int _debugSeekResetsConsumed = 0;
  int _debugResizeCalls = 0;
  int _debugNotesAdded = 0;
  int _debugNotesRemoved = 0;
  int _debugAudioUpdates = 0;
  int _debugAudioPosJumps = 0;
  int? _debugLastAudioPosMs;
  double _debugMaxAbsAudioError = 0.0;
  double _debugMaxAbsCorrection = 0.0;

  int _audioBaseTimeMs = 0;
  int _audioBaseTimestampMs = 0;
  bool isResourcesLoaded = false;

  // SFX
  final List<AudioPlayer> _sfxPool = [];
  int _sfxPoolIndex = 0;
  static const int _sfxPoolSize = 16;
  static const double _hitSoundBaseOffsetSeconds = -0.050;
  List<int> _sfxEventTimesMs = const [];
  int _sfxEventIndex = 0;
  int _lastSfxCheckTimeMs = 0;

  SimaiGame({
    required this.chart,
    this.isPlaying = false,
    this.ringApproachTime = 0.7,
    this.touchApproachTime = 0.7,
    this.playbackRate = 1.0,
    this.musicVolume = 0.8,
    this.hitSoundOffset = 0.0,
    this.hitSoundEnabled = true,
    this.backgroundMode = SimaiBackgroundMode.judgeLine,
    this.mirrorMode = SimaiMirrorMode.none,
    this.rotateSlideStar = true,
    this.pinkSlideStar = false,
    this.standardBreakSlide = false,
    this.highlightExNotes = false,
    this.audioSource,
    this.backgroundImageProvider,
    double initialChartTime = 0.0,
    this.offset = 0.0,
  }) : chartTime = initialChartTime;

  double get _effectiveHitSoundOffsetSeconds =>
      _hitSoundBaseOffsetSeconds + hitSoundOffset;

  late final ChartComponent _chartComponent;

  @override
  Future<void> onLoad() async {
    _chartComponent = ChartComponent(
      game: this,
      backgroundImageProvider: backgroundImageProvider,
    );
    add(_chartComponent);

    _positionSubscription = _audioPlayer.onPositionChanged.listen((p) {
      _debugAudioUpdates++;
      final int ms = p.inMilliseconds;
      final int? lastMs = _debugLastAudioPosMs;
      if (lastMs != null && (ms - lastMs).abs() > 500) {
        _debugAudioPosJumps++;
      }
      _debugLastAudioPosMs = ms;
      _audioBaseTimeMs = p.inMilliseconds;
      _audioBaseTimestampMs = DateTime.now().millisecondsSinceEpoch;
    });

    // Initialize SFX Pool
    // Load from package assets using rootBundle to avoid AssetSource path issues on Web/different platforms
    // and convert to Data URI for reliable playback.
    final assetPath = 'packages/simai_flutter/assets/answer.wav';
    Source sfxSource;

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final base64String = base64Encode(bytes);
      final dataUri = 'data:audio/wav;base64,$base64String';
      sfxSource = UrlSource(dataUri);
      debugPrint("SFX: Loaded $assetPath (${bytes.length} bytes) via Data URI");
    } catch (e) {
      debugPrint("SFX: Failed to load $assetPath from bundle: $e");
      // Fallback to AssetSource if bundle load fails (though unlikely if file exists)
      sfxSource = AssetSource(assetPath);
    }

    _rebuildSfxEventTimes();

    for (int i = 0; i < _sfxPoolSize; i++) {
      final player = AudioPlayer();
      // Set logs to verify errors
      // player.setLogHandler((msg) => debugPrint("SFX Player Log: $msg"));

      try {
        await player.setSource(sfxSource);
        await player.setReleaseMode(ReleaseMode.stop);
        // PlayerMode.lowLatency is Android only, but harmless to set if supported?
        // Actually it's a constructor param or setPlayerMode method.
        // In 6.x, setPlayerMode is async.
        await player.setPlayerMode(PlayerMode.lowLatency);
      } catch (e) {
        debugPrint("SFX: Error initializing player $i: $e");
      }
      _sfxPool.add(player);
    }

    if (audioSource != null) {
      try {
        await _audioPlayer.setSource(audioSource!);
        await _audioPlayer.setVolume(musicVolume);
        await _audioPlayer.setPlaybackRate(playbackRate);
        // Ensure state consistency if source set after isPlaying
        if (isPlaying) {
          await _audioPlayer.resume();
        }
      } catch (e) {
        debugPrint("Error loading audio source: $e");
      }
    }

    add(
      ChartStatusTextComponent(
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    isResourcesLoaded = true;
  }

  @override
  void onRemove() {
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    for (var player in _sfxPool) {
      player.dispose();
    }
    super.onRemove();
  }

  void setPlaying(bool playing) {
    if (isPlaying == playing) return;
    isPlaying = playing;
    if (playing) {
      final ms = ((chartTime - _effectiveHitSoundOffsetSeconds) * 1000).round();
      _lastSfxCheckTimeMs = ms;
      _sfxEventIndex = _lowerBound(_sfxEventTimesMs, ms);
      if (audioSource != null) {
        _audioPlayer.resume().catchError((e) {
          debugPrint("Audio resume failed: $e");
        });
      }
      // Reset timestamp to avoid large jump before first position update
      _audioBaseTimestampMs = DateTime.now().millisecondsSinceEpoch;
      final double audioPos = max(0.0, chartTime - offset);
      _audioBaseTimeMs = (audioPos * 1000).toInt();
    } else {
      if (audioSource != null) {
        _audioPlayer.pause();
      }
    }
  }

  Future<void> setPlaybackRate(double rate) async {
    final safe = rate.isFinite ? rate : 1.0;
    final clamped = safe.clamp(0.1, 1.0).toDouble();
    if (playbackRate == clamped) return;
    playbackRate = clamped;
    try {
      await _audioPlayer.setPlaybackRate(clamped);
    } catch (e) {
      debugPrint("Audio setPlaybackRate failed: $e");
    }
  }

  Future<void> setMusicVolume(double volume) async {
    final safe = volume.isFinite ? volume : 0.8;
    final clamped = safe.clamp(0.0, 1.0).toDouble();
    if (musicVolume == clamped) return;
    musicVolume = clamped;
    try {
      await _audioPlayer.setVolume(clamped);
    } catch (e) {
      debugPrint("Audio setVolume failed: $e");
    }
  }

  void setBackgroundMode(SimaiBackgroundMode mode) {
    if (backgroundMode == mode) return;
    backgroundMode = mode;
    _chartComponent.requestBackgroundRedraw();
  }

  void setMirrorMode(SimaiMirrorMode mode) {
    if (mirrorMode == mode) return;
    mirrorMode = mode;
    _chartComponent.clearSlideCaches();
    _chartComponent.requestBackgroundRedraw();
  }

  void setAudioSource(Source? source) {
    if (audioSource == source) return;
    audioSource = source;
    if (source != null) {
      _audioPlayer
          .setSource(source)
          .then((_) {
            _audioPlayer.setVolume(musicVolume);
            _audioPlayer.setPlaybackRate(playbackRate);
            if (isPlaying) {
              _audioPlayer.resume();
            }
          })
          .catchError((e) {
            debugPrint("Error setting audio source: $e");
          });
    } else {
      _audioPlayer.stop();
    }
  }

  Future<void> seek(double time, {bool syncAudio = true}) async {
    // Calculate target audio position
    double audioPos = time - offset;

    // Clamp to valid range
    if (audioPos < 0) audioPos = 0;

    chartTime = time;
    _pendingSeekReset = true;
    _debugSeekCalls++;
    _debugLastSeekReason = 'seek(syncAudio=$syncAudio)';
    final ms = ((chartTime - _effectiveHitSoundOffsetSeconds) * 1000).round();
    _lastSfxCheckTimeMs = ms;
    _sfxEventIndex = _upperBound(_sfxEventTimesMs, ms);

    if (syncAudio && audioSource != null) {
      final bool wasPlaying = isPlaying;
      try {
        if (wasPlaying) {
          await _audioPlayer.pause();
        }
        await _audioPlayer.seek(
          Duration(milliseconds: (audioPos * 1000).toInt()),
        );

        // Update base time immediately for sync
        _audioBaseTimeMs = (audioPos * 1000).toInt();
        if (wasPlaying) {
          _audioBaseTimestampMs = DateTime.now().millisecondsSinceEpoch;
          await _audioPlayer.resume();
        } else {
          _audioBaseTimestampMs = 0; // Invalidate timestamp
        }
      } catch (e) {
        debugPrint("Seek failed: $e");
      }
    } else {
      // If no audio, just reset base time for dt accumulation if needed
      // But wait, if using dt accumulation, we don't use _audioBaseTimestampMs in the same way?
      // Let's ensure update() handles this.
    }
  }

  double get totalDuration {
    if (chart.finishTiming != null) return chart.finishTiming!;

    if (chart.noteCollections.isEmpty) return 0.0;

    // Calculate from last note
    var lastCollection = chart.noteCollections.last;
    double maxTime = lastCollection.time;

    // Check duration of notes in last collection
    for (var note in lastCollection) {
      double end = lastCollection.time + (note.length ?? 0);
      if (note.type == NoteType.slide) {
        for (var slide in note.slidePaths) {
          if (lastCollection.time + slide.delay + slide.duration > end) {
            end = lastCollection.time + slide.delay + slide.duration;
          }
        }
      }
      if (end > maxTime) maxTime = end;
    }
    return maxTime;
  }

  void setBackgroundImageProvider(ImageProvider? provider) {
    if (backgroundImageProvider == provider) return;
    backgroundImageProvider = provider;
    // Check if _chartComponent is initialized before using it.
    // It might be accessed before onLoad completes if setState happens early.
    try {
      _chartComponent.setBackgroundImageProvider(provider);
    } catch (e) {
      // Ignore if not initialized yet.
      // It will be rendered in onGameResize or render loop once initialized.
    }
  }

  double renderTime = 0.0;

  bool consumeSeekReset() {
    final v = _pendingSeekReset;
    _pendingSeekReset = false;
    if (v) _debugSeekResetsConsumed++;
    return v;
  }

  @override
  void update(double dt) {
    renderTime += dt;
    if (isPlaying) {
      // Update chartTime first so components update against current time.
      int nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_audioBaseTimestampMs > 0) {
        double currentAudioTimeMs =
            _audioBaseTimeMs +
            (nowMs - _audioBaseTimestampMs) * playbackRate +
            offset * 1000;
        final double nextChartTime = currentAudioTimeMs / 1000.0;

        // More aggressive correction during playback to keep sync
        final double predicted = chartTime + dt * playbackRate;
        final double error = nextChartTime - predicted;

        // If error is large (e.g. > 100ms), snap directly
        if (error.abs() > 0.1) {
          chartTime = nextChartTime;
        } else {
          // Normal smooth correction
          final double maxCorrection = dt * 0.8 * playbackRate;
          final double correction = error.clamp(-maxCorrection, maxCorrection);
          chartTime = predicted + correction;
        }

        final double absError = error.abs();
        if (absError > _debugMaxAbsAudioError) {
          _debugMaxAbsAudioError = absError;
        }
      } else {
        // Fallback or initial state if no audio position received yet
        // Maybe just accumulate dt as before, or do nothing?
        // If we want to support offset even before audio starts:
        chartTime += dt * playbackRate;
      }

      // Only update logic when playing
      super.update(dt);
      _updateSfx();

      if (kDebugMode && renderTime >= _debugNextLogTime) {
        debugPrint(
          'SimaiGame dbg: t=${chartTime.toStringAsFixed(3)} dt=${dt.toStringAsFixed(4)} '
          'seekCalls=$_debugSeekCalls seekResets=$_debugSeekResetsConsumed '
          'resizes=$_debugResizeCalls '
          'notes(+$_debugNotesAdded -$_debugNotesRemoved) '
          'audioUpdates=$_debugAudioUpdates audioJumps=$_debugAudioPosJumps '
          'maxErr=${_debugMaxAbsAudioError.toStringAsFixed(4)} '
          'maxCorr=${_debugMaxAbsCorrection.toStringAsFixed(4)} '
          'lastSeek=$_debugLastSeekReason',
        );
        _debugNextLogTime = renderTime + 1.0;
        _debugNotesAdded = 0;
        _debugNotesRemoved = 0;
        _debugAudioUpdates = 0;
        _debugAudioPosJumps = 0;
        _debugResizeCalls = 0;
        _debugMaxAbsAudioError = 0.0;
        _debugMaxAbsCorrection = 0.0;
      }
    } else {
      // Keep engine running (lifecycle events), but freeze time
      // Use a small non-zero dt to avoid division by zero in FpsComponent
      super.update(0.0001);
    }
  }

  void _updateSfx() {
    final ms = ((chartTime - _effectiveHitSoundOffsetSeconds) * 1000).round();
    if (ms < _lastSfxCheckTimeMs) {
      _sfxEventIndex = _upperBound(_sfxEventTimesMs, ms);
    }

    while (_sfxEventIndex < _sfxEventTimesMs.length &&
        _sfxEventTimesMs[_sfxEventIndex] <= ms) {
      if (hitSoundEnabled) _playDaSound();
      _sfxEventIndex++;
    }
    _lastSfxCheckTimeMs = ms;
  }

  void _playDaSound() {
    if (_sfxPool.isEmpty) return;

    final player = _sfxPool[_sfxPoolIndex];

    // Force restart playback
    // If playing, seek to start. If stopped, resume.
    player
        .seek(Duration.zero)
        .then((_) {
          player.resume();
        })
        .catchError((e) {
          debugPrint("SFX: Play failed: $e");
        });

    _sfxPoolIndex = (_sfxPoolIndex + 1) % _sfxPoolSize;
  }

  void _rebuildSfxEventTimes() {
    final set = <int>{};
    for (final collection in chart.noteCollections) {
      set.add((collection.time * 1000).round());
      for (final note in collection) {
        if (note.type == NoteType.hold) {
          final len = note.length ?? 0.0;
          if (len > 0) {
            set.add(((collection.time + len) * 1000).round());
          }
        }
      }
    }
    final list = set.toList()..sort();
    _sfxEventTimesMs = list;
    _sfxEventIndex = 0;
    _lastSfxCheckTimeMs = ((chartTime - _effectiveHitSoundOffsetSeconds) * 1000)
        .round();
  }

  static int _lowerBound(List<int> a, int x) {
    int lo = 0;
    int hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int _upperBound(List<int> a, int x) {
    int lo = 0;
    int hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

class ChartComponent extends PositionComponent {
  final SimaiGame game;

  ui.Picture? _backgroundPicture;
  ui.Image? _backgroundImage;
  ImageStream? _backgroundStream;
  ImageStreamListener? _backgroundStreamListener;
  ui.Image? _sensorImage;
  ImageStream? _sensorStream;
  ImageStreamListener? _sensorStreamListener;
  int _visibleStartIndex = 0;
  Vector2? _lastSize;
  final Map<(Note, SlidePath), Path> _slidePathCache = {};
  final Map<(Note, SlidePath), double> _slideLengthCache = {};
  // Cache slide start counts per collection index
  final Map<int, Map<double, int>> _slideStartCountsCache = {};
  final Map<Note, NoteComponent> _noteComponents = {};

  ChartComponent({required this.game, this.backgroundImageProvider});

  ImageProvider? backgroundImageProvider;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_lastSize != null && (_lastSize! - size).length < 0.5) {
      return;
    }
    _lastSize = size.clone();
    this.size = size;
    game._debugResizeCalls++;
    _renderBackground();
    _resolveBackgroundImage(force: true);
    _resolveSensorImage(force: true);
    _slidePathCache.clear();
    _slideLengthCache.clear();
    _slideStartCountsCache.clear();
  }

  @override
  void onRemove() {
    _stopListeningBackgroundStream();
    _stopListeningSensorStream();
    super.onRemove();
  }

  void setBackgroundImageProvider(ImageProvider? provider) {
    if (backgroundImageProvider == provider) return;
    backgroundImageProvider = provider;
    _resolveBackgroundImage(force: true);
  }

  void _stopListeningBackgroundStream() {
    final listener = _backgroundStreamListener;
    final stream = _backgroundStream;
    if (listener != null && stream != null) {
      stream.removeListener(listener);
    }
    _backgroundStreamListener = null;
    _backgroundStream = null;
  }

  void _stopListeningSensorStream() {
    final listener = _sensorStreamListener;
    final stream = _sensorStream;
    if (listener != null && stream != null) {
      stream.removeListener(listener);
    }
    _sensorStreamListener = null;
    _sensorStream = null;
  }

  void _resolveSensorImage({required bool force}) {
    if (!force && _sensorImage != null) return;

    _stopListeningSensorStream();
    _sensorImage = null;

    const provider = AssetImage('assets/sensor.webp', package: 'simai_flutter');

    final double devicePixelRatio =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final config = ImageConfiguration(
      size: Size(size.x, size.y),
      devicePixelRatio: devicePixelRatio,
    );

    final stream = provider.resolve(config);
    _sensorStream = stream;
    _sensorStreamListener = ImageStreamListener(
      (info, _) {
        _sensorImage = info.image;
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Sensor image resolve failed: $error');
        }
      },
    );
    stream.addListener(_sensorStreamListener!);
  }

  void _resolveBackgroundImage({required bool force}) {
    final provider = backgroundImageProvider;
    if (!force && provider == null) return;

    _stopListeningBackgroundStream();
    _backgroundImage = null;
    if (provider == null) return;

    final double devicePixelRatio =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final config = ImageConfiguration(
      size: Size(size.x, size.y),
      devicePixelRatio: devicePixelRatio,
    );

    final stream = provider.resolve(config);
    _backgroundStream = stream;
    _backgroundStreamListener = ImageStreamListener(
      (info, _) {
        _backgroundImage = info.image;
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Background image resolve failed: $error');
        }
      },
    );
    stream.addListener(_backgroundStreamListener!);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _syncNoteComponents();
  }

  void _renderBackground() {
    final center = Offset(size.x / 2, size.y / 2);
    final radius = min(size.x, size.y) / 2 * 0.85;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final mode = game.backgroundMode;

    if (mode != SimaiBackgroundMode.none) {
      final bool drawRing = mode != SimaiBackgroundMode.dots;
      _drawJudgeLine(canvas, center, radius, drawRing: drawRing);
    }

    _backgroundPicture = recorder.endRecording();
  }

  void clearSlideCaches() {
    _slidePathCache.clear();
    _slideLengthCache.clear();
  }

  void requestBackgroundRedraw() {
    _renderBackground();
  }

  @override
  void render(Canvas canvas) {
    final bgImage = _backgroundImage;
    final sensorImage = _sensorImage;

    if (bgImage != null || sensorImage != null) {
      final center = Offset(size.x / 2, size.y / 2);
      final radius = min(size.x, size.y) / 2 * 0.85;
      final bgRadius = radius * 1.05;
      final rect = Rect.fromCircle(center: center, radius: bgRadius);

      canvas.save();
      canvas.clipPath(Path()..addOval(rect));

      if (bgImage != null) {
        paintImage(
          canvas: canvas,
          rect: rect,
          image: bgImage,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          colorFilter: const ColorFilter.matrix(<double>[
            0.15,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.15,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.15,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
          ]),
        );
      }

      if (sensorImage != null &&
          game.backgroundMode == SimaiBackgroundMode.judgeZone) {
        paintImage(
          canvas: canvas,
          rect: rect,
          image: sensorImage,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          colorFilter: const ColorFilter.matrix(<double>[
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            1,
            1,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
        );
      }

      canvas.restore();
    }

    if (_backgroundPicture != null) {
      canvas.drawPicture(_backgroundPicture!);
    }
  }

  void _resetVisibleNotes() {
    _visibleStartIndex = 0;
    game._debugNotesRemoved += _noteComponents.length;
    for (final component in _noteComponents.values) {
      component.removeFromParent();
    }
    _noteComponents.clear();
    _slidePathCache.clear();
    _slideLengthCache.clear();
    _slideStartCountsCache.clear();
  }

  void _syncNoteComponents() {
    if (!game.isResourcesLoaded) return;

    if (game.consumeSeekReset()) {
      if (kDebugMode) {
        debugPrint(
          'ChartComponent dbg: resetVisibleNotes t=${game.chartTime.toStringAsFixed(3)} reason=${game._debugLastSeekReason}',
        );
      }
      _resetVisibleNotes();
    }

    while (_visibleStartIndex < game.chart.noteCollections.length) {
      var collection = game.chart.noteCollections[_visibleStartIndex];

      double maxDuration = 0;
      for (var note in collection) {
        double d = note.length ?? 0;
        if (note.type == NoteType.slide) {
          for (var slide in note.slidePaths) {
            double slideEnd = slide.delay + slide.duration;
            if (slideEnd > d) d = slideEnd;
          }
        }
        if (d > maxDuration) maxDuration = d;
      }

      double endTime = collection.time + maxDuration;
      if (endTime < game.chartTime - 0.5) {
        _slideStartCountsCache.remove(_visibleStartIndex);
        for (var note in collection) {
          for (final slidePath in note.slidePaths) {
            _slidePathCache.remove((note, slidePath));
            _slideLengthCache.remove((note, slidePath));
          }
          final removed = _noteComponents.remove(note);
          if (removed != null) {
            game._debugNotesRemoved++;
            removed.removeFromParent();
          }
        }
        _visibleStartIndex++;
      } else {
        break;
      }
    }

    double maxApproachTime = max(game.ringApproachTime, game.touchApproachTime);
    for (
      int i = _visibleStartIndex;
      i < game.chart.noteCollections.length;
      i++
    ) {
      var collection = game.chart.noteCollections[i];
      if (collection.time > game.chartTime + maxApproachTime) break;

      if (!_slideStartCountsCache.containsKey(i)) {
        Map<double, int> counts = {};
        for (var note in collection) {
          if (note.type == NoteType.slide) {
            for (var slide in note.slidePaths) {
              double startTime = collection.time + slide.delay;
              double key = (startTime * 1000).round() / 1000.0;
              counts[key] = (counts[key] ?? 0) + 1;
            }
          }
        }
        _slideStartCountsCache[i] = counts;
      }
      Map<double, int> slideStartCounts = _slideStartCountsCache[i]!;

      bool isEach =
          collection.length > 1 || collection.eachStyle == EachStyle.forEach;
      if (collection.eachStyle == EachStyle.forceBroken) isEach = false;

      int noteIndex = 0;
      for (var note in collection) {
        if (_noteComponents.containsKey(note)) {
          noteIndex++;
          continue;
        }

        final component = NoteComponent(
          note: note,
          noteTime: collection.time,
          isEach: isEach,
          slideStartCounts: slideStartCounts,
          slidePathCache: _slidePathCache,
          slideLengthCache: _slideLengthCache,
          priority: i * 1000 + noteIndex,
        );
        _noteComponents[note] = component;
        game._debugNotesAdded++;
        add(component);
        noteIndex++;
      }
    }
  }

  void _drawJudgeLine(
    Canvas canvas,
    Offset center,
    double radius, {
    bool drawRing = true,
  }) {
    final double scale = radius / 300.0;

    if (drawRing) {
      final paint = Paint()
        ..color = SimaiColors.judgeLine.withAlpha(100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 * scale;
      canvas.drawCircle(center, radius, paint);
    }

    final dotPaint = Paint()
      ..color = SimaiColors.judgeLine
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 8; i++) {
      double angle = (-67.5 + i * 45) * pi / 180;
      double dx = center.dx + radius * cos(angle);
      double dy = center.dy + radius * sin(angle);
      canvas.drawCircle(Offset(dx, dy), 8.0 * scale, dotPaint);
    }
  }
}
