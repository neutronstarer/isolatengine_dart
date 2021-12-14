library isolatengine;

import 'dart:async';
import 'dart:isolate';

import 'package:cancelable/cancelable.dart';

/// Handle message.
/// [param] Attached param of method.
/// The content of [param] can be:
///   - [Null]
///   - [bool]
///   - [int]
///   - [double]
///   - [String]
///   - [List] or [Map] (whose elements are any of these)
///   - [TransferableTypedData]
///   - [SendPort]
///   - [Capability]
/// [cancelable] Cancelletion context.
/// [notify] Notify when the operation status changed. Always used to notify progress.
typedef Handle = Future<dynamic> Function(
  dynamic param,
  Cancelable cancelable,
  Notify notify,
);

/// Notify content
/// [param] content of notification
typedef Notify = Function(dynamic param);

/// Isolatengine
abstract class Isolatengine {
  /// [receivePort] ReceivePort of isolate.
  /// [sendPort] In main isolate, this arg always be null. In new isolate should be correct value.
  factory Isolatengine(ReceivePort receivePort, [SendPort? sendPort]) {
    return _Isolatengine(receivePort, sendPort);
  }

  /// Register handle by [method], handle will be triggered when [method] be called by paired isolatengine.
  /// [method] Method name of handle.
  /// [handle] Handle for method.
  operator []=(String method, Handle? handle);

  /// like []=
  /// [method] Method name of handle.
  /// [handle] Handle for method.
  void on(String method, Handle handle);

  /// Emit a message with [method] to paired isolatengine with ignoring reply.
  /// [method] Method witch is registered by paired isolatengine.
  /// [param] Param of this method.
  /// The content of [param] could be:
  ///   - [Null]
  ///   - [bool]
  ///   - [int]
  ///   - [double]
  ///   - [String]
  ///   - [List] or [Map] (whose elements are any of these)
  ///   - [TransferableTypedData]
  ///   - [SendPort]
  ///   - [Capability]
  ///
  Future<void> emit(String method, {dynamic param});

  /// Deliver a message with [method] to paired isolatengine with reply.
  /// [method] Method witch is registered by paired isolatengine.
  /// [param] Param of this method.
  ///   /// The content of [param] could be:
  ///   - [Null]
  ///   - [bool]
  ///   - [int]
  ///   - [double]
  ///   - [String]
  ///   - [List] or [Map] (whose elements are any of these)
  ///   - [TransferableTypedData]
  ///   - [SendPort]
  ///   - [Capability]
  /// [timeout] Timeout.
  /// [cancelable] Cancelletion context.
  /// [onNotify] Notification callback.
  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  });

  /// Continuously receive message.
  Future<void> receive();

  ///[data] Log.
  Function(String name, dynamic data)? log;
}

enum _Typ {
  emit,
  deliver,
  ack,
  notify,
  cancel,
  syn,
  // ignore: unused_field
  fin,
}

class _Message {
  _Typ? typ;
  int? id;
  String? method;
  dynamic param;
  dynamic error;
  _Message({
    this.typ,
    this.id,
    this.method,
    this.param,
    this.error,
  });
  @override
  String toString() {
    return {
      'typ': typ,
      'id': id,
      'method': method,
      'param': param,
      'error': error,
    }.toString();
  }
}

class _Isolatengine implements Isolatengine {
  _Isolatengine(
    this._receivePort, [
    this._sendPort,
  ]) {
    if (_sendPort == null) {
      return;
    }
    _send(_Message(typ: _Typ.syn, param: _receivePort.sendPort));
  }

  @override
  operator []=(String method, Handle? handle) {
    if (handle == null) {
      _handles.remove(method);
      return;
    }
    _handles[method] = handle;
  }

  @override
  void on(String method, Handle handle) {
    this[method] = handle;
  }

  @override
  Future<void> emit(
    String method, {
    dynamic param,
  }) async {
    final message = _Message(typ: _Typ.emit, method: method, param: param);
    await _send(message);
  }

  @override
  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  }) async {
    final id = _id++;
    final message =
        _Message(typ: _Typ.deliver, method: method, param: param, id: id);
    StreamSubscription? sub;
    Timer? after;
    if (onNotify != null) {
      _notifies[id] = onNotify;
    }
    final completer = Completer<dynamic>();
    // ignore: prefer_function_declarations_over_variables
    final onReply = (dynamic param, dynamic error) {
      if (completer.isCompleted) {
        return false;
      }
      if (error == null) {
        completer.complete(param);
      } else {
        completer.completeError(error);
      }
      after?.cancel();
      sub?.cancel();
      _replies.remove(id);
      _notifies.remove(id);
      return true;
    };

    if (cancelable != null) {
      sub = cancelable.whenCancel(() async {
        if (onReply(null, 'cancelled')) {
          final message = _Message(typ: _Typ.cancel, id: id);
          await _send(message);
        }
      });
    }
    if (timeout != null && timeout.inMicroseconds > 0) {
      after = Timer.periodic(timeout, (timer) async {
        if (onReply(null, 'timedout')) {
          final message = _Message(typ: _Typ.cancel, id: id);
          await _send(message);
        }
      });
    }
    _replies[id] = onReply;
    await _send(message);
    return await completer.future;
  }

  @override
  Future<void> receive() async {
    await for (final data in _receivePort) {
      _didReceive(data);
    }
  }

  Function(String name, dynamic data)? log;

  _didReceive(dynamic data) async {
    if (log != null) {
      log?.call('receive', data);
    }
    final message = data;
    final typ = message.typ;
    final method = message.method;
    final id = message.id;
    final param = message.param;
    switch (typ) {
      case _Typ.emit:
        final handle = _handles[method];
        if (handle == null) {
          break;
        }
        handle(param, Cancelable(), (_) {});
        break;
      case _Typ.deliver:
        final handle = _handles[method];
        if (handle == null) {
          break;
        }
        if (id == null) {
          break;
        }
        final cancelable = Cancelable();
        _cancels[id] = () {
          cancelable.cancel();
        };
        try {
          await _send(_Message(
              typ: _Typ.ack,
              id: id,
              param: await handle(param, cancelable, (dynamic param) async {
                await _send(_Message(typ: _Typ.notify, id: id, param: param));
              })));
          _cancels.remove(id);
        } catch (e) {
          await _send(_Message(typ: _Typ.ack, id: id, error: e));
          _cancels.remove(id);
        }
        break;
      case _Typ.ack:
        final reply = _replies[id];
        if (reply != null) {
          reply(param, null);
        }
        break;
      case _Typ.notify:
        final notify = _notifies[id];
        notify?.call(param);
        break;
      case _Typ.cancel:
        final cancel = _cancels[id];
        if (cancel != null) {
          cancel();
        }
        break;
      case _Typ.syn:
        _sendPort = param;
        _sendPortStremController.add(_sendPort);
        break;
      default:
        break;
    }
  }

  Future<void> _send(dynamic data) async {
    if (_sendPort == null) {
      await _sendPortStremController.stream.first;
    }
    if (log != null) {
      log?.call('send', data);
    }
    _sendPort?.send(data);
  }

  SendPort? _sendPort;
  final ReceivePort _receivePort;
  late final _sendPortStremController = StreamController.broadcast();
  late int _id = 0;
  late final _handles = <String, Handle>{};
  late final _replies = <int, Function(dynamic param, dynamic error)>{};
  late final _notifies = <int, Notify>{};
  late final _cancels = <int, Function()>{};
}
