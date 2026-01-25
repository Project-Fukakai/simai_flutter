import 'note_collection.dart';
import '../internal/syntactic_analysis/timing_change.dart';

class MaiChart {
  double? finishTiming;
  List<NoteCollection> noteCollections;
  List<TimingChange> timingChanges;

  MaiChart() : noteCollections = [], timingChanges = [];
}
