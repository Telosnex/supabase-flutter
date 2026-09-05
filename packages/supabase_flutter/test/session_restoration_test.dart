import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'utils.dart';

class DelayedStorage extends LocalStorage {
  DelayedStorage({this.text, this.delayRead = false});
  String? text;
  final bool delayRead;
  final entered = Completer<void>();
  final release = Completer<void>();
  int probes = 0;
  int reads = 0;
  bool fail = false;

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async {
    if (++probes == 2 && !delayRead) {
      entered.complete();
      await release.future;
      if (fail) throw StateError('private storage diagnostic');
    }
    return text != null;
  }

  @override
  Future<String?> accessToken() async {
    if (++reads == 2 && delayRead) {
      entered.complete();
      await release.future;
      if (fail) throw StateError('private storage diagnostic');
    }
    return text;
  }

  // Keep the fixture snapshot stable even if initialSession persistence runs.
  @override
  Future<void> persistSession(String persistSessionString) async {}
  @override
  Future<void> removePersistedSession() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    Supabase sdk;
    try {
      sdk = Supabase.instance;
    } on AssertionError {
      return; // A disposal test already disposed the singleton.
    }
    await sdk.dispose();
  });

  Future<Supabase> initialize(
    DelayedStorage storage, {
    http.Client? client,
    bool refresh = false,
  }) {
    return Supabase.initialize(
      url: 'https://restoration.test',
      publishableKey: 'public-key',
      debug: false,
      httpClient: client ?? MockClient((_) async => http.Response('', 204)),
      authOptions: FlutterAuthClientOptions(
        localStorage: storage,
        autoRefreshToken: refresh,
        detectSessionInUri: false,
      ),
    );
  }

  String session({bool expired = false}) => getSessionData(
    DateTime.now().add(
      expired ? const Duration(hours: -1) : const Duration(hours: 1),
    ),
  ).sessionString;

  for (final hasSession in [false, true]) {
    test(
      'initialize/initialSession are earlier than restoration ($hasSession)',
      () async {
        final storage = DelayedStorage(text: hasSession ? session() : null);
        final sdk = await initialize(storage);
        await storage.entered.future;
        final event = await sdk.client.auth.onAuthStateChange.first;
        expect(event.event, AuthChangeEvent.initialSession);
        var completed = false;
        final barrier = sdk.sessionRestorationComplete.then(
          (_) => completed = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        storage.release.complete();
        await barrier;
        expect(completed, isTrue);
        expect(sdk.client.auth.currentSession != null, hasSession);
        expect(
          identical(
            sdk.sessionRestorationComplete,
            sdk.sessionRestorationComplete,
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'waits for expired-session refresh, not just reading persistence',
    () async {
      final storage = DelayedStorage(text: session(expired: true));
      final requested = Completer<void>(), response = Completer<void>();
      final fresh = session();
      final sdk = await initialize(
        storage,
        refresh: true,
        client: MockClient((r) async {
          expect(r.url.queryParameters['grant_type'], 'refresh_token');
          if (!requested.isCompleted) requested.complete();
          await response.future;
          return http.Response(fresh, 200);
        }),
      );
      storage.release.complete();
      await requested.future;
      var completed = false;
      final barrier = sdk.sessionRestorationComplete.then(
        (_) => completed = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      response.complete();
      await barrier;
      expect(
        sdk.client.auth.currentSession!.accessToken,
        jsonDecode(fresh)['access_token'],
      );
    },
  );

  for (final atRead in [false, true]) {
    test(
      'storage failure is observed, sanitized, and safe without early await ($atRead)',
      () async {
        final storage = DelayedStorage(text: session(), delayRead: atRead);
        final sdk = await initialize(storage);
        await storage.entered.future;
        storage.fail = true;
        storage.release.complete();
        // No observer yet: the opt-in background Future must not throw in zone.
        await Future<void>.delayed(Duration.zero);
        await expectLater(
          sdk.sessionRestorationComplete,
          throwsA(
            isA<SessionRestorationException>().having(
              (e) => e.toString(),
              'sanitized',
              isNot(contains('private')),
            ),
          ),
        );
      },
    );
  }

  test('refresh failure cannot report restoration success', () async {
    final storage = DelayedStorage(text: session(expired: true));
    final sdk = await initialize(
      storage,
      refresh: true,
      client: MockClient(
        (_) async => http.Response(
          '{"msg":"invalid refresh token","code":"refresh_token_not_found"}',
          400,
        ),
      ),
    );
    final rejected = expectLater(
      sdk.sessionRestorationComplete,
      throwsA(isA<SessionRestorationException>()),
    );
    storage.release.complete();
    await rejected;
    expect(sdk.client.auth.currentSession, isNull);
  });

  test('malformed session cannot report success', () async {
    final storage = DelayedStorage(text: '{invalid');
    final sdk = await initialize(storage);
    final rejected = expectLater(
      sdk.sessionRestorationComplete,
      throwsA(isA<SessionRestorationException>()),
    );
    storage.release.complete();
    await rejected;
  });

  test('sign-out during delayed storage prevents resurrection', () async {
    final storage = DelayedStorage(text: session(), delayRead: true);
    final sdk = await initialize(storage);
    await storage.entered.future;
    await sdk.client.auth.signOut(scope: SignOutScope.local);
    final rejected = expectLater(
      sdk.sessionRestorationComplete,
      throwsA(isA<SessionRestorationException>()),
    );
    storage.release.complete();
    await rejected;
    expect(sdk.client.auth.currentSession, isNull);
  });

  test(
    'sign-out during refresh stays signed out after recovery finishes',
    () async {
      final storage = DelayedStorage(text: session(expired: true));
      final entered = Completer<void>(), release = Completer<void>();
      final sdk = await initialize(
        storage,
        refresh: true,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/logout')) return http.Response('', 204);
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return http.Response(session(), 200);
        }),
      );
      storage.release.complete();
      await entered.future;
      await sdk.client.auth.signOut(scope: SignOutScope.local);
      release.complete();
      await sdk.sessionRestorationComplete;
      // The GoTrue client's existing session-version fence discards stale refresh.
      expect(sdk.client.auth.currentSession, isNull);
    },
  );

  test(
    'dispose rejects waiter and old read cannot adopt into reinitialized client',
    () async {
      final old = DelayedStorage(text: session(), delayRead: true);
      final sdk = await initialize(old);
      await old.entered.future;
      final rejected = expectLater(
        sdk.sessionRestorationComplete,
        throwsA(isA<SessionRestorationException>()),
      );
      final oldClient = sdk.client;
      await sdk.dispose();
      await rejected;
      final fresh = DelayedStorage();
      final next = await initialize(fresh);
      fresh.release.complete();
      await next.sessionRestorationComplete;
      old.release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(identical(oldClient, next.client), isFalse);
      expect(next.client.auth.currentSession, isNull);
    },
  );

  test(
    'dispose during initial persistence read rejects both initialization and barrier',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final storage = _InitialReadStorage(entered, release);
      final initialization = initialize(storage);
      await entered.future;
      final sdk = Supabase.instance;
      final rejectedInitialization = expectLater(
        initialization,
        throwsA(isA<SessionRestorationException>()),
      );
      final rejectedRestoration = expectLater(
        sdk.sessionRestorationComplete,
        throwsA(isA<SessionRestorationException>()),
      );
      await sdk.dispose();
      release.complete();
      await rejectedInitialization;
      await rejectedRestoration;
      expect(sdk.isInitialized, isFalse);
    },
  );

  test('custom accessToken mode has no session recovery', () async {
    final sdk = await Supabase.initialize(
      url: 'https://restoration.test',
      publishableKey: 'public-key',
      debug: false,
      accessToken: () async => 'external-token',
    );
    await expectLater(sdk.sessionRestorationComplete, completes);
  });
}

class _InitialReadStorage extends DelayedStorage {
  _InitialReadStorage(this.initialEntered, this.initialRelease);
  final Completer<void> initialEntered, initialRelease;
  @override
  Future<bool> hasAccessToken() async {
    initialEntered.complete();
    await initialRelease.future;
    return false;
  }
}
