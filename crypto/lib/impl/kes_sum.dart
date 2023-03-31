import 'dart:typed_data';

import 'package:bifrost_crypto/ed25519.dart';
import 'package:bifrost_crypto/impl/kes_helper.dart';
import 'package:bifrost_crypto/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:fixnum/fixnum.dart';
import 'package:fpdart/fpdart.dart';
import 'package:topl_protobuf/consensus/models/operational_certificate.pb.dart';

/**
 * Credit to Aaron Schutza
 */
class KesSum {
  const KesSum();
  Future<KeyPairKesSum> createKeyPair(
      List<int> seed, int height, Int64 offset) async {
    final tree = await generateSecretKey(seed, height);
    final vk = await generateVerificationKey(tree);
    return KeyPairKesSum(
        sk: SecretKeyKesSum(tree: tree, offset: offset), vk: vk);
  }

  Future<SignatureKesSum> sign(KesBinaryTree skTree, List<int> message) async {
    Future<SignatureKesSum> loop(
        KesBinaryTree keyTree, List<List<int>> W) async {
      if (keyTree is KesMerkleNode) {
        if (keyTree.left is KesEmpty)
          return loop(keyTree.right, [List.of(keyTree.witnessLeft)]..addAll(W));
        else
          return loop(keyTree.left, [List.of(keyTree.witnessRight)]..addAll(W));
      } else if (keyTree is KesSigningLeaf) {
        return SignatureKesSum(
            verificationKey: Int8List.fromList(keyTree.vk),
            signature: await ed25519.sign(message, keyTree.sk),
            witness: W);
      } else {
        return SignatureKesSum(
            verificationKey: Int8List(32),
            signature: Int8List(64),
            witness: [[]]);
      }
    }

    return loop(skTree, []);
  }

  Future<bool> verify(SignatureKesSum signature, List<int> message,
      VerificationKeyKesSum vk) async {
    bool leftGoing(int level) => ((vk.step / kesHelper.exp(level)) % 2) == 0;
    Future<bool> emptyWitness() async =>
        vk.value.sameElements(await kesHelper.hash(signature.verificationKey));
    Future<bool> singleWitness(List<int> witness) async {
      final hashVkSign = await kesHelper.hash(signature.verificationKey);
      if (leftGoing(0)) {
        return vk.value
            .sameElements(await kesHelper.hash(hashVkSign + witness));
      } else
        return vk.value
            .sameElements(await kesHelper.hash(witness + hashVkSign));
    }

    Future<bool> multiWitness(List<List<int>> witnessList,
        List<int> witnessLeft, List<int> witnessRight, int index) async {
      if (witnessList.isEmpty)
        return vk.value
            .sameElements(await kesHelper.hash(witnessLeft + witnessRight));
      else if (leftGoing(index))
        return multiWitness(
          witnessList.sublist(1),
          await kesHelper.hash(witnessLeft + witnessRight),
          witnessList.first,
          index + 1,
        );
      else
        return multiWitness(
          witnessList.sublist(1),
          witnessList.first,
          await kesHelper.hash(witnessLeft + witnessRight),
          index + 1,
        );
    }

    Future<bool> verifyMerkle(List<List<int>> W) async {
      if (W.isEmpty)
        return emptyWitness();
      else if (W.length == 1)
        return singleWitness(W.first);
      else if (leftGoing(0))
        return multiWitness(W.sublist(1),
            await kesHelper.hash(signature.verificationKey), W.first, 1);
      else
        return multiWitness(W.sublist(1), W.first,
            await kesHelper.hash(signature.verificationKey), 1);
    }

    final merkleVerification = await verifyMerkle(signature.witness);
    if (!merkleVerification) return false;

    final ed25519Verification = await ed25519.verify(
        signature.signature, message, signature.verificationKey);
    return ed25519Verification;
  }

  Future<KesBinaryTree> update(KesBinaryTree tree, int step) async {
    if (step == 0) return tree;
    final totalSteps = kesHelper.exp(kesHelper.getTreeHeight(tree));
    final keyTime = getCurrentStep(tree);
    if (step < totalSteps && keyTime < step) {
      return await evolveKey(tree, step);
    }
    throw Exception(
        "Update error - Max steps: $totalSteps, current step: $keyTime, requested increase: $step");
  }

  int getCurrentStep(KesBinaryTree tree) {
    if (tree is KesMerkleNode) {
      if (tree.left is KesEmpty && tree.right is KesSigningLeaf)
        return 1;
      else if (tree.left is KesEmpty && tree.right is KesMerkleNode)
        return getCurrentStep(tree.right) +
            kesHelper.exp(kesHelper.getTreeHeight(tree.right));
      else if (tree.right is KesEmpty) return getCurrentStep(tree.left);
    }
    return 0;
  }

  Future<KesBinaryTree> generateSecretKey(List<int> seed, int height) async {
    Future<KesBinaryTree> seedTree(List<int> seed, int height) async {
      if (height == 0) {
        final keyPair = await ed25519.generateKeyPairFromSeed(seed);
        return KesSigningLeaf(keyPair.sk, keyPair.vk);
      } else {
        final r = await kesHelper.prng(seed);
        final left = await seedTree(r.first, height - 1);
        final right = await seedTree(r.second, height - 1);
        return KesMerkleNode(r.second, await kesHelper.witness(left),
            await kesHelper.witness(right), left, right);
      }
    }

    KesBinaryTree reduceTree(KesBinaryTree fullTree) {
      if (fullTree is KesMerkleNode) {
        eraseOldNode(fullTree.right);
        return KesMerkleNode(fullTree.seed, fullTree.witnessLeft,
            fullTree.witnessRight, reduceTree(fullTree.left), KesEmpty());
      } else {
        return fullTree;
      }
    }

    final out = reduceTree(await seedTree(seed, height));
    kesHelper.overwriteBytes(seed);
    return out;
  }

  Future<VerificationKeyKesSum> generateVerificationKey(
      KesBinaryTree tree) async {
    if (tree is KesMerkleNode) {
      return VerificationKeyKesSum(
          value: await kesHelper.witness(tree), step: getCurrentStep(tree));
    } else if (tree is KesSigningLeaf) {
      return VerificationKeyKesSum(
          value: await kesHelper.witness(tree), step: 0);
    } else {
      return VerificationKeyKesSum(value: Int8List(32), step: 0);
    }
  }

  void eraseOldNode(KesBinaryTree node) {
    if (node is KesMerkleNode) {
      kesHelper.overwriteBytes(node.seed);
      kesHelper.overwriteBytes(node.witnessLeft);
      kesHelper.overwriteBytes(node.witnessRight);
      eraseOldNode(node.left);
      eraseOldNode(node.right);
    } else if (node is KesSigningLeaf) {
      kesHelper.overwriteBytes(node.sk);
      kesHelper.overwriteBytes(node.vk);
    }
  }

  Future<KesBinaryTree> evolveKey(KesBinaryTree input, int step) async {
    final halfTotalSteps = kesHelper.exp(kesHelper.getTreeHeight(input) - 1);
    shiftStep(int step) => step % halfTotalSteps;
    if (step >= halfTotalSteps) {
      if (input is KesMerkleNode) {
        if (input.left is KesSigningLeaf && input.right is KesEmpty) {
          final keyPair = await ed25519.generateKeyPairFromSeed(input.seed);
          final newNode = KesMerkleNode(
              Int8List(input.seed.length),
              input.witnessLeft,
              input.witnessRight,
              KesEmpty(),
              KesSigningLeaf(keyPair.sk, keyPair.vk));
          eraseOldNode(input.left);
          kesHelper.overwriteBytes(input.seed);
          return newNode;
        }
        if (input.left is KesMerkleNode && input.right is KesEmpty) {
          final newNode = KesMerkleNode(
            Int8List(input.seed.length),
            input.witnessLeft,
            input.witnessRight,
            KesEmpty(),
            await evolveKey(
                await generateSecretKey(
                    input.seed, kesHelper.getTreeHeight(input) - 1),
                shiftStep(step)),
          );
          eraseOldNode(input.left);
          kesHelper.overwriteBytes(input.seed);
          return newNode;
        }
      } else if (input is KesSigningLeaf)
        return input;
      else
        return KesEmpty();
    } else {
      if (input is KesMerkleNode && input.right is KesEmpty) {
        return KesMerkleNode(input.seed, input.witnessLeft, input.witnessRight,
            await evolveKey(input.left, shiftStep(step)), KesEmpty());
      } else if (input is KesMerkleNode && input.left is KesEmpty) {
        return KesMerkleNode(input.seed, input.witnessLeft, input.witnessRight,
            KesEmpty(), await evolveKey(input.right, shiftStep(step)));
      } else if (input is KesSigningLeaf) {
        return input;
      }
      return KesEmpty();
    }
    return KesEmpty();
  }
}

const kesSum = KesSum();

abstract class KesBinaryTree {}

class KesMerkleNode extends KesBinaryTree {
  final List<int> seed;
  final List<int> witnessLeft;
  final List<int> witnessRight;
  final KesBinaryTree left;
  final KesBinaryTree right;

  KesMerkleNode(
      this.seed, this.witnessLeft, this.witnessRight, this.left, this.right);
}

class KesSigningLeaf extends KesBinaryTree {
  final List<int> sk;
  final List<int> vk;

  KesSigningLeaf(this.sk, this.vk);
}

class KesEmpty extends KesBinaryTree {}

class SecretKeyKesSum {
  final KesBinaryTree tree;
  final Int64 offset;

  SecretKeyKesSum({required this.tree, required this.offset});
}

class VerificationKeyKesSum {
  final List<int> value;
  final int step;

  VerificationKeyKesSum({required this.value, required this.step});
}

class KeyPairKesSum {
  final SecretKeyKesSum sk;
  final VerificationKeyKesSum vk;

  KeyPairKesSum({required this.sk, required this.vk});
}
