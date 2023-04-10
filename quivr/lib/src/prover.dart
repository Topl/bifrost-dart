import 'dart:convert';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart';
import 'package:quivr/src/tokens.dart';
import 'package:topl_protobuf/quivr/models/proof.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';

_createTxBind(String tag, SignableBytes message) {
  final m = utf8.encode(tag) + message.value;
  final h = blake2b256.convert(m).bytes;
  return TxBind()..value = h;
}

final LockedProof = Proof().locked = Proof_Locked();
LockedProver() => LockedProof;

DigestProver(Preimage preimage, SignableBytes message) => Proof()
  ..digest = Proof_Digest(
      transactionBind: _createTxBind(Tokens.Digest, message),
      preimage: preimage);

SignatureProver(Witness witness, SignableBytes message) =>
    Proof().digitalSignature = Proof_DigitalSignature(
        transactionBind: _createTxBind(Tokens.DigitalSignature, message),
        witness: witness);

HeightProver(SignableBytes message) => Proof()
  ..heightRange = Proof_HeightRange(
      transactionBind: _createTxBind(Tokens.HeightRange, message));

TickProver(SignableBytes message) => Proof()
  ..tickRange = Proof_TickRange(
      transactionBind: _createTxBind(Tokens.TickRange, message));

ExactMatchProver(SignableBytes message, Int8List compareTo) => Proof()
  ..exactMatch = Proof_ExactMatch(
      transactionBind: _createTxBind(Tokens.ExactMatch, message));

LessThanProver(SignableBytes message) => Proof()
  ..lessThan =
      Proof_LessThan(transactionBind: _createTxBind(Tokens.LessThan, message));

GreaterThanProver(SignableBytes message) => Proof()
  ..greaterThan = Proof_GreaterThan(
      transactionBind: _createTxBind(Tokens.GreaterThan, message));

EqualToProver(String location, SignableBytes message) => Proof()
  ..equalTo =
      Proof_EqualTo(transactionBind: _createTxBind(Tokens.EqualTo, message));

ThresholdProver(List<Proof> responses, SignableBytes message) => Proof()
  ..threshold = Proof_Threshold(
      transactionBind: _createTxBind(Tokens.Threshold, message),
      responses: responses);

NotProver(Proof proof, SignableBytes message) => Proof()
  ..not = Proof_Not(
      transactionBind: _createTxBind(Tokens.Not, message), proof: proof);

AndProver(Proof left, Proof right, SignableBytes message) => Proof()
  ..and = Proof_And(
      transactionBind: _createTxBind(Tokens.And, message),
      left: left,
      right: right);

OrProver(Proof left, Proof right, SignableBytes message) => Proof()
  ..or = Proof_Or(
      transactionBind: _createTxBind(Tokens.Or, message),
      left: left,
      right: right);
