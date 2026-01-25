import '../structures/mai_chart.dart';
import '../internal/syntactic_analysis/timing_change.dart';

class ChartTimingMapper {
  static TimingChange timingAtTime(MaiChart chart, double time) {
    final changes = chart.timingChanges;
    if (changes.isEmpty) {
      return TimingChange(time: 0.0, tempo: 120.0, subdivisions: 4.0);
    }
    TimingChange current = changes.first;
    for (final c in changes) {
      if (c.time <= time) current = c;
    }
    final tempo = current.tempo > 0 ? current.tempo : 120.0;
    final subdivisions = current.subdivisions > 0 ? current.subdivisions : 4.0;
    return TimingChange(time: current.time, tempo: tempo, subdivisions: subdivisions);
  }

  static double beatsAtTime(MaiChart chart, double time) {
    final t = time.isFinite ? time : 0.0;
    if (t <= 0) return 0.0;
    final normalized = _normalizedTimingChanges(chart);
    double beats = 0.0;
    for (int i = 0; i < normalized.length; i++) {
      final current = normalized[i];
      final double segStart = current.time;
      final double segEnd =
          (i + 1 < normalized.length) ? normalized[i + 1].time : double.infinity;
      if (t <= segStart) break;
      final double end = segEnd < t ? segEnd : t;
      final double tempo = current.tempo > 0 ? current.tempo : 120.0;
      final double beatSeconds = 60.0 / tempo;
      beats += (end - segStart) / beatSeconds;
      if (end >= t) break;
    }
    return beats;
  }

  static double timeAtBeats(MaiChart chart, double beats) {
    final b = beats.isFinite ? beats : 0.0;
    if (b <= 0) return 0.0;
    final normalized = _normalizedTimingChanges(chart);
    double remaining = b;
    for (int i = 0; i < normalized.length; i++) {
      final current = normalized[i];
      final double segStart = current.time;
      final double segEnd =
          (i + 1 < normalized.length) ? normalized[i + 1].time : double.infinity;
      final double tempo = current.tempo > 0 ? current.tempo : 120.0;
      final double beatSeconds = 60.0 / tempo;
      if (!segEnd.isFinite) {
        return segStart + remaining * beatSeconds;
      }
      final double segSeconds = (segEnd - segStart).clamp(0.0, double.infinity);
      final double segBeats = segSeconds / beatSeconds;
      if (remaining <= segBeats + 1e-9) {
        return segStart + remaining * beatSeconds;
      }
      remaining -= segBeats;
    }
    final last = normalized.isNotEmpty
        ? normalized.last
        : TimingChange(time: 0.0, tempo: 120.0, subdivisions: 4.0);
    final tempo = last.tempo > 0 ? last.tempo : 120.0;
    return last.time + remaining * (60.0 / tempo);
  }

  static List<TimingChange> _normalizedTimingChanges(MaiChart chart) {
    final changes = chart.timingChanges;
    final normalized = <TimingChange>[];
    if (changes.isNotEmpty) {
      normalized.addAll(changes.map((c) => c.clone()));
      normalized.sort((a, b) => a.time.compareTo(b.time));
    }
    final fallback = normalized.isNotEmpty ? normalized.first : TimingChange();
    final defaultTempo = fallback.tempo > 0 ? fallback.tempo : 120.0;
    if (normalized.isEmpty || normalized.first.time > 0.0) {
      normalized.insert(
        0,
        TimingChange(time: 0.0, tempo: defaultTempo, subdivisions: 4.0),
      );
    } else if (normalized.first.time < 0.0) {
      normalized.first.time = 0.0;
    }
    return normalized;
  }
}

