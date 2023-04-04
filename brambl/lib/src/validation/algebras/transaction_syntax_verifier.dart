import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';

abstract class TransactionSyntaxVerifier {
  Future<List<String>> validate(IoTransaction transaction);
}
