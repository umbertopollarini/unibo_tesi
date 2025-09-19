// lib/payload/health_payload.dart
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

class HealthPayload {
  /// Costruisce un payload compatto e deterministico:
  /// {
  ///   "v": 1,
  ///   "from": "ISO8601-UTC",
  ///   "to": "ISO8601-UTC",
  ///   "c": { "HEART_RATE": 12, "STEPS": 345, ... }
  /// }
  static Map<String, dynamic> build({
    required DateTime from,
    required DateTime to,
    required Map<String, int> countByType,
  }) {
    final keys = countByType.keys.toList()..sort();
    final ordered = LinkedHashMap<String, int>();
    for (final k in keys) {
      ordered[k] = countByType[k] ?? 0;
    }

    return <String, dynamic>{
      'v': 1,
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      'c': ordered,
    };
  }

  /// Serializza in bytes in modo stabile (ordine preservato)
  static Uint8List encode(Map<String, dynamic> payload) {
    final jsonStr = jsonEncode(payload);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }
}
