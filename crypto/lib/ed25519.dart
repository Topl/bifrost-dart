import 'dart:typed_data';

import 'package:bifrost_crypto/impl/ec.dart';
import 'package:bifrost_crypto/utils.dart';
import 'package:cryptography/cryptography.dart' as c;

class Ed25519 {
  static final _algorithm = c.Ed25519();

  Future<Ed25519KeyPair> _convertAlgKeypair(c.SimpleKeyPair algKeypair) async {
    final sk = await algKeypair.extractPrivateKeyBytes();
    final vk = await algKeypair.extractPublicKey();
    final int8Vk = Uint8List.fromList(vk.bytes).int8List;
    return Ed25519KeyPair(Int8List.fromList(sk), int8Vk);
  }

  Future<Ed25519KeyPair> generateKeyPair() async {
    return _convertAlgKeypair(await _algorithm.newKeyPair());
  }

  Future<Ed25519KeyPair> generateKeyPairFromSeed(List<int> seed) async {
    return _convertAlgKeypair(await _algorithm.newKeyPairFromSeed(seed));
  }

  Future<List<int>> sign(List<int> message, List<int> sk) async {
    final vk = await getVerificationKey(sk);
    final uintRes = await signKeyPair(message, Ed25519KeyPair(sk, vk));
    return Uint8List.fromList(uintRes).int8List;
  }

  Future<List<int>> signKeyPair(
      List<int> message, Ed25519KeyPair keyPair) async {
    final algKeyPair = c.SimpleKeyPairData(
      keyPair.sk,
      publicKey: c.SimplePublicKey(keyPair.vk, type: c.KeyPairType.ed25519),
      type: c.KeyPairType.ed25519,
    );

    final algSignature = await _algorithm.sign(message, keyPair: algKeyPair);

    return algSignature.bytes;
  }

  Future<bool> verify(
      List<int> signature, List<int> message, List<int> vk) async {
    final _sig = Uint8List.fromList(signature);
    final _message = Uint8List.fromList(message);
    final _vk = Uint8List.fromList(vk);
    final result = await _algorithm.verify(
      _message,
      signature: c.Signature(
        _sig,
        publicKey: c.SimplePublicKey(_vk, type: c.KeyPairType.ed25519),
      ),
    );
    return result;
  }

  Future<List<int>> getVerificationKey(List<int> sk) async {
    final h = Uint8List.fromList((await c.Sha512().hash(sk)).bytes)
        .int8List
        .sublist(0, 32);
    final s = Int8List(EC.SCALAR_BYTES);
    ec.pruneScalar(h, 0, s);
    final vk = Int8List(32);
    ec.scalarMultBaseEncoded(s, vk, 0);
    return vk;
  }
}

final ed25519 = Ed25519();

class Ed25519KeyPair {
  final List<int> sk;
  final List<int> vk;

  Ed25519KeyPair(this.sk, this.vk);
}
