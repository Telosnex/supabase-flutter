// Heartbeat behaviour, driven through the kernel.
//
// These tests used to fake connectivity by assigning connectionState and
// pendingHeartbeatRef directly, which routed them into compatibility branches
// production never took: the assertions passed while covering dead code. They
// now run a mock transport through connect(), so the heartbeat timer, refs and
// replies are all owned by the socket kernel.

import 'dart:async';
import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockIOWebSocketChannel extends Mock implements IOWebSocketChannel {}

class _MockWebSocketSink extends Mock implements WebSocketSink {}

void main() {
  late RealtimeClient client;
  late List<RealtimeHeartbeatStatus> statuses;
  late StreamSubscription<RealtimeHeartbeatStatus> subscription;
  late StreamController<dynamic> incoming;

  RealtimeClient buildClient({
    Future<String?> Function()? customAccessToken,
    Map<String, dynamic>? parameters,
  }) {
    incoming = StreamController<dynamic>.broadcast();
    final channel = _MockIOWebSocketChannel();
    final sink = _MockWebSocketSink();
    when(() => channel.sink).thenReturn(sink);
    when(() => channel.ready).thenAnswer((_) => Future.value());
    when(() => channel.stream).thenAnswer((_) => incoming.stream);
    when(() => sink.add(any())).thenAnswer((_) {});
    when(() => sink.close(any(), any())).thenAnswer((_) => Future.value());
    when(() => sink.close()).thenAnswer((_) => Future.value());
    return RealtimeClient(
      'wss://localhost:0/',
      parameters: parameters ?? const {},
      customAccessToken: customAccessToken,
      transport: (_, _) => channel,
      decode: (rawMessage) =>
          Map<String, dynamic>.from(jsonDecode(rawMessage as String) as Map),
    );
  }

  setUp(() {
    client = buildClient();
    statuses = [];
    subscription = client.onHeartbeat.listen(statuses.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await incoming.close();
  });

  String heartbeatReply(String ref, String status) {
    return jsonEncode({
      'topic': 'phoenix',
      'event': 'phoenix_reply',
      'payload': {'status': status, 'response': <String, dynamic>{}},
      'ref': ref,
    });
  }

  /// Delivers [frame] over the transport and lets the kernel settle.
  Future<void> deliver(String frame) async {
    incoming.add(frame);
    await pumpEventQueue();
  }

  test('emits nothing when the socket is not connected', () async {
    await client.sendHeartbeat();
    await pumpEventQueue();

    expect(statuses, isEmpty);
  });

  test('emits sent when a heartbeat is pushed', () async {
    await client.connect();

    await client.sendHeartbeat();
    await pumpEventQueue();

    expect(statuses, [RealtimeHeartbeatStatus.sent]);
    expect(client.pendingHeartbeatRef, isNotNull);
  });

  test(
    'invokes customAccessToken on each heartbeat to rotate the JWT',
    () async {
      var customCalls = 0;
      final rotatingClient = buildClient(
        parameters: {'apikey': 'initial-token'},
        customAccessToken: () async {
          customCalls++;
          return 'rotated-token-$customCalls';
        },
      );
      addTearDown(rotatingClient.disconnect);
      await rotatingClient.connect();
      customCalls = 0;

      await rotatingClient.sendHeartbeat();
      await pumpEventQueue();

      expect(
        customCalls,
        1,
        reason:
            'each heartbeat must resolve the current token so callers can '
            'rotate JWTs without manually calling setAccessToken',
      );
      expect(rotatingClient.accessToken, 'rotated-token-1');
    },
  );

  test(
    'emits timeout when the previous heartbeat was not acknowledged',
    () async {
      await client.connect();

      await client.sendHeartbeat();
      await pumpEventQueue();
      expect(statuses, [RealtimeHeartbeatStatus.sent], reason: 'sanity');

      // The next tick finds the previous heartbeat still in flight.
      await client.sendHeartbeat();
      await pumpEventQueue();

      expect(statuses.last, RealtimeHeartbeatStatus.timeout);
      expect(client.pendingHeartbeatRef, isNull);
    },
  );

  test('emits ok when the heartbeat reply succeeds', () async {
    await client.connect();
    await client.sendHeartbeat();
    await pumpEventQueue();
    final ref = client.pendingHeartbeatRef;
    expect(ref, isNotNull, reason: 'sanity: heartbeat in flight');

    await deliver(heartbeatReply(ref!, 'ok'));

    expect(statuses, [
      RealtimeHeartbeatStatus.sent,
      RealtimeHeartbeatStatus.ok,
    ]);
    expect(client.pendingHeartbeatRef, isNull);
  });

  test('emits error when the heartbeat reply fails', () async {
    await client.connect();
    await client.sendHeartbeat();
    await pumpEventQueue();
    final ref = client.pendingHeartbeatRef;

    await deliver(heartbeatReply(ref!, 'error'));

    expect(statuses.last, RealtimeHeartbeatStatus.error);
  });

  test(
    'does not emit for messages that are not the pending heartbeat',
    () async {
      await client.connect();
      await client.sendHeartbeat();
      await pumpEventQueue();
      statuses.clear();

      await deliver(heartbeatReply('not-the-pending-ref', 'ok'));

      expect(statuses, isEmpty);
      expect(
        client.pendingHeartbeatRef,
        isNotNull,
        reason: 'the in-flight heartbeat must still be outstanding',
      );
    },
  );
}
