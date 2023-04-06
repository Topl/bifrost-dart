import 'package:bifrost_ledger/models/transaction_validation_context.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';

abstract class TransactionSemanticValidationAlgebra {
  Future<List<String>> validate(
      IoTransaction transaction, TransactionValidationContext context);
}
