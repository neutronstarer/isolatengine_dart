library isolatengine;

import 'dart:async';
import 'dart:isolate';

import 'package:craba/craba.dart';

/// [Isolatengine]
abstract class Isolatengine {
  /// [receivePort] ReceivePort of isolate.
  /// [sendPort] In main isolate, this arg always be null. In new isolate should be correct value.
  factory Isolatengine(ReceivePort receivePort, [SendPort? sendPort]) {
    return _Isolatengine(receivePort, sendPort);
  }

  /// Register handle by [method], handle will be called when [method] be called by paired isolatengine.
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
  void Function(String name, dynamic data)? log;
}

class _Isolatengine implements Isolatengine {
  _Isolatengine(
    this._receivePort, [
    this._sendPort,
  ]) {
    if (_sendPort == null) {
      return;
    }
    _sendPort?.send(_receivePort.sendPort);
  }

  late final _craba = () {
    final v = Craba((message) async {
      if (_sendPort == null) {
        await _sendPortStremController.stream.first;
      }
      _sendPort?.send(message);
    });
    return v;
  }();

  @override
  void on(String method, Handle handle) {
    _craba.on(method, handle);
  }

  @override
  Future<void> emit(
    String method, {
    dynamic param,
  }) async {
    await _craba.emit(method, param: param);
  }

  @override
  Future<dynamic> deliver(
    String method, {
    dynamic param,
    Duration? timeout,
    Cancelable? cancelable,
    Notify? onNotify,
  }) async {
    return await _craba.deliver(method,
        param: param,
        timeout: timeout,
        cancelable: cancelable,
        onNotify: onNotify);
  }

  @override
  Future<void> receive() async {
    await for (final data in _receivePort) {
      if (data is Message) {
        _craba.receive(data);
        continue;
      }
      if (data is SendPort) {
        _sendPort = data;
        _sendPortStremController.add(_sendPort);
        continue;
      }
    }
  }

  Function(String name, dynamic data)? log;

  SendPort? _sendPort;
  final ReceivePort _receivePort;
  late final _sendPortStremController = StreamController.broadcast();
}
