import 'dart:typed_data';

import 'package:bifrost_crypto/impl/ec.dart';
import 'package:bifrost_crypto/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fpdart/fpdart.dart';

/**
 * AMS 2021:
 * ECVRF-ED25519-SHA512-TAI
 * Elliptic curve Verifiable Random Function based on EdDSA
 * https://tools.ietf.org/html/draft-irtf-cfrg-vrf-04
 */
class Ed25519VRF {
  Ed25519VRF() {
    cofactor[0] = 8;
    oneScalar[0] = 1;
    ec.pointSetNeutralAccum(NP);
    ec.encodePoint(NP, neutralPointBytes, 0);
  }

  static const suite = [3];
  final cofactor = Int8List(EC.SCALAR_BYTES);
  static final zeroScalar = Int8List(EC.SCALAR_BYTES);
  static final oneScalar = Int8List(EC.SCALAR_BYTES);
  final np = Int32List(EC.SCALAR_INTS);
  final nb = Int32List(EC.SCALAR_INTS);
  static const C_BYTES = 16;
  static const PI_BYTES = EC.POINT_BYTES + EC.SCALAR_BYTES + C_BYTES;
  static final neutralPointBytes = Int8List(EC.SCALAR_BYTES);
  final NP = PointAccum.fromField(ec.x25519Field);

  Future<Ed25519VRFKeyPair> generateKeyPair() async {
    final random = SecureRandom.safe;
    final seed = List.generate(32, (index) => random.nextInt(256));
    return generateKeyPairFromSeed(seed);
  }

  Future<Ed25519VRFKeyPair> generateKeyPairFromSeed(List<int> seed) async {
    assert(seed.length == 32);
    final sk = (await _sha512Signed(seed)).sublist(0, 32);
    final vk = await getVerificationKey(sk);
    return Ed25519VRFKeyPair(sk: sk, vk: vk);
  }

  Future<List<int>> getVerificationKey(List<int> secretKey) async {
    assert(secretKey.length == 32);
    final h = await _sha512Signed(secretKey);
    final s = Int8List(EC.SCALAR_BYTES);
    ec.pruneScalar(h, 0, s);
    final vk = Int8List(32);
    ec.scalarMultBaseEncoded(s, vk, 0);
    return vk;
  }

  Future<bool> verify(
      List<int> signature, List<int> message, List<int> vk) async {
    assert(signature.length == 80);
    assert(vk.length == 32);
    final _vk = Int8List.fromList(vk);
    final gamma_str = Int8List.fromList(signature.sublist(0, EC.POINT_BYTES));
    final c = Int8List.fromList(
        signature.sublist(EC.POINT_BYTES, EC.POINT_BYTES + C_BYTES) +
            Int8List(EC.SCALAR_BYTES - C_BYTES));
    final s = Int8List.fromList(signature.sublist(EC.POINT_BYTES + C_BYTES));
    final H = await _hashToCurveTryAndIncrement(_vk, message);
    final gamma = PointExt.fromField(ec.x25519Field);
    final Y = PointExt.fromField(ec.x25519Field);
    ec.decodePointVar(gamma_str, 0, false, gamma);
    ec.decodePointVar(_vk, 0, false, Y);
    final A = PointAccum.fromField(ec.x25519Field);
    final B = PointAccum.fromField(ec.x25519Field);
    final C = PointAccum.fromField(ec.x25519Field);
    final D = PointAccum.fromField(ec.x25519Field);
    final U = PointAccum.fromField(ec.x25519Field);
    final V = PointAccum.fromField(ec.x25519Field);
    final g = PointAccum.fromField(ec.x25519Field);
    final t = PointExt.fromField(ec.x25519Field);
    ec.scalarMultBase(s, A);
    ec.decodeScalar(c, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, Y, B);
    ec.decodeScalar(s, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, ec.pointCopyAccum(H.first), C);
    ec.decodeScalar(c, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, gamma, D);
    ec.decodeScalar(oneScalar, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.pointAddVar2(true, ec.pointCopyAccum(A), ec.pointCopyAccum(B), t);
    ec.scalarMultStraussVar(nb, np, t, U);
    ec.pointAddVar2(true, ec.pointCopyAccum(C), ec.pointCopyAccum(D), t);
    ec.scalarMultStraussVar(nb, np, t, V);
    ec.scalarMultStraussVar(nb, np, gamma, g);
    final cp = await _hashPoints(H.first, g, U, V);
    return c.sameElements(cp);
  }

  Future<List<int>> sign(List<int> sk, List<int> message) async {
    assert(sk.length == 32);
    final x = await _pruneHash(sk);
    final pk = ec.createScalarMultBaseEncoded(x);
    final H = await _hashToCurveTryAndIncrement(pk, message);
    final gamma = PointAccum.fromField(ec.x25519Field);
    ec.decodeScalar(x, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, ec.pointCopyAccum(H.first), gamma);
    final k = await _nonceGenerationRFC8032(sk, H.second);
    assert(ec.checkScalarVar(k));
    final kB = PointAccum.fromField(ec.x25519Field);
    final kH = PointAccum.fromField(ec.x25519Field);
    ec.scalarMultBase(k, kB);
    ec.decodeScalar(k, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, ec.pointCopyAccum(H.first), kH);
    final c = await _hashPoints(H.first, gamma, kB, kH);
    final s = ec.calculateS(k, c, x);
    final gamma_str = Int8List(EC.POINT_BYTES);
    ec.encodePoint(gamma, gamma_str, 0);
    final pi = <int>[]
      ..addAll(gamma_str)
      ..addAll(c.take(C_BYTES))
      ..addAll(s);
    assert(pi.length == PI_BYTES);
    return pi;
  }

  Future<Int8List> proofToHash(List<int> signature) async {
    assert(signature.length == 80);
    final gamma_str = Int8List.fromList(signature.sublist(0, EC.POINT_BYTES));
    final zero = [0x00];
    final three = [0x03];
    final gamma = PointExt.fromField(ec.x25519Field);
    final cg = PointAccum.fromField(ec.x25519Field);
    ec.decodePointVar(gamma_str, 0, false, gamma);
    ec.decodeScalar(cofactor, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, gamma, cg);
    final cg_enc = Int8List(EC.POINT_BYTES);
    ec.encodePoint(cg, cg_enc, 0);
    final input = <int>[]
      ..addAll(suite)
      ..addAll(three)
      ..addAll(cg_enc)
      ..addAll(zero);
    return await _sha512Signed(input);
  }

  _pruneHash(List<int> s) async {
    final h = await _sha512Signed(s);
    h[0] = (h[0] & 0xf8).toByte;
    h[EC.SCALAR_BYTES - 1] = (h[EC.SCALAR_BYTES - 1] & 0x7f).toByte;
    h[EC.SCALAR_BYTES - 1] = (h[EC.SCALAR_BYTES - 1] | 0x40).toByte;
    return h;
  }

  _hashToCurveTryAndIncrement(List<int> Y, List<int> a) async {
    int ctr = 0;
    final one = [0x01];
    final zero = [0x00];
    final hash = Int8List(EC.POINT_BYTES);
    final H = PointExt.fromField(ec.x25519Field);
    final HR = PointAccum.fromField(ec.x25519Field);
    bool isPoint = false;
    while (!isPoint) {
      final ctr_byte = [ctr.toByte];
      final input = <int>[]
        ..addAll(suite)
        ..addAll(one)
        ..addAll(Y)
        ..addAll(a)
        ..addAll(ctr_byte)
        ..addAll(zero);
      final output = await _sha512Signed(input);
      for (int i = 0; i < EC.POINT_BYTES; i++) hash[i] = output[i];
      isPoint = ec.decodePointVar(hash, 0, false, H);
      if (isPoint) {
        isPoint != _isNeutralPoint(H);
      }
      ctr += 1;
    }

    ec.decodeScalar(cofactor, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, H, HR);
    ec.encodePoint(HR, hash, 0);
    return Tuple2(HR, hash);
  }

  _isNeutralPoint(PointExt p) {
    final pBytes = Int8List(EC.POINT_BYTES);
    final pA = PointAccum.fromField(ec.x25519Field);
    ec.decodeScalar(oneScalar, 0, np);
    ec.decodeScalar(zeroScalar, 0, nb);
    ec.scalarMultStraussVar(nb, np, p, pA);
    ec.encodePoint(pA, pBytes, 0);
    return pBytes.sameElements(neutralPointBytes);
  }

  _nonceGenerationRFC8032(List<int> sk, List<int> h) async {
    final sk_hash = await _sha512Signed(sk);
    final trunc_hashed_sk = <int>[]
      ..addAll(sk_hash.sublist(EC.SCALAR_BYTES))
      ..addAll(h);
    final out = await _sha512Signed(trunc_hashed_sk);
    return ec.reduceScalar(out);
  }

  Future<Int8List> _hashPoints(
      PointAccum p1, PointAccum p2, PointAccum p3, PointAccum p4) async {
    final zero = [0x00];
    final two = [0x02];
    final str = <int>[]
      ..addAll(suite)
      ..addAll(two);
    final r = Int8List(EC.POINT_BYTES);
    ec.encodePoint(p1, r, 0);
    str.addAll(r);
    ec.encodePoint(p2, r, 0);
    str.addAll(r);
    ec.encodePoint(p3, r, 0);
    str.addAll(r);
    ec.encodePoint(p4, r, 0);
    str.addAll(r);
    str.addAll(zero);
    final out = await _sha512Signed(str);
    return Int8List.fromList(
        out.sublist(0, C_BYTES) + Int8List(EC.SCALAR_BYTES - C_BYTES));
  }

  Future<Int8List> _sha512Signed(List<int> input) async {
    final o1 = (await Sha512().hash(input)).bytes;
    return Uint8List.fromList(o1).int8List;
  }
}

final ed25519Vrf = Ed25519VRF();

class Ed25519VRFKeyPair {
  final List<int> sk;
  final List<int> vk;

  Ed25519VRFKeyPair({required this.sk, required this.vk});
}
