import 'dart:async';
import 'dart:typed_data';
import 'package:bifrost_common/models/unsigned.dart';
import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';

// Source: https://github.com/dart-lang/sdk/issues/32803#issuecomment-1228291047
extension BigIntOps on BigInt {
  Int8List get bytes {
    final data = ByteData((bitLength / 8).ceil());
    var _bigInt = this;

    for (var i = data.lengthInBytes - 1; i >= 0; i--) {
      data.setUint8(i, _bigInt.toUnsigned(8).toInt());
      _bigInt = _bigInt >> 8;
    }

    return Int8List.view(data.buffer);
  }

  Int128 get toInt128 {
    final b = bytes;
    if (b.length > 16) {
      throw Exception("BigInt too large to fit in Int128");
    }
    return Int128(value: b);
  }
}

extension Int64Ops on Int64 {
  BigInt get toBigInt => BigInt.parse(toString());
}

extension ListIntOps on List<int> {
  BigInt get toBigInt {
    final data = Int8List.fromList(this).buffer.asByteData();
    BigInt _bigInt = BigInt.zero;

    for (var i = 0; i < data.lengthInBytes; i++) {
      _bigInt = (_bigInt << 8) | BigInt.from(data.getUint8(i));
    }
    return _bigInt;
  }
}

extension Int128Ops on Int128 {
  BigInt get toBigInt => value.toBigInt;
}

extension BlockHeaderOps on BlockHeader {
  UnsignedBlockHeader get unsigned => UnsignedBlockHeader(
        parentHeaderId,
        parentSlot,
        txRoot,
        bloomFilter,
        timestamp,
        height,
        slot,
        eligibilityCertificate,
        PartialOperationalCertificate(
            operationalCertificate.parentVK,
            operationalCertificate.parentSignature,
            operationalCertificate.childVK),
        metadata,
        address,
      );
}

// Alias's Flutter's "compute()" function signature
typedef DComputeCallback<Q, R> = FutureOr<R> Function(Q message);

typedef DComputeImpl = Future<R> Function<Q, R>(
    DComputeCallback<Q, R> callback, Q message,
    {String? debugLabel});

Future<R> LocalCompute<Q, R>(DComputeCallback<Q, R> callback, Q message,
        {String? debugLabel}) async =>
    callback(message);
