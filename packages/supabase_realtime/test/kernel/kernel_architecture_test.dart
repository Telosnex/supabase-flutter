import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('production shells delegate lifecycle mutation to queued drivers', () {
    final shells = {
      'socket': File('lib/src/realtime_client.dart').readAsStringSync(),
      'channel': File('lib/src/realtime_channel.dart').readAsStringSync(),
      'push': File('lib/src/push.dart').readAsStringSync(),
    };
    final drivers = {
      'socket': File(
        'lib/src/kernel/realtime_socket_driver.dart',
      ).readAsStringSync(),
      'channel': File(
        'lib/src/kernel/realtime_channel_driver.dart',
      ).readAsStringSync(),
      'push': File(
        'lib/src/kernel/realtime_push_driver.dart',
      ).readAsStringSync(),
    };

    expect(shells['socket'], contains('_socketDriver.dispatch('));
    expect(shells['channel'], contains('_driver.dispatch('));
    expect(shells['push'], contains('_driver.dispatch('));
    for (final source in shells.values) {
      expect(source, isNot(contains('_driver.state.copyWith(')));
      expect(source, isNot(contains('_socketDriver.state.copyWith(')));
      expect(source, isNot(contains('SocketModelState(')));
      expect(source, isNot(contains('ChannelModelState(')));
      expect(source, isNot(contains('PushModelState(')));
      expect(source, isNot(contains('_state = result.postState')));
    }
    for (final source in drivers.values) {
      expect(source, contains('Queue<'));
      expect(source, contains('_state = result.postState;'));
      expect(source, contains('_drainEvents()'));
    }
  });

  test('every generated shell effect has one exhaustive handler', () {
    expect(
      _handledEffects(
        File('lib/src/realtime_client.dart').readAsStringSync(),
        'SocketEffectKind',
      ),
      {
        'openTransport',
        'closeTransport',
        'armReconnectTimer',
        'cancelReconnectTimer',
        'armHeartbeatTimer',
        'cancelHeartbeatTimer',
        'armDisconnectTimer',
        'cancelDisconnectTimer',
        'sendHeartbeat',
        'resolveCurrentToken',
        'emitConnectionOpen',
        'emitConnectionClosed',
        'emitConnectionError',
        'emitHeartbeat',
        'notifyChannelsOfTransportError',
      },
    );
    expect(
      _handledEffects(
        File('lib/src/realtime_channel.dart').readAsStringSync(),
        'ChannelModelEffectKind',
      ),
      {
        'sendChannelJoin',
        'sendChannelLeave',
        'armChannelRejoinTimer',
        'cancelChannelRejoinTimer',
        'evictDuplicateChannels',
        'emitChannelSubscribed',
        'emitChannelError',
        'emitChannelClosed',
      },
    );
    expect(
      _handledEffects(
        File('lib/src/push.dart').readAsStringSync(),
        'PushModelEffectKind',
      ),
      {
        'bindPushReply',
        'unbindPushReply',
        'armPushTimeoutTimer',
        'cancelPushTimeoutTimer',
        'sendPush',
        'deliverPushResult',
      },
    );
  });
}

Set<String?> _handledEffects(String source, String enumName) => RegExp(
  'case $enumName\\.([A-Za-z0-9_]+):',
).allMatches(source).map((match) => match.group(1)).toSet();
