import 'dart:async';

import 'package:bifrost_blockchain/data_stores.dart';
import 'package:bifrost_blockchain/genesis.dart';
import 'package:bifrost_blockchain/private_testnet.dart';
import 'package:bifrost_blockchain/staker_initializer.dart';
import 'package:bifrost_codecs/codecs.dart';
import 'package:bifrost_common/algebras/clock_algebra.dart';
import 'package:bifrost_common/algebras/parent_child_tree_algebra.dart';
import 'package:bifrost_common/interpreters/clock.dart';
import 'package:bifrost_common/interpreters/parent_child_tree.dart';
import 'package:bifrost_consensus/algebras/block_header_validation_algebra.dart';
import 'package:bifrost_consensus/algebras/consensus_validation_state_algebra.dart';
import 'package:bifrost_consensus/algebras/leader_election_validation_algebra.dart';
import 'package:bifrost_consensus/interpreters/block_header_validation.dart';
import 'package:bifrost_consensus/interpreters/chain_selection.dart';
import 'package:bifrost_consensus/interpreters/consensus_data_event_sourced_state.dart';
import 'package:bifrost_consensus/interpreters/consensus_validation_state.dart';
import 'package:bifrost_consensus/interpreters/epoch_boundaries.dart';
import 'package:bifrost_consensus/interpreters/eta_calculation.dart';
import 'package:bifrost_consensus/interpreters/leader_election_validation.dart';
import 'package:bifrost_consensus/interpreters/local_chain.dart';
import 'package:bifrost_consensus/models/vrf_config.dart';
import 'package:bifrost_consensus/utils.dart';
import 'package:bifrost_crypto/ed25519vrf.dart';
import 'package:bifrost_minting/algebras/block_producer_algebra.dart';
import 'package:bifrost_minting/algebras/secure_store_algebra.dart';
import 'package:bifrost_minting/algebras/staking_algebra.dart';
import 'package:bifrost_minting/interpreters/block_packer.dart';
import 'package:bifrost_minting/interpreters/block_producer.dart';
import 'package:bifrost_minting/interpreters/in_memory_secure_store.dart';
import 'package:bifrost_minting/interpreters/operational_key_maker.dart';
import 'package:bifrost_minting/interpreters/staking.dart';
import 'package:bifrost_minting/interpreters/vrf_calculator.dart';
import 'package:fixnum/fixnum.dart';
import 'package:async/async.dart' show StreamGroup;
import 'package:logging/logging.dart';
import 'package:rational/rational.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class Blockchain {
  final GenesisConfig genesisConfig;
  final ClockAlgebra clock;
  final DataStores dataStores;
  final ParentChildTreeAlgebra<BlockId> parentChildTree;
  final EtaCalculation etaCalculation;
  final LeaderElectionValidationAlgebra leaderElection;
  final ConsensusValidationStateAlgebra consensusValidationState;
  final LocalChain localChain;
  final ChainSelection chainSelection;
  final BlockHeadervalidationAlgebra blockHeaderValidation;
  final BlockProducerAlgebra blockProducer;

  final log = Logger("Blockchain");

  Blockchain(
    this.genesisConfig,
    this.clock,
    this.dataStores,
    this.parentChildTree,
    this.etaCalculation,
    this.leaderElection,
    this.consensusValidationState,
    this.localChain,
    this.chainSelection,
    this.blockHeaderValidation,
    this.blockProducer,
  );

  static Future<Blockchain> init() async {
    final log = Logger("Blockchain.Init");

    final genesisTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    final stakerInitializers =
        await PrivateTestnet().stakerInitializers(genesisTimestamp, 1);

    final genesisConfig = await PrivateTestnet()
        .config(genesisTimestamp, stakerInitializers, null);

    final genesisBlock = await genesisConfig.block;

    final genesisBlockId = genesisBlock.header.id;

    final vrfKeyPair = await ed25519Vrf.generateKeyPair();

    final clock = Clock(
      Duration(milliseconds: 200),
      ChainSelectionKLookback * 6,
      genesisTimestamp,
      Int64(50),
    );

    final dataStores = await DataStores.init(genesisBlock);

    final currentEventIdGetterSetters =
        CurrentEventIdGetterSetters(dataStores.currentEventIds);

    final canonicalHeadId =
        await currentEventIdGetterSetters.canonicalHead.get();
    final canonicalHeadSlotData =
        await dataStores.slotData.getOrRaise(canonicalHeadId);

    final parentChildTree = ParentChildTree<BlockId>(
      dataStores.parentChildTree.get,
      dataStores.parentChildTree.put,
      genesisBlock.header.parentHeaderId,
    );

    await parentChildTree.assocate(
        genesisBlockId, genesisBlock.header.parentHeaderId);

    final vrfConfig = VrfConfig(
      lddCutoff: 15,
      precision: 40,
      baselineDifficulty: Rational.fromInt(1, 20),
      amplitude: Rational.fromInt(1, 2),
    );

    final etaCalculation = EtaCalculation(dataStores.slotData.getOrRaise, clock,
        genesisBlock.header.eligibilityCertificate.eta);

    final leaderElection = LeaderElectionValidation(vrfConfig);

    final vrfCalculator =
        VrfCalculator(vrfKeyPair.sk, clock, leaderElection, vrfConfig, 512);

    final secureStore = InMemorySecureStore();

    log.info("Preparing Consensus State");

    final epochBoundaryState = epochBoundariesEventSourcedState(
        clock,
        await currentEventIdGetterSetters.epochBoundaries.get(),
        parentChildTree,
        currentEventIdGetterSetters.epochBoundaries.set,
        dataStores.epochBoundaries,
        dataStores.slotData.getOrRaise);
    final consensusDataState = consensusDataEventSourcedState(
        await currentEventIdGetterSetters.consensusData.get(),
        parentChildTree,
        currentEventIdGetterSetters.consensusData.set,
        ConsensusData(dataStores.operatorStakes, dataStores.activeStake,
            dataStores.registrations),
        dataStores.bodies.getOrRaise,
        dataStores.transactions.getOrRaise);

    final consensusValidationState = ConsensusValidationState(
        genesisBlockId, epochBoundaryState, consensusDataState, clock);

    log.info("Preparing OperationalKeyMaker");

    final operationalKeyMaker = await OperationalKeyMaker.init(
        canonicalHeadSlotData.slotId,
        Int64(150),
        Int64(0),
        stakerInitializers[0].stakingAddress,
        secureStore,
        clock,
        vrfCalculator,
        etaCalculation,
        consensusValidationState,
        stakerInitializers[0].kesKeyPair.sk);

    log.info("Preparing LocalChain");

    final localChain =
        LocalChain(await currentEventIdGetterSetters.canonicalHead.get());

    final chainSelection = ChainSelection(dataStores.slotData.getOrRaise);

    log.info("Preparing Header Validation");

    final blockHeaderValidation = BlockHeaderValidation(
        genesisBlockId,
        etaCalculation,
        consensusValidationState,
        leaderElection,
        clock,
        dataStores.headers.getOrRaise);

    log.info("Preparing Staking");

    final staker = Staking(
      stakerInitializers[0].stakingAddress,
      stakerInitializers[0].vrfKeyPair.vk,
      operationalKeyMaker,
      consensusValidationState,
      etaCalculation,
      vrfCalculator,
      leaderElection,
    );

    log.info("Preparing BlockProducer");

    final blockProducer = BlockProducer(
      StreamGroup.merge([
        Stream.value(canonicalHeadSlotData),
        localChain.adoptions.asyncMap(dataStores.slotData.getOrRaise),
      ]),
      staker,
      clock,
      BlockPacker(),
    );

    log.info("Blockchain Initialized");

    final blockchain = Blockchain(
      genesisConfig,
      clock,
      dataStores,
      parentChildTree,
      etaCalculation,
      leaderElection,
      consensusValidationState,
      localChain,
      chainSelection,
      blockHeaderValidation,
      blockProducer,
    );

    return blockchain;
  }

  Future<void> processBlock(FullBlock block) async {
    final id = block.header.id;

    await parentChildTree.assocate(id, block.header.parentHeaderId);
    await dataStores.slotData.put(id, await block.header.slotData);
    await dataStores.headers.put(id, block.header);

    final headerValidationErrors =
        await blockHeaderValidation.validate(block.header);
    if (headerValidationErrors.isNotEmpty) {
      throw Exception("Invalid block. reason=$headerValidationErrors");
    } else {
      final body = BlockBody(
          transactionIds: block.fullBody.transactions.map((t) => t.id));
      await dataStores.bodies.put(id, body);
      if (await chainSelection.select(id, await localChain.currentHead) == id) {
        log.info("Adopting id=${id.show}");
        localChain.adopt(id);
      }
    }
  }

  void run() {
    unawaited(blockProducer.blocks.asyncMap(processBlock).drain());
  }

  Stream<FullBlock> get blocks => localChain.adoptions.asyncMap((id) async {
        final header = await dataStores.headers.getOrRaise(id);
        final body = await dataStores.bodies.getOrRaise(id);
        final transactions = [
          for (final id in body.transactionIds)
            await dataStores.transactions.getOrRaise(id)
        ];
        final fullBlock = FullBlock(
            header: header,
            fullBody: FullBlockBody(transactions: transactions));
        return fullBlock;
      });
}

final ChainSelectionKLookback = Int64(50);