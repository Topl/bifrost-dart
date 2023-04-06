import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_ledger/algebras/body_semantic_validation_algebra.dart';
import 'package:bifrost_ledger/algebras/transaction_semantic_validation_algebra.dart';
import 'package:bifrost_ledger/models/body_validation_context.dart';
import 'package:bifrost_ledger/models/transaction_validation_context.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class BodySemanticValidation extends BodySemanticValidationAlgebra {
  final Future<IoTransaction> Function(TransactionId) fetchTransaction;
  final TransactionSemanticValidationAlgebra transactionSemanticValidation;

  BodySemanticValidation(
      this.fetchTransaction, this.transactionSemanticValidation);

  @override
  Future<List<String>> validate(
      BlockBody body, BodyValidationContext context) async {
    final prefix = <IoTransaction>[];
    final transactionValidationContext = TransactionValidationContext(
        context.parentHeaderId, prefix, context.height, context.slot);
    for (final transactionId in body.transactionIds) {
      final transaction = await fetchTransaction(transactionId);
      final errors = await transactionSemanticValidation.validate(
          transaction, transactionValidationContext);
      if (errors.isNotEmpty)
        return errors;
      else
        prefix.add(transaction);
    }
    return [];
  }
}
