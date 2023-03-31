import 'dart:typed_data';

import 'package:bifrost_crypto/utils.dart';

import 'package:convert/convert.dart';

extension StringOps on String {
  Int8List get hexStringToBytes => (hex.decode(this) as Uint8List).int8List;
}
