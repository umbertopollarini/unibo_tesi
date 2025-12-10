import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'crypto/encryption_service.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'crypto/key_manager.dart';

//

import 'payload/health_payload.dart';
import 'services/ipfs_client.dart';
import 'models/manifest_v2.dart';
import 'services/directory_client.dart';
import 'services/sharing_client.dart';
import 'utils/canonical.dart';
import 'services/directory_service.dart';
import 'crypto/identity_service.dart';
import 'crypto/wrap_service.dart';
import 'services/anchor_client.dart';
import 'services/ethereum_identity.dart';
import 'pages/shared_with_me_page.dart';
import 'theme/app_theme.dart';

//
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart'; // per deep-link
import 'package:web3dart/crypto.dart' as web3crypto;
//

void main() {
  runApp(const HealthBlockchainApp());
}

class HealthBlockchainApp extends StatelessWidget {
  const HealthBlockchainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Blockchain',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HealthHomePage(),
    );
  }
}

class UploadedRecord {
  final String recordId;
  final String cid;
  final DateTime createdAt;

  UploadedRecord(
      {required this.recordId, required this.cid, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'cid': cid,
        'createdAt': createdAt.toIso8601String(),
      };

  static UploadedRecord fromJson(Map<String, dynamic> m) => UploadedRecord(
        recordId: m['recordId'] as String,
        cid: m['cid'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
      );
}

class HealthHomePage extends StatefulWidget {
  const HealthHomePage({super.key});

  @override
  State<HealthHomePage> createState() => _HealthHomePageState();
}

class _HealthHomePageState extends State<HealthHomePage>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _dataLoaded = false;
  String _statusMessage = "Pronto per il caricamento";
  Map<String, dynamic> _healthData = {};
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  Map<String, dynamic>? _manifestBase; // ← manifest per i wrap chiave (owner)

  static const String kBackendBaseUrl = 'http://193.70.113.55:8787';
  static const int kAnchorChainId = 11155111; // Sepolia
  static const String kAnchorContractAddress =
      '0x3160D7306ab050883ddfb95AADe964117eb3FDdf';

  // Map<String, dynamic>? _manifestBase;
  List<UploadedRecord> _uploadedRecords = [];

  bool _uploadingIpfs = false;
  bool _uploadedOk = false;

  Uint8List? _encryptedBytes; // risultato cifratura da inviare a IPFS
  String? _ipfsCid;

  DateTime? _lastSync;

  // 🔹 Nuovi campi per payload pronto alla cifratura
  Map<String, dynamic>? _payload;
  Uint8List? _payloadBytes;

  String? _myUserId;
  EthereumIdentity? _ethIdentity;

  static const List<HealthDataType> types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
    HealthDataType.BODY_MASS_INDEX,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_WALKING_RUNNING,
  ];

  final _fln = FlutterLocalNotificationsPlugin();
  final Map<String, String> _pendingTxByRecord = {}; // recordId -> txHash
  final Set<String> _minedTx = {}; // per non notificare due volte

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _animationController.forward();
    _initializeHealthData();
    _initNotifications();
    _loadLastSync();
    _loadUploadedRecords();

    // registra/aggiorna la mia identità pubblica sul server (una volta all'avvio)
    DirectoryService.registerSelf().catchError((e) {
      debugPrint('Directory register failed: $e');
    });

    _loadMyUserId();
    _loadEthereumIdentity();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pollTxUntilMined(String recordId, String txHash) async {
    final api = SharingClient(kBackendBaseUrl);
    final etherscan = 'https://sepolia.etherscan.io/tx/$txHash';

    // poll semplice ogni 6s fino a mined/failed (timeout 3 min)
    final started = DateTime.now();
    while (mounted) {
      final st = await api.getTxStatus(txHash);
      if (st.isMined) {
        if (!_minedTx.contains(txHash)) {
          _minedTx.add(txHash);
          await _showTxMinedNotif(
            title: 'Record ancorato on-chain',
            etherscanUrl: etherscan,
          );
        }
        setState(() {}); // per aggiornare badge UI
        break;
      }
      if (st.status == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Anchor on-chain fallito')),
        );
        break;
      }
      if (DateTime.now().difference(started).inMinutes >= 3) {
        // smetto di pollare dopo 3 minuti
        break;
      }
      await Future.delayed(const Duration(seconds: 6));
    }
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: ios);
    await _fln.initialize(initSettings,
        onDidReceiveNotificationResponse: (resp) async {
      final payload = resp.payload;
      if (payload != null && payload.startsWith('https://')) {
        final uri = Uri.parse(payload);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    });
  }

  Future<void> _showTxMinedNotif(
      {required String title, required String etherscanUrl}) async {
    const androidDetails = AndroidNotificationDetails(
      'chain_anchor',
      'On-chain Anchors',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      'Tocco per aprire su Etherscan',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: etherscanUrl,
    );
  }

  Future<void> _loadMyUserId() async {
    try {
      final id = await IdentityService.getMyUserId();
      if (!mounted) return;
      setState(() => _myUserId = id);
    } catch (e) {
      debugPrint('Errore lettura userId: $e');
    }
  }

  Future<void> _loadEthereumIdentity() async {
    try {
      final eth = await IdentityService.getOrCreateEthereumIdentity();
      if (!mounted) return;
      setState(() => _ethIdentity = eth);
    } catch (e) {
      debugPrint('Errore caricamento identità Ethereum: $e');
    }
  }

  void _copyMyUserId() {
    if (_myUserId == null) return;
    Clipboard.setData(ClipboardData(text: _myUserId!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User ID copiato negli appunti')),
    );
  }

  String _formatDate(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} "
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  Future<void> _loadLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString('last_sync_iso');
    if (iso != null) {
      setState(() => _lastSync = DateTime.parse(iso));
    }
  }

  Future<void> _initializeHealthData() async {
    await _checkHealthPermissions();
  }

  Future<bool> _checkHealthPermissions() async {
    try {
      final requested = await Health().requestAuthorization(
        types,
        permissions: types.map((e) => HealthDataAccess.READ).toList(),
      );

      setState(() {
        _statusMessage = requested
            ? "Permessi concessi - Pronto per il caricamento"
            : "Permessi necessari per continuare";
      });

      return requested;
    } catch (e) {
      setState(() {
        _statusMessage = "Errore nei permessi: ${e.toString()}";
      });
      return false;
    }
  }

  // funzione hash
  String _sha256Hex(List<int> data) => crypto.sha256.convert(data).toString();

  // funzione cifratura payload
  Future<void> _encryptCurrentPayload() async {
    if (_payloadBytes == null) return;

    try {
      final recordId = _sha256Hex(_payloadBytes!);

      // Cifra il payload e costruisci il manifest "base" (senza firma/CID).
      final enc = await EncryptionService.encryptPayload(
        payloadBytes: _payloadBytes!,
        recordId: recordId,
      );
      final manifestBase =
          enc.buildManifestBase(); // ← firma/cid in _uploadToIpfs

      setState(() {
        _statusMessage =
            "Payload cifrato! RecordId: $recordId (pronto per IPFS)";
        _encryptedBytes = enc.encryptedBytes;
        _manifestBase = manifestBase; // <-- solo base, niente firma qui
        _uploadedOk = false;
      });

      if (!mounted) return;

      // Notifica visiva
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Payload cifrato!'),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          duration: const Duration(seconds: 3),
          elevation: 4,
        ),
      );

      print("Payload cifrato! RecordId: $recordId (pronto per IPFS)");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore cifratura: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String?> _anchorManifestWithUserSignature({
    required ManifestV2 manifest,
    required String recordId,
    required String cid,
  }) async {
    final ethIdentity = await IdentityService.getOrCreateEthereumIdentity();
    _ethIdentity ??= ethIdentity;

    if (kAnchorContractAddress ==
        '0x0000000000000000000000000000000000000000') {
      throw Exception(
          'Imposta kAnchorContractAddress con l\'indirizzo AnchorRegistry');
    }

    final ownerAddress = ethIdentity.address.hex;
    final anchorClient = AnchorClient(baseUrl: kBackendBaseUrl);

    final manifestBytes =
        Uint8List.fromList(canonicalJsonBytes(manifest.toJson()));
    final manifestHash = web3crypto.keccak256(manifestBytes);
    final manifestHashHex =
        web3crypto.bytesToHex(manifestHash, include0x: true);

    final recordIdHex = _normalizeRecordIdHex(recordId);

    // Richiedi al backend il payloadHash ufficiale
    final payloadHashHex = await anchorClient.prepareAnchor(
      owner: ownerAddress,
      recordIdHex: recordIdHex,
      manifestHashHex: manifestHashHex,
      cid: cid,
    );

    final payloadHashBytes = web3crypto.hexToBytes(payloadHashHex);

    debugPrint('--- Anchor manifest with user signature ---');
    debugPrint('owner: $ownerAddress');
    debugPrint('recordIdHex: $recordIdHex');
    debugPrint('manifestHashHex: $manifestHashHex');
    debugPrint('cid: $cid');
    debugPrint('payloadHash (from backend): $payloadHashHex');

    final sigBytes =
        await ethIdentity.privateKey.signPersonalMessage(payloadHashBytes);
    final signatureHex = web3crypto.bytesToHex(sigBytes, include0x: true);

    debugPrint('signatureHex: $signatureHex');
    debugPrint('signature length: ${sigBytes.length}');

    final txHash = await anchorClient.anchorManifestFor(
      owner: ownerAddress,
      recordIdHex: recordIdHex,
      manifestHashHex: manifestHashHex,
      cid: cid,
      signatureHex: signatureHex,
    );
    return txHash;
  }

  String _normalizeRecordIdHex(String recordId) {
    final clean = recordId.toLowerCase().replaceFirst('0x', '');
    if (clean.length != 64) {
      throw Exception(
          'recordId deve essere 32 byte hex (64 char), got ${clean.length}');
    }
    return '0x$clean';
  }


  Future<void> _uploadToIpfs() async {
    // prima di uploadare il manifest
    await DirectoryService.registerSelf();

    if (_encryptedBytes == null || _payloadBytes == null) return;

    setState(() {
      _uploadingIpfs = true;
      _uploadedOk = false; // ⬅️ reset
    });

    final recordId = _sha256Hex(_payloadBytes!);
    final client = IpfsClient(baseUrl: kBackendBaseUrl);
    try {
      final res = await client.uploadEncryptedBytes(
        encryptedBytes: _encryptedBytes!,
        recordId: recordId,
        filename: 'health_payload.enc',
      );

      if (!mounted) return;
      if (res.ok && res.cid != null) {
        setState(() {
          _ipfsCid = res.cid;
          _uploadedOk = true; // ⬅️ segnala successo
        });

        // ⬇️ INVIA anche il MANIFEST al backend (se presente)
        // ⬇️ INVIA anche il MANIFEST firmato al backend (se presente)
        // ⬇️ INVIA anche il MANIFEST firmato al backend (se presente)
        if (_manifestBase != null) {
          // Costruisci manifest v2 + firma
          final myId = await IdentityService.getOrCreateIdentity();
          final man = ManifestV2.fromBase(
            base: _manifestBase!,
            recordId: recordId,
            cid: res.cid!,
            ownerUserId: myId.userId,
          );

          final toSign = man.canonicalBytesForSignature();
          final sigBytes =
              await IdentityService.signBytes(Uint8List.fromList(toSign));
          man.attachSignature(
            byUserId: myId.userId,
            signatureBase64: base64Encode(sigBytes),
          );

          final sharing = SharingClient(kBackendBaseUrl);
          // final saved = await sharing.uploadSignedManifest(
          //   recordId: recordId,
          //   cid: res.cid!,
          //   manifestJson: man.toJson(),
          // );

          // final saved =
          //     await SharingClient(kBackendBaseUrl).uploadSignedManifest(
          //   recordId: recordId,
          //   cid: res.cid!,
          //   manifestJson: man.toJson(),
          // );

          final saved = await sharing.uploadSignedManifest(
            recordId: recordId,
            cid: res.cid!,
            manifestJson: man.toJson(),
          );

          if (saved.ok && mounted) {
            // /keywraps persiste manifest + keywrap off-chain
            // /anchorManifestFor registra l'anchor on-chain (owner firma, broker inoltra)
            String? txHash = saved.txHash;
            try {
              final anchorTx = await _anchorManifestWithUserSignature(
                manifest: man,
                recordId: recordId,
                cid: res.cid!,
              );
              txHash = anchorTx ?? txHash;
            } catch (e) {
              debugPrint('⚠️ Anchor relayed fallito: $e');
            }

            if (txHash != null) {
              // memorizza e parte il polling
              _pendingTxByRecord[recordId] = txHash;
              _pollTxUntilMined(recordId, txHash);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('🔐 Manifest firmato salvato (anchor in corso)')),
            );
          } else {
            debugPrint('⚠️ Salvataggio/anchor manifest fallito');
          }
        }

        await _rememberUploadedRecord(recordId, res.cid!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Caricato su IPFS\nCID: ${res.cid}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            duration: const Duration(seconds: 4),
            elevation: 4,
          ),
        );
        print('IPFS CID: ${res.cid}, URL: ${res.url}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Upload fallito: ${res.error ?? 'errore sconosciuto'}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Errore upload: $e'),
            behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _uploadingIpfs = false); // ⬅️ STOP loading
    }
  }

  Future<void> _loadHealthData() async {
    setState(() {
      _isLoading = true;
      _dataLoaded = false;
      _encryptedBytes = null;
      _ipfsCid = null;
      _manifestBase = null; // ← reset
    });

    // Mostra lo spinner per almeno 1.5s
    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      final hasPermissions = await _checkHealthPermissions();
      if (!hasPermissions) {
        throw Exception(
          "Permessi HealthKit non concessi. Vai in Impostazioni > Privacy e sicurezza > Salute per abilitarli.",
        );
      }

      final now = DateTime.now();

      // ⏱️ Applica overlap per catturare eventuali backfill
      final lastSyncOriginal = _lastSync; // salva per il filtro anti-duplicati
      const overlap = Duration(hours: 48);
      final start = (lastSyncOriginal != null)
          ? lastSyncOriginal.subtract(overlap)
          : now.subtract(const Duration(days: 7));

      print("=== INIZIO CARICAMENTO DATI SANITARI ===");
      print("Query Health: $start -> $now (overlap ${overlap.inHours}h)");

      // Fetch
      List<HealthDataPoint> healthDataPoints =
          await Health().getHealthDataFromTypes(
        types: types,
        startTime: start,
        endTime: now,
      );

      // 🔎 Filtra fuori i duplicati: prendi solo ciò che è *successivo* all'ultima sync reale
      if (lastSyncOriginal != null) {
        healthDataPoints = healthDataPoints
            .where((dp) => dp.dateTo.isAfter(lastSyncOriginal))
            .toList();
      }

      print("Dati (post-filtro): ${healthDataPoints.length} punti");

      // Fallback solo al primo avvio (se non abbiamo _lastSync e non è uscito nulla)
      if (healthDataPoints.isEmpty && lastSyncOriginal == null) {
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        print("Fallback 30 giorni: $thirtyDaysAgo -> $now");
        healthDataPoints = await Health().getHealthDataFromTypes(
          types: types,
          startTime: thirtyDaysAgo,
          endTime: now,
        );
        print("Dati fallback 30 giorni: ${healthDataPoints.length}");
      }

      // Organizza i dati
      final Map<String, dynamic> organizedData = {};
      final Map<String, int> dataCount = {};

      for (final dp in healthDataPoints) {
        final typeKey = dp.type.name;
        organizedData.putIfAbsent(typeKey, () => []);
        dataCount[typeKey] = (dataCount[typeKey] ?? 0) + 1;

        organizedData[typeKey].add({
          'value': dp.value,
          'unit': dp.unit.name,
          'dateFrom': dp.dateFrom.toIso8601String(),
          'dateTo': dp.dateTo.toIso8601String(),
        });
      }

      // 📦 Costruisci payload compatto/deterministico per cifratura
      // fromEff: l'intervallo "logico" dei dati nuovi (dopo l'ultima sync reale)
      final fromEff = lastSyncOriginal ?? start;
      final payload = {
        'schema': 'health.v2',
        'from': fromEff.toIso8601String(),
        'to': now.toIso8601String(),
        'summary': dataCount, // riepilogo
        'data': organizedData, // <-- tutti i punti per tipo
      };
      final payloadBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(payload)),
      );

      // 💾 Persisti ultima sincronizzazione (ora corrente)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync_iso', now.toIso8601String());

      setState(() {
        _lastSync = now;
        _healthData = {
          'totalDataPoints': healthDataPoints.length,
          'dataByType': organizedData,
          'countByType': dataCount,
          'fetchDate': now.toIso8601String(),
        };

        // salva payload per gli step successivi (cifratura/upload)
        _payload = payload;
        _payloadBytes = payloadBytes;

        _isLoading = false;
        _dataLoaded = true;
        _statusMessage = healthDataPoints.isEmpty
            ? "Nessun dato sanitario nuovo trovato."
            : "Dati caricati con successo! ${healthDataPoints.length} punti dati trovati";
      });

      if (healthDataPoints.isNotEmpty) {
        HapticFeedback.mediumImpact();
      }

      // Debug opzionale
      print("Payload JSON: ${jsonEncode(payload)}");
      print("Payload bytes: ${payloadBytes.length} byte");
      print("=== DATI SANITARI CARICATI ===");
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Errore nel caricamento: ${e.toString()}";
      });
      print("Errore nel caricamento dati sanitari: $e");
    }
  }

  Widget _buildHealthDataSummary() {
    if (!_dataLoaded) return const SizedBox.shrink();

    final countByType =
        (_healthData['countByType'] as Map<String, int>? ?? {});
    final totalPoints = _healthData['totalDataPoints'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppTheme.paddingScreen, 0, AppTheme.paddingScreen, AppTheme.gapMedium),
      padding: const EdgeInsets.all(AppTheme.paddingCardLarge),
      decoration: BoxDecoration(
        gradient: AppTheme.gradientDark,
        borderRadius: BorderRadius.circular(AppTheme.radiusCardLarge),
        boxShadow: AppTheme.shadowCardLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.gapMedium),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppTheme.gapMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Snapshot sanitario pronto",
                      style: AppTheme.cardTitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_lastSync != null)
                      Text(
                        "Ultima sync: ${_formatDate(_lastSync!)}",
                        style: AppTheme.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.gapMedium,
                  vertical: AppTheme.gapSmall,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.data_exploration_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "$totalPoints pts",
                      style: AppTheme.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapLarge),
          Wrap(
            spacing: AppTheme.gapMedium,
            runSpacing: AppTheme.gapMedium,
            children: countByType.entries
                .map(
                  (e) => Container(
                    width: 110,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.gapMedium,
                      vertical: AppTheme.gapMedium,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTypeDisplayName(e.key),
                          style: AppTheme.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${e.value}',
                          style: AppTheme.cardTitle.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppTheme.gapMedium),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 20),
                  label: const Text('Mostra JSON'),
                  onPressed: _payload == null
                      ? null
                      : () => _showPayloadJson(_payload!),
                ),
              ),
              const SizedBox(width: AppTheme.gapMedium),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  label: const Text('Pronto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryDark,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  onPressed: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showPayloadJson(Map<String, dynamic> payload) async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
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
            bottom: AppTheme.paddingCard + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppTheme.gapMedium),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Text('Payload JSON', style: AppTheme.cardTitle),
                const SizedBox(height: AppTheme.gapMedium),
                Container(
                  constraints: const BoxConstraints(maxHeight: 420),
                  padding: const EdgeInsets.all(AppTheme.gapMedium),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      jsonStr,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copia'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: jsonStr));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copiato')));
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close),
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
  }

  String _getTypeDisplayName(String type) {
    const Map<String, String> displayNames = {
      'STEPS': 'Passi',
      'HEART_RATE': 'Frequenza cardiaca',
      'BLOOD_PRESSURE_SYSTOLIC': 'Pressione sistolica',
      'BLOOD_PRESSURE_DIASTOLIC': 'Pressione diastolica',
      'WEIGHT': 'Peso',
      'HEIGHT': 'Altezza',
      'BODY_MASS_INDEX': 'BMI',
      'ACTIVE_ENERGY_BURNED': 'Calorie bruciate',
      'DISTANCE_WALKING_RUNNING': 'Distanza percorsa',
    };
    return displayNames[type] ?? type;
  }

  Future<void> _loadUploadedRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('uploaded_records');
    if (s == null) return;
    final List list = jsonDecode(s) as List;
    setState(() {
      _uploadedRecords = list
          .map((e) => UploadedRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _rememberUploadedRecord(String recordId, String cid) async {
    final rec =
        UploadedRecord(recordId: recordId, cid: cid, createdAt: DateTime.now());
    setState(() {
      // evita duplicati per lo stesso recordId
      _uploadedRecords.removeWhere((r) => r.recordId == recordId);
      _uploadedRecords.insert(0, rec);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'uploaded_records',
      jsonEncode(_uploadedRecords.map((r) => r.toJson()).toList()),
    );
  }

  void _openRecordsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordsPage(
          backendBaseUrl: kBackendBaseUrl,
          records: _uploadedRecords,
          pendingTxByRecord: Map<String, String>.from(_pendingTxByRecord),
          minedTx: Set<String>.from(_minedTx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundMain,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header Premium
              Container(
                padding: const EdgeInsets.all(AppTheme.paddingScreen),
                child: Column(
                  children: [
                    const SizedBox(height: AppTheme.gapLarge),
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: AppTheme.gradientPrimary,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCardLarge),
                          boxShadow: AppTheme.shadowCardMedium,
                        ),
                        child: const Icon(
                          Icons.health_and_safety_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.gapLarge),
                    const Text(
                      "Health Blockchain",
                      style: AppTheme.headingLarge,
                    ),
                    const SizedBox(height: AppTheme.gapSmall),
                    const Text(
                      "Dati sanitari sicuri e decentralizzati",
                      style: AppTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),

                    if (_myUserId != null) ...[
                      const SizedBox(height: AppTheme.gapMedium),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppTheme.paddingCard),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard),
                          boxShadow: AppTheme.shadowCard,
                          border: Border.all(
                            color: AppTheme.primaryMedium.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: AppTheme.avatarDecoration(
                                  AppTheme.primaryMedium),
                              child: const Icon(
                                Icons.badge_rounded,
                                size: 22,
                                color: AppTheme.primaryMedium,
                              ),
                            ),
                            const SizedBox(width: AppTheme.gapMedium),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Il mio User ID',
                                    style: AppTheme.bodyMedium.copyWith(
                                      color: AppTheme.primaryMedium,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SelectableText(
                                    _myUserId!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppTheme.gapSmall),
                            Material(
                              color: AppTheme.primaryMedium.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSmall),
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusSmall),
                                onTap: _copyMyUserId,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  child: const Icon(
                                    Icons.copy_rounded,
                                    size: 20,
                                    color: AppTheme.primaryMedium,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_lastSync != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTheme.gapSmall),
                        child: Text(
                          "Ultima sincronizzazione: ${_formatDate(_lastSync!)}",
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: AppTheme.gapLarge),
                    // Bottoni navigazione premium
                    Row(
                      children: [
                        // Miei record
                        Expanded(
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: _uploadedRecords.isEmpty
                                  ? null
                                  : AppTheme.gradientPrimary,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium),
                              border: _uploadedRecords.isEmpty
                                  ? Border.all(
                                      color: AppTheme.textTertiary
                                          .withValues(alpha: 0.3),
                                    )
                                  : null,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMedium),
                                onTap: _uploadedRecords.isEmpty
                                    ? null
                                    : _openRecordsPage,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.paddingCard),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 20,
                                        color: _uploadedRecords.isEmpty
                                            ? AppTheme.textTertiary
                                            : Colors.white,
                                      ),
                                      const SizedBox(width: AppTheme.gapSmall),
                                      Text(
                                        _uploadedRecords.isEmpty
                                            ? "No record"
                                            : "Miei record",
                                        style: AppTheme.bodyMedium.copyWith(
                                          color: _uploadedRecords.isEmpty
                                              ? AppTheme.textTertiary
                                              : Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.gapMedium),
                        // Condivisi
                        Expanded(
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppTheme.cardBackground,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(
                                color: AppTheme.accentTeal.withValues(alpha: 0.3),
                              ),
                              boxShadow: AppTheme.shadowCard,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMedium),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SharedWithMePage(
                                          backendBaseUrl: kBackendBaseUrl),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.paddingCard),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.inbox_rounded,
                                        size: 20,
                                        color: AppTheme.accentTeal,
                                      ),
                                      const SizedBox(width: AppTheme.gapSmall),
                                      Text(
                                        "Condivisi",
                                        style: AppTheme.bodyMedium.copyWith(
                                          color: AppTheme.accentTeal,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Card principale premium (sparisce quando _dataLoaded = true)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _dataLoaded
                    ? const SizedBox.shrink(key: ValueKey('hidden-card'))
                    : Container(
                        key: const ValueKey('loader-card'),
                        margin: const EdgeInsets.symmetric(
                            horizontal: AppTheme.paddingScreen),
                        padding: const EdgeInsets.all(AppTheme.paddingSection),
                        decoration: AppTheme.cardDecorationLarge(),
                        child: Column(
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                gradient: _isLoading
                                    ? LinearGradient(
                                        colors: [
                                          Colors.orange[400]!,
                                          Colors.orange[600]!
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : AppTheme.gradientPrimary,
                                borderRadius: BorderRadius.circular(55),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isLoading
                                            ? Colors.orange
                                            : AppTheme.primaryMedium)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: _isLoading
                                  ? SpinKitRipple(
                                      color: Colors.white, size: 70)
                                  : const Icon(
                                      Icons.health_and_safety_rounded,
                                      size: 56,
                                      color: Colors.white,
                                    ),
                            ),
                            const SizedBox(height: AppTheme.gapXLarge),
                            Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: AppTheme.bodyLarge.copyWith(
                                color: AppTheme.textPrimary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AppTheme.paddingSection),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () async {
                                        setState(() {
                                          _statusMessage =
                                              "Caricamento dati sanitari...";
                                          _encryptedBytes = null;
                                          _ipfsCid = null;
                                          _manifestBase = null;
                                        });
                                        await _loadHealthData();
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryMedium,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusButton),
                                  ),
                                  disabledBackgroundColor: AppTheme.textTertiary
                                      .withValues(alpha: 0.3),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        "Carica Dati Sanitari",
                                        style: AppTheme.cardTitle
                                            .copyWith(color: Colors.white),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              // Riepilogo dati (appare con animazione quando _dataLoaded = true)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.08), end: Offset.zero)
                      .animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _dataLoaded
                    ? KeyedSubtree(
                        key: const ValueKey('summary'),
                        child: _buildHealthDataSummary(),
                      )
                    : const SizedBox.shrink(key: ValueKey('summary-empty')),
              ),

              // Bottone "Cifra payload" premium
              if (_dataLoaded &&
                  (_encryptedBytes == null || _manifestBase == null))
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.paddingScreen,
                      AppTheme.gapSmall,
                      AppTheme.paddingScreen,
                      AppTheme.paddingSection),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: (_payloadBytes != null)
                          ? _encryptCurrentPayload
                          : null,
                      icon: const Icon(Icons.lock_rounded, size: 22),
                      label: Text(
                        "Cifra payload",
                        style:
                            AppTheme.cardTitle.copyWith(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusButton),
                        ),
                        disabledBackgroundColor:
                            AppTheme.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),

              // Bottone upload IPFS premium
              if (_encryptedBytes != null && _manifestBase != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.paddingScreen,
                      AppTheme.gapSmall,
                      AppTheme.paddingScreen,
                      AppTheme.paddingSection),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: _uploadedOk
                          ? null
                          : LinearGradient(
                              colors: [Colors.green[500]!, Colors.green[700]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: _uploadedOk ? Colors.green[600] : null,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusButton),
                      boxShadow: _uploadedOk ? null : AppTheme.shadowButton,
                    ),
                    child: ElevatedButton.icon(
                      onPressed: (_encryptedBytes != null &&
                              _manifestBase != null &&
                              !_uploadingIpfs &&
                              !_uploadedOk)
                          ? _uploadToIpfs
                          : null,
                      icon: _uploadingIpfs
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.2,
                              ),
                            )
                          : Icon(
                              _uploadedOk
                                  ? Icons.check_circle_rounded
                                  : Icons.cloud_upload_rounded,
                              size: 24,
                            ),
                      label: Text(
                        _uploadingIpfs
                            ? "Caricamento..."
                            : (_uploadedOk
                                ? "Caricato correttamente"
                                : "Carica su IPFS"),
                        style:
                            AppTheme.cardTitle.copyWith(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusButton),
                        ),
                        disabledBackgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),

              // Richiamo “I miei record” anche in basso (comodo)
              // Padding(
              //   padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              //   child: SizedBox(
              //     width: double.infinity,
              //     height: 48,
              //     child: OutlinedButton.icon(
              //       onPressed:
              //           _uploadedRecords.isEmpty ? null : _openRecordsPage,
              //       icon: const Icon(Icons.folder_open),
              //       label: Text(
              //         _uploadedRecords.isEmpty
              //             ? "I miei record (vuoto)"
              //             : "I miei record (${_uploadedRecords.length})",
              //       ),
              //       style: OutlinedButton.styleFrom(
              //         side: BorderSide(color: Colors.blue[200]!),
              //         shape: RoundedRectangleBorder(
              //             borderRadius: BorderRadius.circular(14)),
              //         foregroundColor: Colors.blue[700],
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordsPage extends StatefulWidget {
  final String backendBaseUrl;
  final List<UploadedRecord> records;
  final Map<String, String> pendingTxByRecord; // recordId -> txHash
  final Set<String> minedTx; // set di txHash minati

  const RecordsPage({
    super.key,
    required this.backendBaseUrl,
    required this.records,
    required this.pendingTxByRecord,
    required this.minedTx,
  });

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  bool _busy = false;

  Future<void> _showDecodedPayload(
      BuildContext context, String jsonStr, UploadedRecord rec) async {
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
                        const Text(
                          'Dettagli record',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700),
                        ),
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
                          _pill('CID', _short(rec.cid), Colors.teal),
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

  Future<void> _viewClear(UploadedRecord rec) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final recordId = rec.recordId;

      // 1) Manifest dal backend
      final manifestRes = await http
          .get(Uri.parse('${widget.backendBaseUrl}/keywraps/$recordId'));
      if (manifestRes.statusCode != 200) {
        throw Exception('Manifest non trovato (${manifestRes.statusCode})');
      }
      final manifest = jsonDecode(manifestRes.body) as Map<String, dynamic>;
      final m = manifest['manifest'] as Map<String, dynamic>? ?? {};
      final wraps = (m['wraps'] as Map<String, dynamic>?);
      if (wraps == null) throw Exception('Wraps mancanti');

      final owner = (wraps['owner'] as Map<String, dynamic>);
      final recipients = (wraps['recipients'] as Map<String, dynamic>?) ?? {};
      final cid = (manifest['cid'] ?? m['cid'] ?? rec.cid) as String;

      // 2) Prova come OWNER
      Uint8List? dekBytes;
      try {
        dekBytes = await _unwrapOwnerDek(recordId, owner);
      } catch (_) {
        // 3) Se non owner, prova come RECIPIENT
        final myId = await IdentityService.getOrCreateIdentity();
        final myUserId = myId.userId;
        final myWrap = recipients[myUserId] as Map<String, dynamic>?;
        if (myWrap == null) {
          throw Exception('Nessun accesso per questo utente');
        }
        dekBytes = await WrapService.unwrapDekFromRecipient(
          recordId: recordId,
          myX25519: myId.x25519,
          recipientWrap: myWrap,
        );
      }

      // 4) Scarica blob IPFS (nonce|cipher|mac) da gateway
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
      if (blobRes == null)
        throw Exception('Download IPFS fallito (tutti i gateway)');

      final bytes = blobRes.bodyBytes;
      if (bytes.length < 12 + 16) throw Exception('Blob troppo corto');

      final dataNonce = bytes.sublist(0, 12);
      final dataMac = bytes.sublist(bytes.length - 16);
      final dataCipher = bytes.sublist(12, bytes.length - 16);

      // 5) Decrypt payload (AAD = recordId)
      final aead = AesGcm.with256bits();
      final plain = await aead.decrypt(
        SecretBox(dataCipher, nonce: dataNonce, mac: Mac(dataMac)),
        secretKey: SecretKey(dekBytes),
        aad: utf8.encode(recordId),
      );

      final jsonStr = utf8.decode(plain);
      if (!mounted) return;
      await _showDecodedPayload(context, jsonStr, rec);

      // wipe
      plain.fillRange(0, plain.length, 0);
      dataCipher.fillRange(0, dataCipher.length, 0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore decrypt: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareRecord(UploadedRecord rec) async {
    if (_busy) return;
    final controller = TextEditingController();

    final toUserId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Condividi con utente'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'User ID destinatario',
            hintText: 'incolla userId',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Condividi')),
        ],
      ),
    );

    if (toUserId == null || toUserId.isEmpty) return;

    setState(() => _busy = true);
    try {
      // 1) prendi chiavi del destinatario
      final keys = await DirectoryService.getKeys(toUserId);
      final xPubB64 = keys['pubX25519'] as String;
      final recipientXPub = base64Decode(xPubB64);

      // 2) prendi manifest per recordId per recuperare DEK owner-wrap (lo abbiamo già nel backend)
      final manifestRes = await http
          .get(Uri.parse('${widget.backendBaseUrl}/keywraps/${rec.recordId}'));
      if (manifestRes.statusCode != 200) {
        throw Exception('Manifest non trovato per grant');
      }
      final manifest = jsonDecode(manifestRes.body) as Map<String, dynamic>;
      final m = manifest['manifest'] as Map<String, dynamic>;
      final ownerWrap =
          (m['wraps'] as Map<String, dynamic>)['owner'] as Map<String, dynamic>;

      // 3) DEK: lo unwrappo lato owner con la mia KEK_device
      final aead = AesGcm.with256bits();
      final kek = await KeyManager.deriveKekDevice();
      final wrapNonce = base64Decode(ownerWrap['nonce'] as String);
      final wrapMac = base64Decode(ownerWrap['mac'] as String);
      final wrapCipher = base64Decode(ownerWrap['dek'] as String);
      final dekBytes = await aead.decrypt(
        SecretBox(wrapCipher, nonce: wrapNonce, mac: Mac(wrapMac)),
        secretKey: kek,
        aad: utf8.encode(rec.recordId),
      );

      // 4) crea recipient wrap per il destinatario (x25519+hkdf+gcm)
      final recipientWrap = await WrapService.wrapDekForRecipient(
        recordId: rec.recordId,
        dekBytes: Uint8List.fromList(dekBytes),
        recipientX25519Pub: recipientXPub,
      );

      // 5) firma "grant" con JSON canonico
      final grantMap = {
        'op': 'grant',
        'recordId': rec.recordId,
        'to': toUserId,
        'wrap': recipientWrap,
      };
      final sig = await IdentityService.signBytes(
        Uint8List.fromList(canonicalJsonBytes(grantMap)),
      );

      // 6) POST al backend
      await DirectoryService.postGrant(
        recordId: rec.recordId,
        toUserId: toUserId,
        recipientWrap: recipientWrap,
        grantSigBase64: base64Encode(sig),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Accesso condiviso con $toUserId')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore condivisione: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // === ADD: dialog semplice per scegliere destinatario ===
  // Future<UserDirectoryEntry?> _askRecipient() async {
  //   final controller = TextEditingController();
  //   return showDialog<UserDirectoryEntry?>(
  //     context: context,
  //     builder: (ctx) {
  //       return AlertDialog(
  //         title: const Text('Condividi con...'),
  //         content: TextField(
  //           controller: controller,
  //           decoration: const InputDecoration(
  //             labelText: 'Handle / Email / userId',
  //           ),
  //         ),
  //         actions: [
  //           TextButton(
  //               onPressed: () => Navigator.pop(ctx, null),
  //               child: const Text('Annulla')),
  //           TextButton(
  //             onPressed: () async {
  //               final q = controller.text.trim();
  //               final dir = DirectoryClient(widget.backendBaseUrl);
  //               UserDirectoryEntry? entry;
  //               // se sembra un userId già formattato, prova getByUserId, altrimenti search
  //               if (q.length >= 16) {
  //                 entry = await dir.getByUserId(q) ?? await dir.searchOne(q);
  //               } else {
  //                 entry = await dir.searchOne(q);
  //               }
  //               if (!mounted) return;
  //               Navigator.pop(ctx, entry);
  //             },
  //             child: const Text('Cerca'),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

// === ADD: funzione principale di share ===
  // Future<void> _shareRecord(UploadedRecord rec) async {
  //   if (_busy) return;
  //   final dest = await _askRecipient();
  //   if (dest == null) return;

  //   setState(() => _busy = true);
  //   try {
  //     final recordId = rec.recordId;

  //     // 1) Scarica manifest esistente
  //     final manifestRes = await http
  //         .get(Uri.parse('${widget.backendBaseUrl}/keywraps/$recordId'));
  //     if (manifestRes.statusCode != 200) {
  //       throw Exception('Manifest non trovato (${manifestRes.statusCode})');
  //     }
  //     final manifest = jsonDecode(manifestRes.body) as Map<String, dynamic>;
  //     final m = manifest['manifest'] as Map<String, dynamic>? ?? {};
  //     final wraps = (m['wraps'] as Map<String, dynamic>?);
  //     if (wraps == null) throw Exception('Wraps non presenti nel manifest');

  //     // 2) Prova a ricavare DEK come owner (usando KEK_device)
  //     final owner = wraps['owner'] as Map<String, dynamic>;
  //     final dekBytes = await _unwrapOwnerDek(recordId, owner);

  //     // 3) Wrap per destinatario (X25519+HKDF+AES-GCM)
  //     final recipientWrap = await WrapService.wrapDekForRecipient(
  //       recordId: recordId,
  //       dekBytes: dekBytes,
  //       recipientX25519Pub: base64Decode(dest.pubX25519B64),
  //     );

  //     // 4) Firma richiesta di grant (firma delta semplice)
  //     final payloadToSign = {
  //       'op': 'grant',
  //       'recordId': recordId,
  //       'to': dest.userId,
  //       'wrap': recipientWrap,
  //     };
  //     final sigBytes = await IdentityService.signBytes(
  //       Uint8List.fromList(utf8.encode(jsonEncode(payloadToSign))),
  //     );
  //     final sigB64 = base64Encode(sigBytes);

  //     // 5) POST grant al backend
  //     final sharing = SharingClient(widget.backendBaseUrl);
  //     final ok = await sharing.grantRecipient(
  //       recordId: recordId,
  //       recipientUserId: dest.userId,
  //       recipientWrap: recipientWrap,
  //       signatureBase64: sigB64,
  //     );

  //     if (!ok) {
  //       throw Exception('Grant fallito lato server');
  //     }

  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('✅ Condiviso con ${dest.displayName}')),
  //     );
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Errore condivisione: $e')),
  //     );
  //   } finally {
  //     if (mounted) setState(() => _busy = false);
  //   }
  // }

// === ADD: helper per ricavare la DEK dall'owner wrap (AES-GCM sotto KEK_device)
  Future<Uint8List> _unwrapOwnerDek(
      String recordId, Map<String, dynamic> ownerWrap) async {
    final kek = await KeyManager.deriveKekDevice();
    final aead = AesGcm.with256bits();
    final wrapNonce = base64Decode(ownerWrap['nonce'] as String);
    final wrapMac = base64Decode(ownerWrap['mac'] as String);
    final wrapCipher = base64Decode(ownerWrap['dek'] as String);
    final plainDek = await aead.decrypt(
      SecretBox(wrapCipher, nonce: wrapNonce, mac: Mac(wrapMac)),
      secretKey: kek,
      aad: utf8.encode(recordId),
    );
    return Uint8List.fromList(plainDek);
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

  String _formatDate(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} "
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingTxByRecord.values
        .where((tx) => !widget.minedTx.contains(tx))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('I miei record'),
      ),
      backgroundColor: AppTheme.backgroundMain,
      body: widget.records.isEmpty
          ? Center(
              child: Text(
                'Nessun record caricato finora',
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.paddingCard,
                  vertical: AppTheme.gapMedium),
              itemCount: widget.records.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return _headerSummary(
                      total: widget.records.length,
                      pending: pending,
                      mined: widget.minedTx.length);
                }
                final r = widget.records[i - 1];
                final txHash = widget.pendingTxByRecord[r.recordId];
                final bool isMined =
                    txHash != null && widget.minedTx.contains(txHash);
                final String? etherscan = txHash != null
                    ? 'https://sepolia.etherscan.io/tx/$txHash'
                    : null;
                return _recordCard(
                  r: r,
                  i: i,
                  isMined: isMined,
                  txHash: txHash,
                  etherscan: etherscan,
                );
              }),
    );
  }

  Widget _headerSummary(
      {required int total, required int pending, required int mined}) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.gapMedium),
      padding: const EdgeInsets.all(AppTheme.paddingCardLarge),
      decoration: BoxDecoration(
        gradient: AppTheme.gradientPrimary,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: AppTheme.shadowCardLarge,
      ),
      child: Row(
        children: [
          const Icon(Icons.health_and_safety_rounded,
              color: Colors.white, size: 40),
          const SizedBox(width: AppTheme.gapMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vault sanitario',
                  style: AppTheme.cardTitle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTheme.gapSmall),
                Row(
                  children: [
                    _miniStat('Totali', total.toString(), Colors.white),
                    const SizedBox(width: AppTheme.gapMedium),
                    _miniStat('Mined', mined.toString(),
                        Colors.lightGreenAccent),
                    const SizedBox(width: AppTheme.gapMedium),
                    _miniStat('Pending', pending.toString(), AppTheme.accentAmber),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: color.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: AppTheme.bodyLarge.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _recordCard({
    required UploadedRecord r,
    required int i,
    required bool isMined,
    required String? txHash,
    required String? etherscan,
  }) {
    final statusColor = isMined
        ? AppTheme.statusSuccess
        : txHash != null
            ? AppTheme.statusWarning
            : AppTheme.statusInfo;
    final statusLabel =
        isMined ? 'On-chain' : txHash != null ? 'In attesa' : 'Off-chain';

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
                icon: Icons.folder_rounded,
                color: AppTheme.accentIndigo,
                size: 40,
              ),
              const SizedBox(width: AppTheme.gapMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Record ${_short(r.recordId)}',
                      style: AppTheme.cardSubtitle,
                    ),
                    Text(
                      'CID ${_short(r.cid)}',
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppTheme.buildStatusBadge(
                text: statusLabel,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapMedium),
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                _formatDate(r.createdAt),
                style: AppTheme.caption.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (etherscan != null) ...[
            const SizedBox(height: AppTheme.gapSmall),
            Material(
              color: AppTheme.accentIndigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                onTap: () => launchUrl(Uri.parse(etherscan)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.gapSmall,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: AppTheme.accentIndigo,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Vedi su Etherscan',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.accentIndigo,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTheme.gapMedium),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.visibility_rounded, size: 20),
                  label: const Text('Apri dati'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryDark,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  onPressed: _busy ? null : () => _viewClear(r),
                ),
              ),
              const SizedBox(width: AppTheme.gapMedium),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 20),
                  label: const Text('Condividi'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppTheme.accentTeal.withValues(alpha: 0.3),
                    ),
                    foregroundColor: AppTheme.accentTeal,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                  onPressed: _busy ? null : () => _shareRecord(r),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
