import 'structures/mai_chart.dart';
import 'internal/lexical_analysis/tokenizer.dart';
import 'internal/syntactic_analysis/deserializer.dart';
import 'internal/syntactic_analysis/serializer.dart';

class SimaiConvert {
  static MaiChart deserialize(String value) {
    var tokens = Tokenizer(value).getTokens();
    var chart = Deserializer(tokens).getChart();
    return chart;
  }

  static String serialize(MaiChart chart) {
    var serializer = Serializer();
    var buffer = StringBuffer();
    serializer.serialize(chart, buffer);
    return buffer.toString();
  }
}
