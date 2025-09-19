// lib/services/ipfs_client.dart
//
// Upload dei bytes cifrati su w3up-uploader (tuo server) + endpoint per manifest.
//
// Dipendenze:
//   http: ^1.2.0

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class IpfsUploadResult {
  final bool ok;
  final String? cid;
  final String? url;
  final int? size;
  final String? error;

  IpfsUploadResult(
      {required this.ok, this.cid, this.url, this.size, this.error});
}

class IpfsClient {
  IpfsClient({required this.baseUrl});
  final String baseUrl; // es: http://193.70.113.55:8787

  /// Upload dei bytes cifrati (immutato per compatibilità con main.dart)
  Future<IpfsUploadResult> uploadEncryptedBytes({
    required Uint8List encryptedBytes,
    required String recordId,
    String filename = 'health_payload.enc',
  }) async {
    final uri = Uri.parse('$baseUrl/ipfs/upload');

    final body = jsonEncode({
      'recordId': recordId,
      'name': filename,
      'dataBase64': base64Encode(encryptedBytes),
    });

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      return IpfsUploadResult(
        ok: map['ok'] == true,
        cid: map['cid'] as String?,
        url: map['url'] as String?,
        size: (map['size'] as num?)?.toInt(),
      );
    } else {
      return IpfsUploadResult(
        ok: false,
        error: 'HTTP ${resp.statusCode}: ${resp.body}',
      );
    }
  }

  /// (Opzionale) Salva/aggiorna il MANIFEST (key wraps) sul backend.
  /// Passa un manifest "base" (senza cid) e lo stesso recordId, aggiungi qui il cid.
  Future<bool> uploadManifest({
    required String recordId,
    required String cid,
    required Map<String, dynamic> manifestBase,
  }) async {
    final uri = Uri.parse('$baseUrl/keywraps');
    final payload = {
      'recordId': recordId,
      'cid': cid,
      'manifest': {
        ...manifestBase,
        'cid': cid,
      },
    };
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      return map['ok'] == true;
    }
    return false;
    // NB: main.dart attuale non chiama questo metodo; lo userai quando integri il manifest.
  }
}
