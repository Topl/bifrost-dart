import 'package:bifrost_ledger/src/models/body_validation_context.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

abstract class BodySemanticValidationAlgebra {
  Future<List<String>> validate(BlockBody body, BodyValidationContext context);
}
