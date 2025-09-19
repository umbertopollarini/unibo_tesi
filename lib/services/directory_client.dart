// lib/services/directory_client.dart
//
// Client per rubrica/chiavi pubbliche utenti.

import 'dart:convert';
import 'package:http/http.dart' as http;

class DirectoryClient {
  final String baseUrl;
  DirectoryClient(this.baseUrl);

  /// Ricerca per handle/email/username
  Future<UserDirectoryEntry?> searchOne(String query) async {
    final uri =
        Uri.parse('$baseUrl/users/search?q=${Uri.encodeQueryComponent(query)}');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final list = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    final m = list.first;
    return UserDirectoryEntry(
      userId: m['userId'] as String,
      displayName: m['displayName'] as String? ?? m['userId'] as String,
      pubEd25519B64: m['pubEd25519'] as String,
      pubX25519B64: m['pubX25519'] as String,
    );
  }

  /// Ottenere chiavi pubbliche via userId
  Future<UserDirectoryEntry?> getByUserId(String userId) async {
    final uri = Uri.parse('$baseUrl/users/$userId/keys');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return UserDirectoryEntry(
      userId: m['userId'] as String,
      displayName: m['displayName'] as String? ?? userId,
      pubEd25519B64: m['pubEd25519'] as String,
      pubX25519B64: m['pubX25519'] as String,
    );
  }
}

class UserDirectoryEntry {
  final String userId;
  final String displayName;
  final String pubEd25519B64;
  final String pubX25519B64;

  const UserDirectoryEntry({
    required this.userId,
    required this.displayName,
    required this.pubEd25519B64,
    required this.pubX25519B64,
  });
}
