// lib/crypto/key_manager.dart
//
// Gestisce la User Root Key (URK) e la derivazione della KEK dispositivo
// usando Keychain (iOS) / EncryptedSharedPreferences (Android).
//
// Dipendenze:
//   flutter_secure_storage: ^9.2.2
//   cryptography: ^2.7.0 (o compatibile con Hkdf(outputLength: ...) e AesGcm.encrypt(aad: ...))

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

class KeyManager {
  static const _kUrk = 'urk.v1';
  static const _kDeviceSalt = 'deviceSalt.v1';
  static final _storage = const FlutterSecureStorage();

  /// RNG sicuro cross-platform
  static Uint8List _random(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
  }

  /// Recupera o crea la URK (User Root Key) di 32 byte.
  /// Opzioni iOS/Android lasciate default per compatibilità ampia.
  static Future<Uint8List> getOrCreateUrk() async {
    final b64 = await _storage.read(key: _kUrk);
    if (b64 != null) {
      return Uint8List.fromList(base64Decode(b64));
    }
    final urk = _random(32);
    await _storage.write(
      key: _kUrk,
      value: base64Encode(urk),
      // iOptions: const IOSOptions(accessibility: KeychainAccessibility.afterFirstUnlock),
      // aOptions: const AndroidOptions(encryptedSharedPreferences: true),
    );
    return urk;
  }

  /// Recupera o crea un salt dispositivo (non segreto).
  static Future<Uint8List> getOrCreateDeviceSalt() async {
    final b64 = await _storage.read(key: _kDeviceSalt);
    if (b64 != null) {
      return Uint8List.fromList(base64Decode(b64));
    }
    final salt = _random(32);
    await _storage.write(key: _kDeviceSalt, value: base64Encode(salt));
    return salt;
  }

  /// Deriva la KEK del dispositivo (Key Encryption Key) da URK con HKDF-SHA256.
  static Future<SecretKey> deriveKekDevice() async {
    final urk = await getOrCreateUrk();
    final salt = await getOrCreateDeviceSalt();

    // In questa versione di cryptography, Hkdf richiede outputLength nel costruttore
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );

    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(urk),
      nonce: salt, // salt
      info: utf8.encode('health-app:kek-device:v1'),
      // NIENTE parametro 'length' qui: è già fissato da outputLength nel costruttore
    );
    return derived;
  }

  /// Crea un backup cifrato della URK usando una passphrase (PBKDF2).
  /// Ritorna i parametri da inviare al server per il recovery zero-trust.
  static Future<Map<String, String>> createUrkBackup(
    String passphrase, {
    int iterations = 200000,
  }) async {
    final urk = await getOrCreateUrk();
    final salt = _random(16);

    // Firma aggiornata: richiede macAlgorithm
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );

    final rk = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt, // salt
    );
    final rkBytes = await rk.extractBytes();

    final nonce = _random(12);
    final box = await AesGcm.with256bits().encrypt(
      urk,
      secretKey: SecretKey(rkBytes),
      nonce: nonce,
      aad: utf8.encode('URK-v1'), // <-- parametro corretto in questa versione
    );

    // Concat di cipherText + mac (come da tua logica)
    final wrapped = Uint8List.fromList(
        List<int>.from(box.cipherText)..addAll(box.mac.bytes));

    return {
      'urkWrapped': base64Encode(wrapped),
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': iterations.toString(),
      'aad': 'URK-v1',
      'v': '1',
    };
  }
}
