import 'package:flutter/material.dart';
import '../../simai_flutter.dart';
import 'chart_timing_mapper.dart';
import 'simai_colors.dart';

class SimaiPlayerControls extends StatefulWidget {
  final SimaiPlayerController controller;

  const SimaiPlayerControls({super.key, required this.controller});

  @override
  State<SimaiPlayerControls> createState() => _SimaiPlayerControlsState();
}

class _SimaiPlayerControlsState extends State<SimaiPlayerControls> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(SimaiPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SimaiTimeline(controller: controller, height: 96),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    tooltip: 'Previous Measure',
                    onPressed: controller.previousMeasure,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.navigate_before,
                      color: Colors.white,
                    ),
                    tooltip: 'Previous Note',
                    onPressed: controller.previousNote,
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(12),
                    ),
                    iconSize: 32,
                    icon: Icon(
                      controller.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: controller.togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigate_next, color: Colors.white),
                    tooltip: 'Next Note',
                    onPressed: controller.nextNote,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    tooltip: 'Next Measure',
                    onPressed: controller.nextMeasure,
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay, color: Colors.white),
                    tooltip: 'Replay Measure',
                    onPressed: controller.replayMeasure,
                  ),
                  IconButton(
                    icon: Icon(
                      controller.isFullScreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                    ),
                    tooltip: controller.isFullScreen
                        ? 'Exit Full Screen'
                        : 'Full Screen',
                    onPressed: () {
                      if (controller.onToggleFullScreen != null) {
                        controller.onToggleFullScreen!();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TimelineCategory { tap, touch, each, slide, breakNote }

class _NoteEvent {
  final double time;
  final _TimelineCategory category;

  const _NoteEvent({required this.time, required this.category});
}

class _TimelineData {
  final double totalDuration;
  final List<_NoteEvent> events;
  final List<double> measureStartTimes;

  const _TimelineData({
    required this.totalDuration,
    required this.events,
    required this.measureStartTimes,
  });
}

class _SimaiTimeline extends StatefulWidget {
  final SimaiPlayerController controller;
  final double height;

  const _SimaiTimeline({required this.controller, required this.height});

  @override
  State<_SimaiTimeline> createState() => _SimaiTimelineState();
}

class _SimaiTimelineState extends State<_SimaiTimeline> {
  bool _isDragging = false;
  bool _wasPlayingBeforeDrag = false;
  double _dragTime = 0.0;

  _TimelineData? _data;
  double _lastWidth = 0.0;
  int _lastBinCount = 0;
  List<int> _tapBins = const [];
  List<int> _touchBins = const [];
  List<int> _eachBins = const [];
  List<int> _slideBins = const [];
  List<int> _breakBins = const [];
  int _maxBinSum = 1;

  @override
  void initState() {
    super.initState();
    _rebuildData();
    _dragTime = widget.controller.chartTime;
  }

  @override
  void didUpdateWidget(_SimaiTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _isDragging = false;
      _wasPlayingBeforeDrag = false;
      _lastWidth = 0.0;
      _lastBinCount = 0;
      _rebuildData();
      _dragTime = widget.controller.chartTime;
    }
  }

  void _rebuildData() {
    final controller = widget.controller;
    final total = controller.chartInfo.totalDuration > 0
        ? controller.chartInfo.totalDuration
        : 0.0;
    final events = <_NoteEvent>[];
    for (final collection in controller.chart.noteCollections) {
      final collectionTime = collection.time;
      for (final note in collection) {
        final category = _categorize(collection, note);
        events.add(_NoteEvent(time: collectionTime, category: category));
      }
    }
    final measureStartTimes = _computeMeasureStartTimes(
      controller.chart,
      total > 0 ? total : _inferTotalFromEvents(events),
    );
    _data = _TimelineData(
      totalDuration: total > 0 ? total : _inferTotalFromEvents(events),
      events: events,
      measureStartTimes: measureStartTimes,
    );
  }

  static double _inferTotalFromEvents(List<_NoteEvent> events) {
    double maxT = 0.0;
    for (final e in events) {
      if (e.time > maxT) maxT = e.time;
    }
    return maxT <= 0 ? 1.0 : maxT;
  }

  static _TimelineCategory _categorize(NoteCollection collection, Note note) {
    final isBreak =
        note.type == NoteType.breakNote ||
        (note.styles & NoteStyles.breakHead) != 0;
    if (isBreak) return _TimelineCategory.breakNote;
    final isEach =
        collection.eachStyle != EachStyle.forceBroken &&
        (collection.eachStyle == EachStyle.forEach || collection.length > 1);
    if (isEach) {
      return _TimelineCategory.each;
    }
    final isSlide = note.type == NoteType.slide || note.slidePaths.isNotEmpty;
    if (isSlide) return _TimelineCategory.slide;
    if (note.type == NoteType.touch) return _TimelineCategory.touch;
    return _TimelineCategory.tap;
  }

  static List<double> _computeMeasureStartTimes(MaiChart chart, double total) {
    final starts = <double>[];
    const epsilon = 1e-6;

    void addStart(double t) {
      final clamped = t.clamp(0.0, total).toDouble();
      if (starts.isEmpty) {
        starts.add(clamped);
        return;
      }
      if ((clamped - starts.last).abs() <= 1e-4) return;
      if (clamped < starts.last - 1e-4) return;
      starts.add(clamped);
    }

    final totalSeconds = total.isFinite && total > 0 ? total : 0.0;
    final totalBeats = ChartTimingMapper.beatsAtTime(chart, totalSeconds);
    addStart(0.0);
    for (double b = 4.0; b <= totalBeats + epsilon; b += 4.0) {
      final t = ChartTimingMapper.timeAtBeats(chart, b);
      if (t > totalSeconds + epsilon) break;
      addStart(t);
    }
    return starts;
  }

  void _ensureBinsForWidth(double width) {
    final data = _data;
    if (data == null) return;
    if (width <= 0) return;
    final binCount = (width / 3.0).floor().clamp(24, 600);
    final widthChanged = (width - _lastWidth).abs() >= 1.0;
    if (!widthChanged && binCount == _lastBinCount) return;
    _lastWidth = width;
    _lastBinCount = binCount;

    _tapBins = List<int>.filled(binCount, 0);
    _touchBins = List<int>.filled(binCount, 0);
    _eachBins = List<int>.filled(binCount, 0);
    _slideBins = List<int>.filled(binCount, 0);
    _breakBins = List<int>.filled(binCount, 0);

    final total = data.totalDuration > 0 ? data.totalDuration : 1.0;
    for (final e in data.events) {
      final ratio = (e.time / total).clamp(0.0, 1.0);
      final idx = (ratio * binCount).floor().clamp(0, binCount - 1);
      switch (e.category) {
        case _TimelineCategory.tap:
          _tapBins[idx] += 1;
          break;
        case _TimelineCategory.touch:
          _touchBins[idx] += 1;
          break;
        case _TimelineCategory.each:
          _eachBins[idx] += 1;
          break;
        case _TimelineCategory.slide:
          _slideBins[idx] += 1;
          break;
        case _TimelineCategory.breakNote:
          _breakBins[idx] += 1;
          break;
      }
    }

    int maxSum = 1;
    for (int i = 0; i < binCount; i++) {
      final sum =
          _tapBins[i] +
          _touchBins[i] +
          _eachBins[i] +
          _slideBins[i] +
          _breakBins[i];
      if (sum > maxSum) maxSum = sum;
    }
    _maxBinSum = maxSum;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureBinsForWidth(constraints.maxWidth);
        final data = _data;
        final controller = widget.controller;
        final total =
            data?.totalDuration ??
            (controller.chartInfo.totalDuration > 0
                ? controller.chartInfo.totalDuration
                : 1.0);
        final time = (_isDragging ? _dragTime : controller.chartTime)
            .clamp(0.0, total)
            .toDouble();

        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.globalPosition);
              final t = (local.dx / box.size.width * total)
                  .clamp(0.0, total)
                  .toDouble();
              controller.seek(t, syncAudio: true);
            },
            onHorizontalDragStart: (details) {
              _isDragging = true;
              _wasPlayingBeforeDrag = controller.isPlaying;
              _dragTime = controller.chartTime;
              if (_wasPlayingBeforeDrag) controller.pause();
              setState(() {});
            },
            onHorizontalDragUpdate: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.globalPosition);
              final t = (local.dx / box.size.width * total)
                  .clamp(0.0, total)
                  .toDouble();
              setState(() {
                _dragTime = t;
              });
              controller.seek(t, syncAudio: false);
            },
            onHorizontalDragEnd: (_) async {
              final t = _dragTime.clamp(0.0, total).toDouble();
              _isDragging = false;
              await controller.seek(t, syncAudio: true);
              if (_wasPlayingBeforeDrag) controller.play();
              if (mounted) setState(() {});
            },
            child: CustomPaint(
              painter: _SimaiTimelinePainter(
                totalDuration: total,
                currentTime: time,
                measureStartTimes: data?.measureStartTimes ?? const [],
                tapBins: _tapBins,
                touchBins: _touchBins,
                eachBins: _eachBins,
                slideBins: _slideBins,
                breakBins: _breakBins,
                maxBinSum: _maxBinSum,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SimaiTimelinePainter extends CustomPainter {
  final double totalDuration;
  final double currentTime;
  final List<double> measureStartTimes;
  final List<int> tapBins;
  final List<int> touchBins;
  final List<int> eachBins;
  final List<int> slideBins;
  final List<int> breakBins;
  final int maxBinSum;

  const _SimaiTimelinePainter({
    required this.totalDuration,
    required this.currentTime,
    required this.measureStartTimes,
    required this.tapBins,
    required this.touchBins,
    required this.eachBins,
    required this.slideBins,
    required this.breakBins,
    required this.maxBinSum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final total = totalDuration > 0 ? totalDuration : 1.0;
    final clampedTime = currentTime.clamp(0.0, total).toDouble();

    const topLabelHeight = 18.0;
    const bottomLabelHeight = 24.0;
    final barRect = Rect.fromLTWH(
      0,
      topLabelHeight,
      w,
      h - topLabelHeight - bottomLabelHeight,
    );

    final bgPaint = Paint()..color = Colors.transparent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(8),
      ),
      bgPaint,
    );

    _paintTimeScale(canvas, size, total, topLabelHeight);
    _paintBars(canvas, barRect, total);
    _paintMeasureTicks(canvas, size, total, barRect.bottom, bottomLabelHeight);
    _paintPlayhead(canvas, size, total, clampedTime);
  }

  void _paintTimeScale(
    Canvas canvas,
    Size size,
    double total,
    double topLabelHeight,
  ) {
    final w = size.width;
    final tickPaint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1.0;

    final labelStyle = const TextStyle(
      color: Colors.white,
      fontSize: 10,
      height: 1.0,
    );

    final step = 30.0;
    for (double t = 0.0; t <= total + 1e-6; t += step) {
      final x = (t / total * w).clamp(0.0, w);
      canvas.drawLine(
        Offset(x, topLabelHeight - 4),
        Offset(x, topLabelHeight),
        tickPaint,
      );

      final tp = TextPainter(
        text: TextSpan(text: _formatTime(t), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(dx, 0));
    }
  }

  void _paintBars(Canvas canvas, Rect barRect, double total) {
    final binCount = tapBins.length;
    if (binCount == 0) return;
    final barWidth = barRect.width / binCount;
    final maxSum = maxBinSum <= 0 ? 1 : maxBinSum;

    final tapPaint = Paint()..color = SimaiColors.tapNormal;
    final touchPaint = Paint()..color = SimaiColors.touchNormal;
    final eachPaint = Paint()..color = SimaiColors.tapEach;
    final slidePaint = Paint()..color = SimaiColors.slideNormal;
    final breakPaint = Paint()..color = SimaiColors.tapBreak;

    final gridPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final gridLines = 3;
    for (int i = 1; i <= gridLines; i++) {
      final y = barRect.bottom - barRect.height * (i / (gridLines + 1));
      canvas.drawLine(
        Offset(barRect.left, y),
        Offset(barRect.right, y),
        gridPaint,
      );
    }

    for (int i = 0; i < binCount; i++) {
      final tap = tapBins[i];
      final touch = touchBins[i];
      final each = eachBins[i];
      final slide = slideBins[i];
      final brk = breakBins[i];
      final sum = tap + touch + each + slide + brk;
      if (sum <= 0) continue;

      final totalHeight = barRect.height * (sum / maxSum).clamp(0.0, 1.0);
      double y = barRect.bottom;

      void drawSegment(int count, Paint paint) {
        if (count <= 0) return;
        final segH = totalHeight * (count / sum);
        final rect = Rect.fromLTWH(
          barRect.left + i * barWidth,
          y - segH,
          barWidth,
          segH,
        );
        canvas.drawRect(rect, paint);
        y -= segH;
      }

      drawSegment(tap, tapPaint);
      drawSegment(touch, touchPaint);
      drawSegment(each, eachPaint);
      drawSegment(slide, slidePaint);
      drawSegment(brk, breakPaint);
    }
  }

  void _paintMeasureTicks(
    Canvas canvas,
    Size size,
    double total,
    double barBottomY,
    double bottomLabelHeight,
  ) {
    final w = size.width;
    final h = size.height;
    final minorTickPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.0;
    final majorTickPaint = Paint()
      ..color = Colors.lightBlue
      ..strokeWidth = 1.25;
    final majorLabelStyle = const TextStyle(
      color: Colors.lightBlue,
      fontSize: 10,
      height: 1.0,
      fontWeight: FontWeight.w600,
    );

    final measureCount = measureStartTimes.length;
    final pxPerMeasure = measureCount > 1 ? w / (measureCount - 1) : w;
    final minorStep = pxPerMeasure >= 10.0 ? 1 : 2;
    final majorStep = pxPerMeasure >= 7.0 ? 5 : 10;

    const barToTickGap = 4.0;
    const tickToLabelGap = 3.0;
    const minorTickH = 3.0;
    const majorTickH = 6.0;

    double? lastX;
    if (measureCount <= 1) return;
    for (int i = 0; i < measureCount; i++) {
      if (i % minorStep != 0) continue;
      final x = (i / (measureCount - 1) * w).clamp(0.0, w);
      if (lastX != null && (x - lastX).abs() < 0.75) continue;
      lastX = x;
      final isMajor = i % majorStep == 0;
      final tickH = isMajor ? majorTickH : minorTickH;
      final startY = (barBottomY + barToTickGap).clamp(0.0, h);
      final endY = (startY + tickH).clamp(0.0, h);
      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        isMajor ? majorTickPaint : minorTickPaint,
      );

      if (isMajor) {
        final label = '$i';
        final tp = TextPainter(
          text: TextSpan(text: label, style: majorLabelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final dx = (x - tp.width / 2).clamp(0.0, w - tp.width);
        final labelY = (endY + tickToLabelGap).clamp(
          0.0,
          (h - tp.height).clamp(0.0, h),
        );
        tp.paint(canvas, Offset(dx, labelY));
      }
    }
  }

  void _paintPlayhead(Canvas canvas, Size size, double total, double time) {
    final w = size.width;
    final h = size.height;
    final x = (time / total * w).clamp(0.0, w);
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);

    final measure = _measureIndexForTime(time);
    final label = '$measure';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black, fontSize: 10, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padding = 4.0;
    final boxW = tp.width + padding * 2;
    final boxH = tp.height + padding * 2;
    final dx = (x - boxW / 2).clamp(0.0, w - boxW);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(dx, 2, boxW, boxH),
      const Radius.circular(6),
    );
    final boxPaint = Paint()..color = Colors.white;
    canvas.drawRRect(rect, boxPaint);
    tp.paint(canvas, Offset(dx + padding, 2 + padding));
  }

  int _measureIndexForTime(double time) {
    if (measureStartTimes.isEmpty) return 0;
    int lo = 0;
    int hi = measureStartTimes.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = measureStartTimes[mid];
      if (v <= time) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi < 0 ? 0 : hi;
  }

  static String _formatTime(double seconds) {
    final s = seconds.isFinite ? seconds : 0.0;
    final totalSeconds = s.round().clamp(0, 999999);
    final m = totalSeconds ~/ 60;
    final r = totalSeconds % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _SimaiTimelinePainter oldDelegate) {
    return oldDelegate.currentTime != currentTime ||
        oldDelegate.totalDuration != totalDuration ||
        oldDelegate.maxBinSum != maxBinSum ||
        oldDelegate.tapBins != tapBins ||
        oldDelegate.touchBins != touchBins ||
        oldDelegate.eachBins != eachBins ||
        oldDelegate.slideBins != slideBins ||
        oldDelegate.breakBins != breakBins ||
        oldDelegate.measureStartTimes != measureStartTimes;
  }
}
