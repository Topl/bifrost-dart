import 'package:bifrost_crypto/ed25519.dart';
import 'package:bifrost_crypto/ed25519vrf.dart';
import 'package:bifrost_crypto/kes.dart';
import 'package:bifrost_crypto/utils.dart';
import 'package:brambl/brambl.dart';
import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/brambl/models/address.pb.dart';
import 'package:topl_protobuf/brambl/models/box/challenge.pb.dart';
import 'package:topl_protobuf/brambl/models/box/lock.pb.dart';
import 'package:topl_protobuf/brambl/models/box/value.pb.dart';
import 'package:topl_protobuf/brambl/models/identifier.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/unspent_transaction_output.pb.dart';
import 'package:topl_protobuf/consensus/models/operational_certificate.pb.dart';
import 'package:topl_protobuf/consensus/models/staking_address.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';
import 'package:topl_protobuf/quivr/models/shared.pb.dart';

class StakerInitializer {
  final Ed25519KeyPair operatorKeyPair;
  final Ed25519KeyPair walletKeyPair;
  final Ed25519KeyPair spendingKeyPair;
  final Ed25519VRFKeyPair vrfKeyPair;
  final KeyPairKesProduct kesKeyPair;

  StakerInitializer(this.operatorKeyPair, this.walletKeyPair,
      this.spendingKeyPair, this.vrfKeyPair, this.kesKeyPair);

  static Future<StakerInitializer> fromSeed(
      List<int> seed, TreeHeight treeHeight) async {
    final operatorKeyPair =
        await ed25519.generateKeyPairFromSeed(await (seed + [1]).hash256);
    final walletKeyPair =
        await ed25519.generateKeyPairFromSeed(await (seed + [2]).hash256);
    final spendingKeyPair =
        await ed25519.generateKeyPairFromSeed(await (seed + [3]).hash256);
    final vrfKeyPair =
        await ed25519Vrf.generateKeyPairFromSeed(await (seed + [4]).hash256);
    final kesKeyPair = await kesProduct.generateKeyPair(
        await (seed + [5]).hash256, treeHeight, Int64.ZERO);

    return StakerInitializer(
      operatorKeyPair,
      walletKeyPair,
      spendingKeyPair,
      vrfKeyPair,
      kesKeyPair,
    );
  }

  Future<SignatureKesProduct> get registration async => kesProduct.sign(
        kesKeyPair.sk,
        await (vrfKeyPair.vk + operatorKeyPair.vk).hash256,
      );

  StakingAddress get stakingAddress =>
      StakingAddress(value: operatorKeyPair.vk);

  Lock get spendingLock => Lock(
        predicate: Lock_Predicate(challenges: [
          Challenge(
            revealed: Proposition(
              digitalSignature: Proposition_DigitalSignature(
                routine: "ed25519",
                verificationKey: VerificationKey(value: spendingKeyPair.vk),
              ),
            ),
          )
        ], threshold: 1),
      );

  LockAddress get lockAddress =>
      LockAddress(lock32: Identifier_Lock32(evidence: spendingLock.evidence32));

  Future<List<UnspentTransactionOutput>> genesisOutputs(Int128 stake) async {
    final toplValue = Value(
        topl: Value_TOPL(quantity: stake, stakingAddress: stakingAddress));
    final registrationValue = Value(
        registration: Value_Registration(
            registration: await registration, stakingAddress: stakingAddress));
    return [
      UnspentTransactionOutput(address: lockAddress, value: toplValue),
      UnspentTransactionOutput(address: lockAddress, value: registrationValue)
    ];
  }
}
