import 'dart:math';
import 'dart:ui';
import '../../structures/slide_type.dart';
import '../../structures/location.dart';

class SlidePathGenerator {
  static Path generatePath(
    SlideType type,
    Location start,
    List<Location> vertices,
    Offset center,
    double radius, {
    Path? path,
  }) {
    path ??= Path();
    Offset startPos = _getVertex(start.index, center, radius);

    // Only moveTo if path is empty (approximated by checking metrics/bounds? or just relying on context)
    // Actually, checking if path is empty is tricky with Path API.
    // Assuming if path is passed, it's already at startPos.
    // If path is not passed (null), we create new and moveTo.
    // BUT: If we pass an existing path, we might want to ensure we are at startPos.
    // Ideally we should lineTo(startPos) just in case, but if we are already there, it's fine.
    // If we are NOT there, lineTo draws a connecting line, which is what we want for continuous segments.

    // However, for the very first segment, we MUST moveTo.
    // How do we know if it's the first segment?
    // We can check if path was null.

    // Note: getBounds() might be empty for a single point MoveTo?
    // computeMetrics is better.

    // Actually, simpler: The caller manages the path.
    // If we want to append, we pass the path.
    // If the path is fresh, we do moveTo.

    // Let's rely on a heuristic: if we created the path, we moveTo.
    // If path was passed, we lineTo.

    // But wait, generatePath argument 'path' is optional.
    // If I call it with a path, I expect it to append.

    if (path.computeMetrics().isEmpty) {
      path.moveTo(startPos.dx, startPos.dy);
    } else {
      path.lineTo(startPos.dx, startPos.dy);
    }

    if (vertices.isEmpty) return path;

    // Helper to get end position (assuming single segment usually has 1 vertex, except fan/V)
    // But SlideSegment has List<Location> vertices.
    // We should iterate if needed, but standard slides usually have 1 target per segment.
    // Except 'V' (edgeFold) which has 2 (Relay, End).

    Location endLoc = vertices.last;
    Offset endPos = _getVertex(endLoc.index, center, radius);

    switch (type) {
      case SlideType.straightLine:
        path.lineTo(endPos.dx, endPos.dy);
        break;

      case SlideType.ringCw:
      case SlideType.ringCcw:
        _addRingArc(
          path,
          start.index,
          endLoc.index,
          center,
          radius,
          type == SlideType.ringCw,
        );
        break;

      case SlideType.fold: // v
        path.lineTo(center.dx, center.dy);
        path.lineTo(endPos.dx, endPos.dy);
        break;

      case SlideType.curveCw: // q
      case SlideType.curveCcw: // p
        // Tangent Circle Logic
        // 1. Start -> Entry Tangent (Line)
        // 2. Entry -> Exit (Arc on 0.55R circle)
        // 3. Exit -> End (Line)

        bool isCw = (type == SlideType.curveCw);
        double rMid = radius * 0.39;

        // Vortex logic: q/p slides with distance 0 or 3 are typically loops
        int dist = isCw
            ? (endLoc.index - start.index + 8) % 8
            : (start.index - endLoc.index + 8) % 8;
        bool forceFullCircle = (dist == 0 || dist == 3);

        _addTangentArcPath(
          path,
          startPos,
          endPos,
          center,
          rMid,
          isCw,
          forceFullCircle,
        );
        break;

      case SlideType.zigZagS: // s
      case SlideType.zigZagZ: // z
        // Lightning shape. 3 segments.
        // Start -> A -> B -> End.
        _addZigZag(path, startPos, endPos, radius, type == SlideType.zigZagZ);
        break;

      case SlideType.edgeFold: // V (Big V)
        if (vertices.length >= 2) {
          Offset relayPos = _getVertex(vertices[0].index, center, radius);
          endPos = _getVertex(vertices[1].index, center, radius);
          path.lineTo(relayPos.dx, relayPos.dy);
          path.lineTo(endPos.dx, endPos.dy);
        }
        break;

      case SlideType.edgeCurveCw: // qq
        _addQqPath(path, start.index, endLoc.index, center, radius);
        break;

      case SlideType.edgeCurveCcw: // pp
        _addPpPath(path, start.index, endLoc.index, center, radius);
        break;

      case SlideType.fan: // w
        // "w" slide (Wifi slide)
        // Consists of 3 straight lines:
        // 1. Start -> End (Center)
        // 2. Start -> End - 1 (Left)
        // 3. Start -> End + 1 (Right)

        // The path object will contain 3 disconnected lines (contours).
        // For drawing, this is fine. The star renderer will need to handle multiple paths/stars.
        // But here we are generating the 'track' path.

        // Center line
        path.lineTo(endPos.dx, endPos.dy);

        // Calculate neighbors (1-based index in logic, but 0-based in code)
        // endLoc.index is 0-7.
        int leftIndex = (endLoc.index + 8 - 1) % 8;
        int rightIndex = (endLoc.index + 1) % 8;

        Offset leftPos = _getVertex(leftIndex, center, radius);
        Offset rightPos = _getVertex(rightIndex, center, radius);

        // Draw Left Line
        path.moveTo(startPos.dx, startPos.dy);
        path.lineTo(leftPos.dx, leftPos.dy);

        // Draw Right Line
        path.moveTo(startPos.dx, startPos.dy);
        path.lineTo(rightPos.dx, rightPos.dy);
        break;
    }

    return path;
  }

  static void _addTangentArcPath(
    Path path,
    Offset startPos,
    Offset endPos,
    Offset center,
    double rMid,
    bool isCw,
    bool forceFullCircle,
  ) {
    // 1. Calculate angles of start/end points relative to center
    double dxS = startPos.dx - center.dx;
    double dyS = startPos.dy - center.dy;
    double distS = sqrt(dxS * dxS + dyS * dyS);
    double alphaS = atan2(dyS, dxS);

    double dxE = endPos.dx - center.dx;
    double dyE = endPos.dy - center.dy;
    double distE = sqrt(dxE * dxE + dyE * dyE);
    double alphaE = atan2(dyE, dxE);

    // 2. Calculate beta (offset angle for tangent)
    // beta = acos(r/d)
    // Clamp r/d to 1.0 just in case
    double betaS = (distS > rMid) ? acos(rMid / distS) : 0.0;
    double betaE = (distE > rMid) ? acos(rMid / distE) : 0.0;

    // 3. Determine Entry/Exit angles based on direction
    double thetaEntry, thetaExit;

    // Note on direction:
    // isCw (q): Increasing angle (Clockwise in screen coords? No, standard math CCW is +)
    // Wait, Flutter +Y is down.
    // Right (0) -> Bottom (90). So CW is Positive direction in Flutter.

    if (isCw) {
      // q (CW)
      // Entry: alpha + beta
      // Exit: alpha - beta
      thetaEntry = alphaS + betaS;
      thetaExit = alphaE - betaE;
    } else {
      // p (CCW)
      // Entry: alpha - beta
      // Exit: alpha + beta
      thetaEntry = alphaS - betaS;
      thetaExit = alphaE + betaE;
    }

    // 4. Calculate Points
    Offset entryPos = Offset(
      center.dx + rMid * cos(thetaEntry),
      center.dy + rMid * sin(thetaEntry),
    );

    // 5. Draw Start -> Entry
    path.lineTo(entryPos.dx, entryPos.dy);

    // 6. Draw Arc Entry -> Exit
    // Calculate sweep angle
    double sweep = thetaExit - thetaEntry;

    if (forceFullCircle) {
      Rect rect = Rect.fromCircle(center: center, radius: rMid);
      double fullSweep = isCw ? 2 * pi : -2 * pi;
      // Split to ensure it renders correctly as a loop
      path.arcTo(rect, thetaEntry, fullSweep / 2, false);
      path.arcTo(rect, thetaEntry + fullSweep / 2, fullSweep / 2, false);
      path.lineTo(endPos.dx, endPos.dy);
      return;
    }

    if (isCw) {
      // CW: sweep should be positive?
      // Flutter arcTo: sweepAngle positive = CW.
      // Normalize sweep to (0, 2pi)
      while (sweep <= 0) {
        sweep += 2 * pi;
      }
      if (sweep == 0) {
        sweep = 2 * pi; // Should not happen unless identical?
      }
    } else {
      // CCW: sweep should be negative.
      // Normalize sweep to (-2pi, 0)
      while (sweep >= 0) {
        sweep -= 2 * pi;
      }
      if (sweep == 0) {
        sweep = -2 * pi;
      }
    }

    Rect rect = Rect.fromCircle(center: center, radius: rMid);
    if (sweep.abs() >= 2 * pi - 0.001) {
      // Split large arcs to ensure they render as loops and correctly record metrics
      path.arcTo(rect, thetaEntry, sweep / 2, false);
      path.arcTo(rect, thetaEntry + sweep / 2, sweep / 2, false);
    } else {
      path.arcTo(rect, thetaEntry, sweep, false);
    }

    // 7. Draw Exit -> End
    path.lineTo(endPos.dx, endPos.dy);
  }

  static void _addQqPath(
    Path path,
    int startIndex,
    int endIndex,
    Offset center,
    double radius,
  ) {
    // 1. Get start and opposite positions
    int oppositeIndex = (startIndex + 4) % 8;

    Offset startPos = _getVertex(startIndex, center, radius);
    Offset oppositePos = _getVertex(oppositeIndex, center, radius);
    Offset endPos = _getVertex(endIndex, center, radius);

    // 2. Start -> Guide point (40% from start to opposite)
    Offset guide = startPos + (oppositePos - startPos) * 0.4;

    // 3. Construct outer circle
    Offset diffVector = oppositePos - startPos;
    double len = diffVector.distance;
    Offset dir = len == 0 ? Offset.zero : diffVector / len;

    // normal = Vec2(-dir.y, dir.x)
    Offset normal = Offset(-dir.dy, dir.dx);

    double arcRadius = 0.45 * radius;

    // qq (CW) -> sign = 1.0
    double sign = 1.0;

    Offset arcCenter = guide + normal * arcRadius * sign;

    // 4. Arc Start Angle
    double startAngle = atan2(guide.dy - arcCenter.dy, guide.dx - arcCenter.dx);

    // 5. Determine Turn Angle based on button difference
    int diff = (endIndex - startIndex + 8) % 8;

    double arcAngle;
    switch (diff) {
      case 0:
        arcAngle = 1.25 * pi;
        break;
      case 1:
        arcAngle = 1.5 * pi;
        break;
      case 2:
        arcAngle = 1.625 * pi;
        break;
      case 3:
        arcAngle = 1.875 * pi;
        break;
      case 4:
        arcAngle = 2.0 * pi;
        break;
      case 5:
        arcAngle = 2.25 * pi;
        break;
      case 6:
        arcAngle = 0.75 * pi;
        break;
      case 7:
        arcAngle = 1.125 * pi;
        break;
      default:
        arcAngle = 2.0 * pi;
    }

    arcAngle *= sign;

    // Draw
    path.lineTo(guide.dx, guide.dy);
    Rect arcRect = Rect.fromCircle(center: arcCenter, radius: arcRadius);

    // For angles >= 2pi, arcTo might clamp or optimize away the full loop.
    // If we want to show multiple loops or a full loop, we might need to break it down?
    // Flutter's path.arcTo(rect, startAngle, sweepAngle, forceMoveTo)
    // documentation says: "If the sweep angle is 2pi or greater, it draws a full oval".
    // It doesn't explicitly say it draws MULTIPLE loops.
    // But for 2pi, it should draw a full circle.
    // If user says "Only shows as 0 circles", it implies visually it looks like a short arc or nothing?
    // Or maybe they mean the visual TRAIL doesn't show the loop?

    // If the angle is exactly 2pi, arcTo draws a circle.
    // If > 2pi, it draws circle + overlap.

    // HOWEVER, if the path is being used for ANIMATION (stars moving along it),
    // and `path.computeMetrics()` is used, then a 2pi arc definitely adds length.

    // But if the issue is that it "appears as 0 circles", maybe it's because
    // the start and end points of the arc are identical (mod 2pi),
    // and the renderer optimizes it out?

    // Wait, the user says "greater or equal to 2pi ... shows as 0 circles".
    // This implies that visually it looks like it went straight to the end without looping.

    // Workaround: Split the arc into smaller chunks if it's large?
    // Or maybe `arcTo` behavior with large angles is platform dependent?

    // Let's try splitting it into (Angle - small) and (small).
    // Or just 2 * pi and remainder?

    if (arcAngle.abs() >= 2 * pi - 0.001) {
      // Draw in two parts to ensure the loop is recorded in the path metrics
      // Part 1: First half
      path.arcTo(arcRect, startAngle, arcAngle / 2, false);
      // Part 2: Second half
      path.arcTo(arcRect, startAngle + arcAngle / 2, arcAngle / 2, false);
    } else {
      path.arcTo(arcRect, startAngle, arcAngle, false);
    }

    path.lineTo(endPos.dx, endPos.dy);
  }

  static void _addPpPath(
    Path path,
    int startIndex,
    int endIndex,
    Offset center,
    double radius,
  ) {
    // 1. Get start and opposite positions
    int oppositeIndex = (startIndex + 4) % 8;

    Offset startPos = _getVertex(startIndex, center, radius);
    Offset oppositePos = _getVertex(oppositeIndex, center, radius);
    Offset endPos = _getVertex(endIndex, center, radius);

    // 2. Start -> Guide point (40% from start to opposite)
    Offset guide = startPos + (oppositePos - startPos) * 0.4;

    // 3. Construct outer circle
    Offset diffVector = oppositePos - startPos;
    double len = diffVector.distance;
    Offset dir = len == 0 ? Offset.zero : diffVector / len;

    // normal = Vec2(-dir.y, dir.x)
    Offset normal = Offset(-dir.dy, dir.dx);

    double arcRadius = 0.45 * radius;

    // pp (CCW) -> sign = -1.0
    double sign = -1.0;

    Offset arcCenter = guide + normal * arcRadius * sign;

    // 4. Arc Start Angle
    double startAngle = atan2(guide.dy - arcCenter.dy, guide.dx - arcCenter.dx);

    // 5. Determine Turn Angle based on button difference
    // Use CCW diff index for symmetry with qq
    int ccwDiff = (endIndex - startIndex + 8) % 8;

    double arcAngle;
    switch (ccwDiff) {
      case 0:
        arcAngle = 1.25 * pi;
        break;
      case 1:
        arcAngle = 1.125 * pi;
        break;
      case 2:
        arcAngle = 0.75 * pi;
        break;
      case 3:
        arcAngle = 2.25 * pi;
        break;
      case 4:
        arcAngle = 2.0 * pi;
        break;
      case 5:
        arcAngle = 1.875 * pi;
        break;
      case 6:
        arcAngle = 1.625 * pi;
        break;
      case 7:
        arcAngle = 1.5 * pi;
        break;
      default:
        arcAngle = 2.0 * pi;
    }

    arcAngle *= sign;

    // Draw
    path.lineTo(guide.dx, guide.dy);
    Rect arcRect = Rect.fromCircle(center: arcCenter, radius: arcRadius);

    if (arcAngle.abs() >= 2 * pi - 0.001) {
      // Split large arcs to ensure they render as loops
      path.arcTo(arcRect, startAngle, arcAngle / 2, false);
      path.arcTo(arcRect, startAngle + arcAngle / 2, arcAngle / 2, false);
    } else {
      path.arcTo(arcRect, startAngle, arcAngle, false);
    }

    path.lineTo(endPos.dx, endPos.dy);
  }

  static Offset _getVertex(int index, Offset center, double radius) {
    double angle = (-67.5 + index * 45) * pi / 180;
    return Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );
  }

  static void _addRingArc(
    Path path,
    int startIndex,
    int endIndex,
    Offset center,
    double radius,
    bool clockwise,
  ) {
    double startAngle = (-67.5 + startIndex * 45) * pi / 180;
    double endAngle = (-67.5 + endIndex * 45) * pi / 180;

    // Adjust angles for continuous rotation
    if (clockwise) {
      if (endAngle <= startAngle) endAngle += 2 * pi;
    } else {
      if (endAngle >= startAngle) endAngle -= 2 * pi;
    }

    // Rect for the arc
    Rect rect = Rect.fromCircle(center: center, radius: radius);

    // Using arcTo
    // sweepAngle
    double sweepAngle = endAngle - startAngle;
    if (sweepAngle.abs() >= 2 * pi - 0.001) {
      path.arcTo(rect, startAngle, sweepAngle / 2, false);
      path.arcTo(rect, startAngle + sweepAngle / 2, sweepAngle / 2, false);
    } else {
      path.arcTo(rect, startAngle, sweepAngle, false);
    }
  }

  static void _addZigZag(
    Path path,
    Offset start,
    Offset end,
    double radius,
    bool isZ,
  ) {
    // s / z Path Algorithm
    // 1. Base direction: Start -> End
    // 2. Two control points at 49% and 51%
    // 3. Offset perpendicular to base, amount ~0.4 * Radius
    // 4. s: P1 (+), P2 (-)
    // 5. z: P1 (-), P2 (+) (Mirror of s)

    double dx = end.dx - start.dx;
    double dy = end.dy - start.dy;
    double len = sqrt(dx * dx + dy * dy);

    if (len < 1.0) {
      path.lineTo(end.dx, end.dy);
      return;
    }

    // Unit direction vector
    double ux = dx / len;
    double uy = dy / len;

    // Normal direction (lateral offset)
    // Using (-uy, ux)
    double nx = -uy;
    double ny = ux;

    // Offset amount: 0.4 * radius
    double offsetAmt = 0.4 * radius;

    // Sign for s vs z
    // s (isZ=false) -> +1.0
    // z (isZ=true)  -> -1.0
    double sign = isZ ? -1.0 : 1.0;

    // Control Point 1: 49%, offset +sign
    Offset p1 = Offset(
      start.dx + ux * (len * 0.49) + nx * offsetAmt * sign,
      start.dy + uy * (len * 0.49) + ny * offsetAmt * sign,
    );

    // Control Point 2: 51%, offset -sign
    Offset p2 = Offset(
      start.dx + ux * (len * 0.51) - nx * offsetAmt * sign,
      start.dy + uy * (len * 0.51) - ny * offsetAmt * sign,
    );

    path.lineTo(p1.dx, p1.dy);
    path.lineTo(p2.dx, p2.dy);
    path.lineTo(end.dx, end.dy);
  }
}
