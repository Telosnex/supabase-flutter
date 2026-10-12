import 'package:realtime_client/realtime_client.dart';
import 'package:realtime_client/src/constants.dart';
import 'package:realtime_client/src/message.dart';
import 'package:test/test.dart';

/// A private channel join fails with an expired token, typically right after
/// an app resume. The refreshed token used to wait for the next backoff tick,
/// up to 10 seconds, before any channel tried again.
void main() {
  group('setAuth with a new token', () {
    test('rejoins an errored channel right away with that token', () async {
      final socket = _FakeConnectedSocket(
        // The backoff timer must not be what sends the rejoin.
        reconnectAfterMs: (_) => const Duration(minutes: 10).inMilliseconds,
      );
      final channel = socket.channel('topic');
      channel.subscribe();
      channel.joinPush.trigger('error', {
        'reason': 'Invalid JWTToken: Token has expired',
      });
      expect(channel.isErrored, isTrue);
      final joinsBefore = socket.joins.length;

      await socket.setAuth('fresh-token');

      expect(socket.joins.length, joinsBefore + 1);
      expect(socket.joins.last.payload['access_token'], 'fresh-token');
      expect(channel.isJoining, isTrue);

      channel.joinPush.trigger('ok', {});
    });

    test('leaves a joined channel joined', () async {
      final socket = _FakeConnectedSocket();
      final channel = socket.channel('topic');
      channel.subscribe();
      channel.joinPush.trigger('ok', {});
      final joinsBefore = socket.joins.length;

      await socket.setAuth('fresh-token');

      expect(socket.joins.length, joinsBefore);
      expect(channel.isJoined, isTrue);
    });

    test('does not rejoin for the same token', () async {
      final socket = _FakeConnectedSocket(
        reconnectAfterMs: (_) => const Duration(minutes: 10).inMilliseconds,
      );
      await socket.setAuth('same-token');
      final channel = socket.channel('topic');
      channel.subscribe();
      channel.joinPush.trigger('error', {'reason': 'unauthorized'});
      final joinsBefore = socket.joins.length;

      await socket.setAuth('same-token');

      expect(socket.joins.length, joinsBefore);
      channel.joinPush.trigger('ok', {});
    });

    test('waits for the socket when disconnected', () async {
      final socket = _FakeConnectedSocket(
        reconnectAfterMs: (_) => const Duration(minutes: 10).inMilliseconds,
      );
      final channel = socket.channel('topic');
      channel.subscribe();
      channel.joinPush.trigger('error', {'reason': 'unauthorized'});
      socket.connected = false;
      final joinsBefore = socket.joins.length;

      await socket.setAuth('fresh-token');

      expect(socket.joins.length, joinsBefore);
      expect(channel.isErrored, isTrue, reason: 'socket open rejoins it');
      channel.joinPush.trigger('ok', {});
    });
  });
}

class _FakeConnectedSocket extends RealtimeClient {
  _FakeConnectedSocket({super.reconnectAfterMs})
    : super('wss://example.com/socket');

  bool connected = true;
  final joins = <Message>[];

  @override
  bool get isConnected => connected;

  @override
  String? push(Message message) {
    if (message.event == ChannelEvents.join) joins.add(message);
    return null;
  }
}
