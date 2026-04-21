import 'dart:async';

import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:supabase_realtime/src/message.dart';
import 'package:test/test.dart';

void main() {
  group('phx_error reply on join push', () {
    test('transitions the channel from joining to errored', () {
      final socket = RealtimeClient('wss://example.com/socket');
      final channel = socket.channel('topic');

      channel.subscribe();
      expect(channel.isJoining, isTrue);

      channel.joinPush.trigger('error', {
        'reason': 'Invalid JWTToken: Token has expired',
      });

      expect(channel.isErrored, isTrue);
      expect(channel.isJoining, isFalse);
    });

    test('schedules a rejoin while the socket is connected', () async {
      final socket = _FakeConnectedSocket(
        'wss://example.com/socket',
        reconnectAfter: (_) => const Duration(milliseconds: 10),
      );
      final channel = socket.channel('topic');

      channel.subscribe();
      final firstRef = channel.joinPush.ref;
      expect(firstRef, isNotEmpty);

      channel.joinPush.trigger('error', {
        'reason': 'Invalid JWTToken: Token has expired',
      });

      await socket.secondPush.timeout(const Duration(milliseconds: 200));
      expect(channel.joinPush.ref, isNot(equals(firstRef)));

      // Stop any retry timer armed by the current rejoin implementation.
      channel.joinPush.trigger('ok', {});
    });
  });
}

class _FakeConnectedSocket extends RealtimeClient {
  _FakeConnectedSocket(super.endpoint, {super.reconnectAfter});

  final _secondPush = Completer<void>();
  int _pushes = 0;

  Future<void> get secondPush => _secondPush.future;

  @override
  bool get isConnected => true;

  @override
  void push(Message message) {
    _pushes++;
    if (_pushes == 2 && !_secondPush.isCompleted) {
      _secondPush.complete();
    }
  }
}
