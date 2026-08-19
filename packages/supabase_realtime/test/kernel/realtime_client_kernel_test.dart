import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _SocketChannel extends Mock implements WebSocketChannel {}

class _SocketSink extends Mock implements WebSocketSink {}

void main() {
  test(
    'public connect/disconnect lifecycle is driven by kernel traces',
    () async {
      final channel = _SocketChannel();
      final sink = _SocketSink();
      final stream = StreamController<Object>.broadcast();
      final traces = <Map<String, Object?>>[];
      when(() => channel.ready).thenAnswer((_) async {});
      when(() => channel.sink).thenReturn(sink);
      when(() => channel.stream).thenAnswer((_) => stream.stream);
      when(() => sink.close()).thenAnswer((_) async {});

      final client = RealtimeClient(
        'wss://example.test/socket',
        transport: (_, _) => channel,
        logger: (kind, message, data) {
          if (kind == 'formal' && message == 'socket_transition') {
            traces.add((data! as Map).cast<String, Object?>());
          }
        },
      );

      await client.connect();
      expect(client.connectionState, SocketState.open);
      final openState = SocketModelState.fromJson(
        (traces.last['postState']! as Map).cast<String, Object?>(),
      );
      expect(openState.phase, SocketPhase.open);
      expect(openState.heartbeatTimer.generation, 1);

      await client.disconnect();
      expect(client.connectionState, SocketState.disconnected);
      final disconnectedState = SocketModelState.fromJson(
        (traces.last['postState']! as Map).cast<String, Object?>(),
      );
      expect(disconnectedState.intent, SocketIntent.down);
      expect(disconnectedState.phase, SocketPhase.idle);
      expect(
        traces.map((trace) => trace['action']),
        [
          'startConnect',
          'acceptTransportOpen',
          'beginUserClose',
          'settleCloseIdle',
        ],
      );
      expect(
        traces.map((trace) => trace['sequence']),
        [1, 2, 3, 4],
      );

      await stream.close();
    },
  );
}
