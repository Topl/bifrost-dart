import 'package:bifrost_common/utils.dart';
import 'package:brambl/src/validation/algebras/transaction_syntax_verifier.dart';
import 'package:collection/collection.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/quivr/models/proof.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';

class TransactionSyntaxInterpreter extends TransactionSyntaxVerifier {
  @override
  Future<List<String>> validate(IoTransaction transaction) async {
    for (final validator in validators) {
      final errors = validator(transaction);
      if (errors.isNotEmpty) {
        return errors;
      }
    }

    return [];
  }

  static const validators = [
    nonEmptyInputsValidation,
    distinctInputsValidation,
    maximumOutputsCountValidation,
    positiveTimestampValidation,
    scheduleValidation,
    dataLengthValidation,
    positiveOutputValuesValidation,
    sufficientFundsValidation,
    attestationValidation,
  ];

  static List<String> nonEmptyInputsValidation(IoTransaction transaction) {
    if (transaction.inputs.isEmpty) {
      return ["EmptyInputs"];
    }
    return [];
  }

  static List<String> distinctInputsValidation(IoTransaction transaction) {
    if (transaction.inputs
        .groupListsBy((input) => input.address)
        .entries
        .where((entry) => entry.value.length > 1)
        .isNotEmpty) {
      return ["DuplicateInputs"];
    }
    return [];
  }

  static List<String> maximumOutputsCountValidation(IoTransaction transaction) {
    if (transaction.outputs.length > MaxOutputsCount) {
      return ["ExcessiveOutputsCount"];
    }
    return [];
  }

  static List<String> positiveTimestampValidation(IoTransaction transaction) {
    if (transaction.datum.event.schedule.timestamp < 0) {
      return ["InvalidTimestamp"];
    }
    return [];
  }

  static List<String> scheduleValidation(IoTransaction transaction) {
    final schedule = transaction.datum.event.schedule;
    if (schedule.max < schedule.min || schedule.min < 0) {
      return ["InvalidSchedule"];
    }
    return [];
  }

  static List<String> dataLengthValidation(IoTransaction transaction) {
    // TODO: Transaction immutable bytes
    return [];
  }

  static List<String> positiveOutputValuesValidation(
      IoTransaction transaction) {
    for (final output in transaction.outputs) {
      final value = output.value;
      if (value.hasLvl()) {
        if (value.lvl.quantity.toBigInt <= BigInt.zero)
          return ["NonPositiveOutputValue"];
      } else if (value.hasTopl()) {
        if (value.topl.quantity.toBigInt <= BigInt.zero)
          return ["NonPositiveOutputValue"];
      } else if (value.hasAsset()) {
        if (value.asset.quantity.toBigInt <= BigInt.zero)
          return ["NonPositiveOutputValue"];
      }
    }
    return [];
  }

  static List<String> sufficientFundsValidation(IoTransaction transaction) {
    BigInt lvlsBalance = BigInt.zero;
    BigInt toplsBalance = BigInt.zero;
    Map<String, BigInt> assetsBalance = {};
    for (final input in transaction.inputs) {
      if (input.value.hasLvl()) {
        lvlsBalance += input.value.lvl.quantity.toBigInt;
      } else if (input.value.hasTopl()) {
        toplsBalance += input.value.topl.quantity.toBigInt;
      } else if (input.value.hasAsset()) {
        final aBalance = assetsBalance[input.value.asset.label] ?? BigInt.zero;
        assetsBalance[input.value.asset.label] =
            aBalance + input.value.asset.quantity.toBigInt;
      }
    }
    for (final output in transaction.outputs) {
      if (output.value.hasLvl()) {
        lvlsBalance -= output.value.lvl.quantity.toBigInt;
      } else if (output.value.hasTopl()) {
        toplsBalance -= output.value.topl.quantity.toBigInt;
      } else if (output.value.hasAsset()) {
        final aBalance = assetsBalance[output.value.asset.label] ?? BigInt.zero;
        assetsBalance[output.value.asset.label] =
            aBalance - output.value.asset.quantity.toBigInt;
      }
    }
    if (lvlsBalance < BigInt.zero || toplsBalance < BigInt.zero) {
      return ["InsufficientFunds"];
    }
    for (final assetBalance in assetsBalance.values) {
      if (assetBalance < BigInt.zero) {
        return ["InsufficientFunds"];
      }
    }
    return [];
  }

  static List<String> attestationValidation(IoTransaction transaction) {
    List<String> verifyPropositionProofType(
        Proposition proposition, Proof proof) {
      // Empty proof is always valid
      if (proof == Proof.getDefault()) return [];
      if (proposition.hasLocked() && !proof.hasLocked())
        return ["InvalidProofType"];
      if (proposition.hasDigest() && !proof.hasDigest())
        return ["InvalidProofType"];
      if (proposition.hasDigitalSignature() && !proof.hasDigitalSignature())
        return ["InvalidProofType"];
      if (proposition.hasHeightRange() && !proof.hasHeightRange())
        return ["InvalidProofType"];
      if (proposition.hasTickRange() && !proof.hasTickRange())
        return ["InvalidProofType"];
      if (proposition.hasExactMatch() && !proof.hasExactMatch())
        return ["InvalidProofType"];
      if (proposition.hasLessThan() && !proof.hasLessThan())
        return ["InvalidProofType"];
      if (proposition.hasGreaterThan() && !proof.hasGreaterThan())
        return ["InvalidProofType"];
      if (proposition.hasEqualTo() && !proof.hasEqualTo())
        return ["InvalidProofType"];
      if (proposition.hasThreshold() && !proof.hasThreshold())
        return ["InvalidProofType"];
      if (proposition.hasAnd() && !proof.hasAnd()) return ["InvalidProofType"];
      if (proposition.hasOr() && !proof.hasOr()) return ["InvalidProofType"];
      if (proposition.hasNot() && !proof.hasNot()) return ["InvalidProofType"];
      return <String>[];
    }

    for (final input in transaction.inputs) {
      if (!input.hasAttestation() || !input.attestation.hasPredicate()) {
        return ["InvalidAttestationType"];
      }
      final predicate = input.attestation.predicate;
      final lock = predicate.lock;
      if (lock.challenges.length != predicate.responses.length)
        return ["InvalidAttestation"];
      for (var i = 0; i < lock.challenges.length; i++) {
        final challenge = lock.challenges[i];
        final response = predicate.responses[i];
        final tRes = verifyPropositionProofType(challenge.revealed, response);
        if (tRes.isNotEmpty) return tRes;
      }
    }
    return [];
  }

  static const MaxDataLength = 15360;
  static const MaxOutputsCount = 32767;
}
