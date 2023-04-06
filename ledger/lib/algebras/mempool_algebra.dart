import 'package:bifrost_common/models/common.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';

abstract class MempoolAlgebra {
  Future<Set<TransactionId>> read(BlockId currentHead);
  Future<void> add(TransactionId transactionId);
  Future<void> remove(TransactionId transactionId);
}
