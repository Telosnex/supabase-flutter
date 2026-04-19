import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:test/test.dart';

void main() {
  late RealtimeChannel channel;

  setUp(() {
    final socket = RealtimeClient(
      '',
      timeout: const Duration(milliseconds: 1234),
    );
    channel = RealtimeChannel(
      'topic',
      socket,
      config: const RealtimeChannelConfig(),
    );
  });

  test('resend generates a fresh ref while the previous timer is pending', () {
    final joinPush = channel.joinPush;
    addTearDown(joinPush.destroy);

    joinPush.send();
    expect(
      joinPush.ref,
      isNotEmpty,
      reason: 'sanity check — first send assigns a ref',
    );
    final firstRef = joinPush.ref;

    joinPush.resend(const Duration(seconds: 5));

    expect(
      joinPush.ref,
      isNotEmpty,
      reason:
          'resend must cancel the stale timeout timer so startTimeout() can '
          'assign a new ref',
    );
    expect(joinPush.ref, isNot(equals(firstRef)));
  });

  test('resend arms a new timeout timer on the fresh ref', () async {
    final joinPush = channel.joinPush;
    addTearDown(joinPush.destroy);
    joinPush.send();

    var timedOut = false;
    joinPush.receive('timeout', (_) => timedOut = true);

    joinPush.resend(const Duration(milliseconds: 20));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      timedOut,
      isTrue,
      reason:
          'resend must schedule a new timer; the old pending timer reference '
          'must not block startTimeout()',
    );
  });
}
