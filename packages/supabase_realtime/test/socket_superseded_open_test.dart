import 'dart:async';

import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A sink that records whether it was ever closed.
class _RecordingSink implements WebSocketSink {
  var closed = false;

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<dynamic> stream) async {}

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }

  @override
  Future<dynamic> get done => Completer<void>().future;
}

/// A transport whose handshake never settles, so the socket stays in the
/// window between `transport()` returning and `ready` completing.
class _StalledChannel implements WebSocketChannel {
  final _controller = StreamController<Object?>.broadcast();
  final recordingSink = _RecordingSink();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => recordingSink;

  @override
  Future<void> get ready => Completer<void>().future;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a superseded OpenTransport effect does not open a transport (S1)',
    () async {
      // Effects run after the state commit, so a batch such as
      // [CancelReconnectTimer, OpenTransport] suspends between its effects. A
      // user disconnect processed in that gap moves the model to
      // intent=down / activeGeneration=0. The pending OpenTransport must not
      // then create a transport the model does not own.
      final opened = <_StalledChannel>[];
      var transportCalls = 0;

      final client = RealtimeClient(
        'wss://localhost:0/',
        reconnectAfter: (_) => const Duration(seconds: 30),
        transport: (_, _) {
          transportCalls++;
          // The first attempt throws synchronously so the socket lands in
          // idle/up with an armed reconnect timer. A later connect() then
          // emits CancelReconnectTimer *before* OpenTransport, which is what
          // creates the suspension point this test targets.
          if (transportCalls == 1) {
            throw StateError('synchronous transport failure');
          }
          final channel = _StalledChannel();
          opened.add(channel);
          return channel;
        },
      );

      await client.connect();
      expect(
        transportCalls,
        1,
        reason: 'first attempt should have been made and failed',
      );

      // Deliberately not awaited: connect() commits phase=connecting and then
      // suspends between CancelReconnectTimer and OpenTransport.
      unawaited(client.connect().catchError((_) {}));
      await client.disconnect();

      // Give any still-pending effect batch a chance to run.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        transportCalls,
        1,
        reason:
            'no transport may be opened once the model has settled to '
            'intent=down; the superseded OpenTransport effect must be dropped',
      );
      expect(
        opened,
        isEmpty,
        reason: 'no WebSocket should have been constructed after disconnect',
      );
      expect(client.connectionState, SocketState.disconnected);
    },
  );
}
