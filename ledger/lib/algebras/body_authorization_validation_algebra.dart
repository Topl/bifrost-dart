import 'package:quivr/quivr.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

abstract class BodyAuthorizationValidationAlgebra {
  Future<List<String>> validate(BlockBody body,
      Future<DynamicContext> Function(IoTransaction) quivrContextBuilder);
}
