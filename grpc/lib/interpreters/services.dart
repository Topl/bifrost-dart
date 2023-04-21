import 'package:bifrost_grpc/interpreters/genus_transaction_service_rpc.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:topl_protobuf/genus/genus_rpc.pbgrpc.dart';
import 'package:topl_protobuf/node/services/bifrost_rpc.pbgrpc.dart';

class RpcServices {
  final NodeRpcServiceBase node;
  final BlockServiceBase genusFullBlock;
  final GenusTransactionGrpc genusTransactionGrpc;

  RpcServices(this.node, this.genusFullBlock, this.genusTransactionGrpc);

  final log = Logger("RpcServices");

  Future<void> serve(String bindHost, int bindPort) async {
    final server = Server(
      [node, genusFullBlock, genusTransactionGrpc],
      [],
      CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
    );
    await server.serve(address: bindHost, port: bindPort);
    log.info("RPC Server running at $bindHost:$bindPort");
  }
}
