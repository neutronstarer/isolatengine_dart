import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isolatengine/isolatengine.dart';
import 'package:cancelable/cancelable.dart';

void _entry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  final engine = Isolatengine(receivePort, sendPort);
  engine['ping'] = (param, {cancelable, notify}) async {
    debugPrint('ping');
    final stream = Stream.fromIterable(['1/3', '2/3', '3/3']);
    final ctrl = StreamController();
    cancelable?.whenCancel(() {
      ctrl.close();
    });
    ctrl.stream.take(3).listen((event) {
      notify?.call(event);
    });
    ctrl.addStream(stream, cancelOnError: true);
    await ctrl.done;
    return 'pong';
  };
  await engine.receive();
}

void main() {
  test('adds one to input values', () async {
    final receivePort = ReceivePort();
    final engine = Isolatengine(receivePort);
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final cancelable = Cancelable();
        final replication = await engine.deliver('ping', cancelable: cancelable, notify: (param) {
          debugPrint(param);
        });
        debugPrint(replication);
      } catch (_) {}
    });
    await Isolate.spawn(_entry, receivePort.sendPort);
    await engine.receive();
  });
}
