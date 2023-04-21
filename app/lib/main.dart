import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:bifrost_blockchain/blockchain.dart';
import 'package:bifrost_blockchain/config.dart';
import 'package:bifrost_blockchain/isolate_pool.dart';
import 'package:bifrost_codecs/codecs.dart';
import 'package:bifrost_crypto/kes.dart' as kes;
import 'package:bifrost_crypto/utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:bifrost_crypto/ed25519.dart' as ed25519;
import 'package:bifrost_crypto/ed25519vrf.dart' as ed25519VRF;
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:topl_protobuf/node/models/block.pb.dart';

var _isolate = LocalCompute;

void main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print(
        '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
  });
  if (!kIsWeb) {
    final computePool = IsolatePool(Platform.numberOfProcessors);
    _isolate = computePool.isolate;
  }
  ed25519.ed25519 = ed25519.Ed25519Isolated(_isolate);
  ed25519VRF.ed25519Vrf = ed25519VRF.Ed25519VRFIsolated(_isolate);
  kes.kesProduct = kes.KesProudctIsolated(_isolate);

  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Builder(builder: launchButton)),
      ),
    );
  }

  Widget launchButton(BuildContext context) => TextButton(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (context) => const BlockchainPage())),
        child: const Text("Launch"),
      );
}

class BlockchainPage extends StatefulWidget {
  const BlockchainPage({super.key});

  @override
  _BlockchainPageState createState() => _BlockchainPageState();
}

class _BlockchainPageState extends State<BlockchainPage> {
  Blockchain? blockchain;

  @override
  void initState() {
    super.initState();

    Future<void> launch() async {
      await _flutterBackgroundInit();
      final blockchain = await Blockchain.init(
          BlockchainConfig(rpc: BlockchainRpc(enable: !kIsWeb)), _isolate);
      blockchain.run();
      setState(() => this.blockchain = blockchain);
      return;
    }

    unawaited(launch());
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(_flutterBackgroundRelease());
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: (blockchain != null) ? ready(blockchain!) : loading);

  Widget get loading => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );

  Widget ready(Blockchain blockchain) {
    return Center(
      child: StreamBuilder(
        stream: _accumulateBlocksStream(blockchain),
        builder: (context, snapshot) => _blocksView(snapshot.data ?? []),
      ),
    );
  }

  Stream<List<FullBlock>> _accumulateBlocksStream(Blockchain blockchain) =>
      StreamGroup.merge([
        Stream.fromFuture(blockchain.localChain.currentHead),
        blockchain.localChain.adoptions
      ]).asyncMap((id) async {
        final header = await blockchain.dataStores.headers.getOrRaise(id);
        final body = await blockchain.dataStores.bodies.getOrRaise(id);
        final transactions = await Future.wait(body.transactionIds
            .map(blockchain.dataStores.transactions.getOrRaise));
        final fullBlock = FullBlock(
            header: header,
            fullBody: FullBlockBody(transactions: transactions));
        print(json.encode(fullBlock.toProto3Json()));
        return fullBlock;
      }).transform(StreamTransformer.fromBind((inStream) {
        final List<FullBlock> state = [];
        return inStream.map((block) {
          state.insert(0, block);
          return List.of(state);
        });
      }));

  Widget _blocksView(List<FullBlock> blocks) => SizedBox(
        width: 500,
        child: ListView.separated(
          itemCount: blocks.length,
          itemBuilder: (context, index) => Card(
            color: const Color.fromARGB(210, 255, 255, 255),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder(
                      future: blocks[index].header.id,
                      builder: (context, snapshot) =>
                          Text(snapshot.data?.show ?? "")),
                  Text("Height: ${blocks[index].header.height}"),
                  Text("Slot: ${blocks[index].header.slot}"),
                  Text("Timestamp: ${blocks[index].header.timestamp}"),
                  Text(
                      "Transactions: ${blocks[index].fullBody.transactions.length}"),
                ],
              ),
            ),
          ),
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(),
        ),
      );
}

_flutterBackgroundInit() async {
  if (!kIsWeb && Platform.isAndroid) {
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Bifrost",
      notificationText: "Blockchain is running in the background.",
      notificationImportance: AndroidNotificationImportance.Default,
      enableWifiLock: true,
    );
    bool success =
        await FlutterBackground.initialize(androidConfig: androidConfig);

    assert(success);
    await FlutterBackground.enableBackgroundExecution();
  }
}

_flutterBackgroundRelease() async {
  if (!kIsWeb && Platform.isAndroid) {
    await FlutterBackground.disableBackgroundExecution();
  }
}
