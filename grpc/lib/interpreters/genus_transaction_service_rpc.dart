import 'package:bifrost_common/models/common.dart';
import 'package:grpc/src/server/call.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/genus/genus_models.pb.dart';
import 'package:topl_protobuf/genus/genus_rpc.pbgrpc.dart';

class GenusTransactionGrpc extends TransactionServiceBase {
  final Future<IoTransaction?> Function(TransactionId) _fetchTransaction;

  GenusTransactionGrpc(this._fetchTransaction);

  @override
  Future<CreateOnChainTransactionIndexResponse> createOnChainTransactionIndex(
      ServiceCall call, CreateOnChainTransactionIndexRequest request) {
    // TODO: implement createOnChainTransactionIndex
    throw UnimplementedError();
  }

  @override
  Future<DropIndexResponse> dropIndex(
      ServiceCall call, DropIndexRequest request) {
    // TODO: implement dropIndex
    throw UnimplementedError();
  }

  @override
  Future<GetExistingTransactionIndexesResponse> getExistingTransactionIndexes(
      ServiceCall call, GetExistingTransactionIndexesRequest request) {
    // TODO: implement getExistingTransactionIndexes
    throw UnimplementedError();
  }

  @override
  Stream<TransactionResponse> getIndexedTransactions(
      ServiceCall call, GetIndexedTransactionsRequest request) {
    // TODO: implement getIndexedTransactions
    throw UnimplementedError();
  }

  @override
  Stream<TransactionResponse> getTransactionByAddressStream(
      ServiceCall call, QueryByAddressRequest request) {
    // TODO: implement getTransactionByAddressStream
    throw UnimplementedError();
  }

  @override
  Future<TransactionResponse> getTransactionById(
          ServiceCall call, GetTransactionByIdRequest request) async =>
      // TODO: The other receipt fields require knowledge of which Block contains this Transaction, which isn't readily accessible right now.
      TransactionResponse(
          transactionReceipt: TransactionReceipt(
              transaction: await _fetchTransaction(request.transactionId)));

  @override
  Future<TxoAddressResponse> getTxosByAddress(
      ServiceCall call, QueryByAddressRequest request) {
    // TODO: implement getTxosByAddress
    throw UnimplementedError();
  }

  @override
  Stream<TxoAddressResponse> getTxosByAddressStream(
      ServiceCall call, QueryByAddressRequest request) {
    // TODO: implement getTxosByAddressStream
    throw UnimplementedError();
  }

  @override
  Stream<TxoResponse> getTxosByAssetLabel(
      ServiceCall call, QueryByAssetLabelRequest request) {
    // TODO: implement getTxosByAssetLabel
    throw UnimplementedError();
  }
}
