import 'package:bifrost_common/algebras/store_algebra.dart';
import 'package:bifrost_common/interpreters/event_tree_state.dart';
import 'package:bifrost_common/interpreters/parent_child_tree.dart';
import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/consensus/models/slot_data.pb.dart';

typedef BlockHeightTreeState = Future<BlockId?> Function(Int64);

BlockHeightTree(
  StoreAlgebra<Int64, BlockId> store,
  BlockId currentEventId,
  StoreAlgebra<BlockId, SlotData> slotDataStore,
  ParentChildTree<BlockId> parentChildTree,
  Future<void> Function(BlockId) currentEventChanged,
) {
  Future<BlockHeightTreeState> applyBlock(
      BlockHeightTreeState state, BlockId id) async {
    final slotData = await slotDataStore.getOrRaise(id);
    final height = slotData.height;
    await store.put(height, id);
    return state;
  }

  Future<BlockHeightTreeState> unapplyBlock(
      BlockHeightTreeState state, BlockId id) async {
    final slotData = await slotDataStore.getOrRaise(id);
    final height = slotData.height;
    await store.remove(height);
    return state;
  }

  return EventTreeState<BlockHeightTreeState, BlockId>(applyBlock, unapplyBlock,
      parentChildTree, store.get, currentEventId, currentEventChanged);
}
