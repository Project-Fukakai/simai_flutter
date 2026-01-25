import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../simai_flutter.dart';
import '../painters/note_painter.dart';
import '../simai_game.dart';

class NoteComponent extends Component with HasGameReference<SimaiGame> {
  final Note note;
  final double noteTime;
  final bool isEach;
  final Map<double, int>? slideStartCounts;
  final Map<(Note, SlidePath), Path> slidePathCache;
  final Map<(Note, SlidePath), double> slideLengthCache;

  NoteComponent({
    required this.note,
    required this.noteTime,
    required this.isEach,
    required this.slideStartCounts,
    required this.slidePathCache,
    required this.slideLengthCache,
    super.priority,
  });

  @override
  void render(Canvas canvas) {
    if (!game.isResourcesLoaded) return;

    final center = Offset(game.size.x / 2, game.size.y / 2);
    final radius = min(game.size.x, game.size.y) / 2 * 0.85;

    final double approachTime = (note.location.group != NoteGroup.tap)
        ? game.touchApproachTime
        : game.ringApproachTime;

    final double progress = 1.0 - (noteTime - game.chartTime) / approachTime;

    canvas.save();
    NotePainter.paint(
      canvas,
      center,
      radius,
      note,
      progress,
      isEach,
      game.chartTime,
      game.renderTime,
      noteTime,
      approachTime,
      mirrorMode: game.mirrorMode,
      rotateSlideStar: game.rotateSlideStar,
      pinkSlideStar: game.pinkSlideStar,
      standardBreakSlide: game.standardBreakSlide,
      highlightExNotes: game.highlightExNotes,
      slidePathCache: slidePathCache,
      slideLengthCache: slideLengthCache,
      slideStartCounts: slideStartCounts,
    );
    canvas.restore();
  }
}
