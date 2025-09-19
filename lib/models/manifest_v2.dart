// lib/models/manifest_v2.dart
//
// Manifest v2 con recipients (map) e firma Ed25519.

import 'dart:convert';
import 'package:collection/collection.dart';
import '../utils/canonical.dart'; // aggiungi

class ManifestV2 {
  Map<String, dynamic> data;

  ManifestV2(this.data);

  static ManifestV2 fromBase({
    required Map<String, dynamic> base,
    required String recordId,
    required String cid,
    required String ownerUserId,
  }) {
    final m = {
      ...base,
      'v': 2,
      'cid': cid,
      'acl': {
        'owner': ownerUserId,
        'grants': [],
      },
      'wraps': {
        'owner': base['wraps']['owner'],
        // recipients come mappa { userId: wrapJson }
        'recipients': <String, dynamic>{},
      },
      // firma da aggiungere dopo
    };
    return ManifestV2(m);
  }

  List<int> canonicalBytesForSignature() {
    final clone = Map<String, dynamic>.from(data)..remove('sig');
    return canonicalJsonBytes(clone);
  }

  void addRecipient(String userId, Map<String, dynamic> wrapEntry) {
    final rec = (data['wraps']['recipients'] as Map<String, dynamic>);
    rec[userId] = wrapEntry;
    final grants = (data['acl']['grants'] as List);
    // evita doppi grant
    if (grants.firstWhereOrNull((g) => g['to'] == userId) == null) {
      grants.add({'to': userId, 'scope': 'read', 'until': null});
    }
  }

  /// Ritorna i bytes "canonici" per la firma, escludendo il campo 'sig'
  // List<int> canonicalBytesForSignature() {
  //   final clone = Map<String, dynamic>.from(data);
  //   clone.remove('sig');
  //   // JSON canonico semplice (chiavi in ordine lessico non garantito in dart:convert,
  //   // ma sufficiente se firmi lato client e verifichi lato server con lo stesso encoder)
  //   return utf8.encode(jsonEncode(clone));
  // }

  void attachSignature({
    required String byUserId,
    required String signatureBase64,
  }) {
    data['sig'] = {
      'by': byUserId,
      'scheme': 'ed25519',
      'value': signatureBase64,
    };
  }

  Map<String, dynamic> toJson() => data;
}
