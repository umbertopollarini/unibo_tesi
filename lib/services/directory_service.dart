// lib/services/directory_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../crypto/identity_service.dart';

class DirectoryService {
  static const String baseUrl = 'http://193.70.113.55:8787';

  /// Registra (o aggiorna) la tua identità sul server (pub keys)
  static Future<void> registerSelf() async {
    final entry = await IdentityService.publicDirectoryEntry();
    final uri = Uri.parse('$baseUrl/users/register');
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': entry['userId'],
        'displayName': entry['userId'],
        'pubEd25519': entry['pubEd25519'],
        'pubX25519': entry['pubX25519'],
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Register failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Ottieni le chiavi pubbliche di un utente
  static Future<Map<String, dynamic>> getKeys(String userId) async {
    final uri = Uri.parse('$baseUrl/users/$userId/keys');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('User not found: $userId');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Invia un grant di accesso (aggiunge recipient wrap al manifest)
  static Future<void> postGrant({
    required String recordId,
    required String toUserId,
    required Map<String, dynamic> recipientWrap,
    required String grantSigBase64,
  }) async {
    final uri = Uri.parse('$baseUrl/keywraps/$recordId/grant');
    final payload = {
      'to': toUserId,
      'wrap': recipientWrap,
      'sig': {
        'scheme': 'ed25519',
        'value': grantSigBase64,
      },
    };
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('Grant failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Elenco dei record condivisi con me
  static Future<List<Map<String, dynamic>>> listSharedWithMe(
      String userId) async {
    final uri = Uri.parse('$baseUrl/keywraps/shared-with/$userId');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('shared-with failed: ${resp.statusCode} ${resp.body}');
    }
    final list = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
    return list;
  }
}
