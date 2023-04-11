import 'package:bifrost_common/algebras/event_sourced_state_algebra.dart';
import 'package:bifrost_common/algebras/store_algebra.dart';
import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_consensus/algebras/local_chain_algebra.dart';
import 'package:bifrost_ledger/algebras/mempool_algebra.dart';
import 'package:brambl/brambl.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';
import 'package:topl_protobuf/node/services/bifrost_rpc.pbgrpc.dart';

class NodeGrpc extends NodeRpcServiceBase {
  final Future<BlockHeader?> Function(BlockId) _fetchHeader;
  final Future<BlockBody?> Function(BlockId) _fetchBody;
  final StoreAlgebra<TransactionId, IoTransaction> _transactionStore;
  final LocalChainAlgebra _localChain;
  final MempoolAlgebra _mempool;
  final Future<List<String>> Function(IoTransaction) _validateTransaction;
  final EventSourcedStateAlgebra<Future<BlockId?> Function(Int64), BlockId>
      blockHeights;

  final log = Logger("NodeGrpc");

  NodeGrpc(
    this._fetchHeader,
    this._fetchBody,
    this._transactionStore,
    this._localChain,
    this._mempool,
    this._validateTransaction,
    this.blockHeights,
  );

  @override
  Future<BroadcastTransactionRes> broadcastTransaction(
      ServiceCall call, BroadcastTransactionReq request) async {
    if (!request.hasTransaction()) throw Exception("No transaction provided");
    final transaction = request.transaction;
    final id = await transaction.id;
    if (await _transactionStore.contains(id)) {
      return BroadcastTransactionRes();
    }
    final errors = await _validateTransaction(transaction);
    if (errors.isNotEmpty) throw Exception("Invalid transaction: $errors");
    await _transactionStore.put(id, transaction);
    await _mempool.add(id);
    return BroadcastTransactionRes();
  }

  @override
  Future<CurrentMempoolRes> currentMempool(
      ServiceCall call, CurrentMempoolReq request) async {
    final result = await _mempool.read(await _localChain.currentHead);
    return CurrentMempoolRes(transactionIds: result);
  }

  @override
  Future<FetchBlockHeaderRes> fetchBlockHeader(
          ServiceCall call, FetchBlockHeaderReq request) async =>
      FetchBlockHeaderRes(header: await _fetchHeader(request.blockId));

  @override
  Future<FetchBlockBodyRes> fetchBlockBody(
          ServiceCall call, FetchBlockBodyReq request) async =>
      FetchBlockBodyRes(body: await _fetchBody(request.blockId));

  @override
  Future<FetchTransactionRes> fetchTransaction(
          ServiceCall call, FetchTransactionReq request) async =>
      FetchTransactionRes(
          transaction: await _transactionStore.get(request.transactionId));

  @override
  Future<FetchBlockIdAtDepthRes> fetchBlockIdAtDepth(
      ServiceCall call, FetchBlockIdAtDepthReq request) async {
    if (request.depth < 0) throw Exception("Invalid depth");
    final headId = await _localChain.currentHead;
    if (request.depth == 0) return FetchBlockIdAtDepthRes(blockId: headId);
    final head = (await _fetchHeader(headId))!;
    if (request.depth >= head.height) return FetchBlockIdAtDepthRes();
    return FetchBlockIdAtDepthRes(
        blockId: await blockHeights.useStateAt(
            headId, (f) => f(head.height - request.depth)));
  }

  @override
  Future<FetchBlockIdAtHeightRes> fetchBlockIdAtHeight(
      ServiceCall call, FetchBlockIdAtHeightReq request) async {
    if (request.height < 1) throw Exception("Invalid height");
    final headId = await _localChain.currentHead;
    final head = (await _fetchHeader(headId))!;
    if (head.height == request.height)
      return FetchBlockIdAtHeightRes(blockId: headId);
    else if (head.height < request.height)
      return FetchBlockIdAtHeightRes();
    else
      return FetchBlockIdAtHeightRes(
          blockId:
              await blockHeights.useStateAt(headId, (f) => f(request.height)));
  }

  @override
  Stream<SynchronizationTraversalRes> synchronizationTraversal(
      ServiceCall call, SynchronizationTraversalReq request) {
    // TODO: Unapply steps
    return _localChain.adoptions
        .map((blockId) => SynchronizationTraversalRes(applied: blockId));
  }
}
