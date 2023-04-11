import 'dart:typed_data';

import 'package:bifrost_crypto/ed25519.dart';
import 'package:fixnum/src/int64.dart';
import 'package:hashlib/hashlib.dart';
import 'package:quivr/quivr.dart';
import 'package:topl_protobuf/brambl/models/datum.pb.dart';
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';

class QuivrContextForConstructedBlock extends DynamicContext {
  final BlockHeader header;
  final SignableBytes transactionSignableBytes;

  QuivrContextForConstructedBlock(
    this.header,
    this.transactionSignableBytes,
  );

  @override
  Int64 get currentTick => header.slot;

  @override
  Datum? datums(String key) => null; // TODO

  @override
  DigestVerifier? digestVerifiers(String key) {
    if (key == "blake2b256") return _blake2b256Verifier;

    return null;
  }

  @override
  Int64? heightOf(String label) {
    if (label == "header") return header.height;
    return null;
  }

  @override
  Data? interfaces(String key) {
    return null;
  }

  @override
  Uint8List get signableBytes =>
      Uint8List.fromList(transactionSignableBytes.value);

  @override
  SignatureVerifier? signatureVerifiers(String key) {
    if (key == "ed25519") return _ed25519Verifier;
    return null;
  }
}

class QuivrContextForProposedBlock extends DynamicContext {
  final Int64 _height;
  final Int64 _slot;
  final SignableBytes _transactionSignableBytes;

  QuivrContextForProposedBlock(
      this._height, this._slot, this._transactionSignableBytes);

  @override
  Int64 get currentTick => _slot;

  @override
  Datum? datums(String key) => null; // TODO

  @override
  DigestVerifier? digestVerifiers(String key) {
    if (key == "blake2b256") return _blake2b256Verifier;

    return null;
  }

  @override
  Int64? heightOf(String label) {
    if (label == "header") return _height;
    return null;
  }

  @override
  Data? interfaces(String key) => null; // TODO

  @override
  Uint8List get signableBytes =>
      Uint8List.fromList(_transactionSignableBytes.value);

  @override
  SignatureVerifier? signatureVerifiers(String key) {
    if (key == "ed25519") return _ed25519Verifier;
    return null;
  }
}

Future<String?> _blake2b256Verifier(DigestVerification verification) async {
  final actual = blake2b256
      .convert(verification.preimage.input + verification.preimage.salt)
      .bytes;
  if (actual != Uint8List.fromList(verification.digest.digest32.value)) {
    return "DigestVerificationFailure";
  }
  return null;
}

Future<String?> _ed25519Verifier(SignatureVerification verification) async {
  final actual = await ed25519.verify(
    verification.signature.value,
    verification.message.value,
    verification.verificationKey.ed25519.value,
  );
  if (!actual) {
    return "SignatureVerificationFailure";
  }
  return null;
}
