library isolatengine;

import 'dart:async';
import 'dart:isolate';

import 'package:cancelable/cancelable.dart';

abstract class Isolatengine {
  factory Isolatengine(
    ReceivePort receivePort, [
    SendPort? sendPort,
  ]) {
    return _Isolatengine(receivePort, sendPort);
  }

  operator []=(
    String method,
    Future<dynamic> Function(
      dynamic param, {
      Cancelable? cancelable,
      Function(dynamic param)? notify,
    })?
        handler,
  );

  Future<dynamic> emit(
    String method, {
    dynamic param,
  });

  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Cancelable? cancelable,
    Duration? timeout,
    Function(dynamic param)? notify,
  });

  Future receive();
}

enum _Type {
  syn,
  emit,
  deliver,
  ack,
  notify,
  cancel,
}

enum _Status {
  completed,
  cancelled,
  timedout,
}

class _Message {
  _Type? type;
  String? method;
  int? id;
  dynamic error;
  dynamic param;
  _Message({
    this.type,
    this.method,
    this.id,
    this.param,
    this.error,
  });

  _Message.fromJson(Map<String, dynamic> json) {
    type = json['type'];
    method = json['method'];
    id = json['id'];
    error = json['error'];
    param = json['param'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['type'] = type;
    data['method'] = method;
    data['id'] = id;
    data['error'] = error;
    data['param'] = param;
    return data;
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
    _send(_Message(type: _Type.syn, param: _receivePort.sendPort).toJson());
  }

  @override
  operator []=(
      String method,
      Future<dynamic> Function(
    dynamic param, {
    Cancelable? cancelable,
    Function(dynamic param)? notify,
  })?
          handler) {
    if (handler == null) {
      _handlers.remove(method);
      return;
    }
    _handlers[method] = handler;
  }

  @override
  emit(
    String method, {
    dynamic param,
  }) async {
    final message = _Message(type: _Type.emit, method: method, param: param, id: _id++);
    await _send(message.toJson());
  }

  @override
  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Cancelable? cancelable,
    Duration? timeout,
    Function(dynamic param)? notify,
  }) async {
    final id = _id++;
    final message = _Message(type: _Type.deliver, method: method, param: param, id: id);
    StreamSubscription? sub;
    if (cancelable != null) {
      sub = cancelable.whenCancel(() async {
        final completion = _completions[id];
        if (completion != null) {
          completion(_Status.cancelled);
          final message = _Message(type: _Type.cancel, method: null, param: null, id: id);
          await _send(message.toJson());
        }
      });
    }
    Timer? after;
    if (timeout != null) {
      after = Timer.periodic(timeout, (timer) async {
        final completion = _completions[id];
        if (completion != null) {
          completion(_Status.timedout);
        }
      });
    }
    if (notify != null) {
      _notifications[id] = notify;
    }
    final completer = Completer<dynamic>();
    _completions[id] = (_Status status, {dynamic param}) {
      switch (status) {
        case _Status.cancelled:
          completer.completeError(Exception('cancelled'));
          break;
        case _Status.timedout:
          completer.completeError(Exception('timedout'));
          break;
        default:
          completer.complete(param);
          break;
      }
      after?.cancel();
      sub?.cancel();
      _completions.remove(id);
      _notifications.remove(id);
    };
    await _send(message.toJson());
    return await completer.future;
  }

  @override
  receive() async {
    await for (final data in _receivePort) {
      _didReceive(data);
    }
  }

  _didReceive(dynamic data) {
    final message = _Message.fromJson(data);
    final type = message.type;
    final method = message.method;
    final id = message.id;
    final param = message.param;
    switch (type) {
      case _Type.emit:
        final handler = _handlers[method];
        if (handler == null) {
          break;
        }
        handler(param);
        break;
      case _Type.deliver:
        final handler = _handlers[method];
        if (handler == null) {
          break;
        }
        final cancelable = Cancelable();
        _cancellations[id!] = cancelable;
        handler(param, cancelable: cancelable, notify: (dynamic param) {
          final replication = _Message(type: _Type.notify, id: id, param: param);
          _send(replication.toJson());
        }).then((value) {
          _cancellations.remove(id);
          final replication = _Message(type: _Type.ack, id: id, param: value);
          _send(replication.toJson());
        }).catchError((e) {
          _cancellations.remove(id);
          final replication = _Message(type: _Type.ack, id: id, error: e);
          _send(replication.toJson());
        });
        break;
      case _Type.ack:
        final completion = _completions[id];
        if (completion != null) {
          completion(_Status.completed, param: param);
        }
        break;
      case _Type.cancel:
        final cancelable = _cancellations[id];
        if (cancelable != null) {
          cancelable.cancel();
          _cancellations.remove(id);
        }
        break;
      case _Type.notify:
        final notify = _notifications[id];
        notify?.call(param);
        break;
      case _Type.syn:
        _sendPort = param;
        _sendPortStremController.add(_sendPort);
        break;
      default:
        break;
    }
  }

  Future _send(dynamic data) async {
    if (_sendPort == null) {
      await _sendPortStremController.stream.first;
    }
    _sendPort?.send(data);
  }

  SendPort? _sendPort;
  final ReceivePort _receivePort;
  late final _sendPortStremController = StreamController.broadcast();
  late int _id = 0;
  late final _handlers = <String, Future<dynamic> Function(dynamic param, {Cancelable? cancelable, Function(dynamic param)? notify})>{};
  late final _completions = <int, Function(_Status status, {dynamic param})>{};
  late final _notifications = <int, Function(dynamic param)>{};
  late final _cancellations = <int, Cancelable>{};
}
