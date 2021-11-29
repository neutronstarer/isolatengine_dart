import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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
    final sub = cancelable?.whenCancel(() {
      ctrl.close();
    });
    ctrl.stream.take(3).listen((event) {
      notify?.call(event);
    });
    ctrl.addStream(stream, cancelOnError: true);
    await ctrl.done;
    sub?.cancel();
    return 'pong';
  };
  try {
    await engine.receive();
  } catch (_) {}
}

void main() {
  test('adds one to input values', () async {
    final receivePort = ReceivePort();
    final engine = Isolatengine(receivePort);
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final cancelable = Cancelable();
        final replication = await engine.deliver('ping', cancelable: cancelable,
            notify: (param) async {
          debugPrint(param);
        });
        debugPrint(replication);
      } catch (e) {
        debugPrint(e.toString());
      }
    });
    await Isolate.spawn(_entry, receivePort.sendPort);
    try {
      await engine.receive();
    } catch (_) {}
  });
}
