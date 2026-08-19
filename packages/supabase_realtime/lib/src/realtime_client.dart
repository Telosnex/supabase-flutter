import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:supabase_realtime/supabase_realtime.dart';
import 'package:supabase_realtime/src/constants.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/realtime_socket_driver.dart';
import 'package:supabase_realtime/src/message.dart';
import 'package:supabase_realtime/src/retry_timer.dart';
import 'package:supabase_realtime/src/serializer.dart';
import 'package:supabase_realtime/src/websocket/websocket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WebSocketTransport =
    WebSocketChannel Function(
      String url,
      Map<String, String> headers,
    );

/// Serializes an outgoing message into the `String` or binary frame written to
/// the WebSocket.
typedef RealtimeEncode = Object Function(Map<String, dynamic> payload);

/// Deserializes a raw incoming WebSocket frame (`String` or binary) into a
/// message map.
typedef RealtimeDecode = Map<String, dynamic> Function(Object payload);

/// Event details for when the connection closed.
class RealtimeCloseEvent {
  /// Web socket protocol status codes for when a connection is closed.
  ///
  /// The full list can be found at the following:
  ///
  /// https://datatracker.ietf.org/doc/html/rfc6455#section-7.4
  final int code;

  /// Connection closed reason sent from the server
  ///
  /// https://datatracker.ietf.org/doc/html/rfc6455#section-7.1.6
  final String? reason;

  const RealtimeCloseEvent({
    required this.code,
    required this.reason,
  });

  @override
  String toString() {
    return 'RealtimeCloseEvent(code: $code, reason: $reason)';
  }
}

final class _CloseRequest {
  const _CloseRequest({required this.code, required this.reason});

  final int? code;
  final String? reason;
}

/// The lifecycle status of a heartbeat reported to
/// [RealtimeClient.onHeartbeat].
enum RealtimeHeartbeatStatus {
  sent,
  ok,
  error,
  timeout,
}

/// The status of the WebSocket connection reported by
/// [RealtimeClient.onStatusChange].
enum RealtimeConnectionStatus {
  /// The connection is open and messages can be sent and received.
  open,

  /// The connection is closed, either because [RealtimeClient.disconnect] was
  /// called or because it dropped, in which case the client reconnects with
  /// backoff. [RealtimeClient.connectionState] tells the two apart.
  closed,
}

/// A connection status change emitted by [RealtimeClient.onStatusChange].
class RealtimeConnectionStatusChange {
  /// The new status of the WebSocket connection.
  final RealtimeConnectionStatus status;

  /// The close code and reason sent by the server, `null` for
  /// [RealtimeConnectionStatus.open] and for a close without one.
  final RealtimeCloseEvent? closeEvent;

  const RealtimeConnectionStatusChange(this.status, [this.closeEvent]);

  @override
  String toString() =>
      'RealtimeConnectionStatusChange(status: ${status.name}, '
      'closeEvent: $closeEvent)';
}

/// Manages a persistent WebSocket connection to the Supabase Realtime server.
///
/// [RealtimeClient] is the central hub for all real-time communication. It owns
/// the WebSocket lifecycle — opening, closing, and reconnecting with
/// exponential backoff — and multiplexes multiple [RealtimeChannel]
/// subscriptions over a single connection.
///
/// **Responsibilities:**
/// - Establishes and maintains the WebSocket connection to [endpoint].
/// - Sends periodic heartbeat messages to detect stale connections and
///   reconnects automatically when a heartbeat goes unanswered.
/// - Encodes outgoing messages and decodes incoming messages (JSON by default).
/// - Manages a registry of [RealtimeChannel] instances, routing inbound
///   messages to the correct channel by topic.
/// - Refreshes the access token and propagates it to all joined channels so
///   that subscriptions remain authorized across token rotations.
///
/// **Key collaborators:**
/// - [RealtimeChannel] — created via [channel] and registered here; the client
///   dispatches server messages to each channel by topic.
/// - `RetryTimer` — drives the reconnect backoff strategy.
/// - [WebSocketTransport] — injectable transport layer used in tests.
///
/// **Lifecycle:**
/// 1. Construct with an endpoint URL and optional configuration.
/// 2. Call [connect] to open the WebSocket. The client begins heartbeating
///    immediately and reconnects on unexpected disconnections.
/// 3. Create channels with [channel], subscribe to events, and call
///    `RealtimeChannel.subscribe()` to join server-side topics.
/// 4. Call [disconnect] when real-time functionality is no longer needed; this
///    removes all channels and closes the underlying socket.
///
/// **Platform notes:**
/// - Works on all Dart platforms (Flutter mobile/desktop, web, server).
/// - On web, the underlying [WebSocketChannel] uses the browser WebSocket API.
class RealtimeClient {
  String? accessToken;
  List<RealtimeChannel> channels = [];
  final String endpoint;

  final Map<String, String> headers;
  final Map<String, dynamic> parameters;

  final RealtimeProtocolVersion version;
  final Duration connectionCloseTimeout;
  final Duration timeout;
  final WebSocketTransport transport;
  final Client? httpClient;
  final _log = Logger('supabase.realtime');
  Duration heartbeatInterval = RealtimeConstants.defaultHeartbeatInterval;
  @internal
  Timer? heartbeatTimer;
  Timer? _kernelReconnectTimer;
  int? _kernelReconnectTimerId;
  int? _kernelHeartbeatTimerId;
  int? _kernelDisconnectTimerId;
  int? _kernelPendingHeartbeatGeneration;
  int? _kernelPendingHeartbeatRef;

  /// Delay before the socket is disconnected once the last channel has been
  /// removed. [Duration.zero] disconnects immediately. Defaults to twice the
  /// heartbeat interval.
  @internal
  late final Duration disconnectOnEmptyChannelsAfter;

  /// Timer that fires the deferred disconnect once all channels are gone.
  ///
  /// Cancelled when a new channel is created or the client disconnects before
  /// it fires, so that quickly switching channels reuses the open socket.
  Timer? _pendingDisconnectTimer;

  /// reference ID of the most recently sent heartbeat.
  ///
  /// Used to keep track of whether the client is connected to the server.
  @internal
  String? pendingHeartbeatRef;

  /// Counter used by [makeRef] to generate a unique reference ID for every
  /// pushed message, including heartbeats.
  @internal
  int ref = 0;
  @internal
  late RetryTimer reconnectTimer;
  void Function(String? kind, String? message, dynamic data)? logger;
  static final Serializer _serializer = Serializer();
  final RealtimeEncode encode;
  final RealtimeDecode decode;
  late TimerCalculation reconnectAfter;
  WebSocketChannel? connection;
  StreamSubscription<dynamic>? _connectionSubscription;
  final Map<int, WebSocketChannel> _connectionsByGeneration = {};
  final Map<int, StreamSubscription<dynamic>> _subscriptionsByGeneration = {};
  final Set<int> _terminalGenerationsReported = {};
  late final RealtimeSocketDriver _socketDriver;
  var _formalTraceSequence = 0;
  var _preserveLegacyClosedState = false;
  @internal
  List<dynamic> sendBuffer = [];

  final _statusController =
      StreamController<RealtimeConnectionStatusChange>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  final _heartbeatController =
      StreamController<RealtimeHeartbeatStatus>.broadcast();

  /// The current state of the socket, or `null` before the first [connect].
  SocketState? connectionState;
  @internal
  void emitFormalTrace(Map<String, Object?> trace) {
    _log.finest('formal.lifecycle ${jsonEncode(trace)}');
    logger?.call('formal', 'lifecycle_transition', trace);
  }

  Future<String?> Function()? customAccessToken;

  /// Initializes the Socket
  ///
  /// [endpoint] The string WebSocket endpoint, ie, "ws://example.com/socket",
  /// "wss://example.com", or "/socket" (which inherits the host and protocol).
  ///
  /// [transport] The Websocket Transport, for example WebSocket.
  ///
  /// [timeout] The default timeout to trigger push timeouts.
  ///
  /// [connectionCloseTimeout] The timeout to wait for the connection to close
  /// before dismissing the result. Defaults to 6 seconds.
  ///
  /// [parameters] The optional parameters to pass when connecting.
  ///
  /// [headers] The optional headers to pass when connecting.
  ///
  /// [heartbeatInterval] The interval at which to send a heartbeat message.
  ///
  /// [disconnectOnEmptyChannelsAfter] The delay before disconnecting the socket
  /// once the last channel is removed. If a new channel is created before the
  /// delay elapses, the pending disconnect is cancelled and the open socket is
  /// reused. Pass [Duration.zero] to disconnect immediately. Defaults to twice
  /// the heartbeat interval.
  ///
  /// [logger] The optional function for specialized logging, ie:
  ///
  /// ```dart
  /// logger: (kind, message, data) => print('$kind: $message $data')
  /// ```
  ///
  /// [encode] Overrides how outgoing messages are serialized, for example to
  /// use a faster JSON implementation. Defaults to the codec for [version].
  ///
  /// [decode] Overrides how incoming frames are deserialized. Defaults to the
  /// codec for [version].
  ///
  /// [reconnectAfter] The optional function that returns the reconnect
  /// interval. Defaults to the stepped backoff of
  /// [RetryTimer.createRetryFunction].
  ///
  /// [logLevel] Specifies the log level for the connection on the server.
  ///
  /// [version] The Realtime protocol version. Defaults to
  /// [RealtimeProtocolVersion.v2]; pass [RealtimeProtocolVersion.v1] for the
  /// legacy object-shaped JSON frames.
  RealtimeClient(
    String endpoint, {
    WebSocketTransport? transport,
    this.timeout = RealtimeConstants.defaultTimeout,
    this.connectionCloseTimeout =
        RealtimeConstants.defaultConnectionCloseTimeout,
    this.heartbeatInterval = RealtimeConstants.defaultHeartbeatInterval,
    Duration? disconnectOnEmptyChannelsAfter,
    this.logger,
    RealtimeEncode? encode,
    RealtimeDecode? decode,
    TimerCalculation? reconnectAfter,
    Map<String, String>? headers,
    this.parameters = const {},
    RealtimeLogLevel? logLevel,
    this.httpClient,
    this.customAccessToken,
    this.version = RealtimeProtocolVersion.v2,
  }) : endpoint = Uri.parse('$endpoint/websocket')
           .replace(
             queryParameters: logLevel == null
                 ? null
                 : {'log_level': logLevel.name},
           )
           .toString(),
       headers = {
         ...RealtimeConstants.defaultHeaders,
         ...?headers,
       },
       transport = transport ?? createWebSocketClient,
       encode =
           encode ??
           (version == RealtimeProtocolVersion.v1
               ? _encodeLegacy
               : _serializer.encode),
       decode =
           decode ??
           (version == RealtimeProtocolVersion.v1
               ? _decodeLegacy
               : _serializer.decode) {
    _socketDriver = RealtimeSocketDriver(
      executeEffect: _executeSocketEffect,
      traceSink: _onSocketTrace,
      validateRepresentation: _socketRepresentationMatches,
    );
    _log.config(
      'Initialize RealtimeClient with endpoint: $endpoint, timeout: $timeout, '
      'heartbeatInterval: $heartbeatInterval, '
      'logLevel: ${logLevel?.name}',
    );
    _log.finest('Initialize with headers: $headers, parameters: $parameters');
    final customJWT = this.headers['Authorization']?.split(' ').last;
    accessToken = customJWT ?? parameters['apikey'];

    this.disconnectOnEmptyChannelsAfter =
        disconnectOnEmptyChannelsAfter ?? (heartbeatInterval * 2);

    this.reconnectAfter = reconnectAfter ?? RetryTimer.createRetryFunction();
    reconnectTimer = RetryTimer(
      () {
        final timerId = _kernelReconnectTimerId;
        if (timerId != null) {
          unawaited(
            _socketDriver.dispatch(
              SocketModelEvent.reconnectTimerFired(timerId: timerId),
            ),
          );
        }
      },
      this.reconnectAfter,
    );
  }

  /// Connects the socket.
  @internal
  Future<void> connect() async {
    await _socketDriver.dispatch(SocketModelEvent.connectRequested());
  }

  /// Disconnects the socket with status [code] and [reason] for the disconnect
  Future<void> disconnect({int? code, String? reason}) async {
    final legacyState = connectionState;
    final legacyConnection = connection;
    final legacyOnlyConnection = _connectionsByGeneration.isEmpty;
    _preserveLegacyClosedState = legacyState == SocketState.closed;
    await _socketDriver.dispatch(
      SocketModelEvent.disconnectRequested(),
      metadata: _CloseRequest(code: code, reason: reason),
    );
    if (legacyConnection != null &&
        legacyState == SocketState.open &&
        legacyOnlyConnection) {
      if (code != null) {
        await legacyConnection.sink.close(code, reason ?? '');
      } else {
        await legacyConnection.sink.close();
      }
    }
    await _disposeAllTransports();
    connection = null;
    if (legacyState == SocketState.closed) {
      connectionState = SocketState.closed;
    }
    _preserveLegacyClosedState = false;
    log('transport', 'disconnected', null, Level.FINE);
  }

  List<RealtimeChannel> getChannels() {
    return channels;
  }

  Future<String> removeChannel(RealtimeChannel channel) async {
    final status = await channel.unsubscribe();
    return status;
  }

  Future<List<String>> removeAllChannels() async {
    final values = await Future.wait(
      channels.map((channel) => channel.unsubscribe()),
    );
    await disconnect();
    return values;
  }

  /// Logs the message. Override `this.logger` for specialized logging.
  ///
  /// [level] must be [Level.FINEST] for sensitive data
  void log([
    String? kind,
    String? message,
    dynamic data,
    Level level = Level.FINEST,
  ]) {
    _log.log(level, '$kind: $message', data);
    logger?.call(kind, message, data);
  }

  /// Emits whenever the WebSocket connection opens or closes.
  ///
  /// Connection errors are emitted as stream errors, so they are observed with
  /// the `onError` handler of [Stream.listen] rather than as status changes:
  ///
  /// ```dart
  /// final subscription = client.onStatusChange.listen(
  ///   (change) => print('Socket ${change.status.name}.'),
  ///   onError: (error) => print('Socket error: $error'),
  /// );
  /// ```
  ///
  /// The connection level statuses and errors are informational: a dropped
  /// connection and its cause also reach every channel through
  /// [RealtimeChannel.onStatusChange], which is what a subscription should
  /// react to.
  Stream<RealtimeConnectionStatusChange> get onStatusChange =>
      _statusController.stream;

  /// Emits every decoded message received over the WebSocket.
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  /// Emits a status whenever a heartbeat is sent, acknowledged, errors, or
  /// times out.
  Stream<RealtimeHeartbeatStatus> get onHeartbeat =>
      _heartbeatController.stream;

  /// Returns `true` is the connection is open.
  bool get isConnected => connectionState == SocketState.open;

  /// Removes a subscription from the socket.
  ///
  /// Matches on identity rather than on [RealtimeChannel.joinRef], which is
  /// the empty string until a channel is subscribed and is therefore shared
  /// by every channel that has not joined yet.
  @internal
  void remove(RealtimeChannel channel) {
    channels = channels.where((c) => !identical(c, channel)).toList();
    if (channels.isEmpty) {
      log('transport', 'no channels remaining, scheduling disconnect');
      _schedulePendingDisconnect();
    }
  }

  RealtimeChannel channel(
    String topic, [
    RealtimeChannelConfig config = const RealtimeChannelConfig(),
  ]) {
    final newChannel = RealtimeChannel('realtime:$topic', this, config: config);
    _cancelPendingDisconnect();
    channels.add(newChannel);
    return newChannel;
  }

  /// Schedules a disconnect once the last channel is removed.
  ///
  /// When [disconnectOnEmptyChannelsAfter] is [Duration.zero] the socket
  /// disconnects immediately, otherwise the disconnect is deferred so that a
  /// channel created within the delay can reuse the open socket.
  void _schedulePendingDisconnect() {
    unawaited(
      _socketDriver.dispatch(
        SocketModelEvent.channelDemandDisappeared(
          grace: disconnectOnEmptyChannelsAfter == Duration.zero
              ? GraceKind.zero
              : GraceKind.nonzero,
        ),
      ),
    );
  }

  /// Cancels a scheduled disconnect when channel activity is detected.
  void _cancelPendingDisconnect() {
    unawaited(
      _socketDriver.dispatch(SocketModelEvent.channelDemandAppeared()),
    );
  }

  /// Push out a message if the socket is connected.
  ///
  /// If the socket is not connected, the message gets enqueued within a local
  /// buffer, and sent out when a connection is next established.
  @internal
  void push(Message message) {
    void callback() {
      connection?.sink.add(encode(message.toJson()));
    }

    log(
      'push',
      '${message.topic} ${message.event.name} (${message.ref})',
      message.payload,
    );

    if (isConnected) {
      callback();
    } else {
      sendBuffer.add(callback);
    }
  }

  void onConnectionMessage(Object rawMessage) {
    final Map<String, dynamic> message;
    try {
      message = decode(rawMessage);
    } catch (error) {
      log('transport', 'failed to decode message', error);
      return;
    }

    final topic = message['topic'] as String;
    final event = message['event'] as String;
    final payload = message['payload'];
    final messageRef = message['ref'] as String?;
    if (messageRef != null && messageRef == pendingHeartbeatRef) {
      final heartbeatStatus = payload is Map ? payload['status'] : null;
      final parsedRef = int.tryParse(messageRef);
      if (parsedRef != null &&
          _kernelPendingHeartbeatGeneration != null &&
          _kernelPendingHeartbeatRef == parsedRef) {
        unawaited(
          _socketDriver.dispatch(
            SocketModelEvent.heartbeatReplyReceived(
              generation: _kernelPendingHeartbeatGeneration!,
              ref: parsedRef,
              heartbeatStatus: heartbeatStatus == 'ok'
                  ? HeartbeatStatus.ok
                  : HeartbeatStatus.error,
            ),
          ),
        );
      } else {
        // Compatibility for callers that historically assigned the public
        // pendingHeartbeatRef test seam directly.
        pendingHeartbeatRef = null;
        _heartbeatController.add(
          heartbeatStatus == 'ok'
              ? RealtimeHeartbeatStatus.ok
              : RealtimeHeartbeatStatus.error,
        );
      }
    }

    final status = payload is Map ? (payload['status'] ?? '') : '';
    log(
      'receive',
      "$status $topic $event ${messageRef != null ? '($messageRef)' : ''}",
      payload,
    );

    channels
        .where((channel) => channel.isMember(topic))
        .forEach(
          (channel) => channel.trigger(
            event,
            payload,
            messageRef,
          ),
        );
    _messageController.add(message);
  }

  static Object _encodeLegacy(Map<String, dynamic> message) =>
      jsonEncode(message);

  static Map<String, dynamic> _decodeLegacy(Object rawMessage) =>
      Map.from(jsonDecode(rawMessage as String) as Map);

  /// Returns the URL of the websocket.
  String get endpointUrl {
    final queryParameters = Map<String, String>.from(parameters);
    queryParameters['vsn'] = version.wireVersion;
    return _appendParameters(endpoint, queryParameters);
  }

  /// Return the next message ref, accounting for overflows
  @internal
  String makeRef() {
    final int newRef = ref + 1;
    if (newRef < 0) {
      ref = 0;
    } else {
      ref = newRef;
    }
    return ref.toString();
  }

  void _onSocketTrace(Map<String, Object?> trace) {
    final sequence = trace['sequence']! as int;
    assert(sequence == _formalTraceSequence + 1);
    _formalTraceSequence = sequence;
    final state = SocketModelState.fromJson(
      (trace['postState']! as Map).cast<String, Object?>(),
    );
    if (!_preserveLegacyClosedState) {
      connectionState = _publicConnectionState(state);
    }
    pendingHeartbeatRef = state.pendingHeartbeat.active
        ? state.pendingHeartbeat.ref.toString()
        : null;
    if (!state.pendingHeartbeat.active) {
      _kernelPendingHeartbeatGeneration = null;
      _kernelPendingHeartbeatRef = null;
    }
    _log.finest('formal.socket ${jsonEncode(trace)}');
    logger?.call('formal', 'socket_transition', trace);
  }

  SocketState? _publicConnectionState(SocketModelState state) {
    if (!state.started) return null;
    return switch (state.phase) {
      SocketPhase.connecting => SocketState.connecting,
      SocketPhase.open => SocketState.open,
      SocketPhase.closing when state.closeKind == CloseKind.user =>
        SocketState.disconnecting,
      SocketPhase.closing => SocketState.open,
      SocketPhase.idle when state.intent == SocketIntent.up =>
        SocketState.closed,
      SocketPhase.idle => SocketState.disconnected,
    };
  }

  bool _socketRepresentationMatches(SocketModelState state) {
    final ownsTransport = state.activeGeneration > 0;
    return (!state.reconnectTimer.armed ||
            state.reconnectTimer.id == _kernelReconnectTimerId) &&
        (!state.heartbeatTimer.armed ||
            state.heartbeatTimer.id == _kernelHeartbeatTimerId) &&
        (!state.disconnectTimer.armed ||
            state.disconnectTimer.id == _kernelDisconnectTimerId) &&
        (!state.pendingHeartbeat.active ||
            _kernelPendingHeartbeatRef != null) &&
        (!state.pendingHeartbeat.active ||
            (state.pendingHeartbeat.ref == _kernelPendingHeartbeatRef &&
                state.pendingHeartbeat.generation ==
                    _kernelPendingHeartbeatGeneration)) &&
        (!ownsTransport ||
            _connectionsByGeneration.containsKey(state.activeGeneration) ||
            _terminalGenerationsReported.contains(state.activeGeneration));
  }

  Future<void> _executeSocketEffect(
    SocketModelEffect effect,
    SocketEffectContext context,
  ) async {
    switch (effect.kind) {
      case SocketEffectKind.openTransport:
        await _openTransport(effect.generation!);
      case SocketEffectKind.closeTransport:
        await _closeTransport(
          effect.generation!,
          effect.closeReason!,
          context.metadata,
        );
      case SocketEffectKind.armReconnectTimer:
        _armReconnectTimer(effect.timerId!, effect.delayOrdinal!);
      case SocketEffectKind.cancelReconnectTimer:
        _cancelReconnectTimer(effect.timerId!);
      case SocketEffectKind.armHeartbeatTimer:
        _armHeartbeatTimer(effect.timerId!);
      case SocketEffectKind.cancelHeartbeatTimer:
        _cancelHeartbeatTimer(effect.timerId!);
      case SocketEffectKind.armDisconnectTimer:
        _armDisconnectTimer(effect.timerId!);
      case SocketEffectKind.cancelDisconnectTimer:
        _cancelDisconnectTimer(effect.timerId!);
      case SocketEffectKind.sendHeartbeat:
        _sendKernelHeartbeat(effect.generation!, effect.ref!);
      case SocketEffectKind.resolveCurrentToken:
        await setAccessToken(null);
      case SocketEffectKind.emitConnectionOpen:
        _onConnectionOpen();
      case SocketEffectKind.emitConnectionClosed:
        _onConnectionClose(context.metadata as RealtimeCloseEvent?);
      case SocketEffectKind.emitConnectionError:
        _onConnectionError(
          context.cause ??
              StateError(
                'Realtime transport ${effect.failureKind!.wireName} failure',
              ),
        );
      case SocketEffectKind.emitHeartbeat:
        _emitHeartbeat(effect.heartbeatStatus!);
      case SocketEffectKind.notifyChannelsOfTransportError:
        _triggerChanError(context.cause ?? context.metadata);
    }
  }

  Future<void> _openTransport(int generation) async {
    // The model committed this OpenTransport obligation, but effects run after
    // the commit and other events may have been processed in between. If the
    // model no longer owns this attempt, opening a transport here would create
    // a resource the model does not know about and nothing would ever close it
    // (ADR-013 S1: no transport opens while intent is down).
    if (_socketDriver.state.activeGeneration != generation) {
      log('transport', 'open superseded before connect', null, Level.FINE);
      return;
    }
    log('transport', 'connecting to $endpointUrl', null);
    log('transport', 'connecting', null, Level.FINE);
    final WebSocketChannel localConnection;
    try {
      localConnection = transport(endpointUrl, headers);
    } catch (error) {
      if (connectionState == SocketState.disconnecting) {
        await _socketDriver.dispatch(
          SocketModelEvent.transportOpenFailed(
            generation: generation,
            failureKind: FailureKind.syncValue,
          ),
          cause: error,
        );
        await _socketDriver.dispatch(SocketModelEvent.disconnectRequested());
        return;
      }
      await _socketDriver.dispatch(
        SocketModelEvent.transportOpenFailed(
          generation: generation,
          failureKind: FailureKind.syncValue,
        ),
        cause: error,
      );
      return;
    }
    connection = localConnection;
    _connectionsByGeneration[generation] = localConnection;
    _terminalGenerationsReported.remove(generation);

    try {
      await localConnection.ready;
    } catch (error) {
      await _disposeGeneration(generation);
      await _socketDriver.dispatch(
        SocketModelEvent.transportOpenFailed(
          generation: generation,
          failureKind: FailureKind.asyncValue,
        ),
        cause: error,
      );
      return;
    }

    if (identical(_connectionsByGeneration[generation], localConnection)) {
      try {
        final subscription = localConnection.stream.listen(
          (message) => onConnectionMessage(message as Object),
          onError: (Object error, StackTrace stackTrace) {
            unawaited(
              _socketDriver.dispatch(
                SocketModelEvent.transportErrorObserved(
                  generation: generation,
                  failureKind: FailureKind.stream,
                ),
                cause: error,
              ),
            );
          },
          onDone: () {
            unawaited(_transportDone(generation, localConnection));
          },
        );
        _subscriptionsByGeneration[generation] = subscription;
        _connectionSubscription = subscription;
      } on TypeError {
        // Some existing injected test transports only implement ready/sink.
        // A production WebSocketChannel always exposes a stream.
      }
    }
    await _socketDriver.dispatch(
      SocketModelEvent.transportOpened(generation: generation),
    );
  }

  Future<void> _transportDone(
    int generation,
    WebSocketChannel localConnection,
  ) async {
    final closeEvent = _closeEvent(localConnection);
    await _reportTransportTerminated(
      SocketModelEvent.transportClosed(
        generation: generation,
        failureKind: FailureKind.server,
      ),
      metadata: closeEvent,
    );
  }

  Future<void> _reportTransportTerminated(
    SocketModelEvent event, {
    Object? cause,
    Object? metadata,
  }) async {
    final generation = event.generation!;
    if (!_terminalGenerationsReported.add(generation)) return;
    await _socketDriver.dispatch(
      event,
      cause: cause,
      metadata: metadata,
    );
    await _disposeGeneration(generation);
  }

  Future<void> _closeTransport(
    int generation,
    CloseReason closeReason,
    Object? metadata,
  ) async {
    final localConnection = _connectionsByGeneration[generation];
    if (localConnection == null) {
      final error = StateError(
        'Generation $generation has no transport handle to close',
      );
      await _socketDriver.dispatch(
        SocketModelEvent.transportCloseFailed(
          generation: generation,
          failureKind: FailureKind.asyncValue,
        ),
        cause: error,
      );
      return;
    }
    final request = metadata is _CloseRequest ? metadata : null;
    log('transport', 'disconnecting', {
      'code': request?.code,
      'reason': request?.reason,
      'closeReason': closeReason.wireName,
    }, Level.FINE);
    try {
      final Future<void> closing;
      if (request?.code != null) {
        closing = localConnection.sink.close(
          request!.code,
          request.reason ?? '',
        );
      } else if (closeReason == CloseReason.heartbeatTimeout) {
        closing = localConnection.sink.close(
          RealtimeConstants.webSocketCloseNormal,
          'heartbeat timeout',
        );
      } else {
        closing = localConnection.sink.close();
      }
      await closing.timeout(connectionCloseTimeout);
      final closeEvent = _closeEvent(localConnection);
      await _reportTransportTerminated(
        SocketModelEvent.transportClosed(
          generation: generation,
          failureKind: FailureKind.requested,
        ),
        metadata: closeEvent,
      );
    } on TimeoutException catch (error) {
      await _reportTransportTerminated(
        SocketModelEvent.transportClosed(
          generation: generation,
          failureKind: FailureKind.timeout,
        ),
        cause: error,
      );
    } catch (error) {
      await _reportTransportTerminated(
        SocketModelEvent.transportCloseFailed(
          generation: generation,
          failureKind: FailureKind.asyncValue,
        ),
        cause: error,
      );
    }
  }

  RealtimeCloseEvent? _closeEvent(WebSocketChannel localConnection) {
    final statusCode = localConnection.closeCode;
    return statusCode == null
        ? null
        : RealtimeCloseEvent(
            code: statusCode,
            reason: localConnection.closeReason,
          );
  }

  Future<void> _disposeGeneration(int generation) async {
    _connectionsByGeneration.remove(generation);
    final subscription = _subscriptionsByGeneration.remove(generation);
    if (identical(subscription, _connectionSubscription)) {
      _connectionSubscription = null;
    }
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<void> _disposeAllTransports() async {
    _connectionsByGeneration.clear();
    final subscriptions = _subscriptionsByGeneration.values.toList();
    _subscriptionsByGeneration.clear();
    _connectionSubscription = null;
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  void _armReconnectTimer(int timerId, int delayOrdinal) {
    _kernelReconnectTimer?.cancel();
    _kernelReconnectTimerId = timerId;
    _kernelReconnectTimer = Timer(reconnectAfter(delayOrdinal), () {
      if (_kernelReconnectTimerId != timerId) return;
      _kernelReconnectTimer = null;
      _kernelReconnectTimerId = null;
      unawaited(
        _socketDriver.dispatch(
          SocketModelEvent.reconnectTimerFired(timerId: timerId),
        ),
      );
    });
  }

  void _cancelReconnectTimer(int timerId) {
    if (_kernelReconnectTimerId != timerId) return;
    _kernelReconnectTimer?.cancel();
    _kernelReconnectTimer = null;
    _kernelReconnectTimerId = null;
    reconnectTimer.cancel();
  }

  void _armHeartbeatTimer(int timerId) {
    heartbeatTimer?.cancel();
    _kernelHeartbeatTimerId = timerId;
    heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_kernelHeartbeatTimerId != timerId) return;
      unawaited(
        _socketDriver.dispatch(
          SocketModelEvent.heartbeatTimerFired(timerId: timerId),
        ),
      );
    });
  }

  void _cancelHeartbeatTimer(int timerId) {
    if (_kernelHeartbeatTimerId != timerId) return;
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
    _kernelHeartbeatTimerId = null;
  }

  void _armDisconnectTimer(int timerId) {
    _pendingDisconnectTimer?.cancel();
    _kernelDisconnectTimerId = timerId;
    _pendingDisconnectTimer = Timer(disconnectOnEmptyChannelsAfter, () {
      if (_kernelDisconnectTimerId != timerId) return;
      _pendingDisconnectTimer = null;
      _kernelDisconnectTimerId = null;
      unawaited(
        _socketDriver.dispatch(
          SocketModelEvent.disconnectTimerFired(timerId: timerId),
        ),
      );
    });
  }

  void _cancelDisconnectTimer(int timerId) {
    if (_kernelDisconnectTimerId != timerId) return;
    _pendingDisconnectTimer?.cancel();
    _pendingDisconnectTimer = null;
    _kernelDisconnectTimerId = null;
  }

  void _sendKernelHeartbeat(int generation, int heartbeatRef) {
    final localConnection = _connectionsByGeneration[generation];
    if (localConnection == null) {
      scheduleMicrotask(() {
        unawaited(
          _socketDriver.dispatch(
            SocketModelEvent.heartbeatSendFailed(
              generation: generation,
              ref: heartbeatRef,
              failureKind: FailureKind.send,
            ),
            cause: StateError('Generation $generation has no transport'),
          ),
        );
      });
      return;
    }
    pendingHeartbeatRef = heartbeatRef.toString();
    _kernelPendingHeartbeatGeneration = generation;
    _kernelPendingHeartbeatRef = heartbeatRef;
    final message = Message(
      topic: 'phoenix',
      event: ChannelEvent.heartbeat,
      payload: const {},
      ref: pendingHeartbeatRef!,
    );
    try {
      localConnection.sink.add(encode(message.toJson()));
    } catch (error) {
      scheduleMicrotask(() {
        unawaited(
          _socketDriver.dispatch(
            SocketModelEvent.heartbeatSendFailed(
              generation: generation,
              ref: heartbeatRef,
              failureKind: FailureKind.syncValue,
            ),
            cause: error,
          ),
        );
      });
    }
  }

  void _emitHeartbeat(HeartbeatStatus status) {
    if (status != HeartbeatStatus.sent) {
      pendingHeartbeatRef = null;
      _kernelPendingHeartbeatGeneration = null;
      _kernelPendingHeartbeatRef = null;
    }
    _heartbeatController.add(switch (status) {
      HeartbeatStatus.sent => RealtimeHeartbeatStatus.sent,
      HeartbeatStatus.ok => RealtimeHeartbeatStatus.ok,
      HeartbeatStatus.error => RealtimeHeartbeatStatus.error,
      HeartbeatStatus.timeout => RealtimeHeartbeatStatus.timeout,
      HeartbeatStatus.none => throw StateError('Invalid heartbeat status'),
    });
  }

  /// Sets the JWT access token used for channel subscription authorization and
  /// Realtime RLS.
  ///
  /// `token` A JWT strings.
  Future<void> setAccessToken(String? token) async {
    final tokenToSend =
        token ?? (await customAccessToken?.call()) ?? accessToken;

    if (accessToken == tokenToSend) {
      return;
    }

    accessToken = tokenToSend;

    for (final channel in channels) {
      if (tokenToSend != null) {
        channel.updateJoinPayload({
          'access_token': tokenToSend,
          'version': RealtimeConstants.defaultHeaders['X-Client-Info'],
        });
      }
      if (channel.joinedOnce && channel.isJoined) {
        channel.push(ChannelEvent.accessToken, {'access_token': tokenToSend});
      }
    }
  }

  /// Unsubscribe from joined or joining channels with the specified topic.
  @internal
  void leaveOpenTopic(String topic, {RealtimeChannel? except}) {
    final dupChannel = channels.firstWhereOrNull(
      (c) =>
          !identical(c, except) &&
          c.topic == topic &&
          (c.isJoined || c.isJoining),
    );
    if (dupChannel != null) {
      log('transport', 'leaving duplicate topic "$topic"');
      unawaited(dupChannel.unsubscribe());
    }
  }

  void _onConnectionOpen() {
    log('transport', 'connected to $endpointUrl');
    log('transport', 'connected', null, Level.FINE);
    unawaited(_resolveAccessTokenAndFlush());

    try {
      for (final channel in channels) {
        if (channel.isErrored) {
          channel.rejoin();
        }
      }
    } catch (error) {
      log('transport', 'error while rejoining channels', error, Level.WARNING);
    }

    _statusController.add(
      const RealtimeConnectionStatusChange(RealtimeConnectionStatus.open),
    );
  }

  /// communication has been closed
  void _onConnectionClose([RealtimeCloseEvent? event]) {
    log('transport', 'close', event, Level.FINE);
    _statusController.add(
      RealtimeConnectionStatusChange(RealtimeConnectionStatus.closed, event),
    );
  }

  void _onConnectionError(Object error) {
    log('transport', error.toString());
    _triggerChanError(error);
    _statusController.addError(error);
  }

  void _triggerChanError([dynamic error]) {
    for (final channel in channels) {
      channel.trigger(ChannelEvent.error.eventName(), error);
    }
  }

  String _appendParameters(String url, Map<String, String> queryParameters) {
    if (queryParameters.keys.isEmpty) {
      return url;
    }

    var uri = Uri.parse(url);
    uri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        ...queryParameters,
      },
    );

    return uri.toString();
  }

  void _flushSendBuffer() {
    if (isConnected && sendBuffer.isNotEmpty) {
      for (final callback in sendBuffer) {
        callback();
      }
      sendBuffer = [];
    }
  }

  /// Resolves the access token before flushing the send buffer so that
  /// buffered channel join payloads carry the correct token.
  ///
  /// When [RealtimeChannel.subscribe] runs before an asynchronous access token
  /// has resolved (common when [customAccessToken] reads from async storage),
  /// the buffered join payload has no `access_token`. That buffered message
  /// captured the stale payload, so once auth has settled the join payloads are
  /// patched with the resolved token, the stale buffered joins are dropped, and
  /// the join is re-sent for any channel still joining.
  Future<void> _resolveAccessTokenAndFlush() async {
    try {
      if (customAccessToken != null) {
        await setAccessToken(null);
        if (accessToken != null) {
          for (final channel in channels) {
            channel.updateJoinPayload({'access_token': accessToken!});
          }
          sendBuffer = [];
          for (final channel in channels) {
            if (channel.isJoining) {
              channel.forceRejoin();
            }
          }
        }
      }
    } catch (error) {
      log('transport', 'error resolving access token on connect', error);
    } finally {
      _flushSendBuffer();
    }
  }

  @internal
  Future<void> sendHeartbeat() async {
    if (!isConnected) return;
    final timerId = _kernelHeartbeatTimerId;
    if (timerId != null) {
      await _socketDriver.dispatch(
        SocketModelEvent.heartbeatTimerFired(timerId: timerId),
      );
      return;
    }

    // Compatibility for the historically mutable connectionState and
    // pendingHeartbeatRef test seams. Production connections always own a
    // kernel heartbeat timer and use the branch above.
    if (pendingHeartbeatRef != null) {
      pendingHeartbeatRef = null;
      _heartbeatController.add(RealtimeHeartbeatStatus.timeout);
      unawaited(
        connection?.sink.close(
          RealtimeConstants.webSocketCloseNormal,
          'heartbeat timeout',
        ),
      );
      return;
    }
    pendingHeartbeatRef = makeRef();
    push(
      Message(
        topic: 'phoenix',
        event: ChannelEvent.heartbeat,
        payload: {},
        ref: pendingHeartbeatRef!,
      ),
    );
    _heartbeatController.add(RealtimeHeartbeatStatus.sent);
    await setAccessToken(null);
  }
}
