import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_ledger/algebras/box_state_algebra.dart';
import 'package:bifrost_ledger/algebras/transaction_semantic_validation_algebra.dart';
import 'package:bifrost_ledger/interpreters/box_state.dart';
import 'package:bifrost_ledger/models/transaction_validation_context.dart';
import 'package:brambl/brambl.dart';
import 'package:topl_protobuf/brambl/models/box/lock.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/spent_transaction_output.pb.dart';

class TransactionSemanticValidation
    extends TransactionSemanticValidationAlgebra {
  final Future<IoTransaction> Function(TransactionId) fetchTransaction;
  final BoxStateAlgebra boxState;

  TransactionSemanticValidation(this.fetchTransaction, this.boxState);

  @override
  Future<List<String>> validate(
      IoTransaction transaction, TransactionValidationContext context) async {
    var augmentation = StateAugmentation.empty();

    for (final transaction in context.prefix) {
      augmentation.augment(transaction);
    }

    final errors = <String>[];
    errors.addAll(_scheduleValidation(transaction, context));
    if (errors.isNotEmpty) return errors;
    for (final input in transaction.inputs) {
      errors.addAll(await _dataValidation(input, context));
      if (errors.isNotEmpty) return errors;
      errors.addAll(await _spendableValidation(input, context));
      if (errors.isNotEmpty) return errors;
    }
    return [];
  }

  List<String> _scheduleValidation(
      IoTransaction transaction, TransactionValidationContext context) {
    final schedule = transaction.datum.event.schedule;
    final slot = context.slot;
    if (slot >= schedule.min && slot <= schedule.max)
      return [];
    else
      return ["UnsatifiedSchedule"];
  }

  Future<List<String>> _dataValidation(SpentTransactionOutput input,
      TransactionValidationContext context) async {
    final spentTransaction =
        await fetchTransaction(input.address.ioTransaction32);
    if (spentTransaction.outputs.length <= input.address.index)
      return ["UnspendableBox"];
    final spentOutput = spentTransaction.outputs[input.address.index];
    if (spentOutput.value != input.value) return ["InputDataMismatch"];
    // TODO: Other predicate types
    final expectedEvidence =
        Lock(predicate: input.attestation.predicate.lock).evidence32;
    if (spentOutput.address.lock32.evidence != expectedEvidence)
      return ["InputDataMismatch"];
    return [];
  }

  Future<List<String>> _spendableValidation(SpentTransactionOutput input,
      TransactionValidationContext context) async {
    final boxExists =
        await boxState.boxExistsAt(context.parentHeaderId, input.address);
    if (!boxExists) return ["UnspendableBox"];
    return [];
  }
}
