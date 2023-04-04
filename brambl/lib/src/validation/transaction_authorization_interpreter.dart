import 'package:brambl/src/validation/algebras/transaction_authorization_verifier.dart';
import 'package:quivr/src/verifier.dart';
import 'package:topl_protobuf/brambl/models/transaction/io_transaction.pb.dart';
import 'package:topl_protobuf/quivr/models/proof.pb.dart';
import 'package:topl_protobuf/quivr/models/proposition.pb.dart';

class TransactionAuthorizationInterpreter
    extends TransactionAuthorizationVerifier {
  @override
  Future<List<String>> validate(
      IoTransaction transaction, DynamicContext context) async {
    for (final input in transaction.inputs) {
      final attestation = input.attestation;
      if (attestation.hasPredicate()) {
        final predicate = attestation.predicate;
        final errors = await thresholdVerifier(
          predicate.lock.challenges.map((c) => c.revealed).toList(),
          predicate.responses,
          predicate.lock.threshold,
          context,
        );
        if (errors.isNotEmpty) return errors;
      } else if (attestation.hasImage32()) {
        final image32 = attestation.image32;
        final errors = await thresholdVerifier(
          image32.known.map((k) => k.revealed).toList(),
          image32.responses,
          image32.lock.threshold,
          context,
        );
        if (errors.isNotEmpty) return errors;
      } else if (attestation.hasImage64()) {
        final image64 = attestation.image64;
        final errors = await thresholdVerifier(
          image64.known.map((k) => k.revealed).toList(),
          image64.responses,
          image64.lock.threshold,
          context,
        );
        if (errors.isNotEmpty) return errors;
      } else if (attestation.hasCommitment32()) {
        final commitment = attestation.commitment32;
        final result = await thresholdVerifier(
          commitment.known.map((k) => k.revealed).toList(),
          commitment.responses,
          commitment.lock.threshold,
          context,
        );
        if (result.isNotEmpty) return result;
      } else if (attestation.hasCommitment64()) {
        final commitment = attestation.commitment64;
        final errors = await thresholdVerifier(
          commitment.known.map((k) => k.revealed).toList(),
          commitment.responses,
          commitment.lock.threshold,
          context,
        );
        if (errors.isNotEmpty) return errors;
      }
    }
    return [];
  }

  static Future<List<String>> thresholdVerifier(List<Proposition> propositions,
      List<Proof> proofs, int threshold, DynamicContext context) async {
    if (threshold == 0)
      return [];
    else if (threshold > propositions.length)
      return ["AuthorizationFailed"];
    else if (proofs.isEmpty || proofs.length != propositions.length)
      return ["AuthorizationFailed"];
    else {
      final errors = <String>[];
      int successCount = 0;
      int index = 0;
      while (index < propositions.length && successCount < threshold) {
        final error = await Verify(propositions[index], proofs[index], context);
        if (error == null)
          successCount++;
        else
          errors.add(error);
        index++;
      }
      if (successCount >= threshold)
        return [];
      else
        return errors;
    }
  }
}
