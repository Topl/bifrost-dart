import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';

class TransactionValidationContext {
  final BlockId parentHeaderId;
  final List<IoTransaction> prefix;
  final Int64 height;
  final Int64 slot;

  TransactionValidationContext(
    this.parentHeaderId,
    this.prefix,
    this.height,
    this.slot,
  );
}
