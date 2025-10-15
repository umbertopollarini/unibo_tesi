// lib/services/sharing_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class UploadManifestResponse {
  final bool ok;
  final bool? verified;
  final String? txHash; // <-- nuovo
  UploadManifestResponse({required this.ok, this.verified, this.txHash});
}

class GrantResponse {
  final bool ok;
  final String? txHash; // <-- nuovo
  GrantResponse({required this.ok, this.txHash});
}

class TxStatus {
  final String status; // 'pending' | 'mined' | 'failed'
  final int? blockNumber;
  TxStatus({required this.status, this.blockNumber});
  bool get isPending => status == 'pending';
  bool get isMined => status == 'mined';
}

class SharingClient {
  final String baseUrl;
  SharingClient(this.baseUrl);

  Future<UploadManifestResponse> uploadSignedManifest({
    required String recordId,
    required String cid,
    required Map<String, dynamic> manifestJson,
  }) async {
    final uri = Uri.parse('$baseUrl/keywraps');
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'recordId': recordId, 'cid': cid, 'manifest': manifestJson}),
    );

    if (resp.statusCode != 200) {
      return UploadManifestResponse(ok: false);
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    final chain = (m['chain'] as Map?) ?? {};
    return UploadManifestResponse(
      ok: m['ok'] == true,
      verified: m['verified'] as bool?,
      txHash: chain['txHash'] as String?,
    );
  }

  Future<GrantResponse> grantRecipient({
    required String recordId,
    required String recipientUserId,
    required Map<String, dynamic> recipientWrap,
    required String signatureBase64,
  }) async {
    final uri = Uri.parse('$baseUrl/keywraps/$recordId/grant');
    final body = jsonEncode({
      'to': recipientUserId,
      'wrap': recipientWrap,
      'sig': {'scheme': 'ed25519', 'value': signatureBase64}
    });

    final resp = await http.post(uri,
        headers: {'Content-Type': 'application/json'}, body: body);

    if (resp.statusCode != 200) {
      return GrantResponse(ok: false);
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    final chain = (m['chain'] as Map?) ?? {};
    return GrantResponse(
        ok: m['ok'] == true, txHash: chain['txHash'] as String?);
  }

  Future<TxStatus> getTxStatus(String txHash) async {
    final uri = Uri.parse('$baseUrl/chain/tx/$txHash');
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final m = jsonDecode(resp.body);
      if (m['found'] == true) {
        return TxStatus(
            status: m['status'] as String,
            blockNumber: (m['blockNumber'] as num?)?.toInt());
      }
    }
    return TxStatus(status: 'pending');
  }
}
