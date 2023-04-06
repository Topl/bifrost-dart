import 'package:bifrost_common/algebras/event_sourced_state_algebra.dart';
import 'package:bifrost_common/algebras/store_algebra.dart';
import 'package:bifrost_common/interpreters/event_tree_state.dart';
import 'package:bifrost_common/interpreters/parent_child_tree.dart';
import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_ledger/src/algebras/box_state_algebra.dart';
import 'package:brambl/brambl.dart';
import 'package:fpdart/fpdart.dart';
import 'package:topl_protobuf/brambl/models/address.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

typedef State = StoreAlgebra<TransactionId, List<int>>;
typedef FetchBlockBody = Future<BlockBody> Function(BlockId);
typedef FetchTransaction = Future<IoTransaction> Function(TransactionId);

class BoxState extends BoxStateAlgebra {
  final EventSourcedStateAlgebra<State, BlockId> eventSourcedState;

  BoxState(this.eventSourcedState);

  @override
  Future<bool> boxExistsAt(
      BlockId blockId, TransactionOutputAddress boxId) async {
    final spendableIndices = await eventSourcedState.useStateAt(
        blockId, (state) => state.get(boxId.ioTransaction32));
    return spendableIndices != null && spendableIndices.contains(boxId.index);
  }

  static EventSourcedStateAlgebra<State, BlockId> createEventSourcedState(
      State initialState,
      BlockId currentBlockId,
      Future<BlockBody> Function(BlockId) fetchBlockBody,
      Future<IoTransaction> Function(TransactionId) fetchTransaction,
      ParentChildTree<BlockId> parentChildTree,
      Future<void> Function(BlockId) currentEventChanged) {
    return EventTreeState<State, BlockId>(
      (state, blockId) => _applyBlock(
        fetchBlockBody,
        fetchTransaction,
        state,
        blockId,
      ),
      (state, blockId) => _unapplyBlock(
        fetchBlockBody,
        fetchTransaction,
        state,
        blockId,
      ),
      parentChildTree,
      initialState,
      currentBlockId,
      currentEventChanged,
    );
  }
}

Future<State> _applyBlock(FetchBlockBody fetchBlockBody,
    FetchTransaction fetchTransaction, State state, BlockId blockId) async {
  final body = await fetchBlockBody(blockId);
  for (final transactionId in body.transactionIds) {
    final transaction = await fetchTransaction(transactionId);
    for (final input in transaction.inputs) {
      final spentTxId = input.address.ioTransaction32;
      final unspentIndices = await state.getOrRaise(spentTxId);
      final newUnspentIndices = unspentIndices
          .where((index) => index != input.address.index)
          .toList();
      if (newUnspentIndices.isEmpty) {
        await state.remove(spentTxId);
      } else {
        state.put(spentTxId, newUnspentIndices);
      }
    }
    if (transaction.outputs.isNotEmpty) {
      final indices =
          transaction.outputs.mapWithIndex((t, index) => index).toList();
      await state.put(await transaction.id, indices);
    }
  }
  return state;
}

Future<State> _unapplyBlock(FetchBlockBody fetchBlockBody,
    FetchTransaction fetchTransaction, State state, BlockId blockId) async {
  final body = await fetchBlockBody(blockId);
  for (final transactionId in body.transactionIds) {
    final transaction = await fetchTransaction(transactionId);
    state.remove(transactionId);
    for (final input in transaction.inputs) {
      final spentTxId = input.address.ioTransaction32;
      final unspentIndices = await state.get(spentTxId);
      if (unspentIndices != null) {
        final newUnspentIndices = List.of(unspentIndices)
          ..add(input.address.index);
        await state.put(spentTxId, newUnspentIndices);
      } else {
        await state.put(spentTxId, [input.address.index]);
      }
    }
  }
  return state;
}

class AugmentedBoxState extends BoxStateAlgebra {
  final BoxStateAlgebra boxState;
  final StateAugmentation stateAugmentation;

  AugmentedBoxState(this.boxState, this.stateAugmentation);
  @override
  Future<bool> boxExistsAt(
      BlockId blockId, TransactionOutputAddress boxId) async {
    if (stateAugmentation.newBoxIds.contains(boxId))
      return true;
    else if (stateAugmentation.spentBoxIds.contains(boxId))
      return false;
    else
      return boxState.boxExistsAt(blockId, boxId);
  }
}

class StateAugmentation {
  final Set<TransactionOutputAddress> spentBoxIds;
  final Set<TransactionOutputAddress> newBoxIds;

  StateAugmentation(this.spentBoxIds, this.newBoxIds);

  StateAugmentation.empty()
      : spentBoxIds = {},
        newBoxIds = {};

  Future<StateAugmentation> augment(IoTransaction transaction) async {
    final transactionSpentBoxIds =
        transaction.inputs.map((i) => i.address).toSet();
    final transactionId = await transaction.id;
    final transactionNewBoxIds = transaction.outputs
        .mapWithIndex((t, index) => TransactionOutputAddress(
            index: index, ioTransaction32: transactionId))
        .toSet();

    transactionNewBoxIds.addAll(newBoxIds);
    transactionNewBoxIds.removeAll(transactionSpentBoxIds);
    return StateAugmentation(
        transactionSpentBoxIds..addAll(spentBoxIds), transactionNewBoxIds);
  }
}
