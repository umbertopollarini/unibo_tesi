// lib/crypto/identity_service.dart
//
// Gestione identità utente: chiavi Ed25519 (firma) e X25519 (scambio).
// Persistenza in Keychain/Keystore via flutter_secure_storage.
//
// Dipendenze:
//   flutter_secure_storage: ^9.2.2
//   cryptography: ^2.7.0

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:web3dart/crypto.dart' as web3crypto;
import 'package:web3dart/credentials.dart';
import '../services/ethereum_identity.dart';

class IdentityService {
  static const _kEdSk = 'id.ed25519.sk';
  static const _kEdPk = 'id.ed25519.pk';
  static const _kXSk = 'id.x25519.sk';
  static const _kXPk = 'id.x25519.pk';
  static const _kUserId = 'id.userId';
  static const _kEthSk = 'id.eth.sk';
  static const _kEthAddress = 'id.eth.addr';

  static final _storage = const FlutterSecureStorage();
  static final _ed = Ed25519();
  static final _x = X25519();
  static EthereumIdentity? _ethCache;

  /// Inizializza o recupera la coppia di chiavi Ed25519 e X25519
  /// e calcola uno userId deterministico: base64url(sha256(pubEd25519))[0..22]
  static Future<UserIdentity> getOrCreateIdentity() async {
    // prova a leggere
    final edSkB64 = await _storage.read(key: _kEdSk);
    final edPkB64 = await _storage.read(key: _kEdPk);
    final xSkB64 = await _storage.read(key: _kXSk);
    final xPkB64 = await _storage.read(key: _kXPk);
    String? userId = await _storage.read(key: _kUserId);

    SimpleKeyPairData edData;
    SimpleKeyPairData xData;

    if (edSkB64 != null && edPkB64 != null) {
      final edPk = SimplePublicKey(
        base64Decode(edPkB64),
        type: KeyPairType.ed25519,
      );
      edData = SimpleKeyPairData(
        base64Decode(edSkB64),
        publicKey: edPk,
        type: KeyPairType.ed25519,
      );
    } else {
      final kp = await _ed.newKeyPair();
      final ex = await kp.extract();
      await _storage.write(key: _kEdSk, value: base64Encode(ex.bytes));
      await _storage.write(
        key: _kEdPk,
        value: base64Encode(ex.publicKey.bytes),
      );
      edData = ex;
    }

    if (xSkB64 != null && xPkB64 != null) {
      final xPk = SimplePublicKey(
        base64Decode(xPkB64),
        type: KeyPairType.x25519,
      );
      xData = SimpleKeyPairData(
        base64Decode(xSkB64),
        publicKey: xPk,
        type: KeyPairType.x25519,
      );
    } else {
      final kp = await _x.newKeyPair();
      final ex = await kp.extract();
      await _storage.write(key: _kXSk, value: base64Encode(ex.bytes));
      await _storage.write(
        key: _kXPk,
        value: base64Encode(ex.publicKey.bytes),
      );
      xData = ex;
    }

    if (userId == null) {
      final digest = crypto.sha256.convert(edData.publicKey.bytes);
      // base64url senza padding, tagliato per leggibilità
      userId =
          base64UrlEncode(digest.bytes).replaceAll('=', '').substring(0, 22);
      await _storage.write(key: _kUserId, value: userId);
    }

    return UserIdentity(
      userId: userId,
      ed25519: edData,
      x25519: xData,
    );
  }

  static Future<String> getMyUserId() async {
    final id = await getOrCreateIdentity();
    return id.userId;
  }

// Sostituisci l’intero metodo signBytes in lib/crypto/identity_service.dart con questo:

  static Future<Uint8List> signBytes(Uint8List message) async {
    final id = await getOrCreateIdentity();
    // SimpleKeyPairData implementa KeyPair, puoi usarlo direttamente
    final sig = await _ed.sign(message, keyPair: id.ed25519);
    return Uint8List.fromList(sig.bytes);
  }

  /// Ottiene o crea l'identità Ethereum locale (persistita in secure storage).
  static Future<EthereumIdentity> getOrCreateEthereumIdentity() async {
    if (_ethCache != null) return _ethCache!;

    final savedPk = await _storage.read(key: _kEthSk);
    final savedAddr = await _storage.read(key: _kEthAddress);
    if (savedPk != null && savedAddr != null) {
      final eth = await EthereumIdentity.fromHex(savedPk);
      _ethCache = eth;
      return eth;
    }

    final generated = await EthereumIdentity.generate();
    await _storage.write(key: _kEthSk, value: generated.privateKeyHex);
    await _storage.write(key: _kEthAddress, value: generated.address.hex);
    _ethCache = generated;
    return generated;
  }

  static Future<String> getEthereumPrivateKeyHex() async {
    final eth = await getOrCreateEthereumIdentity();
    return web3crypto.bytesToHex(eth.privateKey.privateKey, include0x: true);
  }

  static Future<String> getEthereumAddress() async {
    final eth = await getOrCreateEthereumIdentity();
    return eth.address.hex;
  }

  static Future<Map<String, String>> publicDirectoryEntry() async {
    final id = await getOrCreateIdentity();
    return {
      'userId': id.userId,
      'pubEd25519': base64Encode(id.ed25519.publicKey.bytes),
      'pubX25519': base64Encode(id.x25519.publicKey.bytes),
    };
  }
}

class UserIdentity {
  final String userId;
  final SimpleKeyPairData ed25519;
  final SimpleKeyPairData x25519;

  const UserIdentity({
    required this.userId,
    required this.ed25519,
    required this.x25519,
  });
}
