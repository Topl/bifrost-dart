import 'dart:io';

import 'package:bifrost_blockchain/blockchain.dart';
import 'package:bifrost_blockchain/config.dart';
import 'package:bifrost_blockchain/isolate_pool.dart';
import 'package:bifrost_codecs/codecs.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  final log = Logger("App");

  final blockchain = await Blockchain.init(BlockchainConfig.defaultConfig,
      IsolatePool(Platform.numberOfProcessors).isolate);

  log.info("Let's get this party started!");

  blockchain.run();

  // Access the stream of (adopted) blocks, and do "something" with each.
  blockchain.blocks.asyncMap((block) => block.header.id).forEach((id) {
    log.finer("Got block: ${id.show}");
  });
}
