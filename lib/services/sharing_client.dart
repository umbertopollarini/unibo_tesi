// lib/services/sharing_client.dart
//
// Endpoint per grant/revoke e upload manifest firmato.

import 'dart:convert';
import 'package:http/http.dart' as http;

class SharingClient {
  final String baseUrl;
  SharingClient(this.baseUrl);

  /// Upload/aggiornamento manifest firmato
  /// Il server si aspetta: { recordId, cid, manifest }
  Future<bool> uploadSignedManifest({
    required String recordId,
    required String cid,
    required Map<String, dynamic> manifestJson,
  }) async {
    final uri = Uri.parse('$baseUrl/keywraps');
    final body = jsonEncode({
      'recordId': recordId,
      'cid': cid,
      'manifest': manifestJson,
    });

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode != 200) {
      // print('uploadSignedManifest FAILED: ${resp.statusCode} ${resp.body}');
      return false;
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return m['ok'] == true;
  }

  /// Grant "delta": aggiunge un recipient wrap per recordId
  Future<bool> grantRecipient({
    required String recordId,
    required String recipientUserId,
    required Map<String, dynamic> recipientWrap,
    required String signatureBase64,
  }) async {
    final uri = Uri.parse('$baseUrl/keywraps/$recordId/grant');
    final body = jsonEncode({
      'to': recipientUserId,
      'wrap': recipientWrap,
      'sig': {
        'scheme': 'ed25519',
        'value': signatureBase64,
      }
    });

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode != 200) {
      // print('grantRecipient FAILED: ${resp.statusCode} ${resp.body}');
      return false;
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return m['ok'] == true;
  }
}
