import 'dart:io';
import 'dart:typed_data';

import 'package:bifrost_codecs/codecs.dart';
import 'package:bifrost_common/algebras/store_algebra.dart';
import 'package:bifrost_persistence/objectbox.g.dart';
import 'package:fast_base58/fast_base58.dart';
import 'package:fixnum/fixnum.dart';
import 'package:path_provider/path_provider.dart';
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/consensus/models/eligibility_certificate.pb.dart';
import 'package:topl_protobuf/consensus/models/operational_certificate.pb.dart';
import 'package:topl_protobuf/consensus/models/staking_address.pb.dart';

class BoxStore<Key, Value, BoxRepr> extends StoreAlgebra<Key, Value> {
  final Box<BoxRepr> box;
  final Future<Condition<BoxRepr>> Function(Key) fetchByKeyQuery;
  final Future<Value> Function(BoxRepr) convertToValue;
  final Future<BoxRepr> Function(Value) convertToBoxRepr;

  BoxStore(this.box, this.fetchByKeyQuery, this.convertToValue,
      this.convertToBoxRepr);

  @override
  Future<bool> contains(Key id) async {
    final query = box.query(await fetchByKeyQuery(id)).build();

    final resultsCount = query.count();
    query.close();
    return resultsCount > 0;
  }

  @override
  Future<Value?> get(Key id) async {
    final query = box.query(await fetchByKeyQuery(id)).build();

    final resultOpt = await query.findFirstAsync();
    query.close();
    if (resultOpt != null)
      return convertToValue(resultOpt);
    else
      return null;
  }

  @override
  Future<void> put(Key id, Value value) async =>
      box.putAsync(await convertToBoxRepr(value));

  @override
  Future<void> remove(Key id) async {
    final query = box.query(await fetchByKeyQuery(id)).build();
    final ids = await query.findIdsAsync();
    query.close();
    await box.removeManyAsync(ids);
  }
}

class HeaderStore extends StoreAlgebra<BlockId, BlockHeader> {
  final Store objectBoxStore;

  HeaderStore(this.objectBoxStore);

  Box<ObjectBoxBlockHeader> get box => objectBoxStore.box();

  static Future<HeaderStore> create({Directory? basePath}) async {
    defaultDocsDir() async {
      final tmp = await getTemporaryDirectory();
      return Directory(
          tmp.path + '/bifrost-dart-${DateTime.now().millisecondsSinceEpoch}');
    }

    Directory docsDir = basePath ?? (await defaultDocsDir());
    await docsDir.create(recursive: true);
    final store =
        await openStore(directory: docsDir.path + '/object-box-headers');

    return HeaderStore(store);
  }

  StoreAlgebra<BlockId, BlockHeader> get store =>
      BoxStore<BlockId, BlockHeader, ObjectBoxBlockHeader>(
          box, _fetchByKeyQuery, _convertToValue, _convertToBoxRepr);

  Future<Condition<ObjectBoxBlockHeader>> _fetchByKeyQuery(BlockId id) async =>
      ObjectBoxBlockHeader_.idBase58.equals(id.value.base58);

  Future<BlockHeader> _convertToValue(ObjectBoxBlockHeader result) async =>
      BlockHeader(
        parentHeaderId:
            BlockId(value: Base58Decode(result.parentHeaderIdBase58)),
        parentSlot: Int64(result.parentSlot),
        txRoot: result.txRoot,
        bloomFilter: result.bloomFilter,
        timestamp: Int64(result.timestamp),
        height: Int64(result.height),
        slot: Int64(result.slot),
        eligibilityCertificate:
            EligibilityCertificate.fromBuffer(result.eligibilityCertificate),
        operationalCertificate:
            OperationalCertificate.fromBuffer(result.operationalCertificate),
        metadata: result.metadata,
        address: StakingAddress(value: Base58Decode(result.address)),
      );

  Future<ObjectBoxBlockHeader> _convertToBoxRepr(BlockHeader header) async {
    final id = await header.id;
    final idBase58 = id.value.base58;
    final parentHeaderIdBase58 = header.parentHeaderId.value.base58;
    final address = header.address.value.base58;
    return ObjectBoxBlockHeader(
      idBase58: idBase58,
      parentHeaderIdBase58: parentHeaderIdBase58,
      parentSlot: header.parentSlot.toInt(),
      txRoot: Uint8List.fromList(header.txRoot),
      bloomFilter: Uint8List.fromList(header.bloomFilter),
      timestamp: header.timestamp.toInt(),
      height: header.height.toInt(),
      slot: header.slot.toInt(),
      eligibilityCertificate: header.eligibilityCertificate.writeToBuffer(),
      operationalCertificate: header.operationalCertificate.writeToBuffer(),
      metadata:
          header.hasMetadata() ? Uint8List.fromList(header.metadata) : null,
      address: address,
    );
  }

  @override
  Future<BlockHeader?> get(BlockId id) async {
    final idBase58 = id.value.base58;

    final query =
        box.query(ObjectBoxBlockHeader_.idBase58.equals(idBase58)).build();

    final resultOpt = await query.findFirstAsync();
    query.close();
    if (resultOpt != null) {
      final ObjectBoxBlockHeader result = resultOpt;
      return BlockHeader(
        parentHeaderId:
            BlockId(value: Base58Decode(result.parentHeaderIdBase58)),
        parentSlot: Int64(result.parentSlot),
        txRoot: result.txRoot,
        bloomFilter: result.bloomFilter,
        timestamp: Int64(result.timestamp),
        height: Int64(result.height),
        slot: Int64(result.slot),
        eligibilityCertificate:
            EligibilityCertificate.fromBuffer(result.eligibilityCertificate),
        operationalCertificate:
            OperationalCertificate.fromBuffer(result.operationalCertificate),
        metadata: result.metadata,
        address: StakingAddress(value: Base58Decode(result.address)),
      );
    } else
      return null;
  }

  @override
  Future<void> put(BlockId id, BlockHeader header) async {
    final idBase58 = id.value.base58;
    final parentHeaderIdBase58 = header.parentHeaderId.value.base58;
    final address = header.address.value.base58;
    final newHeader = ObjectBoxBlockHeader(
      idBase58: idBase58,
      parentHeaderIdBase58: parentHeaderIdBase58,
      parentSlot: header.parentSlot.toInt(),
      txRoot: Uint8List.fromList(header.txRoot),
      bloomFilter: Uint8List.fromList(header.bloomFilter),
      timestamp: header.timestamp.toInt(),
      height: header.height.toInt(),
      slot: header.slot.toInt(),
      eligibilityCertificate: header.eligibilityCertificate.writeToBuffer(),
      operationalCertificate: header.operationalCertificate.writeToBuffer(),
      metadata:
          header.hasMetadata() ? Uint8List.fromList(header.metadata) : null,
      address: address,
    );
    await box.putAsync(newHeader);
  }

  @override
  Future<bool> contains(BlockId id) async {
    final idBase58 = id.value.base58;
    final query =
        box.query(ObjectBoxBlockHeader_.idBase58.equals(idBase58)).build();

    final resultsCount = query.count();
    query.close();
    return resultsCount > 0;
  }

  @override
  Future<void> remove(BlockId id) async {
    final idBase58 = id.value.base58;
    final query =
        box.query(ObjectBoxBlockHeader_.idBase58.equals(idBase58)).build();
    final ids = await query.findIdsAsync();
    query.close();
    await box.removeManyAsync(ids);
  }
}

@Entity()
class ObjectBoxBlockHeader {
  int id;
  @Unique()
  String idBase58;
  @Index()
  String parentHeaderIdBase58;
  int parentSlot;
  Uint8List txRoot;
  Uint8List bloomFilter;
  int timestamp;
  @Index()
  int height;
  @Index()
  int slot;
  Uint8List eligibilityCertificate;
  Uint8List operationalCertificate;
  Uint8List? metadata;
  @Index()
  String address;

  ObjectBoxBlockHeader({
    this.id = 0,
    required this.idBase58,
    required this.parentHeaderIdBase58,
    required this.parentSlot,
    required this.txRoot,
    required this.bloomFilter,
    required this.timestamp,
    required this.height,
    required this.slot,
    required this.eligibilityCertificate,
    required this.operationalCertificate,
    this.metadata,
    required this.address,
  });
}
