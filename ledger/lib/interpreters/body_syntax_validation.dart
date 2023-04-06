import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_ledger/algebras/body_syntax_validation_algebra.dart';
import 'package:brambl/brambl.dart';
import 'package:topl_protobuf/brambl/models/address.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class BodySyntaxValidation extends BodySyntaxValidationAlgebra {
  final Future<IoTransaction> Function(TransactionId) fetchTransaction;
  final TransactionSyntaxVerifier transactionSyntaxVerifier;

  BodySyntaxValidation(this.fetchTransaction, this.transactionSyntaxVerifier);
  @override
  Future<List<String>> validate(BlockBody body) async {
    final transactions = await Future.wait(body.transactionIds
        .map((transactionId) => fetchTransaction(transactionId)));
    final errors = <String>[];
    errors.addAll(_validateDistinctInputs(transactions));
    if (errors.isNotEmpty) return errors;
    for (final transaction in transactions) {
      errors.addAll(await transactionSyntaxVerifier.validate(transaction));
      if (errors.isNotEmpty) return errors;
    }
    return [];
  }

  List<String> _validateDistinctInputs(Iterable<IoTransaction> transactions) {
    final inputs = <TransactionOutputAddress>{};
    for (final transaction in transactions) {
      for (final input in transaction.inputs) {
        final address = input.address;
        if (inputs.contains(address)) {
          return ["DoubleSpend"];
        }
        inputs.add(address);
      }
    }
    return [];
  }
}
