import 'dart:convert';

const geoCacheLifetime = Duration(days: 7);

class GeoCache {
  final Map<String, String> countries = {};
  final Map<String, DateTime> timestamps = {};
  GeoCache();
  factory GeoCache.decode(String text, {DateTime? now}) {
    final cache = GeoCache();
    final current = now ?? DateTime.now();
    try {
      final data = jsonDecode(text);
      if (data is! Map) return cache;
      for (final e in data.entries) {
        // Old entries have no age: discard and refresh once, rather than
        // guessing their creation time and extending them indefinitely.
        if (e.value is! Map) continue;
        final cc = e.value['country'];
        final at = DateTime.tryParse('${e.value['at']}');
        if (cc is! String ||
            !RegExp(r'^[A-Z]{2}$').hasMatch(cc) ||
            at == null ||
            at.isAfter(current) ||
            current.difference(at) > geoCacheLifetime)
          continue;
        cache.countries[e.key.toString()] = cc;
        cache.timestamps[e.key.toString()] = at;
      }
    } catch (_) {}
    return cache;
  }
  void addAll(Map<String, String> values, {DateTime? now}) {
    for (final e in values.entries) {
      countries[e.key] = e.value;
      timestamps[e.key] = now ?? DateTime.now();
    }
  }

  String encode() => jsonEncode({
    for (final e in countries.entries)
      e.key: {'country': e.value, 'at': timestamps[e.key]!.toIso8601String()},
  });
}
