import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const modelSourcePaths = [
  'formal/RealtimeSocket.tla',
  'formal/SocketBehavior.tla',
  'formal/SocketTransitions.tla',
  'formal/SocketSafety.cfg',
  'formal/SocketOracle.tla',
  'formal/SocketOracle.cfg',
  'formal/LifecycleTraceValidation.tla',
  'formal/RealtimeChannelPush.tla',
  'formal/ChannelPushTransitions.tla',
  'formal/ChannelPushSafety.cfg',
  'formal/ChannelOracle.tla',
  'formal/PushOracle.tla',
  'formal/ChannelPushOracle.cfg',
  'formal/generated/KernelSchema.tla',
];

String manifestSha256(Directory packageRoot) => sha256
    .convert(
      File('${packageRoot.path}/formal/manifest.json').readAsBytesSync(),
    )
    .toString();

String modelSha256(Directory packageRoot) {
  final bytes = BytesBuilder(copy: false);
  for (final path in modelSourcePaths) {
    bytes
      ..add(utf8.encode(path))
      ..addByte(0)
      ..add(File('${packageRoot.path}/$path').readAsBytesSync())
      ..addByte(0);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}
