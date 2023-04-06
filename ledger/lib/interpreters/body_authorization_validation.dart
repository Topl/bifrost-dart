import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_ledger/algebras/body_authorization_validation_algebra.dart';
import 'package:brambl/brambl.dart';
import 'package:quivr/src/verifier.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class BodyAuthorizationValidation extends BodyAuthorizationValidationAlgebra {
  final Future<IoTransaction> Function(TransactionId) fetchTransaction;
  final TransactionAuthorizationVerifier transactionAuthorizationVerifier;

  BodyAuthorizationValidation(
      this.fetchTransaction, this.transactionAuthorizationVerifier);

  @override
  Future<List<String>> validate(
      BlockBody body,
      Future<DynamicContext> Function(IoTransaction)
          quivrContextBuilder) async {
    for (final transactionId in body.transactionIds) {
      final transaction = await fetchTransaction(transactionId);
      final errors = await transactionAuthorizationVerifier.validate(
          transaction, await quivrContextBuilder(transaction));
      if (errors.isNotEmpty) return errors;
    }
    return [];
  }
}
