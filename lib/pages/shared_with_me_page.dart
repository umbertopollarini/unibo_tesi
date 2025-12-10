import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../crypto/identity_service.dart';
import '../crypto/wrap_service.dart';
import '../crypto/key_manager.dart';
import '../theme/app_theme.dart';

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
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusModal),
                ),
              ),
              padding: EdgeInsets.only(
                left: AppTheme.paddingCard,
                right: AppTheme.paddingCard,
                top: AppTheme.paddingCard,
                bottom: AppTheme.paddingCard +
                    MediaQuery.of(context).viewInsets.bottom,
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
                        margin:
                            const EdgeInsets.only(bottom: AppTheme.gapMedium),
                        decoration: BoxDecoration(
                          color: AppTheme.textTertiary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text('Dettagli record', style: AppTheme.cardTitle),
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
                      const SizedBox(height: AppTheme.gapMedium),
                      Text(
                        'Tipi di dato',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppTheme.gapSmall),
                      ...dataByType.entries.map((e) {
                        final entries = (e.value as List).cast<Map>();
                        final count = entries.length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppTheme.gapSmall),
                          padding: const EdgeInsets.all(AppTheme.gapMedium),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppTheme.accentIndigo,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              const SizedBox(width: AppTheme.gapMedium),
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: AppTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                '$count campi',
                                style: AppTheme.caption.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 420),
                        padding: const EdgeInsets.all(AppTheme.gapMedium),
                        decoration: BoxDecoration(
                          color: AppTheme.darkBackground,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard),
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
                    const SizedBox(height: AppTheme.gapMedium),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            label: const Text('Copia JSON'),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: AppTheme.accentIndigo
                                    .withValues(alpha: 0.3),
                              ),
                              foregroundColor: AppTheme.accentIndigo,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMedium),
                              ),
                            ),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: jsonStr));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copiato negli appunti'),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: AppTheme.gapMedium),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 20),
                            label: const Text('Chiudi'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryMedium,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMedium),
                              ),
                            ),
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
    return AppTheme.buildPill(
      label: label,
      value: value,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Condivisi con me'),
      ),
      backgroundColor: AppTheme.backgroundMain,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'Nessun record condiviso',
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.paddingCard,
                    vertical: AppTheme.gapMedium,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppTheme.gapMedium),
                      padding: const EdgeInsets.all(AppTheme.paddingCard),
                      decoration: AppTheme.cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppTheme.buildAvatar(
                                icon: Icons.lock_open_rounded,
                                color: AppTheme.accentTeal,
                                size: 40,
                              ),
                              const SizedBox(width: AppTheme.gapMedium),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Record ${_short(it['recordId'])}',
                                      style: AppTheme.cardSubtitle,
                                    ),
                                    Text(
                                      'Owner: ${it['ownerUserId'] ?? '-'}',
                                      style: AppTheme.caption.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.gapMedium),
                          Row(
                            children: [
                              const Icon(
                                Icons.folder_rounded,
                                size: 16,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'CID ${_short(it['cid'] as String)}',
                                  style: AppTheme.caption.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.gapMedium),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.visibility_rounded,
                                    size: 20,
                                  ),
                                  label: const Text('Apri dati'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryMedium,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.radiusMedium),
                                    ),
                                  ),
                                  onPressed:
                                      _busy ? null : () => _viewClear(it),
                                ),
                              ),
                              const SizedBox(width: AppTheme.gapMedium),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy_rounded, size: 20),
                                label: const Text('CID'),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: AppTheme.accentTeal
                                        .withValues(alpha: 0.3),
                                  ),
                                  foregroundColor: AppTheme.accentTeal,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMedium),
                                  ),
                                ),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                      text: it['cid'] as String));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('CID copiato negli appunti'),
                                    ),
                                  );
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
