import 'package:supabase_realtime/src/kernel/generated/model_hash.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_driver.dart';
import 'package:test/test.dart';

void main() {
  test('driver owns state and emits a schema/model-hashed trace', () async {
    final effects = <SocketModelEffect>[];
    final traces = <Map<String, Object?>>[];
    final driver = RealtimeSocketDriver(
      executeEffect: (effect, context) => effects.add(effect),
      traceSink: traces.add,
    );

    final result = await driver.dispatch(SocketModelEvent.connectRequested());

    expect(result.action, SocketAction.startConnect);
    expect(driver.state.phase, SocketPhase.connecting);
    expect(effects.single.kind, SocketEffectKind.openTransport);
    expect(traces, hasLength(1));
    expect(traces.single, {
      'schemaHash': realtimeFormalManifestSha256,
      'modelHash': realtimeSocketModelSha256,
      'machine': 'socket',
      'instance': 'socket',
      'sequence': 1,
      'event': {'kind': 'ConnectRequested'},
      'action': 'startConnect',
      'disposition': 'applied',
      'preState': isA<Map<String, Object?>>(),
      'postState': driver.state.toJson(),
      'effects': [
        {'kind': 'OpenTransport', 'generation': 1},
      ],
    });
  });

  test('driver rejects a shell contract violation', () async {
    final driver = RealtimeSocketDriver(
      executeEffect: (effect, context) {},
    );

    await expectLater(
      driver.dispatch(SocketModelEvent.transportOpened(generation: 0)),
      throwsStateError,
    );
  });
}
