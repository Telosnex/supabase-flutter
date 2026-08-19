import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_channel_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_driver.dart';

const _stepsPerMachine = 200;
const _seed = 13013;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw const FormatException('Usage: generate_random_trace.dart OUTPUT');
  }
  final random = Random(_seed);
  final clock = _FakeClock();
  final traces = <Map<String, Object?>>[];

  final socket = RealtimeSocketDriver(
    executeEffect: (effect, context) {},
    traceSink: traces.add,
  );
  for (var index = 0; index < _stepsPerMachine; index++) {
    clock.tick();
    await socket.dispatch(_socketEvent(socket.state, random));
  }

  final channel = RealtimeChannelDriver(
    channelId: 1,
    executeEffect: (effect, metadata) {},
    traceSink: traces.add,
  );
  for (var index = 0; index < _stepsPerMachine; index++) {
    clock.tick();
    await channel.dispatch(_channelEvent(channel.state, random));
  }

  final push = RealtimePushDriver(
    executeEffect: (effect, metadata) {},
    traceSink: traces.add,
  );
  for (var index = 0; index < _stepsPerMachine; index++) {
    clock.tick();
    await push.dispatch(_pushEvent(push.state, random));
  }

  File(arguments.single).writeAsStringSync(
    '${traces.map(jsonEncode).join('\n')}\n',
  );
  stdout.writeln(
    'Generated ${traces.length} seeded lifecycle entries '
    '(seed $_seed, fake ticks ${clock.ticks}).',
  );
}

SocketModelEvent _socketEvent(SocketModelState state, Random random) {
  switch (state.phase) {
    case SocketPhase.idle:
      if (state.intent == SocketIntent.up && state.reconnectTimer.armed) {
        return SocketModelEvent.reconnectTimerFired(
          timerId: state.reconnectTimer.id,
        );
      }
      return SocketModelEvent.connectRequested();
    case SocketPhase.connecting:
      if (random.nextInt(4) == 0) {
        return SocketModelEvent.transportOpenFailed(
          generation: state.activeGeneration,
          failureKind: random.nextBool()
              ? FailureKind.syncValue
              : FailureKind.asyncValue,
        );
      }
      return SocketModelEvent.transportOpened(
        generation: state.activeGeneration,
      );
    case SocketPhase.open:
      if (random.nextInt(8) == 0) {
        return SocketModelEvent.disconnectRequested();
      }
      if (state.pendingHeartbeat.active && random.nextBool()) {
        return SocketModelEvent.heartbeatReplyReceived(
          generation: state.pendingHeartbeat.generation,
          ref: state.pendingHeartbeat.ref,
          heartbeatStatus: random.nextBool()
              ? HeartbeatStatus.ok
              : HeartbeatStatus.error,
        );
      }
      return SocketModelEvent.heartbeatTimerFired(
        timerId: state.heartbeatTimer.id,
      );
    case SocketPhase.closing:
      return SocketModelEvent.transportClosed(
        generation: state.activeGeneration,
        failureKind: state.intent == SocketIntent.down
            ? FailureKind.requested
            : FailureKind.server,
      );
  }
}

ChannelModelEvent _channelEvent(ChannelModelState state, Random random) {
  switch (state.phase) {
    case ChannelPhase.closed:
      return ChannelModelEvent.channelSubscribeRequested();
    case ChannelPhase.joining:
      return ChannelModelEvent.channelJoinReplyReceived(
        epoch: state.activeJoinEpoch,
        replyStatus: switch (random.nextInt(4)) {
          0 => ReplyStatus.error,
          1 => ReplyStatus.timeout,
          _ => ReplyStatus.ok,
        },
      );
    case ChannelPhase.joined:
      if (random.nextInt(5) == 0) {
        return ChannelModelEvent.channelUnsubscribeRequested();
      }
      return ChannelModelEvent.channelErrorObserved(
        epoch: state.activeJoinEpoch,
      );
    case ChannelPhase.errored:
      if (state.socketAvailable != random.nextBool()) {
        return ChannelModelEvent.channelSocketAvailabilityChanged(
          available: !state.socketAvailable,
        );
      }
      return ChannelModelEvent.channelRejoinTimerFired(
        timerId: state.rejoinTimer.id,
      );
    case ChannelPhase.leaving:
      return ChannelModelEvent.channelClosedObserved(
        epoch: state.activeJoinEpoch,
      );
  }
}

PushModelEvent _pushEvent(PushModelState state, Random random) {
  switch (state.phase) {
    case PushPhase.idle:
      return random.nextBool()
          ? PushModelEvent.pushSendRequested()
          : PushModelEvent.pushPrepareRequested();
    case PushPhase.pending:
      if (!state.sent) return PushModelEvent.pushSendRequested();
      if (random.nextInt(3) == 0) {
        return PushModelEvent.pushTimeoutFired(
          timerId: state.timeoutTimer.id,
        );
      }
      return PushModelEvent.pushReplyReceived(
        ref: state.activeRef,
        replyStatus: random.nextBool() ? ReplyStatus.ok : ReplyStatus.error,
      );
    case PushPhase.terminal:
      return random.nextBool()
          ? PushModelEvent.pushResendRequested()
          : PushModelEvent.pushDestroyRequested();
  }
}

final class _FakeClock {
  var ticks = 0;

  void tick() => ticks++;
}
