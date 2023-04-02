import 'dart:async';

import 'package:async/async.dart';
import 'package:bifrost_blockchain/blockchain.dart';
import 'package:bifrost_codecs/codecs.dart';
import 'package:flutter/material.dart';
import 'package:integral_isolates/integral_isolates.dart';
import 'package:logging/logging.dart';
import 'package:topl_protobuf/consensus/models/block_header.pb.dart';
import 'package:bifrost_crypto/ed25519.dart' as ed25519;
import 'package:bifrost_crypto/ed25519vrf.dart' as ed25519VRF;

void main() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print(
        '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
  });
  final isolate1 = Isolated();
  ed25519.ed25519 = ed25519.Ed25519Isolated(isolate1.isolate);
  final isolate2 = Isolated();
  ed25519VRF.ed25519Vrf = ed25519VRF.Ed25519VRFIsolated(isolate2.isolate);

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
      final blockchain = await Blockchain.init();
      blockchain.run();
      setState(() => this.blockchain = blockchain);
      return;
    }

    unawaited(launch());
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
