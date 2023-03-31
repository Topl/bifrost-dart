import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:hashlib/hashlib.dart';

extension IterableEqOps<T> on Iterable<T> {
  bool sameElements(Iterable<T> other) =>
      const IterableEquality().equals(this, other);
}

extension Uint8ListOps on Uint8List {
  Int8List get int8List {
    final result = Int8List(this.length);
    for (int i = 0; i < this.length; i++) {
      result[i] = this[i] & 0xff;
    }
    return result;
  }
}

extension ListIntOps on List<int> {
  Future<List<int>> get hash256 async =>
      blake2b256.convert(this).bytes.int8List;

  Future<List<int>> get hash512 async =>
      blake2b512.convert(this).bytes.int8List;
}
