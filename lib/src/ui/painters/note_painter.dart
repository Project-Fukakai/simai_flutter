import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../simai_flutter.dart';
import '../simai_colors.dart';
import 'slide_path_generator.dart';

class NotePainter {
  static Location _mirrorLocation(Location location, SimaiMirrorMode mode) {
    if (mode == SimaiMirrorMode.none) return location;

    int index = location.index;
    NoteGroup group = location.group;

    if (group == NoteGroup.cSensor) {
      return location;
    }

    bool isShifted =
        (group == NoteGroup.tap ||
        group == NoteGroup.aSensor ||
        group == NoteGroup.bSensor);

    if (mode == SimaiMirrorMode.horizontal || mode == SimaiMirrorMode.full) {
      if (isShifted) {
        const hMap = {0: 7, 1: 6, 2: 5, 3: 4, 4: 3, 5: 2, 6: 1, 7: 0};
        index = hMap[index] ?? index;
      } else {
        const hMap = {0: 0, 1: 7, 2: 6, 3: 5, 4: 4, 5: 3, 6: 2, 7: 1};
        index = hMap[index] ?? index;
      }
    }

    if (mode == SimaiMirrorMode.vertical || mode == SimaiMirrorMode.full) {
      if (isShifted) {
        const vMap = {0: 3, 1: 2, 2: 1, 3: 0, 4: 7, 5: 6, 6: 5, 7: 4};
        index = vMap[index] ?? index;
      } else {
        const vMap = {0: 4, 1: 3, 2: 2, 3: 1, 4: 0, 5: 7, 6: 6, 7: 5};
        index = vMap[index] ?? index;
      }
    }

    return Location(index, group);
  }

  static SlideType _mirrorSlideType(SlideType type, SimaiMirrorMode mode) {
    if (mode == SimaiMirrorMode.none || mode == SimaiMirrorMode.full) {
      return type;
    }

    // Horizontal/Vertical mirror flips rotation sense
    switch (type) {
      case SlideType.ringCw:
        return SlideType.ringCcw;
      case SlideType.ringCcw:
        return SlideType.ringCw;
      case SlideType.curveCw:
        return SlideType.curveCcw;
      case SlideType.curveCcw:
        return SlideType.curveCw;
      case SlideType.edgeCurveCw:
        return SlideType.edgeCurveCcw;
      case SlideType.edgeCurveCcw:
        return SlideType.edgeCurveCw;
      case SlideType.zigZagS:
        return SlideType.zigZagZ;
      case SlideType.zigZagZ:
        return SlideType.zigZagS;
      default:
        return type;
    }
  }

  static void paint(
    Canvas canvas,
    Offset center,
    double radius,
    Note note,
    double progress,
    bool isEach,
    double currentTime,
    double renderTime,
    double noteTime,
    double approachTime, {
    SimaiMirrorMode mirrorMode = SimaiMirrorMode.none,
    bool rotateSlideStar = true,
    bool pinkSlideStar = false,
    bool standardBreakSlide = false,
    bool highlightExNotes = false,
    Map<(Note, SlidePath), Path>? slidePathCache,
    Map<(Note, SlidePath), double>? slideLengthCache,
    Map<double, int>? slideStartCounts,
  }) {
    if (progress < 0.0) return; // Not visible yet

    // Determine Color based on Type and Each/Break
    // For Tap and Slide(Star), disappear immediately after hit (progress > 1.0)
    // BUT: For Slide, we still need to draw the Slide Path.
    // So we should NOT return here for Slide type if we want to draw the path.
    // The slide path drawing logic is handled inside the switch case.
    if (progress > 1.0) {
      if (note.type == NoteType.tap ||
          // note.type == NoteType.slide || // REMOVED: Slide needs to continue drawing
          note.type == NoteType.breakNote) {
        return;
      }
    }

    // For Hold, check tail progress
    if (note.type == NoteType.hold) {
      // Hold duration is in note.length
      double tailTime = noteTime + (note.length ?? 0);

      final double extra = note.location.group == NoteGroup.tap ? 0.0 : 0.05;
      if (currentTime > tailTime + extra) {
        return;
      }
    }

    // Current position radius
    // Notes move from center (0) to radius (1.0)
    // Logic:
    // 0.0 - 0.2: Appear Phase. Stay at START_RADIUS. Scale 0 -> 1.
    // 0.2 - 1.0: Move Phase. Move START_RADIUS -> ring. Scale = 1.

    double noteScale = radius / 300.0;

    double appearRatio = 0.2;
    double startRadius =
        radius * 0.2; // Spawn near center (10% out), not exact center
    double scale;
    double currentRadius;

    int alpha = 255; // Always opaque if visible

    if (progress < appearRatio) {
      // Appear Phase
      currentRadius = startRadius;
      scale = (progress / appearRatio).clamp(0.0, 1.0);
    } else {
      // Move Phase
      double moveProgress = ((progress - appearRatio) / (1.0 - appearRatio))
          .clamp(0.0, 1.0);
      // Interpolate from startRadius to radius
      currentRadius = startRadius + (radius - startRadius) * moveProgress;
      scale = 1.0;
    }

    // Angle
    Location mirroredLoc = _mirrorLocation(note.location, mirrorMode);
    int index = mirroredLoc.index;
    double angle = (-67.5 + index * 45) * pi / 180;

    Offset position = Offset(
      center.dx + currentRadius * cos(angle),
      center.dy + currentRadius * sin(angle),
    );

    Color baseColor;
    bool isBreak =
        note.type == NoteType.breakNote || (note.styles & NoteStyles.mine) != 0;
    bool isEx = (note.styles & NoteStyles.ex) != 0 && highlightExNotes;

    // Determine Color based on Type and Each/Break
    switch (note.type) {
      case NoteType.tap:
        baseColor = isBreak
            ? SimaiColors.tapBreak
            : (isEach ? SimaiColors.tapEach : SimaiColors.tapNormal);
        _drawTap(
          canvas,
          position,
          baseColor,
          scale,
          alpha,
          noteScale,
          highlight: isEx,
        );
        break;
      case NoteType.slide:
        // Slide Head (Star)
        final bool headIsBreak = (note.styles & NoteStyles.breakHead) != 0;
        Color headColor;
        if (pinkSlideStar) {
          headColor = headIsBreak
              ? SimaiColors.tapBreak
              : (isEach ? SimaiColors.tapEach : SimaiColors.tapNormal);
        } else {
          headColor = headIsBreak
              ? SimaiColors.slideBreak
              : (isEach ? SimaiColors.slideEach : SimaiColors.slideNormal);
        }

        if (standardBreakSlide && headIsBreak) {
          headColor = isEach ? SimaiColors.slideEach : SimaiColors.slideNormal;
          if (pinkSlideStar) {
            headColor = isEach ? SimaiColors.tapEach : SimaiColors.tapNormal;
          }
        }

        final Color trackBaseColor = isEach
            ? SimaiColors.slideEach
            : SimaiColors.slideNormal;

        // Draw Approach Star (disappears after hit)
        if (progress <= 1.0) {
          double rotation = angle;
          if (rotateSlideStar) {
            // Rotate during approach: progress goes 0 -> 1
            // Use a constant rotation speed
            rotation += progress * 8.0;
          }
          drawStar(
            canvas,
            position,
            headColor,
            scale,
            alpha,
            rotation,
            noteScale,
            highlight: isEx,
          );
        }

        // Draw Slide Path and Moving Star
        _drawSlidePath(
          canvas,
          center,
          radius,
          note,
          currentTime,
          renderTime,
          noteTime,
          trackBaseColor,
          scale,
          approachTime,
          mirrorMode: mirrorMode,
          rotateSlideStar: rotateSlideStar,
          pinkSlideStar: pinkSlideStar,
          standardBreakSlide: standardBreakSlide,
          slidePathCache: slidePathCache,
          slideLengthCache: slideLengthCache,
          slideStartCounts: slideStartCounts,
          noteScale: noteScale,
        );
        break;
      case NoteType.hold:
        if (note.location.group != NoteGroup.tap) {
          baseColor = isBreak
              ? SimaiColors.touchBreak
              : (isEach ? SimaiColors.touchEach : SimaiColors.touchNormal);
          _drawTouch(
            canvas,
            center,
            radius,
            note,
            progress,
            currentTime,
            noteTime,
            approachTime,
            baseColor,
            alpha,
            noteScale,
            mirrorMode: mirrorMode,
            highlight: isEx,
          );
          break;
        }

        baseColor = isBreak
            ? SimaiColors.holdBreak
            : (isEach ? SimaiColors.holdEach : SimaiColors.holdNormal);

        // Hold involves a head and a tail.
        // Tail length depends on duration.
        // We need to draw the tail from head position to... where?
        // Tail moves towards center if we hold?
        // Actually:
        // "头部到达判定线后应该保持不动，头尾最长为Note出入点点距离"
        // Meaning: Head stays at judge line. Tail approaches from center.
        // If progress > 1.0 (after hit), head stays at radius.

        _drawHold(
          canvas,
          center,
          radius,
          note,
          progress,
          baseColor,
          scale,
          alpha,
          angle,
          currentTime,
          noteTime,
          approachTime,
          noteScale,
          highlight: isEx,
        );
        break;
      case NoteType.touch:
        baseColor = isBreak
            ? SimaiColors.touchBreak
            : (isEach ? SimaiColors.touchEach : SimaiColors.touchNormal);
        // Touch notes might be in different locations (C, A1..E8).
        // If location is Tap group, treat as Touch?
        // If NoteType is Touch, it's a Touch note.
        // Touch location logic needs separate handling if it's not on the ring.
        _drawTouch(
          canvas,
          center,
          radius,
          note,
          progress,
          currentTime,
          noteTime,
          approachTime,
          baseColor,
          alpha,
          noteScale,
          mirrorMode: mirrorMode,
          highlight: isEx,
        );
        break;
      case NoteType.breakNote:
        baseColor = SimaiColors.tapBreak;
        _drawTap(canvas, position, baseColor, scale, alpha, noteScale);
        break;
      default:
        // Fallback
        baseColor = Colors.grey;
        canvas.drawCircle(
          position,
          10 * scale,
          Paint()..color = baseColor.withAlpha(alpha),
        );
    }
  }

  static void _drawSlidePath(
    Canvas canvas,
    Offset center,
    double radius,
    Note note,
    double currentTime,
    double renderTime,
    double noteTime,
    Color color,
    double scale,
    double approachTime, {
    SimaiMirrorMode mirrorMode = SimaiMirrorMode.none,
    bool rotateSlideStar = true,
    bool pinkSlideStar = false,
    bool standardBreakSlide = false,
    Map<(Note, SlidePath), Path>? slidePathCache,
    Map<(Note, SlidePath), double>? slideLengthCache,
    Map<double, int>? slideStartCounts,
    double noteScale = 1.0,
  }) {
    // Phase 1: Approach (currentTime < noteTime)
    // We want to draw even if currentTime < noteTime (Fade In)
    // So remove the check: if (currentTime < noteTime) return;

    // However, we shouldn't draw if it's too far away (e.g. before spawn).
    // The main loop in SimaiGame filters visible notes.
    // If it's called, it's likely visible.

    for (var slidePath in note.slidePaths) {
      double startTime = noteTime + slidePath.delay;

      Color effectiveColor = color;
      if (slidePath.type == NoteType.breakNote && !standardBreakSlide) {
        effectiveColor = SimaiColors.slideBreak;
      } else {
        final double key = (startTime * 1000).round() / 1000.0;
        final int count = slideStartCounts?[key] ?? 0;
        if (count > 1) {
          effectiveColor = pinkSlideStar
              ? SimaiColors.tapEach
              : SimaiColors.slideEach;
        } else if (color == SimaiColors.slideEach ||
            color == SimaiColors.slideNormal) {
          effectiveColor = pinkSlideStar
              ? SimaiColors.tapNormal
              : SimaiColors.slideNormal;
        }
      }

      int trackAlpha = 255;
      double strokeScale = 1.0;

      // 1. Approach Phase
      if (currentTime < noteTime) {
        double p = 1.0 - (noteTime - currentTime) / approachTime;
        // Fade in: 0 -> 255
        trackAlpha = (255 * p).clamp(0, 255).toInt();
      }
      // 2. Wait Phase (Impact -> Start)
      else if (currentTime < startTime) {
        // "Arrive at judge line, disappear then zoom in and fade in"
        // The track should remain VISIBLE and STATIC during this wait phase.
        // The track appeared during approach (fade in).
        // So once it hits noteTime, it should stay fully visible (Alpha 255) until the star starts moving (or just stay visible).

        // Previous logic: trackAlpha = 0 (to hide it while star does zoom anim).
        // New logic: trackAlpha = 255.

        trackAlpha = 255;
        strokeScale = 1.0;
      }
      // 3. Move Phase
      else {
        trackAlpha = 255;
      }

      if (trackAlpha == 0) continue;

      // Generate Full Path
      final cacheKey = (note, slidePath);
      Path path;
      if (slidePathCache != null && slidePathCache.containsKey(cacheKey)) {
        path = slidePathCache[cacheKey]!;
      } else {
        path = Path();
        Location currentStart = _mirrorLocation(note.location, mirrorMode);
        for (var segment in slidePath.segments) {
          final mirroredVertices = segment.vertices
              .map((v) => _mirrorLocation(v, mirrorMode))
              .toList();

          SlidePathGenerator.generatePath(
            _mirrorSlideType(segment.slideType, mirrorMode),
            currentStart,
            mirroredVertices,
            center,
            radius,
            path: path,
          );
          if (mirroredVertices.isNotEmpty) {
            currentStart = mirroredVertices.last;
          }
        }
        slidePathCache?[cacheKey] = path;
      }

      // Generate Full Path
      // Path path = Path();
      // Location currentStart = note.location;
      // for (var segment in slidePath.segments) {
      //   SlidePathGenerator.generatePath(
      //     segment.slideType,
      //     currentStart,
      //     segment.vertices,
      //     center,
      //     radius,
      //     path: path,
      //   );
      //   if (segment.vertices.isNotEmpty) {
      //     currentStart = segment.vertices.last;
      //   }
      // }

      // 4. Erase Trajectory (Trim Path)
      // User requested: "Arrow position and arrangement should NOT be affected by erasing"
      // "Widened arrow"

      // If we trim the path, the metrics change, and arrows shift.
      // To keep arrows static, we should use the FULL path to determine arrow positions.
      // But we only DRAW arrows that are within the visible range (after slideP).

      // So:
      // 1. Calculate full length of path.
      // 2. Iterate d from 0 to fullLength with arrowSpacing.
      // 3. If d < startDistance (erased part), skip drawing.
      // 4. Else, draw arrow.

      double startDistance = 0.0;
      double slideP = 0.0;
      if (currentTime >= startTime) {
        if (slidePath.duration > 0) {
          slideP = (currentTime - startTime) / slidePath.duration;
          // Calculate total length first
          double totalLength;
          if (slideLengthCache != null &&
              slideLengthCache.containsKey(cacheKey)) {
            totalLength = slideLengthCache[cacheKey]!;
          } else {
            totalLength = path.computeMetrics().fold(
              0.0,
              (p, m) => p + m.length,
            );
            slideLengthCache?[cacheKey] = totalLength;
          }
          startDistance = totalLength * slideP;

          if (slideP >= 1.0) continue; // Finished
        }
      }

      // Draw Track
      if (trackAlpha > 0) {
        // Arrow Shape Configuration
        // "Widened arrow" -> Increase arrowSize and maybe stroke width?
        // Or wider angle? ">>>>>>" usually implies wider angle chevrons.

        double arrowSpacing = 25.0 * strokeScale * noteScale;
        double fanArrowSpacing = 40.0 * strokeScale * noteScale;
        double arrowSize =
            40.0 *
            strokeScale *
            noteScale; // Increased from 20.0 to 35.0 (Wider)
        // arrowAngle was pi/3 (60 deg). Let's keep it or make it wider?
        // Chevron shape logic below defines aspect ratio.

        Paint arrowPaint = Paint()
          ..color = effectiveColor.withAlpha(trackAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              12.0 *
              strokeScale *
              noteScale // Thicker stroke (was 4.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        Paint whitePaint = Paint()
          ..color = Colors.white.withAlpha(trackAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              3.0 * strokeScale * noteScale; // Thicker white stroke (was 2.0)

        final metrics = path.computeMetrics().toList();
        final bool isFan = slidePath.segments.any(
          (s) => s.slideType == SlideType.fan,
        );

        if (isFan && metrics.length >= 3) {
          final ui.PathMetric centerMetric = metrics[0];
          final ui.PathMetric leftMetric = metrics[1];
          final ui.PathMetric rightMetric = metrics[2];

          final double baseLen = centerMetric.length;
          if (baseLen > 0) {
            for (double d = 0; d <= baseLen; d += fanArrowSpacing) {
              final double p = d / baseLen;
              if (p < slideP) continue;

              final Offset pCenter =
                  centerMetric
                      .getTangentForOffset(centerMetric.length * p)
                      ?.position ??
                  Offset.zero;
              final Offset pLeft =
                  leftMetric
                      .getTangentForOffset(leftMetric.length * p)
                      ?.position ??
                  Offset.zero;
              final Offset pRight =
                  rightMetric
                      .getTangentForOffset(rightMetric.length * p)
                      ?.position ??
                  Offset.zero;

              final Path wifiArrow = Path()
                ..moveTo(pLeft.dx, pLeft.dy)
                ..lineTo(pCenter.dx, pCenter.dy)
                ..lineTo(pRight.dx, pRight.dy);

              canvas.drawPath(wifiArrow, arrowPaint);
            }
          }
        } else {
          for (var metric in metrics) {
            double length = metric.length;
            for (double d = 0; d < length; d += arrowSpacing) {
              if (d < startDistance) continue;

              ui.Tangent? t = metric.getTangentForOffset(d);
              if (t == null) continue;

              Offset pos = t.position;

              canvas.save();
              canvas.translate(pos.dx, pos.dy);
              canvas.rotate(-t.angle);

              double width = arrowSize * 0.5;
              double height = arrowSize;
              double offset = 0.0;

              Path arrowPath = Path()
                ..moveTo(-width / 2 + offset, -height / 2)
                ..lineTo(width / 2, 0)
                ..lineTo(-width / 2 + offset, height / 2);

              arrowPaint.strokeJoin = StrokeJoin.miter;
              whitePaint.strokeJoin = StrokeJoin.miter;
              arrowPaint.strokeCap = StrokeCap.butt;
              whitePaint.strokeCap = StrokeCap.butt;

              canvas.drawPath(arrowPath, arrowPaint);
              canvas.restore();
            }
          }
        }
      }

      // Draw Moving Star
      if (currentTime >= noteTime) {
        double starScale = 1.0;
        int starAlpha = 255;
        double starRotation = 0.0;

        // 1. Wait Phase Animation (noteTime -> startTime)
        // Usually slidePath.delay is one beat (e.g. 0.5s at 120bpm)
        if (currentTime < startTime) {
          double waitDuration = startTime - noteTime;
          if (waitDuration > 0) {
            double p = (currentTime - noteTime) / waitDuration;
            // Scale up and fade in during the wait duration
            starScale = p.clamp(0.0, 1.0);
            starAlpha = (255 * p).clamp(0, 255).toInt();
          } else {
            starScale = 1.0;
            starAlpha = 255;
          }
        }
        // 2. Move Phase
        else if (currentTime >= startTime) {
          starScale = 1.0;
          starAlpha = 255;
          starRotation = 0.0; // No spin during move phase per user request
        }

        if (starAlpha > 0) {
          // Draw Moving Star
          bool isFan = slidePath.segments.any(
            (s) => s.slideType == SlideType.fan,
          );

          if (isFan) {
            if (slidePath.duration > 0) {
              double p = (currentTime - startTime) / slidePath.duration;
              p = p.clamp(0.0, 1.0);
              // In wait phase, p will be 0.0, so star stays at start.
              // If p >= 1.0, star should be gone.
              if (currentTime >= startTime && p >= 1.0) continue;

              var metrics = path.computeMetrics().toList();
              if (metrics.length >= 3) {
                ui.Tangent? getTan(ui.PathMetric metric, double progress) {
                  double dist = metric.length * progress;
                  return metric.getTangentForOffset(dist);
                }

                final ui.Tangent? tanCenter = getTan(metrics[0], p);
                final ui.Tangent? tanLeft = getTan(metrics[1], p);
                final ui.Tangent? tanRight = getTan(metrics[2], p);

                if (tanCenter != null) {
                  drawStar(
                    canvas,
                    tanCenter.position,
                    effectiveColor,
                    starScale,
                    starAlpha,
                    starRotation - tanCenter.angle,
                    noteScale,
                  );
                }

                if (tanLeft != null) {
                  drawStar(
                    canvas,
                    tanLeft.position,
                    effectiveColor,
                    starScale,
                    starAlpha,
                    starRotation - tanLeft.angle,
                    noteScale,
                  );
                }

                if (tanRight != null) {
                  drawStar(
                    canvas,
                    tanRight.position,
                    effectiveColor,
                    starScale,
                    starAlpha,
                    starRotation - tanRight.angle,
                    noteScale,
                  );
                }
              }
            }
          } else {
            // Standard Single Star
            double p = 0.0;
            if (slidePath.duration > 0) {
              p = (currentTime - startTime) / slidePath.duration;
              p = p.clamp(0.0, 1.0);
            }
            if (currentTime >= startTime && p >= 1.0) continue;

            ui.Tangent? tangent;
            for (final metric in path.computeMetrics()) {
              double distance = p * metric.length;
              tangent = metric.getTangentForOffset(distance);
              if (tangent != null) break;
            }

            if (tangent != null) {
              drawStar(
                canvas,
                tangent.position,
                effectiveColor,
                starScale,
                starAlpha,
                starRotation - tangent.angle,
                noteScale,
              );
            }
          }
        }
      }
    }
  }

  static void _drawTap(
    Canvas canvas,
    Offset position,
    Color color,
    double scale,
    int alpha,
    double noteScale, {
    bool highlight = false,
  }) {
    // Pure Canvas Tap (Ring)
    double outerRadius = 35.0 * scale * noteScale;

    if (highlight && alpha > 0) {
      final highlightPaint = Paint()
        ..color = color.withAlpha((alpha * 0.4).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 * scale * noteScale;
      canvas.drawCircle(
        position,
        outerRadius + 4.0 * scale * noteScale,
        highlightPaint,
      );
    }

    // Ring thickness ratio (e.g., 0.3 of radius)
    double innerRatio = 0.65;
    double innerRadius = outerRadius * innerRatio;

    Paint paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;

    // Create Ring Path
    Path path = Path();
    path.fillType = PathFillType.evenOdd;
    path.addOval(Rect.fromCircle(center: position, radius: outerRadius));
    path.addOval(Rect.fromCircle(center: position, radius: innerRadius));

    canvas.drawPath(path, paint);

    // Draw White Strokes
    Paint strokePaint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale * noteScale;

    canvas.drawCircle(position, outerRadius, strokePaint);
    canvas.drawCircle(position, innerRadius, strokePaint);

    // Center dot
    double dotRadius = 4.0 * scale * noteScale;
    canvas.drawCircle(position, dotRadius, paint);
  }

  static Path _createStarPath(double r) {
    Path path = Path();
    double angle = 0; // Start at Right (0 deg) to point forward
    double step = pi / 5; // 36 degrees
    // Star fatness ratio (inner radius / outer radius of the star points)
    double starShapeRatio = 0.5;
    double rIn = r * starShapeRatio;

    path.moveTo(r * cos(angle), r * sin(angle));

    for (int i = 1; i < 10; i++) {
      double currentR = (i % 2 == 0) ? r : rIn;
      double currentAngle = angle + i * step;
      path.lineTo(currentR * cos(currentAngle), currentR * sin(currentAngle));
    }
    path.close();
    return path;
  }

  static void drawStar(
    Canvas canvas,
    Offset position,
    Color color,
    double scale,
    int alpha,
    double rotation,
    double noteScale, {
    bool highlight = false,
  }) {
    // Pure Canvas Star
    double radius = 40.0 * scale * noteScale;

    if (highlight && alpha > 0) {
      final highlightPaint = Paint()
        ..color = color.withAlpha((alpha * 0.4).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 * scale * noteScale
        ..strokeJoin = StrokeJoin.round;

      Path highlightStarPath = _createStarPath(
        radius + 6.0 * scale * noteScale,
      );
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(rotation);
      canvas.drawPath(highlightStarPath, highlightPaint);
      canvas.restore();
    }

    // Hollow ratio similar to Hold/Tap
    double innerRatio = 0.6;

    // Outer Star
    Path outerPath = _createStarPath(radius);

    // Inner Star (Hollow hole)
    Path innerPath = _createStarPath(radius * innerRatio);

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);

    Paint paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;

    Path combinedPath = Path();
    combinedPath.fillType = PathFillType.evenOdd;
    combinedPath.addPath(outerPath, Offset.zero);
    combinedPath.addPath(innerPath, Offset.zero);

    canvas.drawPath(combinedPath, paint);

    // Draw White Strokes
    Paint strokePaint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale * noteScale
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(outerPath, strokePaint);
    canvas.drawPath(innerPath, strokePaint);

    canvas.restore();
  }

  static void _drawHold(
    Canvas canvas,
    Offset center,
    double radius,
    Note note,
    double progress,
    Color color,
    double scale,
    int alpha,
    double angle,
    double currentTime,
    double noteTime,
    double approachTime,
    double noteScale, {
    bool highlight = false,
  }) {
    // Hold Head Logic:
    // If progress <= 1.0: Head is at currentRadius = radius * progress.
    // If progress > 1.0: Head is at radius (clamped).

    // Apply same movement logic to Hold Head
    double appearRatio = 0.2;
    double startRadius = radius * 0.2;

    double getMovementProgress(double p) {
      if (p < appearRatio) return 0.0;
      return ((p - appearRatio) / (1.0 - appearRatio)).clamp(0.0, 1.0);
    }

    double movementProgress = getMovementProgress(progress);

    // For Head Scale:
    // If progress < appearRatio, scale is progress/appearRatio
    // Else scale is 1.0
    // But headRadius uses movementProgress (0 at center).

    double headRadius = startRadius + (radius - startRadius) * movementProgress;

    Offset headPos = Offset(
      center.dx + headRadius * cos(angle),
      center.dy + headRadius * sin(angle),
    );

    // Tail Logic:
    // Tail end time = noteTime + duration.
    double duration = note.length ?? 0;
    double endTime = noteTime + duration;

    // Tail progress logic:
    // progress = 1.0 - (noteTime - currentTime) / approachTime
    // tailProgress = 1.0 - (endTime - currentTime) / approachTime

    double tailProgressRaw = 1.0 - (endTime - currentTime) / approachTime;
    double tailMovementProgress = getMovementProgress(tailProgressRaw);

    // Clamp tail radius
    double tailRadius =
        startRadius + (radius - startRadius) * tailMovementProgress;

    // Draw Hexagon from Head to Tail
    // But head is at headRadius (clamped 1.0), Tail is at tailRadius.
    // If tailProgress < 0, tail is at center (0).

    Offset tailPos = Offset(
      center.dx + tailRadius * cos(angle),
      center.dy + tailRadius * sin(angle),
    );

    // Draw Hexagon connecting headPos and tailPos
    _drawHexagon(
      canvas,
      headPos,
      tailPos,
      color,
      scale,
      alpha,
      angle,
      noteScale,
      highlight: highlight,
    );
  }

  static void _drawHexagon(
    Canvas canvas,
    Offset head,
    Offset tail,
    Color color,
    double scale,
    int alpha,
    double rotation,
    double noteScale, {
    bool highlight = false,
  }) {
    // Hexagon shape body (Hold) - Pure Canvas Implementation
    // Increase base thickness from 70.0 to 90.0 to make Hold bigger
    double thickness = 80.0 * scale * noteScale;
    double outerRadius = thickness / 2;

    // Calculate angle from Tail to Head
    double dx = head.dx - tail.dx;
    double dy = head.dy - tail.dy;
    double angle = atan2(dy, dx);

    // Helper to get hexagon vertices
    List<Offset> getHexVertices(Offset center, double r, double a) {
      List<Offset> points = [];
      for (int i = 0; i < 6; i++) {
        double theta = a + i * pi / 3; // 60 degrees
        points.add(
          Offset(center.dx + r * cos(theta), center.dy + r * sin(theta)),
        );
      }
      return points;
    }

    // Helper to get Convex Hull (simplistic for this specific shape)
    List<Offset> getHull(List<Offset> h, List<Offset> t) {
      return [t[2], h[2], h[1], h[0], h[5], t[5], t[4], t[3]];
    }

    List<Offset> outerHead = getHexVertices(head, outerRadius, angle);
    List<Offset> outerTail = getHexVertices(tail, outerRadius, angle);

    List<Offset> outerHullPoints = getHull(outerHead, outerTail);

    if (highlight && alpha > 0) {
      final highlightPaint = Paint()
        ..color = color.withAlpha((alpha * 0.4).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 * scale * noteScale
        ..strokeJoin = StrokeJoin.round;

      List<Offset> highlightHead = getHexVertices(
        head,
        outerRadius + 6.0 * scale * noteScale,
        angle,
      );
      List<Offset> highlightTail = getHexVertices(
        tail,
        outerRadius + 6.0 * scale * noteScale,
        angle,
      );
      List<Offset> highlightHullPoints = getHull(highlightHead, highlightTail);

      Path highlightPath = Path()..addPolygon(highlightHullPoints, true);
      canvas.drawPath(highlightPath, highlightPaint);
    }

    // Inner radius ratio (e.g., 0.6 means the hole is 60% of the width)
    double innerRatio = 0.7;
    double innerRadius = outerRadius * innerRatio;

    // Generate Outer and Inner vertices
    List<Offset> innerHead = getHexVertices(head, innerRadius, angle);
    List<Offset> innerTail = getHexVertices(tail, innerRadius, angle);

    Path path = Path();
    path.fillType = PathFillType.evenOdd;

    // Add Outer Hull
    path.addPolygon(outerHullPoints, true);

    // Add Inner Hull
    List<Offset> innerHullPoints = getHull(innerHead, innerTail);
    path.addPolygon(innerHullPoints, true);

    // Draw
    Paint paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Draw White Strokes
    Paint strokePaint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale * noteScale
      ..strokeJoin = StrokeJoin.round;

    Path outerPath = Path()..addPolygon(outerHullPoints, true);
    Path innerPath = Path()..addPolygon(innerHullPoints, true);

    canvas.drawPath(outerPath, strokePaint);
    canvas.drawPath(innerPath, strokePaint);

    // Draw center dots for Head and Tail
    double dotRadius = 5.0 * scale * noteScale;
    canvas.drawCircle(head, dotRadius, paint);
    canvas.drawCircle(tail, dotRadius, paint);
  }

  static void _drawTouch(
    Canvas canvas,
    Offset center,
    double radius,
    Note note,
    double progress,
    double currentTime,
    double noteTime,
    double approachTime,
    Color color,
    int alpha,
    double noteScale, {
    SimaiMirrorMode mirrorMode = SimaiMirrorMode.none,
    bool highlight = false,
  }) {
    final bool isHold = note.type == NoteType.hold;
    final Offset h = _getTouchPosition(
      center,
      radius,
      _mirrorLocation(note.location, mirrorMode),
    );

    final double r = max(approachTime, 0.001);
    final double n = noteTime - currentTime;
    double o = 0.05;
    if (isHold) {
      o = (note.length ?? 0) + 0.05;
    }
    if (n > r || n < -o) return;

    double a = 1.0;
    if (n > r * 0.95) {
      a = 1.0 - (n - r * 0.95) / (r * 0.05);
    }

    double c = 1.0;
    if (n > 0 && n < r) {
      final double s = r - n;
      if (s < 0.15) c = s / 0.15;
    }

    final bool m = !isHold && (note.parentCollection?.length ?? 0) >= 2;
    final double t = (a * c).clamp(0.0, 1.0);

    final double cornerRadius = 8.0 * noteScale;
    final double innerCornerRadius = cornerRadius * 0.4;
    final double outlineWidth = 3.0 * noteScale;
    final double dotRadius = 8.0 * noteScale;

    final double u = 40.0 * noteScale;
    final double gapEnd = 0;
    final double gapStart = gapEnd + 18.0 * noteScale;
    final double fEnd = u + gapEnd;
    final double fStart = u + gapStart;

    double f = fStart;
    if (n > 0 && n <= r) {
      final double s = 1.0 - n / r;
      final double k = s * s * s * s;
      f = fStart - (fStart - fEnd) * k;
    } else if (n <= 0) {
      f = fEnd;
    }

    final List<double> angles = [-pi / 4, pi / 4, 3 * pi / 4, -3 * pi / 4];
    final double w = isHold ? 0.0 : -pi / 4;

    final List<Offset> petalTips = [];
    final List<Offset> petalLefts = [];
    final List<Offset> petalRights = [];

    for (int idx = 0; idx < 4; idx++) {
      final double k = angles[idx] + w;
      final Offset petal = Offset(h.dx + cos(k) * f, h.dy + sin(k) * f);
      final double v = u;
      petalTips.add(
        Offset(petal.dx + cos(k + pi) * v, petal.dy + sin(k + pi) * v),
      );
      petalLefts.add(
        Offset(petal.dx + cos(k + pi / 2) * v, petal.dy + sin(k + pi / 2) * v),
      );
      petalRights.add(
        Offset(petal.dx + cos(k - pi / 2) * v, petal.dy + sin(k - pi / 2) * v),
      );
    }

    if (highlight && alpha > 0) {
      final highlightPaint = Paint()
        ..color = color.withAlpha((alpha * 0.4).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0 * noteScale
        ..strokeJoin = StrokeJoin.round;

      for (int i = 0; i < 4; i++) {
        final highlightPath = _roundedTrianglePath(
          petalTips[i],
          petalLefts[i],
          petalRights[i],
          cornerRadius + 6.0 * noteScale,
        );
        canvas.drawPath(highlightPath, highlightPaint);
      }
    }

    final List<Color> holdColors = [
      SimaiColors.touchHoldTopRight,
      SimaiColors.touchHoldBottomRight,
      SimaiColors.touchHoldBottomLeft,
      SimaiColors.touchHoldTopLeft,
    ];

    final List<Offset> holdCorners = List.filled(8, Offset.zero);
    int holdCornerIndex = 0;

    for (int idx = 0; idx < 4; idx++) {
      final double k = angles[idx] + w;
      final Offset petal = Offset(h.dx + cos(k) * f, h.dy + sin(k) * f);

      final Offset tip = petalTips[idx];
      final Offset left = petalLefts[idx];
      final Offset right = petalRights[idx];
      if (isHold) {
        holdCorners[holdCornerIndex++] = left;
        holdCorners[holdCornerIndex++] = right;
      }

      final Path outer = _roundedTrianglePath(tip, left, right, cornerRadius);
      Path fillPath = outer;

      if (!isHold) {
        final Offset centroid = Offset(
          (tip.dx + left.dx + right.dx) / 3,
          (tip.dy + left.dy + right.dy) / 3,
        );
        final Offset innerTip = centroid + (tip - centroid) * 0.4;
        final Offset innerLeft = centroid + (left - centroid) * 0.4;
        final Offset innerRight = centroid + (right - centroid) * 0.4;
        final Path inner = _roundedTrianglePath(
          innerTip,
          innerLeft,
          innerRight,
          innerCornerRadius,
        );
        fillPath = Path()
          ..fillType = PathFillType.evenOdd
          ..addPath(outer, Offset.zero)
          ..addPath(inner, Offset.zero);
      }

      canvas.drawShadow(
        outer,
        Color.fromARGB((128 * t).round(), 0, 0, 0),
        8.0 * noteScale,
        true,
      );

      final Paint fillPaint = Paint()..style = PaintingStyle.fill;

      if (isHold) {
        fillPaint.color = holdColors[idx].withAlpha((255 * t).round());
      } else {
        final Color g0 = m ? const Color(0xFFFFFF00) : color;
        final Color g1 = m
            ? const Color(0xFFFFD700)
            : Color.lerp(color, Colors.black, 0.35)!;
        fillPaint.shader = ui.Gradient.linear(petal, tip, [
          g0.withAlpha((255 * t).round()),
          g1.withAlpha((255 * t).round()),
        ]);
        fillPaint.color = Colors.white.withAlpha((255 * t).round());
      }

      canvas.drawPath(fillPath, fillPaint);

      final Paint strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withAlpha((255 * t).round());

      canvas.drawPath(outer, strokePaint);

      if (!isHold) {
        final Offset centroid = Offset(
          (tip.dx + left.dx + right.dx) / 3,
          (tip.dy + left.dy + right.dy) / 3,
        );
        final Offset innerTip = centroid + (tip - centroid) * 0.4;
        final Offset innerLeft = centroid + (left - centroid) * 0.4;
        final Offset innerRight = centroid + (right - centroid) * 0.4;
        final Path inner = _roundedTrianglePath(
          innerTip,
          innerLeft,
          innerRight,
          innerCornerRadius,
        );
        canvas.drawPath(inner, strokePaint);
      }
    }

    if (isHold && n < 0 && (note.length ?? 0) > 0) {
      final double elapsed = -n;
      final double holdP = (elapsed / (note.length ?? 1)).clamp(0.0, 1.0);

      Offset top = holdCorners[0];
      Offset bottom = holdCorners[0];
      Offset leftMost = holdCorners[0];
      Offset rightMost = holdCorners[0];
      for (final p in holdCorners) {
        if (p.dy < top.dy) top = p;
        if (p.dy > bottom.dy) bottom = p;
        if (p.dx < leftMost.dx) leftMost = p;
        if (p.dx > rightMost.dx) rightMost = p;
      }

      final List<Offset> vertices = [top, rightMost, bottom, leftMost];

      const double outward = 12.0;
      final List<Offset> bVertices = List.filled(4, Offset.zero);
      for (int i = 0; i < 4; i++) {
        final Offset v = vertices[i];
        final Offset dv = v - h;
        final double lv = dv.distance;
        bVertices[i] = lv == 0 ? v : v + dv / lv * (outward * noteScale);
      }

      final List<double> lens = List.filled(4, 0.0);
      double perimeter = 0.0;
      for (int i = 0; i < 4; i++) {
        final Offset b0 = bVertices[i];
        final Offset b1 = bVertices[(i + 1) % 4];
        final double segLen = (b1 - b0).distance;
        lens[i] = segLen;
        perimeter += segLen;
      }

      if (perimeter > 0) {
        double remaining = perimeter * holdP;
        final double strokeW = max(3.0, outlineWidth * 5.0);

        for (int i = 0; i < 4; i++) {
          if (remaining <= 0) break;
          final Offset b0 = bVertices[i];
          final Offset b1 = bVertices[(i + 1) % 4];
          final double segLen = lens[i];
          if (segLen <= 0) continue;
          final double drawLen = min(remaining, segLen);
          final double tSeg = drawLen / segLen;
          final Offset end = Offset(
            b0.dx + (b1.dx - b0.dx) * tSeg,
            b0.dy + (b1.dy - b0.dy) * tSeg,
          );

          final Paint p = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeW
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = holdColors[i].withAlpha((255 * a).round());

          canvas.drawLine(b0, end, p);
          remaining -= drawLen;
        }
      }
    }

    final Paint dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = (m ? const Color(0xFFFFFF00) : color).withAlpha(
        (255 * a).round(),
      );
    canvas.drawCircle(h, dotRadius, dotPaint);

    final Paint dotStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineWidth
      ..color = Colors.white.withAlpha((255 * a).round());
    canvas.drawCircle(h, dotRadius, dotStroke);
  }

  static Offset _getTouchPosition(Offset center, double radius, Location loc) {
    if (loc.group == NoteGroup.cSensor) return center;
    if (loc.group == NoteGroup.aSensor) {
      final double r = radius * 0.8;
      final double angle = (-67.5 + loc.index * 45) * pi / 180;
      return center + Offset(r * cos(angle), r * sin(angle));
    }
    if (loc.group == NoteGroup.bSensor) {
      final double r = radius * 0.4;
      final double angle = (-67.5 + loc.index * 45) * pi / 180;
      return center + Offset(r * cos(angle), r * sin(angle));
    }
    if (loc.group == NoteGroup.dSensor) {
      final double r = radius * 0.8;
      final double angle = (-90 + loc.index * 45) * pi / 180;
      return center + Offset(r * cos(angle), r * sin(angle));
    }
    if (loc.group == NoteGroup.eSensor) {
      final double r = radius * 0.45;
      final double angle = (-90 + loc.index * 45) * pi / 180;
      return center + Offset(r * cos(angle), r * sin(angle));
    }
    final double angle = (-67.5 + loc.index * 45) * pi / 180;
    return Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );
  }

  static Path _roundedTrianglePath(
    Offset p0,
    Offset p1,
    Offset p2,
    double radius,
  ) {
    final List<Offset> pts = [p0, p1, p2];
    final List<Offset> starts = List.filled(3, Offset.zero);
    final List<Offset> ends = List.filled(3, Offset.zero);

    for (int i = 0; i < 3; i++) {
      final Offset prev = pts[(i + 2) % 3];
      final Offset curr = pts[i];
      final Offset next = pts[(i + 1) % 3];
      final Offset v1 = prev - curr;
      final Offset v2 = next - curr;
      final double len1 = v1.distance;
      final double len2 = v2.distance;
      double r = radius;
      if (len1 > 0) r = min(r, len1 / 2);
      if (len2 > 0) r = min(r, len2 / 2);
      final Offset s = curr + (len1 == 0 ? Offset.zero : v1 / len1 * r);
      final Offset e = curr + (len2 == 0 ? Offset.zero : v2 / len2 * r);
      starts[i] = s;
      ends[i] = e;
    }

    final Path path = Path()..moveTo(ends[0].dx, ends[0].dy);
    path.lineTo(starts[1].dx, starts[1].dy);
    path.quadraticBezierTo(pts[1].dx, pts[1].dy, ends[1].dx, ends[1].dy);
    path.lineTo(starts[2].dx, starts[2].dy);
    path.quadraticBezierTo(pts[2].dx, pts[2].dy, ends[2].dx, ends[2].dy);
    path.lineTo(starts[0].dx, starts[0].dy);
    path.quadraticBezierTo(pts[0].dx, pts[0].dy, ends[0].dx, ends[0].dy);
    path.close();
    return path;
  }
}
