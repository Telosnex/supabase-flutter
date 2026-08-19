import 'dart:async';

import 'package:meta/meta.dart';
import 'package:supabase_realtime/src/constants.dart';
import 'package:supabase_realtime/src/kernel/generated/model_schema.dart';
import 'package:supabase_realtime/src/kernel/push_representation.dart';
import 'package:supabase_realtime/src/kernel/realtime_push_driver.dart';
import 'package:supabase_realtime/src/message.dart';
import 'package:supabase_realtime/src/types.dart';
import 'package:supabase_realtime/supabase_realtime.dart';

@internal
typedef Callback = void Function(dynamic response);

/// One request/reply exchange with a model-owned ref and timeout obligation.
@internal
class Push {
  Push(
    this._channel,
    this._event, [
    this.payload = const {},
    this._timeout = RealtimeConstants.defaultTimeout,
  ]) {
    _driver = RealtimePushDriver(
      executeEffect: _executeEffect,
      traceSink: _channel.socket.emitFormalTrace,
      validateRepresentation: _pushRepresentationMatches,
    );
  }

  final RealtimeChannel _channel;
  final ChannelEvent _event;
  late final RealtimePushDriver _driver;

  Timer? _timeoutTimer;
  int? _timeoutTimerId;
  String _ref = '';
  Map<String, dynamic>? _receivedResponse;
  final List<Hook> _receiveHooks = [];
  String? _refEvent;

  late Map<String, dynamic> payload;
  Duration _timeout;

  bool get sent => _driver.sent;
  String get ref => _ref;
  Duration get timeout => _timeout;

  void resend(Duration newTimeout) {
    _timeout = newTimeout;
    _receivedResponse = null;
    unawaited(_driver.dispatch(PushModelEvent.pushResendRequested()));
  }

  void send() {
    if (_hasReceived('timeout')) return;
    unawaited(_driver.dispatch(PushModelEvent.pushSendRequested()));
  }

  void updatePayload(Map<String, dynamic> newPayload) {
    payload = {...payload, ...newPayload};
  }

  Push receive(String status, Callback callback) {
    if (_hasReceived(status)) {
      callback(_receivedResponse?['response']);
    }
    _receiveHooks.add(Hook(status, callback));
    return this;
  }

  void startTimeout() {
    unawaited(_driver.dispatch(PushModelEvent.pushPrepareRequested()));
  }

  void trigger(String status, Map<String, dynamic> response) {
    if (status == 'timeout') {
      final timerId = _timeoutTimerId;
      if (timerId != null) {
        unawaited(
          _driver.dispatch(
            PushModelEvent.pushTimeoutFired(timerId: timerId),
            metadata: response,
          ),
        );
      }
      return;
    }
    if (_refEvent != null) {
      _channel.trigger(
        _refEvent!,
        {'status': status, 'response': response},
      );
    }
  }

  void destroy() {
    unawaited(_driver.dispatch(PushModelEvent.pushDestroyRequested()));
  }

  void _executeEffect(PushModelEffect effect, Object? metadata) {
    switch (effect.kind) {
      case PushModelEffectKind.bindPushReply:
        _bindReply(effect.ref!);
      case PushModelEffectKind.unbindPushReply:
        _cancelRefEvent();
      case PushModelEffectKind.armPushTimeoutTimer:
        _armTimeout(effect.timerId!);
      case PushModelEffectKind.cancelPushTimeoutTimer:
        _cancelTimeout(effect.timerId!);
      case PushModelEffectKind.sendPush:
        _sendFrame();
      case PushModelEffectKind.deliverPushResult:
        _deliver(effect.replyStatus!, metadata);
    }
  }

  bool _pushRepresentationMatches(PushModelState state) =>
      pushRepresentationMatches(
        state,
        PushShellSnapshot(
          timeoutTimerLive: _timeoutTimer?.isActive ?? false,
          timeoutTimerId: _timeoutTimerId,
          replyBound: _refEvent != null,
          ref: _ref,
        ),
      );

  void _bindReply(int modelRef) {
    _cancelRefEvent();
    _ref = _channel.socket.makeRef();
    _refEvent = _channel.replyEventName(_ref);
    _channel.onEvents(_refEvent!, ChannelFilter(), (dynamic value, [_]) {
      if (value is! Map) return;
      final status = switch (value['status']) {
        'ok' => ReplyStatus.ok,
        'error' => ReplyStatus.error,
        _ => null,
      };
      if (status == null) return;
      unawaited(
        _driver.dispatch(
          PushModelEvent.pushReplyReceived(
            ref: modelRef,
            replyStatus: status,
          ),
          metadata: value['response'],
        ),
      );
    });
  }

  void _armTimeout(int timerId) {
    _timeoutTimer?.cancel();
    _timeoutTimerId = timerId;
    _timeoutTimer = Timer(timeout, () {
      if (_timeoutTimerId != timerId) return;
      _timeoutTimer = null;
      _timeoutTimerId = null;
      unawaited(
        _driver.dispatch(
          PushModelEvent.pushTimeoutFired(timerId: timerId),
          metadata: const <String, dynamic>{},
        ),
      );
    });
  }

  void _sendFrame() {
    _channel.socket.push(
      Message(
        topic: _channel.topic,
        event: _event,
        payload: payload,
        ref: ref,
        joinRef: _channel.joinRef,
      ),
    );
  }

  void _deliver(ReplyStatus status, Object? response) {
    _receivedResponse = {
      'status': status.wireName,
      'response': response,
    };
    _matchReceive(status.wireName, response);
  }

  void _cancelRefEvent() {
    final event = _refEvent;
    if (event == null) return;
    _channel.off(event, {});
    _refEvent = null;
  }

  void _cancelTimeout(int timerId) {
    if (_timeoutTimerId != timerId) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeoutTimerId = null;
  }

  void _matchReceive(String status, dynamic response) {
    for (final hook in _receiveHooks.where((hook) => hook.status == status)) {
      hook.callback(response);
    }
  }

  bool _hasReceived(String status) => _receivedResponse?['status'] == status;
}

@internal
class Hook {
  const Hook(this.status, this.callback);

  final String status;
  final Callback callback;
}
