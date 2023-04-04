import 'package:topl_protobuf/brambl/models/address.pb.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';

abstract class BoxStateAlgebra {
  Future<bool> boxExistsAt(BlockId blockId, TransactionOutputAddress boxId);
}
