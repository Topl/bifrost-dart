import 'package:bifrost_crypto/utils.dart';
import 'package:brambl/brambl.dart';
import 'package:convert/convert.dart';
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';
import 'package:topl_protobuf/brambl/models/box/challenge.pb.dart';
import 'package:topl_protobuf/brambl/models/box/lock.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';

void main() {
  group("Codecs", () {
    test("Lock Immutable Bytes", () {
      final HeightLockOneProposition = Proposition(
          heightRange: Proposition_HeightRange(
              chain: "header", min: Int64.ONE, max: Int64.MAX_VALUE));

      final HeightLockOneChallenge =
          Challenge(revealed: HeightLockOneProposition);

      final HeightLockOneLock = Lock(
          predicate: Lock_Predicate(
              challenges: [HeightLockOneChallenge], threshold: 1));

      final lockImmutableBytes = HeightLockOneLock.immutable;
      final expectedLockImmutableBytes = hex
          .decode("01006865696768745f72616e6765686561646572017fffffffffffffff");

      expect(lockImmutableBytes.value.sameElements(expectedLockImmutableBytes),
          true);

      final evidence = HeightLockOneLock.evidence32.digest.value;
      final expectedEvidence = hex.decode(
          "03f981636e19ec936600002af2e444590bd1626bbe2c8e2fe69df5ab48ac6a74");

      expect(evidence.sameElements(expectedEvidence), true);
    });
  });
}
