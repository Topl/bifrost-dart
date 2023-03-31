import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/quivr/models/proof.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';

LockedProposer(Data? data) =>
    Proposition()..locked = Proposition_Locked(data: data);

DigestProposer(String routine, Digest digest) => Proposition()
  ..digest = Proposition_Digest(routine: routine, digest: digest);

SignatureProposer(String routine, VerificationKey vk) => Proposition()
  ..digitalSignature =
      Proposition_DigitalSignature(routine: routine, verificationKey: vk);

HeightProposer(String chain, Int64 min, Int64 max) => Proposition()
  ..heightRange = Proposition_HeightRange(chain: chain, min: min, max: max);

TickProposer(Int64 min, Int64 max) =>
    Proposition()..tickRange = Proposition_TickRange(min: min, max: max);

ExactMatchProposer(String location, Int8List compareTo) => Proposition()
  ..exactMatch =
      Proposition_ExactMatch(location: location, compareTo: compareTo);

LessThanProposer(String location, Int128 compareTo) => Proposition()
  ..lessThan = Proposition_LessThan(location: location, compareTo: compareTo);

GreaterThanProposer(String location, Int128 compareTo) => Proposition()
  ..greaterThan =
      Proposition_GreaterThan(location: location, compareTo: compareTo);

EqualToProposer(String location, Int128 compareTo) => Proposition()
  ..equalTo = Proposition_EqualTo(location: location, compareTo: compareTo);

ThresholdProposer(List<Proposition> challenges, int threshold) => Proposition()
  ..threshold =
      Proposition_Threshold(challenges: challenges, threshold: threshold);

AndProposer(Proposition left, Proposition right) =>
    Proposition()..and = Proposition_And(left: left, right: right);

OrProposer(Proposition left, Proposition right) =>
    Proposition()..or = Proposition_Or(left: left, right: right);
