import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';

class BodyValidationContext {
  final BlockId parentHeaderId;
  final Int64 height;
  final Int64 slot;

  BodyValidationContext(
    this.parentHeaderId,
    this.height,
    this.slot,
  );
}
