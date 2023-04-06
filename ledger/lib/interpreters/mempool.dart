import 'dart:async';

import 'package:bifrost_common/algebras/event_sourced_state_algebra.dart';
import 'package:bifrost_common/interpreters/event_tree_state.dart';
import 'package:bifrost_common/interpreters/parent_child_tree.dart';
import 'package:bifrost_common/models/common.dart';
import 'package:bifrost_ledger/algebras/mempool_algebra.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class Mempool extends MempoolAlgebra {
  final Map<TransactionId, MempoolEntry> _state;
  final Future<BlockBody> Function(BlockId) fetchBlockBody;
  final EventSourcedStateAlgebra<Map<TransactionId, MempoolEntry>, BlockId>
      eventSourcedState;

  Mempool._(this._state, this.fetchBlockBody, this.eventSourcedState);

  factory Mempool(
      Future<BlockBody> Function(BlockId) fetchBlockBody,
      ParentChildTree<BlockId> parentChildTree,
      BlockId currentEventId,
      Duration expirationDuration) {
    final state = <TransactionId, MempoolEntry>{};
    final eventSourcedState =
        EventTreeState<Map<TransactionId, MempoolEntry>, BlockId>(
      (state, blockId) async {
        final blockBody = await fetchBlockBody(blockId);
        blockBody.transactionIds.forEach(state.remove);
        return state;
      },
      (state, blockId) async {
        final blockBody = await fetchBlockBody(blockId);
        for (final transactionId in blockBody.transactionIds) {
          state[transactionId] = MempoolEntry(
              transactionId, DateTime.now().add(expirationDuration));
        }
        return state;
      },
      parentChildTree,
      state,
      currentEventId,
      (p0) async => {},
    );

    Timer.periodic(Duration(seconds: 30), (timer) {
      final now = DateTime.now();
      state.removeWhere((key, value) => value.addedAt.isBefore(now));
    });

    return Mempool._(state, fetchBlockBody, eventSourcedState);
  }

  @override
  Future<void> add(TransactionId transactionId) async {
    _state[transactionId] = MempoolEntry(transactionId, DateTime.now());
  }

  @override
  Future<Set<TransactionId>> read(BlockId currentHead) => eventSourcedState
      .useStateAt(currentHead, (state) async => state.keys.toSet());

  @override
  Future<void> remove(TransactionId transactionId) async {
    _state.remove(transactionId);
  }
}

class MempoolEntry {
  final TransactionId transactionId;
  final DateTime addedAt;

  MempoolEntry(this.transactionId, this.addedAt);
}
