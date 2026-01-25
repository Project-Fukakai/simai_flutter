import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:audioplayers/audioplayers.dart';
import 'package:simai_flutter/simai_flutter.dart';

void main() {
  runApp(const MaterialApp(home: ExampleApp()));
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  SimaiPlayerController? _controller;
  Source? _audioSource;
  ImageProvider? _bgImageProvider;
  double _chartOffset = 0.0;
  Key _playerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadChart();
  }

  Future<void> _loadChart() async {
    // Load from assets (works on Web, Mobile, Desktop)
    const assetPath = 'assets/Never Give Up!/maidata.txt';

    try {
      final content = await rootBundle.loadString(assetPath);
      var simaiFile = SimaiFile(content);

      // Try loading Master (4) first, then others
      // Priorities: 4 (Master), 3 (Expert), 5 (Re:Master), 2 (Advanced), 1 (Basic)
      var chartText = simaiFile.getValue("inote_6");
      var firstStr = simaiFile.getValue("first");
      double offset = 0.0;
      if (firstStr != null) {
        offset = double.tryParse(firstStr) ?? 0.0;
      }

      if (chartText != null) {
        final chart = SimaiConvert.deserialize(chartText);
        setState(() {
          _chartOffset = offset;
          _audioSource = AssetSource('Never Give Up!/track.mp3');
          _bgImageProvider = const AssetImage('assets/Never Give Up!/bg.png');
          _controller?.dispose();
          _controller = SimaiPlayerController(
            chart: chart,
            audioSource: _audioSource,
            backgroundImageProvider: _bgImageProvider,
            initialChartTime: -_chartOffset,
          )..title = "Never Give Up!";
          _playerKey = UniqueKey();
        });
        return;
      }
    } catch (e) {
      debugPrint("Error loading chart from assets: $e");
    }

    // Fallback to sample chart if file load fails
    const sampleChart = """
&inote_1=(140){4}
1,2,3,4,5,6,7,8,
1h[4:1],2h[4:1],3h[4:1],4h[4:1],
1b,2b,3b,4b,
C,A1,A2,A3,A4,A5,A6,A7,A8,
B1,B2,B3,B4,B5,B6,B7,B8,
1-4[4:1],2-5[4:1],
E
""";

    var simaiFile = SimaiFile(sampleChart);
    var chartText = simaiFile.getValue("inote_1");
    if (chartText != null) {
      final chart = SimaiConvert.deserialize(chartText);
      setState(() {
        _chartOffset = 0.0;
        _audioSource = null;
        _bgImageProvider = null;
        _controller?.dispose();
        _controller = SimaiPlayerController(
          chart: chart,
          audioSource: _audioSource,
          backgroundImageProvider: _bgImageProvider,
          initialChartTime: -_chartOffset,
        );
        _playerKey = UniqueKey();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : SimaiPlayerPage(key: _playerKey, controller: _controller!),
    );
  }
}
