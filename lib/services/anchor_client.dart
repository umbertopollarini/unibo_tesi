import 'dart:convert';
import 'package:http/http.dart' as http;

class AnchorClient {
  final String baseUrl; // es: http://server:8787
  final http.Client httpClient;

  AnchorClient({required this.baseUrl, http.Client? httpClient})
      : httpClient = httpClient ?? http.Client();

  Future<BigInt> getUserNonce(String ownerAddress) async {
    final uri = Uri.parse('$baseUrl/nonce/$ownerAddress');
    final resp = await httpClient.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('getUserNonce failed: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return BigInt.parse(data['nonce'] as String);
  }

  Future<String> prepareAnchor({
    required String owner,
    required String recordIdHex,
    required String manifestHashHex,
    required String cid,
  }) async {
    final uri = Uri.parse('$baseUrl/anchor/prepare');
    final body = jsonEncode({
      'owner': owner,
      'recordId': recordIdHex,
      'manifestHash': manifestHashHex,
      'cid': cid,
    });
    final resp = await httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode != 200) {
      throw Exception('prepareAnchor failed: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['payloadHash'] as String;
  }

  Future<String> anchorManifestFor({
    required String owner,
    required String recordIdHex,
    required String manifestHashHex,
    required String cid,
    required String signatureHex,
  }) async {
    final uri = Uri.parse('$baseUrl/anchorManifestFor');
    final body = jsonEncode({
      'owner': owner,
      'recordId': recordIdHex,
      'manifestHash': manifestHashHex,
      'cid': cid,
      'signature': signatureHex,
    });
    final resp = await httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode != 200) {
      throw Exception('anchorManifestFor failed: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['txHash'] as String;
  }
}
