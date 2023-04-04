import 'package:topl_protobuf/node/models/block.pb.dart';

abstract class BodySyntaxValidationAlgebra {
  Future<List<String>> validate(BlockBody body);
}
