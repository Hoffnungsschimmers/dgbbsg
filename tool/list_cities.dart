import 'dart:convert';
import 'dart:io';

void main() {
  final lines = File(r'C:\Users\2540\Downloads\Telegram Desktop\Global-proxyip-443.csv').readAsLinesSync(encoding: utf8);
  final cities = <String, int>{};
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    final cols = <String>[];
    var idx = 0;
    while (idx < line.length) {
      if (line[idx] == '"') {
        final end = line.indexOf('"', idx + 1);
        if (end < 0) { cols.add(line.substring(idx + 1)); break; }
        cols.add(line.substring(idx + 1, end));
        idx = end + 1;
        if (idx < line.length && line[idx] == ',') idx++;
      } else {
        final end = line.indexOf(',', idx);
        if (end < 0) { cols.add(line.substring(idx)); break; }
        cols.add(line.substring(idx, end));
        idx = end + 1;
      }
    }
    if (cols.length > 10) {
      final city = cols[10].trim();
      cities[city] = (cities[city] ?? 0) + 1;
    }
  }
  for (final e in (cities.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) {
    print('${e.key}: ${e.value}');
  }
}
