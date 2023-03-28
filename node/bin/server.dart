import 'package:bifrost_blockchain/blockchain.dart';
import 'package:bifrost_codecs/codecs.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  Logger.root.level = Level.FINE;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  final log = Logger("App");

  final blockchain = await Blockchain.init();

  log.info("Let's get this party started!");

  blockchain.run();

  // Access the stream of (adopted) blocks, and do "something" with each.
  blockchain.blocks.forEach((block) {
    log.finer("Got block: ${block.header.id.show}");
  });
}
