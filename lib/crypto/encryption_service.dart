// lib/crypto/encryption_service.dart
//
// Envelope encryption:
//  - DEK (random 256-bit) cifra i dati con AES-256-GCM
//  - DEK viene "wrappata" (cifrata) sotto KEK_device derivata da URK via HKDF
//  - Ritorna bytes combinati [nonce|ciphertext|mac] + info per MANIFEST (owner wrap)
//
// Dipendenze:
//   cryptography: ^2.7.0 (firma encrypt(..., aad: ...))
//   key_manager.dart (questo progetto)

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'key_manager.dart';

class EncryptionResult {
  /// Bytes cifrati combinati nel formato: [dataNonce | dataCipher | dataMac]
  final Uint8List encryptedBytes;

  /// Identificatore logico del record (es. hash del payload)
  final String recordId;

  /// Algoritmo usato
  final String algorithm;

  /// Nonce per i dati (Base64)
  final String dataNonceBase64;

  /// MAC per i dati (Base64)
  final String dataMacBase64;

  /// Wrap owner (DEK cifrata sotto KEK_device)
  final OwnerWrap ownerWrap;

  /// Formato bytes combinati
  final String combinedFormat; // "nonce|ciphertext|mac"

  /// Manifest "base" senza CID (lo aggiungerai dopo l'upload IPFS)
  Map<String, dynamic> buildManifestBase() {
    return {
      'v': 1,
      'alg': algorithm,
      'recordId': recordId,
      'tagLen': 16,
      'nonce': dataNonceBase64,
      'aad': 'recordId', // AAD = recordId usata durante cifratura dati
      'wraps': {
        'owner': ownerWrap.toJson(),
        'recipients': <Map<String, dynamic>>[],
      },
    };
  }

  const EncryptionResult({
    required this.encryptedBytes,
    required this.recordId,
    required this.algorithm,
    required this.dataNonceBase64,
    required this.dataMacBase64,
    required this.ownerWrap,
    this.combinedFormat = 'nonce|ciphertext|mac',
  });
}

class OwnerWrap {
  final String alg; // AES-256-GCM
  final String nonceBase64;
  final String macBase64;
  final String dekWrappedBase64; // ciphertext della DEK
  final String aad; // "recordId"

  const OwnerWrap({
    required this.alg,
    required this.nonceBase64,
    required this.macBase64,
    required this.dekWrappedBase64,
    this.aad = 'recordId',
  });

  Map<String, dynamic> toJson() => {
        'alg': alg,
        'nonce': nonceBase64,
        'mac': macBase64,
        'dek': dekWrappedBase64,
        'aad': aad,
      };
}

class EncryptionService {
  static final AesGcm _aead = AesGcm.with256bits();

  /// Cifra il payload con DEK random (AES-256-GCM) + wrap DEK con KEK_device.
  static Future<EncryptionResult> encryptPayload({
    required Uint8List payloadBytes,
    required String recordId,
  }) async {
    // === 1) DEK per i dati
    final SecretKey dek = await _aead.newSecretKey();
    final dekBytes = await dek.extractBytes();

    // === 2) Cifra dati
    final Uint8List dataNonce = _randomBytes(12);
    final SecretBox dataBox = await _aead.encrypt(
      payloadBytes,
      secretKey: dek,
      nonce: dataNonce,
      aad: utf8.encode(recordId), // AAD = recordId
    );
    final dataCipher = Uint8List.fromList(dataBox.cipherText);
    final dataMac = Uint8List.fromList(dataBox.mac.bytes);

    final Uint8List combined =
        Uint8List(dataNonce.length + dataCipher.length + dataMac.length);
    combined.setRange(0, dataNonce.length, dataNonce);
    combined.setRange(
        dataNonce.length, dataNonce.length + dataCipher.length, dataCipher);
    combined.setRange(
        dataNonce.length + dataCipher.length, combined.length, dataMac);

    // === 3) KEK_device da URK via HKDF
    final SecretKey kekDevice = await KeyManager.deriveKekDevice();

    // === 4) Wrap DEK sotto KEK_device
    final Uint8List wrapNonce = _randomBytes(12);
    final SecretBox wrapBox = await _aead.encrypt(
      dekBytes,
      secretKey: kekDevice,
      nonce: wrapNonce,
      aad: utf8.encode(recordId), // AAD = recordId
    );
    final wrapCipher = wrapBox.cipherText; // contiene la DEK cifrata
    final wrapMac = wrapBox.mac.bytes;

    final ownerWrap = OwnerWrap(
      alg: 'AES-256-GCM',
      nonceBase64: base64Encode(wrapNonce),
      macBase64: base64Encode(wrapMac),
      dekWrappedBase64: base64Encode(wrapCipher),
      aad: 'recordId',
    );

    return EncryptionResult(
      encryptedBytes: combined,
      recordId: recordId,
      algorithm: 'AES-256-GCM',
      dataNonceBase64: base64Encode(dataNonce),
      dataMacBase64: base64Encode(dataMac),
      ownerWrap: ownerWrap,
    );
  }

  /// RNG sicuro
  static Uint8List _randomBytes(int len) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(len, (_) => rnd.nextInt(256)));
  }
}
