library isolatengine;

import 'dart:async';
import 'dart:isolate';

import 'package:npc/npc.dart';

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
  void emit(String method, {dynamic param});

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
  Future<void> receiveContinuously();
}

class _Isolatengine extends NPC implements Isolatengine {
  _Isolatengine(
    this._receivePort, [
    this._sendPort,
  ]) : super(null) {
    if (_sendPort == null) {
      return;
    }
    _sendPort?.send(_receivePort.sendPort);
  }

  @override
  Future<void> send(Message message) async {
    if (_sendPort == null) {
      await _sendPortStremController.stream.first;
    }
    _sendPort?.send(message);
    return super.send(message);
  }

  SendPort? _sendPort;
  final ReceivePort _receivePort;
  late final _sendPortStremController = StreamController.broadcast();

  @override
  Future<void> receiveContinuously() async {
    await for (final data in _receivePort) {
      if (data is Message) {
        await receive(data);
        continue;
      }
      if (data is SendPort) {
        _sendPort = data;
        _sendPortStremController.add(_sendPort);
        continue;
      }
    }
  }
}
