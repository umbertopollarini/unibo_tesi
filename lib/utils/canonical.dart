// lib/utils/canonical.dart
//
// Utility per firmare strutture JSON semplici.

import 'dart:convert';
// lib/utils/canonical.dart

dynamic _canonicalize(dynamic v) {
  if (v is Map) {
    final keys = v.keys.map((e) => e.toString()).toList()..sort();
    final out = <String, dynamic>{};
    for (final k in keys) {
      out[k] = _canonicalize(v[k]);
    }
    return out;
  } else if (v is List) {
    return v.map(_canonicalize).toList(growable: false);
  }
  return v; // string/num/bool/null
}

String canonicalJsonString(Map<String, dynamic> m) =>
    jsonEncode(_canonicalize(m));

List<int> canonicalJsonBytes(Map<String, dynamic> m) =>
    utf8.encode(canonicalJsonString(m));

// String base64OfJson(Map<String, dynamic> m) =>
//     base64Encode(utf8.encode(jsonEncode(m)));
