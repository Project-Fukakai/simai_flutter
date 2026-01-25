# simai_flutter

[![pub package](https://img.shields.io/pub/v/simai_flutter.svg)](https://pub.dev/packages/simai_flutter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个用于解析、转换和渲染 simai 格式谱面的 Flutter 软件包。使用 Flame 引擎进行渲染。

A Flutter package for parsing, converting, and rendering simai format charts. Supports chart visualization with Flame engine.

## 特性 | Features

- **解析与转换**：支持将 simai 字符串解析为结构化的 `MaiChart` 对象。
- **谱面文件支持**：使用 `SimaiFile` 轻松读取包含多个难度和元数据的 `.txt` 谱面文件。
- **高性能渲染**：基于 [Flame](https://flame-engine.org/) 引擎，提供平滑的 60fps+ 谱面预览。
- **音频同步**：内置 `SimaiPlayerController`，支持音频播放与谱面时间的精确同步。
- **高度可定制**：支持自定义背景、控制按钮和 UI 组件。

## 快速开始 | Getting started

### 安装 | Installation

在你的 `pubspec.yaml` 中添加：

```yaml
dependencies:
  simai_flutter: ^0.1.0
```

或者运行：

```bash
flutter pub add simai_flutter
```

## 使用方法 | Usage

### 1. 解析谱面 | Parsing a Chart

```dart
import 'package:simai_flutter/simai_flutter.dart';

// 解析单个谱面字符串
String chartData = "(140){4}1,2,3,4,E";
MaiChart chart = SimaiConvert.deserialize(chartData);

// 或者从 simai 文件（maidata.txt）中解析
String fileContent = "..."; // 读取文件内容
SimaiFile simaiFile = SimaiFile(fileContent);
String? masterChart = simaiFile.getValue("inote_4");
if (masterChart != null) {
  MaiChart chart = SimaiConvert.deserialize(masterChart);
}
```

### 2. 使用播放器 | Using the Player

```dart
import 'package:simai_flutter/simai_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

// 在 StatefulWidget 中初始化控制器
late SimaiPlayerController _controller;

@override
void initState() {
  super.initState();
  _controller = SimaiPlayerController(
    chart: chart,
    audioSource: AssetSource('music.mp3'),
    backgroundImageProvider: AssetImage('assets/bg.png'),
  );
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: SimaiPlayerPage(controller: _controller),
  );
}

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

## 示例项目 | Example

查看 [example](https://github.com/Project-Fukakai/simai_flutter/tree/main/example) 目录以获取完整的演示应用。

## 贡献 | Contributing

欢迎提交 Issue 或 Pull Request 来完善此项目。

## 许可证 | License

本项目采用 MIT 许可证。详见 [LICENSE](https://github.com/Project-Fukakai/simai_flutter/blob/main/LICENSE) 文件。
