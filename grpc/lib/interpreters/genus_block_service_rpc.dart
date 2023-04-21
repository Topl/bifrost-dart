import 'package:bifrost_common/algebras/event_sourced_state_algebra.dart';
import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_consensus/algebras/local_chain_algebra.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/src/server/call.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/genus/genus_rpc.pbgrpc.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class GenusFullBlockGrpc extends BlockServiceBase {
  final Future<BlockHeader?> Function(BlockId) _fetchHeader;
  final Future<BlockBody?> Function(BlockId) _fetchBody;
  final Future<IoTransaction?> Function(TransactionId) _fetchTransaction;
  final LocalChainAlgebra _localChain;
  final EventSourcedStateAlgebra<Future<BlockId?> Function(Int64), BlockId>
      blockHeights;

  GenusFullBlockGrpc(this._fetchHeader, this._fetchBody, this._fetchTransaction,
      this._localChain, this.blockHeights);
  @override
  Future<BlockResponse> getBlockByDepth(
      ServiceCall call, GetBlockByDepthRequest request) async {
    if (request.depth.value < 0) throw Exception("Invalid depth");
    final headId = await _localChain.currentHead;
    if (request.depth == 0) return _blockById(headId);
    final head = (await _fetchHeader(headId))!;
    if (request.depth.value >= head.height) return BlockResponse();
    final targetId = await blockHeights.useStateAt(
        headId, (f) => f(head.height - request.depth.value));
    if (targetId == null) return BlockResponse();
    return _blockById(targetId);
  }

  @override
  Future<BlockResponse> getBlockByHeight(
      ServiceCall call, GetBlockByHeightRequest request) async {
    if (request.height.value < 0) throw Exception("Invalid height");
    final headId = await _localChain.currentHead;
    final head = (await _fetchHeader(headId))!;
    if (head.height == request.height.value)
      return _blockById(headId);
    else if (head.height < request.height.value) return BlockResponse();
    final targetId =
        await blockHeights.useStateAt(headId, (f) => f(request.height.value));
    if (targetId == null) return BlockResponse();
    return _blockById(targetId);
  }

  @override
  Future<BlockResponse> getBlockById(
          ServiceCall call, GetBlockByIdRequest request) =>
      _blockById(request.blockId);

  Future<BlockResponse> _blockById(BlockId id) async {
    final header = await _fetchHeader(id);
    if (header == null) return BlockResponse();
    final body = await _fetchBody(id);
    if (body == null) return BlockResponse();
    final transactions = await Future.wait(
        body.transactionIds.map((id) async => (await _fetchTransaction(id))!));
    final block = FullBlock(
        header: header, fullBody: FullBlockBody(transactions: transactions));
    return BlockResponse(block: block);
  }
}
