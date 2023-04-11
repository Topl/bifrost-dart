import 'dart:async';

import 'package:bifrost_blockchain/config.dart';
import 'package:bifrost_blockchain/data_stores.dart';
import 'package:bifrost_blockchain/private_testnet.dart';
import 'package:bifrost_blockchain/validators.dart';
import 'package:bifrost_codecs/codecs.dart';
import 'package:bifrost_common/algebras/clock_algebra.dart';
import 'package:bifrost_common/algebras/parent_child_tree_algebra.dart';
import 'package:bifrost_common/interpreters/block_height_tree.dart';
import 'package:bifrost_common/interpreters/clock.dart';
import 'package:bifrost_common/interpreters/parent_child_tree.dart';
import 'package:bifrost_consensus/algebras/consensus_validation_state_algebra.dart';
import 'package:bifrost_consensus/algebras/leader_election_validation_algebra.dart';
import 'package:bifrost_consensus/interpreters/chain_selection.dart';
import 'package:bifrost_consensus/interpreters/consensus_data_event_sourced_state.dart';
import 'package:bifrost_consensus/interpreters/consensus_validation_state.dart';
import 'package:bifrost_consensus/interpreters/epoch_boundaries.dart';
import 'package:bifrost_consensus/interpreters/eta_calculation.dart';
import 'package:bifrost_consensus/interpreters/leader_election_validation.dart';
import 'package:bifrost_consensus/interpreters/local_chain.dart';
import 'package:bifrost_consensus/models/vrf_config.dart';
import 'package:bifrost_consensus/utils.dart';
import 'package:bifrost_crypto/kes.dart';
import 'package:bifrost_crypto/utils.dart';
import 'package:bifrost_grpc/interpreters/genus_block_service_rpc.dart';
import 'package:bifrost_grpc/interpreters/genus_transaction_service_rpc.dart';
import 'package:bifrost_grpc/interpreters/node_grpc.dart';
import 'package:bifrost_grpc/interpreters/services.dart';
import 'package:bifrost_ledger/interpreters/mempool.dart';
import 'package:bifrost_ledger/interpreters/quivr_context.dart';
import 'package:bifrost_ledger/models/body_validation_context.dart';
import 'package:bifrost_minting/algebras/block_producer_algebra.dart';
import 'package:bifrost_minting/interpreters/block_packer.dart';
import 'package:bifrost_minting/interpreters/block_producer.dart';
import 'package:bifrost_minting/interpreters/in_memory_secure_store.dart';
import 'package:bifrost_minting/interpreters/operational_key_maker.dart';
import 'package:bifrost_minting/interpreters/staking.dart';
import 'package:bifrost_minting/interpreters/vrf_calculator.dart';
import 'package:brambl/brambl.dart';
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/streams.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';
import 'package:topl_protobuf/node/models/block.pb.dart';

class Blockchain {
  final ClockAlgebra clock;
  final DataStores dataStores;
  final ParentChildTreeAlgebra<BlockId> parentChildTree;
  final EtaCalculation etaCalculation;
  final LeaderElectionValidationAlgebra leaderElection;
  final ConsensusValidationStateAlgebra consensusValidationState;
  final LocalChain localChain;
  final ChainSelection chainSelection;
  final Validators validators;
  final BlockProducerAlgebra blockProducer;

  final log = Logger("Blockchain");

  Blockchain(
    this.clock,
    this.dataStores,
    this.parentChildTree,
    this.etaCalculation,
    this.leaderElection,
    this.consensusValidationState,
    this.localChain,
    this.chainSelection,
    this.validators,
    this.blockProducer,
  );

  static Future<Blockchain> init(
      BlockchainConfig config, DComputeImpl isolate) async {
    final log = Logger("Blockchain.Init");

    final genesisTimestamp = config.genesis.timestamp;

    log.info("Genesis timestamp=$genesisTimestamp");

    final stakerInitializers = await PrivateTestnet.stakerInitializers(
        genesisTimestamp,
        config.genesis.stakerCount,
        TreeHeight(
            config.consensus.kesKeyHours, config.consensus.kesKeyMinutes));

    log.info("Staker initializers prepared");

    final stakerInitializer =
        stakerInitializers[config.genesis.localStakerIndex!];

    final genesisConfig = await PrivateTestnet.config(
        genesisTimestamp, stakerInitializers, config.genesis.stakes);

    final genesisBlock = await genesisConfig.block;

    final genesisBlockId = await genesisBlock.header.id;

    final vrfConfig = VrfConfig(
      lddCutoff: config.consensus.vrfLddCutoff,
      precision: config.consensus.vrfPrecision,
      baselineDifficulty: config.consensus.vrfBaselineDifficulty,
      amplitude: config.consensus.vrfAmpltitude,
    );

    final clock = Clock(
      config.consensus.slotDuration,
      config.consensus.epochLength,
      genesisTimestamp,
      config.consensus.forwardBiastedSlotWindow,
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

    final etaCalculation = EtaCalculation(dataStores.slotData.getOrRaise, clock,
        genesisBlock.header.eligibilityCertificate.eta);

    final leaderElection = LeaderElectionValidation(vrfConfig, isolate);

    final vrfCalculator = VrfCalculator(
        stakerInitializer.vrfKeyPair.sk, clock, leaderElection, vrfConfig);

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
      config.consensus.operationalPeriodLength,
      Int64(0),
      stakerInitializer.stakingAddress,
      secureStore,
      clock,
      vrfCalculator,
      etaCalculation,
      consensusValidationState,
      stakerInitializer.kesKeyPair.sk,
    );

    log.info("Preparing LocalChain");

    final localChain =
        LocalChain(await currentEventIdGetterSetters.canonicalHead.get());

    final chainSelection = ChainSelection(dataStores.slotData.getOrRaise);

    log.info("Preparing Validators");

    final validators = await Validators.make(
      dataStores,
      genesisBlockId,
      currentEventIdGetterSetters,
      parentChildTree,
      etaCalculation,
      consensusValidationState,
      leaderElection,
      clock,
    );

    log.info("Preparing Staking");

    final staker = Staking(
      stakerInitializer.stakingAddress,
      stakerInitializer.vrfKeyPair.vk,
      operationalKeyMaker,
      consensusValidationState,
      etaCalculation,
      vrfCalculator,
      leaderElection,
    );

    log.info("Preparing mempool");
    final mempool = Mempool(dataStores.bodies.getOrRaise, parentChildTree,
        await currentEventIdGetterSetters.mempool.get(), Duration(minutes: 5));

    log.info("Preparing BlockProducer");

    final blockProducer = BlockProducer(
      ConcatStream([
        Stream.value(canonicalHeadSlotData).asyncMap(
            (d) => clock.delayedUntilSlot(d.slotId.slot).then((_) => d)),
        localChain.adoptions.asyncMap(dataStores.slotData.getOrRaise),
      ]),
      staker,
      clock,
      BlockPacker(
          mempool,
          dataStores.transactions.getOrRaise,
          dataStores.transactions.contains,
          BlockPacker.makeBodyValidator(validators.bodySyntax,
              validators.bodySemantic, validators.bodyAuthorization)),
    );

    log.info("Preparing RPC Server");

    final blockHeightTree = BlockHeightTree(
      dataStores.blockHeightTree,
      await currentEventIdGetterSetters.blockHeightTree.get(),
      dataStores.slotData,
      parentChildTree,
      currentEventIdGetterSetters.blockHeightTree.set,
    );

    final rpcServices = RpcServices(
      NodeGrpc(
        dataStores.headers.get,
        dataStores.bodies.get,
        dataStores.transactions,
        localChain,
        mempool,
        validators.transactionSyntax.validate,
        blockHeightTree,
      ),
      GenusFullBlockGrpc(
        dataStores.headers.get,
        dataStores.bodies.get,
        dataStores.transactions.get,
        localChain,
        blockHeightTree,
      ),
      GenusTransactionGrpc(dataStores.transactions.get),
    );

    await rpcServices.serve(config.rpc.bindHost, config.rpc.bindPort);

    log.info("Blockchain Initialized");

    final blockchain = Blockchain(
      clock,
      dataStores,
      parentChildTree,
      etaCalculation,
      leaderElection,
      consensusValidationState,
      localChain,
      chainSelection,
      validators,
      blockProducer,
    );

    return blockchain;
  }

  Future<void> processBlock(FullBlock block) async {
    final id = await block.header.id;

    final body = BlockBody(transactionIds: [
      for (final transaction in block.fullBody.transactions)
        await transaction.id
    ]);
    await validateBlock(id, Block(header: block.header, body: body));
    await dataStores.bodies.put(id, body);
    if (await chainSelection.select(id, await localChain.currentHead) == id) {
      log.info("Adopting id=${id.show}");
      localChain.adopt(id);
    }
  }

  Future<void> validateBlock(BlockId id, Block block) async {
    await parentChildTree.assocate(id, block.header.parentHeaderId);
    await dataStores.slotData.put(id, await block.header.slotData);
    await dataStores.headers.put(id, block.header);

    final errors = await validators.header.validate(block.header);
    throwErrors() async {
      if (errors.isNotEmpty) {
        // TODO: ParentChildTree disassociate
        await dataStores.slotData.remove(id);
        await dataStores.headers.remove(id);
        throw Exception("Invalid block. reason=$errors");
      }
    }

    await throwErrors();

    errors.addAll(await validators.bodySyntax.validate(block.body));
    await throwErrors();
    final bodyValidationContext = BodyValidationContext(
        block.header.parentHeaderId, block.header.height, block.header.slot);
    errors.addAll(await validators.bodySemantic
        .validate(block.body, bodyValidationContext));
    await throwErrors();
    errors.addAll(await validators.bodyAuthorization.validate(
      block.body,
      (tx) async =>
          QuivrContextForConstructedBlock(block.header, await tx.signableBytes),
    ));
    await throwErrors();
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
