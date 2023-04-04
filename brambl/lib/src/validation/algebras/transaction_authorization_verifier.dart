import 'package:quivr/quivr.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';

abstract class TransactionAuthorizationVerifier {
  Future<List<String>> validate(
      IoTransaction transaction, DynamicContext context);
}
