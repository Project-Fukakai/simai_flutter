import 'package:flutter_test/flutter_test.dart';
import 'package:simai_flutter/simai_flutter.dart';

void main() {
  test('CanReadSingularLocation', () {
    var content = "&inote_1=1";
    var simaiFile = SimaiFile(content);
    var chartText = simaiFile.getValue("inote_1");
    expect(chartText, "1");

    var chart = SimaiConvert.deserialize(chartText!);
    expect(chart.noteCollections.length, 1);
    expect(chart.noteCollections[0].length, 1);
    expect(chart.noteCollections[0][0].location.index, 0); // 1 -> index 0
    expect(chart.noteCollections[0][0].location.group, NoteGroup.tap);
  });

  test('CanReadTempoWithDefaultSubdivisions', () {
    var content = "&inote_1=(60)1,1";
    var simaiFile = SimaiFile(content);
    var chartText = simaiFile.getValue("inote_1");
    var chart = SimaiConvert.deserialize(chartText!);

    expect(chart.timingChanges.length, 1);
    expect(chart.timingChanges[0].tempo, 60);

    expect(chart.noteCollections.length, 2);
    expect(chart.noteCollections[0].time, closeTo(0, 1e-5));
    expect(chart.noteCollections[1].time, closeTo(1.0, 1e-5));
  });

  test('Complex chart serialization', () {
    // Round trip test
    var original = "&inote_1=(120){4}1,2,3,4,5,6,7,8E";
    var simaiFile = SimaiFile(original);
    var chartText = simaiFile.getValue("inote_1");
    var chart = SimaiConvert.deserialize(chartText!);

    var serialized = SimaiConvert.serialize(chart);
    // ignore: avoid_print
    print("Serialized: $serialized");

    // Check if it can be deserialized back
    var chart2 = SimaiConvert.deserialize(serialized);
    expect(chart2.noteCollections.length, chart.noteCollections.length);
    expect(chart2.timingChanges.length, chart.timingChanges.length);
  });

  test('CanReadTouchHold', () {
    var chart = SimaiConvert.deserialize("A1h[#1]");
    expect(chart.noteCollections.length, 1);
    expect(chart.noteCollections[0].length, 1);
    final note = chart.noteCollections[0][0];
    expect(note.location.group, NoteGroup.aSensor);
    expect(note.type, NoteType.hold);
    expect(note.length, closeTo(1.0, 1e-5));
  });

  test('Duration tempo override does not affect subsequent timing', () {
    final chart = SimaiConvert.deserialize("(120)1h[60#4:1],2");
    expect(chart.timingChanges.length, 1);
    expect(chart.timingChanges[0].tempo, 120);
    expect(chart.noteCollections.length, 2);
    expect(chart.noteCollections[0].time, closeTo(0.0, 1e-6));
    expect(chart.noteCollections[0][0].length, closeTo(1.0, 1e-6));
    expect(chart.noteCollections[1].time, closeTo(0.5, 1e-6));
  });

  test('CanReadBreakSlideWithJoiner', () {
    final chart = SimaiConvert.deserialize("4bx-2-6-8[4:9]*s8b[4:9]");
    expect(chart.noteCollections.length, 1);
    expect(chart.noteCollections[0].length, 1);

    final note = chart.noteCollections[0][0];
    expect(note.location.index, 3);
    expect(note.type, NoteType.slide);
    expect((note.styles & NoteStyles.breakHead) != 0, true);
    expect(note.slidePaths.length, 2);
    expect(note.slidePaths[0].type, NoteType.slide);
    expect(note.slidePaths[1].type, NoteType.breakNote);
  });

  test(
    'Slide default delay waits one quarter note regardless subdivisions',
    () {
      final chart = SimaiConvert.deserialize("(60){8}1-2[4:1]");
      expect(chart.noteCollections.length, 1);
      expect(chart.noteCollections[0].length, 1);

      final note = chart.noteCollections[0][0];
      expect(note.slidePaths.length, 1);
      expect(note.slidePaths[0].delay, closeTo(1.0, 1e-6));
    },
  );

  test('Slide default delay uses tempo at note time', () {
    final chart = SimaiConvert.deserialize("(240)1,(60){8}1-2[4:1]");
    expect(chart.noteCollections.length, 2);

    final note = chart.noteCollections[1][0];
    expect(note.slidePaths.length, 1);
    expect(note.slidePaths[0].delay, closeTo(1.0, 1e-6));
  });

  test('SimaiPlayerController clamps speed and maps approachTime', () {
    final chart = SimaiConvert.deserialize("1");
    final controller = SimaiPlayerController(chart: chart);

    controller.speed = 2.0;
    expect(controller.speed, 3.0);
    expect(controller.approachTime, closeTo(1.2, 1e-6));

    controller.speed = 8.0;
    expect(controller.speed, 8.0);
    expect(controller.approachTime, closeTo(0.45, 1e-6));
  });

  test('SimaiPlayerController computes next/previous measure time', () {
    final chart = SimaiConvert.deserialize("(60)1,1");
    final controller = SimaiPlayerController(chart: chart);

    expect(controller.computeNextMeasureTime(0.0), closeTo(4.0, 1e-6));
    expect(controller.computeNextMeasureTime(3.0), closeTo(4.0, 1e-6));
    expect(controller.computePreviousMeasureTime(4.25), closeTo(4.0, 1e-6));
    expect(controller.computePreviousMeasureTime(4.15), closeTo(0.0, 1e-6));
    expect(controller.computePreviousMeasureTime(4.0001), closeTo(0.0, 1e-6));
    expect(controller.computePreviousMeasureTime(6.0), closeTo(4.0, 1e-6));

    expect(controller.computeCurrentMeasureStartTime(2.0), closeTo(0.0, 1e-6));
    expect(controller.computeCurrentMeasureStartTime(4.5), closeTo(4.0, 1e-6));
  });

  test('SimaiPlayerController computes next/previous note time', () {
    final chart = SimaiConvert.deserialize("(60)1,2,3,4");
    final controller = SimaiPlayerController(chart: chart);

    expect(controller.computeNextNoteTime(0.0), closeTo(1.0, 1e-6));
    expect(controller.computeNextNoteTime(0.5), closeTo(1.0, 1e-6));
    expect(controller.computeNextNoteTime(1.0), closeTo(2.0, 1e-6));

    expect(controller.computePreviousNoteTime(3.0), closeTo(2.0, 1e-6));
    expect(controller.computePreviousNoteTime(2.11), closeTo(2.0, 1e-6));
    expect(controller.computePreviousNoteTime(2.09), closeTo(1.0, 1e-6));
    expect(controller.computePreviousNoteTime(2.0001), closeTo(1.0, 1e-6));
  });
}
