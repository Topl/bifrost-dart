import 'dart:async';
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
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:bifrost_crypto/ed25519.dart' as ed25519;
import 'package:bifrost_crypto/ed25519vrf.dart' as ed25519VRF;
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
      final blockchain =
          await Blockchain.init(BlockchainConfig.defaultConfig, _isolate);
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
      (blockchain != null) ? ready(blockchain!) : loading;

  Widget get loading => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );

  Widget ready(Blockchain blockchain) {
    return Scaffold(
      body: Center(
        child: StreamBuilder(
          stream: _accumulateBlocksStream(blockchain),
          builder: (context, snapshot) => _headersView(snapshot.data ?? []),
        ),
      ),
    );
  }

  Stream<List<BlockHeader>> _accumulateBlocksStream(Blockchain blockchain) =>
      StreamGroup.merge([
        Stream.fromFuture(blockchain.localChain.currentHead),
        blockchain.localChain.adoptions
      ])
          .asyncMap(blockchain.dataStores.headers.getOrRaise)
          .transform(StreamTransformer.fromBind((inStream) {
        final List<BlockHeader> state = [];
        return inStream.map((block) {
          state.insert(0, block);
          return List.of(state);
        });
      }));

  ListView _headersView(List<BlockHeader> headers) => ListView.separated(
        itemCount: headers.length,
        itemBuilder: (context, index) => Column(
          children: [
            FutureBuilder(
                future: headers[index].id,
                builder: (context, snapshot) =>
                    Text(snapshot.data?.show ?? "")),
            Text("Height: ${headers[index].height}"),
            Text("Slot: ${headers[index].slot}"),
          ],
        ),
        separatorBuilder: (BuildContext context, int index) => const Divider(),
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
