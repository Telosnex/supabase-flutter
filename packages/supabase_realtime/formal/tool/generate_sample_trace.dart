import 'dart:convert';
import 'dart:io';

import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_channel_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_driver.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_driver.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw const FormatException('Usage: generate_sample_trace.dart OUTPUT');
  }
  final traces = <Map<String, Object?>>[];
  final socket = RealtimeSocketDriver(
    executeEffect: (effect, context) {},
    traceSink: traces.add,
  );

  await socket.dispatch(SocketModelEvent.connectRequested());
  final generation = socket.state.activeGeneration;
  await socket.dispatch(
    SocketModelEvent.transportOpened(generation: generation),
  );
  final heartbeatTimerId = socket.state.heartbeatTimer.id;
  await socket.dispatch(
    SocketModelEvent.heartbeatTimerFired(timerId: heartbeatTimerId),
  );
  final debt = socket.state.pendingHeartbeat;
  await socket.dispatch(
    SocketModelEvent.heartbeatReplyReceived(
      generation: debt.generation,
      ref: debt.ref,
      heartbeatStatus: HeartbeatStatus.ok,
    ),
  );
  await socket.dispatch(SocketModelEvent.disconnectRequested());
  await socket.dispatch(
    SocketModelEvent.transportClosed(
      generation: generation,
      failureKind: FailureKind.requested,
    ),
  );

  final channel = RealtimeChannelDriver(
    channelId: 1,
    executeEffect: (effect, metadata) {},
    traceSink: traces.add,
  );
  await channel.dispatch(
    ChannelModelEvent.channelSocketAvailabilityChanged(available: true),
  );
  await channel.dispatch(ChannelModelEvent.channelSubscribeRequested());
  final epoch = channel.state.activeJoinEpoch;
  await channel.dispatch(
    ChannelModelEvent.channelJoinReplyReceived(
      epoch: epoch,
      replyStatus: ReplyStatus.ok,
    ),
  );
  await channel.dispatch(ChannelModelEvent.channelUnsubscribeRequested());
  await channel.dispatch(
    ChannelModelEvent.channelClosedObserved(epoch: epoch),
  );

  final push = RealtimePushDriver(
    executeEffect: (effect, metadata) {},
    traceSink: traces.add,
  );
  await push.dispatch(PushModelEvent.pushSendRequested());
  await push.dispatch(
    PushModelEvent.pushReplyReceived(
      ref: push.state.activeRef,
      replyStatus: ReplyStatus.ok,
    ),
  );

  File(arguments.single).writeAsStringSync(
    '${traces.map(jsonEncode).join('\n')}\n',
  );
  stdout.writeln('Generated ${traces.length} runtime trace entries.');
}
