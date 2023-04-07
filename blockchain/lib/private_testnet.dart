import 'package:bifrost_codecs/codecs.dart';
import 'package:bifrost_common/utils.dart';
import 'package:bifrost_crypto/kes.dart';
import 'package:bifrost_blockchain/genesis.dart';
import 'package:bifrost_blockchain/staker_initializer.dart';
import 'package:bifrost_crypto/utils.dart';
import 'package:brambl/brambl.dart';
import 'package:fixnum/fixnum.dart';
import 'package:topl_protobuf/brambl/models/address.pb.dart';
import 'package:topl_protobuf/brambl/models/box/challenge.pb.dart';
import 'package:topl_protobuf/brambl/models/box/lock.pb.dart';
import 'package:topl_protobuf/brambl/models/box/value.pb.dart';
import 'package:topl_protobuf/brambl/models/identifier.pb.dart';
import 'package:topl_protobuf/brambl/models/transaction/unspent_transaction_output.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';

class PrivateTestnet {
  static final DefaultTotalStake = BigInt.from(10000000);

  static Future<List<StakerInitializer>> stakerInitializers(
      Int64 timestamp, int stakerCount, TreeHeight kesTreeHeight) async {
    assert(stakerCount >= 0);
    final out = <StakerInitializer>[];
    for (int i = 0; i < stakerCount; i++) {
      final seed = await (timestamp.immutableBytes + i.immutableBytes).hash256;
      out.add(await StakerInitializer.fromSeed(seed, kesTreeHeight));
    }
    return out;
  }

  static Future<GenesisConfig> config(Int64 timestamp,
      List<StakerInitializer> stakers, List<BigInt> stakes) async {
    assert(stakers.length == stakes.length);
    final outputs = [
      UnspentTransactionOutput(
          address: HeightLockOneSpendingAddress,
          value:
              Value(lvl: Value_LVL(quantity: BigInt.from(10000000).toInt128))),
    ];
    for (int i = 0; i < stakers.length; i++) {
      final staker = stakers[i];
      final stake = stakes[i];
      final genesisOutputs = await staker.genesisOutputs(stake.toInt128);
      outputs.addAll(genesisOutputs);
    }

    return GenesisConfig(timestamp, outputs, GenesisConfig.DefaultEtaPrefix);
  }
}

final HeightLockOneProposition = Proposition(
    heightRange: Proposition_HeightRange(
        chain: "header", min: Int64.ONE, max: Int64.MAX_VALUE));

final HeightLockOneChallenge = Challenge(revealed: HeightLockOneProposition);

final HeightLockOneLock = Lock(predicate: Lock_Predicate(challenges: [HeightLockOneChallenge], threshold: 1));

final HeightLockOneSpendingAddress = LockAddress(
  lock32: Identifier_Lock32(evidence: HeightLockOneLock.evidence32)
);
