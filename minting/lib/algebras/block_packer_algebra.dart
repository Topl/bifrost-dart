import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

abstract class BlockPackerAlgebra {
  Future<Iterative<FullBlockBody>> improvePackedBlock(
    BlockId parentBlockId,
    Int64 height,
    Int64 slot,
  );
}

typedef Iterative<E> = Future<E?> Function(E);
