import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';

import '../crypto/identity_service.dart';
import '../crypto/wrap_service.dart';
import '../crypto/key_manager.dart';

class SharedWithMePage extends StatefulWidget {
  final String backendBaseUrl;
  const SharedWithMePage({super.key, required this.backendBaseUrl});

  @override
  State<SharedWithMePage> createState() => _SharedWithMePageState();
}

class _SharedWithMePageState extends State<SharedWithMePage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await IdentityService.getOrCreateIdentity();
      final uri = Uri.parse(
          '${widget.backendBaseUrl}/keywraps/shared-with/${me.userId}');
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
      final list = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
      setState(() {
        _items = list;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _viewClear(Map<String, dynamic> item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final recordId = item['recordId'] as String;
      final cid = item['cid'] as String;

      // 1) manifest
      final r = await http
          .get(Uri.parse('${widget.backendBaseUrl}/keywraps/$recordId'));
      if (r.statusCode != 200)
        throw Exception('Manifest non trovato (${r.statusCode})');
      final mwrap = jsonDecode(r.body) as Map<String, dynamic>;
      final manifest = (mwrap['manifest'] as Map<String, dynamic>? ?? {});
      final wraps = (manifest['wraps'] as Map<String, dynamic>?);
      if (wraps == null) throw Exception('Wraps mancanti');
      final recipients = (wraps['recipients'] as Map<String, dynamic>? ?? {});

      // 2) unwrap come recipient
      final me = await IdentityService.getOrCreateIdentity();
      final myWrap = recipients[me.userId] as Map<String, dynamic>?;
      if (myWrap == null) throw Exception('Nessun wrap per me');

      final dekBytes = await WrapService.unwrapDekFromRecipient(
        recordId: recordId,
        myX25519: me.x25519,
        recipientWrap: myWrap,
      );

      // 3) scarica blob IPFS
      final candidates = <String>[
        'https://w3s.link/ipfs/$cid',
        'https://$cid.ipfs.w3s.link',
        'https://ipfs.io/ipfs/$cid',
        'https://cloudflare-ipfs.com/ipfs/$cid',
        'https://dweb.link/ipfs/$cid',
      ];

      http.Response? blobRes;
      for (final u in candidates) {
        try {
          final r =
              await http.get(Uri.parse(u)).timeout(const Duration(seconds: 12));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            blobRes = r;
            break;
          }
        } catch (_) {}
      }
      if (blobRes == null) throw Exception('Download IPFS fallito');

      final bytes = blobRes.bodyBytes;
      if (bytes.length < 28) throw Exception('Blob troppo corto');
      final dataNonce = bytes.sublist(0, 12);
      final dataMac = bytes.sublist(bytes.length - 16);
      final dataCipher = bytes.sublist(12, bytes.length - 16);

      // 4) decrypt
      final aead = AesGcm.with256bits();
      final plain = await aead.decrypt(
        SecretBox(dataCipher, nonce: dataNonce, mac: Mac(dataMac)),
        secretKey: SecretKey(dekBytes),
        aad: utf8.encode(recordId),
      );
      final jsonStr = utf8.decode(plain);

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (_) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Text(jsonStr,
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore decrypt: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Condivisi con me')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Nessun record condiviso'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor: Colors.white,
                      title: Text('RecordId: ${it['recordId']}'),
                      subtitle: Text(
                          'Owner: ${it['ownerUserId'] ?? 'sconosciuto'}\nCID: ${it['cid']}'),
                      trailing: ElevatedButton(
                        onPressed: _busy ? null : () => _viewClear(it),
                        child: const Text('Vedi'),
                      ),
                    );
                  },
                ),
      backgroundColor: const Color(0xFFF2F2F7),
    );
  }
}
