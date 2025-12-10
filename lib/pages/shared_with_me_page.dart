import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

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
  Future<void> _showDecodedPayload(
      BuildContext context, String jsonStr, Map<String, dynamic> item) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final summary =
        (data['summary'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final dataByType =
        (data['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final from = data['from'] as String?;
    final to = data['to'] as String?;
    final schema = data['schema'] as String?;
    final totalPoints = summary.values.fold<int>(
        0, (prev, element) => prev + (element as num).toInt());
    final rawToggle = ValueNotifier<bool>(false);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ValueListenableBuilder<bool>(
          valueListenable: rawToggle,
          builder: (_, showRaw, __) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Text('Dettagli record',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => rawToggle.value = !showRaw,
                          child:
                              Text(showRaw ? 'Vista smart' : 'JSON grezzo'),
                        ),
                      ],
                    ),
                    if (!showRaw) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (schema != null)
                            _pill('Schema', schema, Colors.indigo),
                          _pill('Da', from ?? '-', Colors.blueGrey),
                          _pill('A', to ?? '-', Colors.blueGrey),
                          _pill('Totale punti', '$totalPoints',
                              Colors.deepPurple),
                          _pill('CID', _short(item['cid'] as String),
                              Colors.teal),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tipi di dato',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      ...dataByType.entries.map((e) {
                        final entries = (e.value as List).cast<Map>();
                        final count = entries.length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: Colors.indigo,
                                    borderRadius: BorderRadius.circular(20)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text('$count campi',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      }),
                    ] else ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 420),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1225),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            const JsonEncoder.withIndent('  ')
                                .convert(json.decode(jsonStr)),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('Copia JSON'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: jsonStr));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Copiato negli appunti')));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.lock_open_outlined),
                            label: const Text('Chiudi'),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

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
      await _showDecodedPayload(context, jsonStr, item);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore decrypt: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _short(String s, {int head = 8, int tail = 6}) {
    if (s.length <= head + tail) return s;
    return '${s.substring(0, head)}…${s.substring(s.length - tail)}';
  }

  Widget _pill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: color.withOpacity(0.9),
                  fontSize: 11,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Condivisi con me'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF7F8FB),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text('Nessun record condiviso',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 6))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.teal.shade50,
                                child: const Icon(Icons.lock_open,
                                    color: Colors.teal),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Record ${_short(it['recordId'])}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    Text('Owner: ${it['ownerUserId'] ?? '-'}',
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.folder_outlined,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'CID ${_short(it['cid'] as String)}',
                                  style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon:
                                      const Icon(Icons.visibility_outlined),
                                  label: const Text('Apri dati'),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF0B5394)),
                                  onPressed:
                                      _busy ? null : () => _viewClear(it),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy),
                                label: const Text('CID'),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: it['cid'] as String));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('CID copiato negli appunti')));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
