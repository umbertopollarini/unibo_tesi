// lib/crypto/wrap_service.dart
//
// Wrap/unwrap DEK per destinatari usando X25519 + HKDF-SHA256 + AES-256-GCM
//
// Dipendenze:
//   cryptography: ^2.7.0

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class WrapService {
  static final _x = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aead = AesGcm.with256bits();

  /// Crea un recipient wrap (x25519 + hkdf + aes-gcm)
  /// Restituisce il blocco JSON da mettere in manifest.wraps.recipients[recipientId]
  static Future<Map<String, dynamic>> wrapDekForRecipient({
    required String recordId,
    required Uint8List dekBytes,
    required List<int> recipientX25519Pub, // bytes
  }) async {
    // Ephemeral per il KEM
    final eph = await _x.newKeyPair();
    final ephPub = await eph.extractPublicKey();

    final shared = await _x.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(
        recipientX25519Pub,
        type: KeyPairType.x25519,
      ),
    );

    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('wrap:v1'), // salt
      info: utf8.encode('record:$recordId'),
    );

    final nonce = _random(12);
    final box = await _aead.encrypt(
      dekBytes,
      secretKey: kek,
      nonce: nonce,
      aad: utf8.encode(recordId),
    );

    return {
      'alg': 'x25519-hkdf-aesgcm',
      'epk': base64Encode(ephPub.bytes),
      'nonce': base64Encode(nonce),
      'dek': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
      'aad': 'recordId',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'expiresAt': null,
    };
  }

  /// Sblocca DEK da un recipient wrap (lato destinatario)
  static Future<Uint8List> unwrapDekFromRecipient({
    required String recordId,
    required SimpleKeyPairData myX25519,
    required Map<String, dynamic> recipientWrap,
  }) async {
    final epk = base64Decode(recipientWrap['epk'] as String);

    final shared = await _x.sharedSecretKey(
      keyPair: myX25519, // SimpleKeyPairData implementa KeyPair
      remotePublicKey: SimplePublicKey(
        epk,
        type: KeyPairType.x25519,
      ),
    );

    final kek = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('wrap:v1'),
      info: utf8.encode('record:$recordId'),
    );

    final nonce = base64Decode(recipientWrap['nonce'] as String);
    final cipher = base64Decode(recipientWrap['dek'] as String);
    final mac = base64Decode(recipientWrap['mac'] as String);

    final plain = await _aead.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: kek,
      aad: utf8.encode(recordId),
    );
    return Uint8List.fromList(plain);
  }

  static Uint8List _random(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
  }
}
