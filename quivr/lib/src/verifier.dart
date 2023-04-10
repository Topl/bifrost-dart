import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:hashlib/hashlib.dart';
import 'package:quivr/src/tokens.dart';
import 'package:topl_protobuf/brambl/models/datum.pb.dart';
import 'package:topl_protobuf/quivr/models/proof.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';
import 'package:collection/collection.dart';

typedef Err = String;
typedef SignatureVerifier = Future<Err?> Function(SignatureVerification);
typedef DigestVerifier = Future<Err?> Function(DigestVerification);

abstract class DynamicContext {
  Datum? datums(String key);
  Data? interfaces(String key);
  SignatureVerifier? signatureVerifiers(String key);
  DigestVerifier? digestVerifiers(String key);
  Int8List get signableBytes;
  Int64 get currentTick;
  Int64? heightOf(String label);
}

VerifyLocked() => "LockedPropositionIsUnsatisfiable";

Future<String?> Verify(
    Proposition proposition, Proof proof, DynamicContext context) async {
  if (proposition.hasLocked() && proof.hasLocked())
    return VerifyLocked();
  else if (proposition.hasDigest() && proof.hasDigest())
    return VerifyDigest(proposition.digest, proof.digest, context);
  else if (proposition.hasDigitalSignature() && proof.hasDigitalSignature())
    return VerifySignature(
        proposition.digitalSignature, proof.digitalSignature, context);
  else if (proposition.hasHeightRange() && proof.hasHeightRange())
    return VerifyHeightRange(
        proposition.heightRange, proof.heightRange, context);
  else if (proposition.hasTickRange() && proof.hasTickRange())
    return VerifyTickRange(proposition.tickRange, proof.tickRange, context);
  else if (proposition.hasExactMatch() && proof.hasExactMatch())
    return VerifyExactMatch(proposition.exactMatch, proof.exactMatch, context);
  else if (proposition.hasLessThan() && proof.hasLessThan())
    return VerifyLessThan(proposition.lessThan, proof.lessThan, context);
  else if (proposition.hasGreaterThan() && proof.hasGreaterThan())
    return VerifyGreaterThan(
        proposition.greaterThan, proof.greaterThan, context);
  else if (proposition.hasEqualTo() && proof.hasEqualTo())
    return VerifyEqualTo(proposition.equalTo, proof.equalTo, context);
  else if (proposition.hasThreshold() && proof.hasThreshold())
    return VerifyThreshold(proposition.threshold, proof.threshold, context);
  else if (proposition.hasAnd() && proof.hasAnd())
    return VerifyAnd(proposition.and, proof.and, context);
  else if (proposition.hasOr() && proof.hasOr())
    return VerifyOr(proposition.or, proof.or, context);
  else
    return "PropositionAndProofMismatch";
}

Future<String?> VerifyDigest(Proposition_Digest proposition, Proof_Digest proof,
    DynamicContext context) async {
  final wProof = Proof()..digest = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final verifier = context.digestVerifiers(proposition.routine);
  if (verifier == null) return "DigestVerifierNotFound";
  return verifier(
      DigestVerification(digest: proposition.digest, preimage: proof.preimage));
}

Future<String?> VerifySignature(Proposition_DigitalSignature proposition,
    Proof_DigitalSignature proof, DynamicContext context) async {
  final wProof = Proof()..digitalSignature = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final verifier = context.signatureVerifiers(proposition.routine);
  if (verifier == null) return "SignatureVerifierNotFound";
  return verifier(SignatureVerification(
      verificationKey: proposition.verificationKey,
      signature: proof.witness,
      message: Message(value: context.signableBytes)));
}

String? VerifyHeightRange(Proposition_HeightRange proposition,
    Proof_HeightRange proof, DynamicContext context) {
  final wProof = Proof()..heightRange = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final chainHeight = context.heightOf(proposition.chain);
  if (chainHeight == null) return "EvaluationAuthorizationFailed";
  if (chainHeight < proposition.min || chainHeight > proposition.max)
    return "EvaluationAuthorizationFailed";
  return null;
}

String? VerifyTickRange(Proposition_TickRange proposition,
    Proof_TickRange proof, DynamicContext context) {
  final wProof = Proof()..tickRange = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final tick = context.currentTick;
  if (tick < proposition.min || tick > proposition.max)
    return "EvaluationAuthorizationFailed";
  return null;
}

String? VerifyExactMatch(Proposition_ExactMatch proposition,
    Proof_ExactMatch proof, DynamicContext context) {
  final wProof = Proof()..exactMatch = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final datum = context.interfaces(proposition.location);
  if (datum == null) return "EvaluationAuthorizationFailed";
  if (!_listEq(datum.value, proposition.compareTo))
    return "EvaluationAuthorizationFailed";
  return null;
}

String? VerifyLessThan(Proposition_LessThan proposition, Proof_LessThan proof,
    DynamicContext context) {
  final wProof = Proof()..lessThan = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final datum = context.interfaces(proposition.location);
  if (datum == null) return "EvaluationAuthorizationFailed";
  final bigInt1 = datum.value.toBigInt;
  final bigInt2 = proposition.compareTo.value.toBigInt;
  if (bigInt1 >= bigInt2) return "EvaluationAuthorizationFailed";
  return null;
}

String? VerifyGreaterThan(Proposition_GreaterThan proposition,
    Proof_GreaterThan proof, DynamicContext context) {
  final wProof = Proof()..greaterThan = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final datum = context.interfaces(proposition.location);
  if (datum == null) return "EvaluationAuthorizationFailed";
  final bigInt1 = datum.value.toBigInt;
  final bigInt2 = proposition.compareTo.value.toBigInt;
  if (bigInt1 <= bigInt2) return "EvaluationAuthorizationFailed";
  return null;
}

String? VerifyEqualTo(Proposition_EqualTo proposition, Proof_EqualTo proof,
    DynamicContext context) {
  final wProof = Proof()..equalTo = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final datum = context.interfaces(proposition.location);
  if (datum == null) return "EvaluationAuthorizationFailed";
  final bigInt1 = datum.value.toBigInt;
  final bigInt2 = proposition.compareTo.value.toBigInt;
  if (bigInt1 != bigInt2) return "EvaluationAuthorizationFailed";
  return null;
}

Future<String?> VerifyThreshold(Proposition_Threshold proposition,
    Proof_Threshold proof, DynamicContext context) async {
  final wProof = Proof()..threshold = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  if (proposition.threshold == 0)
    return null;
  else if (proposition.threshold >= proposition.challenges.length)
    return "EvaluationAuthorizationFailed";
  else if (proof.responses.isEmpty)
    return "EvaluationAuthorizationFailed";
  else if (proof.responses.length != proposition.challenges.length)
    return "EvaluationAuthorizationFailed";
  else {
    int i = 0;
    int successCount = 0;
    while (i < proposition.challenges.length &&
        successCount < proposition.threshold) {
      final challenge = proposition.challenges[i];
      final response = proof.responses[i];
      final subError = await Verify(challenge, response, context);
      if (subError != null) successCount++;
      i++;
    }
    if (successCount < proposition.threshold)
      return "EvaluationAuthorizationFailed";
  }
  return null;
}

Future<String?> VerifyNot(Proposition_Not proposition, Proof_Not proof,
    DynamicContext context) async {
  final wProof = Proof()..not = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final subError = await Verify(proposition.proposition, proof.proof, context);
  if (subError != null) return "EvaluationAuthorizationFailed";
  return null;
}

Future<String?> VerifyAnd(Proposition_And proposition, Proof_And proof,
    DynamicContext context) async {
  final wProof = Proof()..and = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final leftSubError = await Verify(proposition.left, proof.left, context);
  if (leftSubError != null) return leftSubError;
  final rightSubError = await Verify(proposition.right, proof.right, context);
  return rightSubError;
}

Future<String?> VerifyOr(
    Proposition_Or proposition, Proof_Or proof, DynamicContext context) async {
  final wProof = Proof()..or = proof;
  final msgResult =
      _evaluateTxBind(Tokens.Digest, wProof, proof.transactionBind, context);
  if (msgResult != null) return msgResult;
  final leftSubError = await Verify(proposition.left, proof.left, context);
  if (leftSubError == null) return null;
  final rightSubError = await Verify(proposition.right, proof.right, context);
  return rightSubError;
}

final _listEq = const ListEquality().equals;

String? _evaluateTxBind(
    String tag, Proof proof, TxBind txBind, DynamicContext context) {
  final sb = context.signableBytes;
  final m = utf8.encode(tag) + sb;
  final expected = blake2b256.convert(m).bytes;
  if (!_listEq(expected, Uint8List.fromList(txBind.value))) {
    return "MessageAuthorizationFailed";
  }
  return null;
}

extension _ListIntOps on List<int> {
  BigInt get toBigInt {
    final data = Int8List.fromList(this).buffer.asByteData();
    BigInt _bigInt = BigInt.zero;

    for (var i = 0; i < data.lengthInBytes; i++) {
      _bigInt = (_bigInt << 8) | BigInt.from(data.getUint8(i));
    }
    return _bigInt;
  }
}
