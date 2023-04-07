import 'dart:convert';

import 'package:bifrost_common/utils.dart';
import 'package:fixnum/fixnum.dart';
import 'package:hashlib/hashlib.dart';
import 'package:quivr/quivr.dart';
import 'package:brambl/src/common/tags.dart';
import 'package:topl_protobuf/brambl/models/address.pb.dart';
import 'package:topl_protobuf/brambl/models/box/attestation.pb.dart';
import 'package:topl_protobuf/brambl/models/box/box.pb.dart';
import 'package:topl_protobuf/brambl/models/box/challenge.pb.dart';
import 'package:topl_protobuf/brambl/models/box/lock.pb.dart';
import 'package:topl_protobuf/brambl/models/box/value.pb.dart';
import 'package:topl_protobuf/brambl/models/common.pb.dart';
import 'package:topl_protobuf/brambl/models/datum.pb.dart';
import 'package:topl_protobuf/brambl/models/event.pb.dart';
import 'package:topl_protobuf/brambl/models/evidence.pb.dart';
import 'package:topl_protobuf/brambl/models/identifier.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/schedule.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/spent_transaction_output.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/unspent_transaction_output.pb.dart';
import 'package:topl_protobuf/consensus/models/operational_certificate.pb.dart';
import 'package:topl_protobuf/consensus/models/staking_address.pb.dart';
import 'package:topl_protobuf/quivr/models/proof.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';

extension ImmutableBytesSyntax on ImmutableBytes {
  ImmutableBytes operator +(ImmutableBytes other) =>
      ImmutableBytes()..value = value + other.value;
}

extension Int32Immutable on Int32 {
  ImmutableBytes get immutable => ImmutableBytes()..value = this.toBigInt.bytes;
}

extension Int64Immutable on Int64 {
  ImmutableBytes get immutable => ImmutableBytes()..value = this.toBigInt.bytes;
}

extension ArrayByteImmutable on List<int> {
  ImmutableBytes get immutable => ImmutableBytes()..value = this;
}

extension StringImmutable on String {
  ImmutableBytes get immutable => ImmutableBytes()..value = utf8.encode(this);
}

extension ListImmutable<T> on List<T> {
  // TODO: Does not align with BramblSc
  ImmutableBytes immutable(ImmutableBytes Function(T) f) =>
      ImmutableBytes()..value = map(f).expand((e) => e.value).toList();
}

// extension NullableImmutable<T> on T? {
//   ImmutableBytes get immutable => this == null
//       ? (ImmutableBytes()..value = [0])
//       : (0x01.immutable + this!.immutable);
// }

extension Int128Immutable on Int128 {
  ImmutableBytes get immutable => value.immutable;
}

extension SmallDataImmutable on SmallData {
  ImmutableBytes get immutable => value.immutable;
}

extension RootImmutable on Root {
  ImmutableBytes get immutable =>
      hasRoot32() ? root32.immutable : root64.immutable;
}

extension VerificationKeyImmutable on VerificationKey {
  ImmutableBytes get immutable => value.immutable;
}

extension WitnessImmutable on Witness {
  ImmutableBytes get immutable => value.immutable;
}

extension DatumImmutable on Datum {
  ImmutableBytes get immutable {
    if (hasEon())
      return eon.immutable;
    else if (hasEra())
      return era.immutable;
    else if (hasEpoch())
      return epoch.immutable;
    else if (hasHeader())
      return header.immutable;
    else if (hasIoTransaction())
      return ioTransaction.immutable;
    else
      throw MatchError(this);
  }
}

extension EonDatumImmutable on Datum_Eon {
  ImmutableBytes get immutable => event.immutable;
}

extension EraDatumImmutable on Datum_Era {
  ImmutableBytes get immutable => event.immutable;
}

extension EpochDatumImmutable on Datum_Epoch {
  ImmutableBytes get immutable => event.immutable;
}

extension HeaderDatumImmutable on Datum_Header {
  ImmutableBytes get immutable => event.immutable;
}

extension IoTransactionDatumImmutable on Datum_IoTransaction {
  ImmutableBytes get immutable => event.immutable;
}

extension IoTransactionImmutable on IoTransaction {
  ImmutableBytes get immutable =>
      inputs.immutable((i) => i.immutable) +
      outputs.immutable((o) => o.immutable) +
      datum.immutable;
}

extension IoTransactionSignable on IoTransaction {
  Future<SignableBytes> get signableBytes async {
    removeProofs(SpentTransactionOutput stxo) {
      // TODO: Other attestation types
      final attestation = stxo.attestation.hasPredicate()
          ? (Attestation()
            ..predicate =
                Attestation_Predicate(lock: stxo.attestation.predicate.lock))
          : stxo.attestation;
      return SpentTransactionOutput()
        ..address = stxo.address
        ..attestation = attestation
        ..value = stxo.value;
    }

    final immutable = (IoTransaction()
          ..inputs.addAll(inputs.map(removeProofs))
          ..outputs.addAll(outputs)
          ..datum = datum)
        .immutable;

    final hash = blake2b256.convert(immutable.value);
    return SignableBytes()..value = hash.bytes;
  }
}

extension IoTransactionIdentifiable on IoTransaction {
  Future<Identifier_IoTransaction32> get id async {
    final signable = await signableBytes;
    return Identifier_IoTransaction32(
        evidence:
            Evidence_Sized32(digest: Digest_Digest32(value: signable.value)));
  }
}

extension ScheduleImmutable on Schedule {
  ImmutableBytes get immutable => min.immutable + max.immutable;
}

extension SpentOutputImmutable on SpentTransactionOutput {
  ImmutableBytes get immutable =>
      address.immutable + attestation.immutable + value.immutable;
}

extension UnspentOutputImmutable on UnspentTransactionOutput {
  ImmutableBytes get immutable => address.immutable + value.immutable;
}

extension BoxImmutable on Box {
  ImmutableBytes get immutable => lock.immutable + value.immutable;
}

extension ValueImmutable on Value {
  ImmutableBytes get immutable {
    if (hasLvl())
      return lvl.immutable;
    else if (hasTopl())
      return topl.immutable;
    else if (hasAsset())
      return asset.immutable;
    else if (hasRegistration())
      return registration.immutable;
    else
      return Int32.ZERO.immutable;
  }
}

extension AddressImmutable on Address {
  ImmutableBytes get immutable =>
      Int32(network).immutable + Int32(ledger).immutable + id.immutable;
}

extension Sized32EvidenceImmutable on Evidence_Sized32 {
  ImmutableBytes get immutable => digest.immutable;
}

extension Sized64EvidenceImmutable on Evidence_Sized64 {
  ImmutableBytes get immutable => digest.immutable;
}

extension EvidenceImmutable on Evidence {
  ImmutableBytes get immutable {
    if (hasSized32())
      return sized32.immutable;
    else if (hasSized64())
      return sized64.immutable;
    else
      throw MatchError(this);
  }
}

extension Digest32Immutable on Digest_Digest32 {
  ImmutableBytes get immutable => value.immutable;
}

extension Digest64Immutable on Digest_Digest64 {
  ImmutableBytes get immutable => value.immutable;
}

extension DigestImmutable on Digest {
  ImmutableBytes get immutable {
    if (hasDigest32())
      return digest32.immutable;
    else if (hasDigest64())
      return digest64.immutable;
    else
      throw MatchError(this);
  }
}

extension PreImageImmutable on Preimage {
  ImmutableBytes get immutable => input.immutable + salt.immutable;
}

extension AccumulatorRoot32IdentifierImmutable on Identifier_AccumulatorRoot32 {
  ImmutableBytes get immutable =>
      IdentifierTags.AccumulatorRoot32.immutable + evidence.immutable;
}

extension AccumulatorRoot64IdentifierImmutable on Identifier_AccumulatorRoot64 {
  ImmutableBytes get immutable =>
      IdentifierTags.AccumulatorRoot64.immutable + evidence.immutable;
}

extension Lock32IdentifierImmutable on Identifier_Lock32 {
  ImmutableBytes get immutable =>
      IdentifierTags.Lock32.immutable + evidence.immutable;
}

extension Lock64IdentifierImmutable on Identifier_Lock64 {
  ImmutableBytes get immutable =>
      IdentifierTags.Lock64.immutable + evidence.immutable;
}

extension IoTransaction32IdentifierImmutable on Identifier_IoTransaction32 {
  ImmutableBytes get immutable =>
      IdentifierTags.IoTransaction32.immutable + evidence.immutable;
}

extension IoTansaction64IdentifierImmutable on Identifier_IoTransaction64 {
  ImmutableBytes get immutable =>
      IdentifierTags.IoTransaction64.immutable + evidence.immutable;
}

extension IdentifierImmutable on Identifier {
  ImmutableBytes get immutable {
    if (hasAccumulatorRoot32())
      return accumulatorRoot32.immutable;
    else if (hasAccumulatorRoot64())
      return accumulatorRoot64.immutable;
    else if (hasLock32())
      return lock32.immutable;
    else if (hasLock64())
      return lock64.immutable;
    else if (hasIoTransaction32())
      return ioTransaction32.immutable;
    else if (hasIoTransaction64())
      return ioTransaction64.immutable;
    else
      throw MatchError(this);
  }
}

extension TransactionOutputAddressImmutable on TransactionOutputAddress {
  ImmutableBytes get immutable =>
      Int32(network).immutable +
      Int32(ledger).immutable +
      Int32(index).immutable +
      (hasIoTransaction32()
          ? ioTransaction32.immutable
          : ioTransaction64.immutable);
}

extension LockAddresImmutable on LockAddress {
  ImmutableBytes get immutable =>
      Int32(network).immutable +
      Int32(ledger).immutable +
      (hasLock32() ? lock32.immutable : lock64.immutable);
}

extension LvlValueImmutable on Value_LVL {
  ImmutableBytes get immutable => quantity.immutable;
}

extension ToplValueImmutable on Value_TOPL {
  ImmutableBytes get immutable => quantity.immutable;
}

extension AssetValueImmutable on Value_Asset {
  ImmutableBytes get immutable =>
      label.immutable + quantity.immutable + metadata.immutable;
}

extension SignatureKesSumImmutable on SignatureKesSum {
  ImmutableBytes get immutable =>
      verificationKey.immutable +
      signature.immutable +
      witness.immutable((l) => l.immutable);
}

extension SignatureKesProductImmutable on SignatureKesProduct {
  ImmutableBytes get immutable =>
      superSignature.immutable + subSignature.immutable + subRoot.immutable;
}

extension StakingAddressImmutable on StakingAddress {
  ImmutableBytes get immutable => value.immutable;
}

extension RegistrationValueImmutable on Value_Registration {
  ImmutableBytes get immutable =>
      registration.immutable + stakingAddress.immutable;
}

extension PredicateLockImmutable on Lock_Predicate {
  ImmutableBytes get immutable =>
      Int32(threshold).immutable + challenges.immutable((c) => c.immutable);
}

extension Image32LockImmutable on Lock_Image32 {
  ImmutableBytes get immutable =>
      Int32(threshold).immutable + leaves.immutable((l) => l.immutable);
}

extension Image64LockImmutable on Lock_Image64 {
  ImmutableBytes get immutable =>
      Int32(threshold).immutable + leaves.immutable((l) => l.immutable);
}

extension Commitment32LockImmutable on Lock_Commitment32 {
  ImmutableBytes get immutable =>
      Int32(threshold).immutable +
      (hasRoot() ? [1].immutable + root.immutable : [0].immutable);
}

extension Commitment64LockImmutable on Lock_Commitment64 {
  ImmutableBytes get immutable =>
      Int32(threshold).immutable +
      (hasRoot() ? [1].immutable + root.immutable : [0].immutable);
}

extension LockImmutable on Lock {
  ImmutableBytes get immutable {
    if (hasPredicate())
      return predicate.immutable;
    else if (hasImage32())
      return image32.immutable;
    else if (hasImage64())
      return image64.immutable;
    else if (hasCommitment32())
      return commitment32.immutable;
    else if (hasCommitment64())
      return commitment64.immutable;
    else
      throw MatchError(this);
  }

  Evidence_Sized32 get evidence32 => Evidence_Sized32(
      digest:
          Digest_Digest32(value: blake2b256.convert(immutable.value).bytes));

  LockAddress address({int network = 0, int ledger = 0}) => LockAddress(
      network: 0, ledger: 0, lock32: Identifier_Lock32(evidence: evidence32));
}

extension PredicateAttestationImmutable on Attestation_Predicate {
  ImmutableBytes get immutable =>
      lock.immutable + responses.immutable((r) => r.immutable);
}

extension Image32AttestationImmutable on Attestation_Image32 {
  ImmutableBytes get immutable =>
      lock.immutable +
      known.immutable((k) => k.immutable) +
      responses.immutable((r) => r.immutable);
}

extension Image64AttestationImmutable on Attestation_Image64 {
  ImmutableBytes get immutable =>
      lock.immutable +
      known.immutable((k) => k.immutable) +
      responses.immutable((r) => r.immutable);
}

extension Commitment32AttetationImmutable on Attestation_Commitment32 {
  ImmutableBytes get immutable =>
      lock.immutable +
      known.immutable((k) => k.immutable) +
      responses.immutable((r) => r.immutable);
}

extension Commitment64AttestationImmutable on Attestation_Commitment64 {
  ImmutableBytes get immutable =>
      lock.immutable +
      known.immutable((k) => k.immutable) +
      responses.immutable((r) => r.immutable);
}

extension AttetationImmutable on Attestation {
  ImmutableBytes get immutable {
    if (hasPredicate())
      return predicate.immutable;
    else if (hasImage32())
      return image32.immutable;
    else if (hasImage64())
      return image64.immutable;
    else if (hasCommitment32())
      return commitment32.immutable;
    else if (hasCommitment64())
      return commitment64.immutable;
    else
      throw MatchError(this);
  }
}

extension TransactionInputAddressImmutable on TransactionInputAddress {
  ImmutableBytes get immutable =>
      Int32(network).immutable +
      Int32(ledger).immutable +
      Int32(index).immutable +
      (hasIoTransaction32()
          ? ioTransaction32.immutable
          : ioTransaction64.immutable);
}

extension PreviousPropositionChallengeContainsImmutable
    on Challenge_PreviousProposition {
  ImmutableBytes get immutable => address.immutable + Int32(index).immutable;
}

extension ChallengeContainsImmutable on Challenge {
  ImmutableBytes get immutable {
    if (hasRevealed())
      return revealed.immutable;
    else if (hasPrevious())
      return previous.immutable;
    else
      throw MatchError(this);
  }
}

extension EonEventImmutable on Event_Eon {
  ImmutableBytes get immutable => beginSlot.immutable + height.immutable;
}

extension EraEventImmutable on Event_Era {
  ImmutableBytes get immutable => beginSlot.immutable + height.immutable;
}

extension EpochEventImmutable on Event_Epoch {
  ImmutableBytes get immutable => beginSlot.immutable + height.immutable;
}

extension HeaderEventImmutable on Event_Header {
  ImmutableBytes get immutable => height.immutable;
}

extension IoTransactionEventImmutable on Event_IoTransaction {
  ImmutableBytes get immutable => schedule.immutable + metadata.immutable;
}

extension EventImmutable on Event {
  ImmutableBytes get immutable {
    if (hasEon())
      return eon.immutable;
    else if (hasEra())
      return era.immutable;
    else if (hasEpoch())
      return epoch.immutable;
    else if (hasHeader())
      return header.immutable;
    else if (hasIoTransaction())
      return ioTransaction.immutable;
    else
      throw MatchError(this);
  }
}

extension TxBindImmutable on TxBind {
  ImmutableBytes get immutable => value.immutable;
}

extension LockedImmutable on Proposition_Locked {
  ImmutableBytes get immutable => Tokens.Locked.immutable;
}

extension LockedProofImmutable on Proof_Locked {
  ImmutableBytes get immutable => ImmutableBytes();
}

extension DigestPropositionImmutable on Proposition_Digest {
  ImmutableBytes get immutable =>
      Tokens.Digest.immutable + routine.immutable + digest.immutable;
}

extension DigestProofImmutable on Proof_Digest {
  ImmutableBytes get immutable =>
      transactionBind.immutable + preimage.immutable;
}

extension SignatureImmutable on Proposition_DigitalSignature {
  ImmutableBytes get immutable =>
      Tokens.DigitalSignature.immutable +
      routine.immutable +
      verificationKey.immutable;
}

extension SignatureProofImmutable on Proof_DigitalSignature {
  ImmutableBytes get immutable => transactionBind.immutable + witness.immutable;
}

extension HeightRangeImmutable on Proposition_HeightRange {
  ImmutableBytes get immutable =>
      Tokens.HeightRange.immutable +
      chain.immutable +
      min.immutable +
      max.immutable;
}

extension HeightRangeProofImmutable on Proof_HeightRange {
  ImmutableBytes get immutable => transactionBind.immutable;
}

extension TickRangeImmutable on Proposition_TickRange {
  ImmutableBytes get immutable =>
      Tokens.TickRange.immutable + min.immutable + max.immutable;
}

extension TickRangeProofImmutable on Proof_TickRange {
  ImmutableBytes get immutable => transactionBind.immutable;
}

extension ExactMatchImmutable on Proposition_ExactMatch {
  ImmutableBytes get immutable =>
      Tokens.ExactMatch.immutable + location.immutable + compareTo.immutable;
}

extension ExactMatchProofImmutable on Proof_ExactMatch {
  ImmutableBytes get immutable => transactionBind.immutable;
}

extension LessThanImmutable on Proposition_LessThan {
  ImmutableBytes get immutable =>
      Tokens.LessThan.immutable + location.immutable + compareTo.immutable;
}

extension LessThanProofImmutable on Proof_LessThan {
  ImmutableBytes get immutable => transactionBind.immutable;
}

extension GreaterThanImmutable on Proposition_GreaterThan {
  ImmutableBytes get immutable =>
      Tokens.GreaterThan.immutable + location.immutable + compareTo.immutable;
}

extension GreaterThanProofImmutable on Proof_GreaterThan {
  ImmutableBytes get immutable => transactionBind.immutable;
}

extension EqualToImmutable on Proposition_EqualTo {
  ImmutableBytes get immutable =>
      Tokens.EqualTo.immutable + location.immutable + compareTo.immutable;
}

extension EqualToProofImmutable on Proof_EqualTo {
  ImmutableBytes get immutable => transactionBind.immutable;
}

extension ThresholdImmutable on Proposition_Threshold {
  ImmutableBytes get immutable =>
      Tokens.Threshold.immutable +
      Int32(threshold).immutable +
      challenges.immutable((c) => c.immutable);
}

extension ThresholdProofImmutable on Proof_Threshold {
  ImmutableBytes get immutable =>
      transactionBind.immutable + responses.immutable((p) => p.immutable);
}

extension NotImmutable on Proposition_Not {
  ImmutableBytes get immutable => Tokens.Not.immutable + proposition.immutable;
}

extension NotProofImmutable on Proof_Not {
  ImmutableBytes get immutable => transactionBind.immutable + proof.immutable;
}

extension AndImmutable on Proposition_And {
  ImmutableBytes get immutable =>
      Tokens.And.immutable + left.immutable + right.immutable;
}

extension AndProofImmutable on Proof_And {
  ImmutableBytes get immutable =>
      transactionBind.immutable + left.immutable + right.immutable;
}

extension OrImmutable on Proposition_Or {
  ImmutableBytes get immutable =>
      Tokens.Or.immutable + left.immutable + right.immutable;
}

extension OrProofImmutable on Proof_Or {
  ImmutableBytes get immutable =>
      transactionBind.immutable + left.immutable + right.immutable;
}

extension PropositionImmutable on Proposition {
  ImmutableBytes get immutable {
    if (hasLocked())
      return locked.immutable;
    else if (hasDigest())
      return digest.immutable;
    else if (hasDigitalSignature())
      return digitalSignature.immutable;
    else if (hasHeightRange())
      return heightRange.immutable;
    else if (hasTickRange())
      return tickRange.immutable;
    else if (hasExactMatch())
      return exactMatch.immutable;
    else if (hasLessThan())
      return lessThan.immutable;
    else if (hasGreaterThan())
      return greaterThan.immutable;
    else if (hasEqualTo())
      return equalTo.immutable;
    else if (hasThreshold())
      return threshold.immutable;
    else if (hasNot())
      return not.immutable;
    else if (hasAnd())
      return and.immutable;
    else if (hasOr())
      return or.immutable;
    else
      throw MatchError(this);
  }
}

extension ProofImmutable on Proof {
  ImmutableBytes get immutable {
    if (hasLocked())
      return locked.immutable;
    else if (hasDigest())
      return digest.immutable;
    else if (hasDigitalSignature())
      return digitalSignature.immutable;
    else if (hasHeightRange())
      return heightRange.immutable;
    else if (hasTickRange())
      return tickRange.immutable;
    else if (hasExactMatch())
      return exactMatch.immutable;
    else if (hasLessThan())
      return lessThan.immutable;
    else if (hasGreaterThan())
      return greaterThan.immutable;
    else if (hasEqualTo())
      return equalTo.immutable;
    else if (hasThreshold())
      return threshold.immutable;
    else if (hasNot())
      return not.immutable;
    else if (hasAnd())
      return and.immutable;
    else if (hasOr())
      return or.immutable;
    else
      throw MatchError(this);
  }
}

class MatchError implements Exception {
  final Object value;

  MatchError(this.value);
  @override
  String toString() => 'MatchError: $value';
}
