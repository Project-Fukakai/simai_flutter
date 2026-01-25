import 'package:flame/components.dart';
import '../simai_game.dart';
import '../chart_timing_mapper.dart';

class ChartStatusTextComponent extends TextComponent
    with HasGameReference<SimaiGame> {
  ChartStatusTextComponent({super.position, super.textRenderer})
    : super(anchor: Anchor.topLeft);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Position at top-left with minimal padding to stay clear of the circle
    position = Vector2(8, 8);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final double t = game.chartTime;
    final timing = ChartTimingMapper.timingAtTime(game.chart, t);
    final double bpm = timing.tempo;
    final double subdivisions = timing.subdivisions;
    final int denom = subdivisions.round().clamp(1, 1024);
    final measure = _measureNumberAt(t);
    final progress = _quarterProgressCodeAt(t);
    text = 'BPM ${bpm.toStringAsFixed(1)}  M$measure  $progress  [1/$denom]';
  }

  double _beatsAt(double time) {
    return ChartTimingMapper.beatsAtTime(game.chart, time);
  }

  int _measureNumberAt(double time) {
    final beats = _beatsAt(time);
    final int measureIndex = (beats / 4.0).floor();
    return measureIndex + 1;
  }

  String _quarterProgressCodeAt(double time) {
    final beats = _beatsAt(time);
    final double beatInMeasure = (beats - (beats / 4.0).floorToDouble() * 4.0)
        .clamp(0.0, 3.999999);
    final int beatIndex = beatInMeasure.floor().clamp(0, 3) + 1;
    final double local = beatInMeasure - (beatIndex - 1);
    final int pct = (local * 100).floor().clamp(0, 99);
    return '$beatIndex.${pct.toString().padLeft(2, '0')}';
  }
}
