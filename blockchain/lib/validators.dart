import 'package:bifrost_blockchain/data_stores.dart';
import 'package:bifrost_common/algebras/clock_algebra.dart';
import 'package:bifrost_common/interpreters/parent_child_tree.dart';
import 'package:bifrost_consensus/algebras/block_header_to_body_validation_algebra.dart';
import 'package:bifrost_consensus/algebras/consensus_validation_state_algebra.dart';
import 'package:bifrost_consensus/algebras/eta_calculation_algebra.dart';
import 'package:bifrost_consensus/algebras/leader_election_validation_algebra.dart';
import 'package:bifrost_consensus/interpreters/block_header_to_body_validation.dart';
import 'package:bifrost_consensus/interpreters/block_header_validation.dart';
import 'package:bifrost_ledger/algebras/body_syntax_validation_algebra.dart';
import 'package:bifrost_ledger/algebras/body_semantic_validation_algebra.dart';
import 'package:bifrost_ledger/algebras/body_authorization_validation_algebra.dart';
import 'package:bifrost_ledger/algebras/box_state_algebra.dart';
import 'package:bifrost_ledger/interpreters/body_authorization_validation.dart';
import 'package:bifrost_ledger/interpreters/body_semantic_validation.dart';
import 'package:bifrost_ledger/interpreters/body_syntax_validation.dart';
import 'package:bifrost_ledger/interpreters/box_state.dart';
import 'package:bifrost_ledger/interpreters/transaction_semantic_validation.dart';
import 'package:brambl/brambl.dart';
import 'package:topl_protobuf/consensus/models/block_id.pb.dart';

class Validators {
  final BlockHeaderValidation header;
  final BlockHeaderToBodyValidationAlgebra headerToBody;
  final TransactionSyntaxVerifier transactionSyntax;
  final BodySyntaxValidationAlgebra bodySyntax;
  final BodySemanticValidationAlgebra bodySemantic;
  final BodyAuthorizationValidationAlgebra bodyAuthorization;
  final BoxStateAlgebra boxState;

  Validators(
    this.header,
    this.headerToBody,
    this.transactionSyntax,
    this.bodySyntax,
    this.bodySemantic,
    this.bodyAuthorization,
    this.boxState,
  );

  static Future<Validators> make(
    DataStores dataStores,
    BlockId genesisBlockId,
    CurrentEventIdGetterSetters currentEventIdGetterSetters,
    ParentChildTree<BlockId> parentChildTree,
    EtaCalculationAlgebra etaCalculation,
    ConsensusValidationStateAlgebra consensusValidationState,
    LeaderElectionValidationAlgebra leaderElectionValidation,
    ClockAlgebra clock,
  ) async {
    final headerValidation = BlockHeaderValidation(
        genesisBlockId,
        etaCalculation,
        consensusValidationState,
        leaderElectionValidation,
        clock,
        dataStores.headers.getOrRaise);

    final headerToBodyValidation = BlockHeaderToBodyValidation();

    final boxState = BoxState.make(
      dataStores.spendableBoxIds,
      await currentEventIdGetterSetters.boxState.get(),
      dataStores.bodies.getOrRaise,
      dataStores.transactions.getOrRaise,
      parentChildTree,
      currentEventIdGetterSetters.boxState.set,
    );

    final transactionSyntaxValidation = TransactionSyntaxInterpreter();
    final transactionSemanticValidation = TransactionSemanticValidation(
        dataStores.transactions.getOrRaise, boxState);
    final transactionAuthorizationValidation =
        TransactionAuthorizationInterpreter();
    final bodySyntaxValidation = BodySyntaxValidation(
        dataStores.transactions.getOrRaise, transactionSyntaxValidation);
    final bodySemanticValidation = BodySemanticValidation(
        dataStores.transactions.getOrRaise, transactionSemanticValidation);
    final bodyAuthorizationValidation = BodyAuthorizationValidation(
        dataStores.transactions.getOrRaise, transactionAuthorizationValidation);

    return Validators(
      headerValidation,
      headerToBodyValidation,
      transactionSyntaxValidation,
      bodySyntaxValidation,
      bodySemanticValidation,
      bodyAuthorizationValidation,
      boxState,
    );
  }
}
