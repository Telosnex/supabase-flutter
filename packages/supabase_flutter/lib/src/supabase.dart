import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:supabase/supabase.dart';
import 'package:supabase_common/supabase_common.dart';
import 'package:supabase_flutter/src/constants.dart';
import 'package:supabase_flutter/src/flutter_go_true_client_options.dart';
import 'package:supabase_flutter/src/local_storage.dart';
import 'package:supabase_flutter/src/supabase_auth.dart';

import 'hot_restart_cleanup_stub.dart'
    if (dart.library.js_interop) 'hot_restart_cleanup_web.dart';
import 'version.dart';

final _log = Logger('supabase.supabase_flutter');

/// Startup restoration failed or was interrupted. Contains no session data.
class SessionRestorationException implements Exception {
  const SessionRestorationException();

  @override
  String toString() => 'Session restoration failed or was interrupted.';
}

/// Supabase instance.
///
/// It must be initialized before used, otherwise an error is thrown.
///
/// ```dart
/// await Supabase.initialize(...)
/// ```
///
/// Use it:
///
/// ```dart
/// final instance = Supabase.instance;
/// ```
///
/// See also:
///
///   * [SupabaseAuth]
class Supabase {
  /// Gets the current supabase instance.
  ///
  /// An [AssertionError] is thrown if supabase isn't initialized yet.
  /// Call [Supabase.initialize] to initialize it.
  static Supabase get instance {
    assert(
      _instance._isInitialized,
      'You must initialize the supabase instance before calling Supabase.instance',
    );
    return _instance;
  }

  /// Initialize the current supabase instance
  ///
  /// This must be called only once. If called more than once, an
  /// [AssertionError] is thrown
  ///
  /// [url] and [publishableKey] can be found on your Supabase dashboard.
  /// Use the `publishable` (anon) key here — never the secret key in a
  /// Flutter app.
  ///
  /// You can access none public schema by passing different [schema].
  ///
  /// Default headers can be overridden by specifying [headers].
  ///
  /// Pass [localStorage] to override the default local storage option used to
  /// persist auth.
  ///
  /// Custom http client can be used by passing [httpClient] parameter.
  ///
  /// [storageRetryAttempts] specifies how many retry attempts there should be
  /// to upload a file to Supabase storage when failed due to network
  /// interruption.
  ///
  /// Set [authFlowType] to [AuthFlowType.implicit] to use the old implicit flow for authentication
  /// involving deep links.
  ///
  /// PKCE flow uses shared preferences for storing the code verifier by default.
  /// Pass a custom storage to [pkceAsyncStorage] to override the behavior.
  ///
  /// If [debug] is set to `true`, debug logs will be printed in debug console. Default is `kDebugMode`.
  static Future<Supabase> initialize({
    required String url,
    String? publishableKey,
    @Deprecated(
      'Use publishableKey instead. anonKey will be removed in a future major version.',
    )
    String? anonKey,
    Map<String, String>? headers,
    Client? httpClient,
    RealtimeClientOptions realtimeClientOptions = const RealtimeClientOptions(),
    PostgrestClientOptions postgrestOptions = const PostgrestClientOptions(),
    StorageClientOptions storageOptions = const StorageClientOptions(),
    FlutterAuthClientOptions authOptions = const FlutterAuthClientOptions(),
    TracePropagationOptions tracePropagationOptions =
        const TracePropagationOptions(),
    Future<String?> Function()? accessToken,
    bool? debug,
  }) async {
    assert(
      publishableKey != null || anonKey != null,
      'Either publishableKey or anonKey must be provided.',
    );
    final effectiveKey = publishableKey ?? anonKey!;

    if (_instance._isInitialized) {
      _log.info('Supabase is already initialized. Skipping reinitialization.');
      return _instance;
    }

    _instance._debugEnable = debug ?? (kDebugMode && !isRunningInFlutterTest);

    if (_instance._debugEnable) {
      _instance._logSubscription = Logger('supabase').onRecord.listen((record) {
        if (record.level >= Level.INFO) {
          debugPrint(
            '${record.loggerName}: ${record.level.name}: ${record.message} ${record.error ?? ""}',
          );
        }
      });
    }

    _log.config("Initialize Supabase v$version");

    if (authOptions.pkceAsyncStorage == null) {
      authOptions = authOptions.copyWith(
        pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
      );
    }
    if (authOptions.localStorage == null) {
      authOptions = authOptions.copyWith(
        localStorage: authOptions.persistSession
            ? SharedPreferencesLocalStorage(
                persistSessionKey:
                    "sb-${Uri.parse(url).host.split(".").first}-auth-token",
              )
            : const EmptyLocalStorage(),
      );
    }
    _instance._init(
      url,
      effectiveKey,
      httpClient: httpClient,
      customHeaders: headers,
      realtimeClientOptions: realtimeClientOptions,
      authOptions: authOptions,
      postgrestOptions: postgrestOptions,
      storageOptions: storageOptions,
      tracePropagationOptions: tracePropagationOptions,
      accessToken: accessToken,
    );

    final restoration = _instance._sessionRestoration;
    if (accessToken == null) {
      final supabaseAuth = SupabaseAuth();
      _instance._supabaseAuth = supabaseAuth;
      try {
        await supabaseAuth.initialize(options: authOptions);
      } catch (_) {
        if (!restoration.isCompleted) {
          restoration.completeError(const SessionRestorationException());
        }
        rethrow;
      }

      // Observe the underlying operation, not CancelableOperation.value:
      // cancellation suppresses that value forever, but does not cancel IO.
      final recovery = supabaseAuth.recoverSession().then((succeeded) {
        if (!restoration.isCompleted) {
          if (succeeded) {
            restoration.complete();
          } else {
            restoration.completeError(const SessionRestorationException());
          }
        }
      });
      _instance._restoreSessionCancellableOperation =
          CancelableOperation.fromFuture(recovery);
    } else {
      restoration.complete(); // Third-party accessToken mode has no recovery.
    }

    _log.info('***** Supabase init completed *****');

    return _instance;
  }

  Supabase._();
  static final Supabase _instance = Supabase._();

  bool _isInitialized = false;

  /// Whether the Supabase instance has been initialized. Useful for debugging.
  bool get isInitialized => _isInitialized;

  /// The supabase client for this instance
  ///
  /// Throws an error if [Supabase.initialize] was not called.
  late SupabaseClient client;

  late Completer<void> _sessionRestoration;

  /// Completes after this initialization's persisted-session recovery,
  /// including any token refresh it awaits. Unlike [initialize] returning or
  /// `initialSession`, success means that startup recovery is no longer pending.
  /// It does NOT assert signed-in/signed-out state or wait for app listeners,
  /// persistence writes, future refreshes or unrelated auth operations.
  ///
  /// Throws [SessionRestorationException] on recovery failure or disposal before
  /// completion. Disposal does not cancel already-dispatched IO. Await success
  /// and recheck current identity before dispatching account-changing work.
  /// No recovery runs with a custom `accessToken`; that mode completes normally.
  /// A future retained across dispose/reinitialize belongs to the old lifecycle.
  Future<void> get sessionRestorationComplete => _sessionRestoration.future;

  SupabaseAuth? _supabaseAuth;

  bool _debugEnable = false;

  /// Wraps the `recoverSession()` call so that it can be terminated when `dispose()` is called
  ///
  /// Only set when [Supabase.initialize] is called without a custom
  /// `accessToken`, since session recovery is skipped for third-party auth.
  CancelableOperation<dynamic>? _restoreSessionCancellableOperation;

  // Listener for app lifecycle events to handle Realtime reconnection.
  AppLifecycleListener? _lifecycleListener;

  /// Serial queue for lifecycle operations (connect/disconnect). Each event
  /// appends via `.then()` so operations never overlap.
  Future<void> _pendingLifecycleOperation = Future.value();

  /// The most recently requested lifecycle state. Checked inside
  /// [_processLifecycle] after each `await` to skip stale operations
  /// (e.g. abort a reconnect if the app went back to background).
  AppLifecycleState? _targetLifecycleState;

  StreamSubscription<dynamic>? _logSubscription;

  /// Dispose the instance to free up resources.
  Future<void> dispose() async {
    _targetLifecycleState = null;
    if (!_sessionRestoration.isCompleted) {
      _sessionRestoration.completeError(const SessionRestorationException());
    }
    _supabaseAuth?.dispose();
    _supabaseAuth = null;
    await _restoreSessionCancellableOperation?.cancel();
    await _logSubscription?.cancel();
    await client.dispose();
    _lifecycleListener?.dispose();
    _isInitialized = false;
  }

  void _init(
    String supabaseUrl,
    String supabaseKey, {
    Client? httpClient,
    Map<String, String>? customHeaders,
    required RealtimeClientOptions realtimeClientOptions,
    required PostgrestClientOptions postgrestOptions,
    required StorageClientOptions storageOptions,
    required AuthClientOptions authOptions,
    required TracePropagationOptions tracePropagationOptions,
    required Future<String?> Function()? accessToken,
  }) {
    _sessionRestoration = Completer<void>();
    // The API is opt-in; background failure must not become an unhandled error
    // when nobody observes it. Awaiters still receive the original failure.
    _sessionRestoration.future.ignore();
    _restoreSessionCancellableOperation = null;
    final headers = {...Constants.defaultHeaders, ...?customHeaders};
    client = SupabaseClient(
      supabaseUrl,
      supabaseKey,
      httpClient: httpClient,
      headers: headers,
      realtimeClientOptions: realtimeClientOptions,
      postgrestOptions: postgrestOptions,
      storageOptions: storageOptions,
      authOptions: authOptions,
      tracePropagationOptions: tracePropagationOptions,
      accessToken: accessToken,
    );

    // Close any previous realtime client that may still be connected due to
    // flutter web hot-restart.
    if (kDebugMode) {
      disposePreviousClient();
      markClientToDispose(client);
    }

    _setupLifecycleListener();

    _isInitialized = true;
  }

  void _setupLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        switch (state) {
          case AppLifecycleState.resumed:
          case AppLifecycleState.paused:
          case AppLifecycleState.detached:
            _targetLifecycleState = state;
            _pendingLifecycleOperation = _pendingLifecycleOperation
                .then((_) => _processLifecycle(state))
                .catchError((_) {});
          case AppLifecycleState.inactive:
          case AppLifecycleState.hidden:
            break;
        }
      },
    );
  }

  /// Processes a lifecycle state change. Operations are serialized via
  /// [_pendingLifecycleOp] so that disconnect and connect never overlap.
  ///
  /// [captured] is the lifecycle state at the time the event was enqueued.
  /// If a newer event has arrived since, this one is skipped (stale).
  Future<void> _processLifecycle(AppLifecycleState captured) async {
    // Skip if a newer lifecycle event has superseded this one.
    if (captured != _targetLifecycleState) return;

    final realtime = Supabase.instance.client.realtime;

    if (captured == AppLifecycleState.resumed) {
      // No channels subscribed — nothing to reconnect.
      if (realtime.channels.isEmpty) return;

      // Already connected (e.g. coming from [AppLifecycleState.inactive]
      // where no disconnect happened).
      if (realtime.isConnected) return;

      // ignore: invalid_use_of_internal_member
      await realtime.connect();

      // Abort rejoin if app went back to background during connect.
      if (_targetLifecycleState != AppLifecycleState.resumed) return;

      // Re-send join messages for channels that were previously joined.
      // After a disconnect/reconnect the WebSocket is fresh, but the
      // channel objects still have joined state — forceRejoin() restores
      // the server-side subscriptions.
      for (final channel in realtime.channels) {
        // ignore: invalid_use_of_internal_member
        if (channel.isJoined) {
          // ignore: invalid_use_of_internal_member
          channel.forceRejoin();
        }
      }
    } else {
      // paused or detached — disconnect the WebSocket if it is active.
      // These states are not triggered on web
      if (realtime.isConnected ||
          realtime.connState == SocketStates.connecting) {
        await realtime.disconnect();
      }
    }
  }
}
