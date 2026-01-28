import 'package:flutter/services.dart';

Future<void> enterFullScreenImpl() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

Future<void> exitFullScreenImpl() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Force back to portrait first to ensure we leave landscape mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // Then allow other orientations again
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
