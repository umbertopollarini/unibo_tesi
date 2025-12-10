import 'dart:math';
import 'dart:typed_data';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart' as web3crypto;

class EthereumIdentity {
  final EthPrivateKey privateKey;
  final EthereumAddress address;

  EthereumIdentity._(this.privateKey, this.address);

  String get privateKeyHex =>
      web3crypto.bytesToHex(privateKey.privateKey, include0x: true);

  static Future<EthereumIdentity> generate() async {
    final rnd = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    final pk = EthPrivateKey(bytes);
    final addr = await pk.extractAddress();
    return EthereumIdentity._(pk, addr);
  }

  static Future<EthereumIdentity> fromHex(String privateKeyHex) async {
    final pk = EthPrivateKey.fromHex(privateKeyHex);
    final addr = await pk.extractAddress();
    return EthereumIdentity._(pk, addr);
  }
}
