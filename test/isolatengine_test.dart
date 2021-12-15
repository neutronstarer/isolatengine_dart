import 'dart:async';
import 'dart:isolate';

import 'package:isolatengine/isolatengine.dart';
import 'package:test/test.dart';

void main() {
  test('isolatengine', () async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_entry, receivePort.sendPort);
    final engine = Isolatengine(receivePort);
    _config(engine);
    _run(engine);
    await engine.receive();
  });
}

void _run(Isolatengine engine) async {
  final r0 = await engine.deliver('ping');
  print(r0);
  final r1 = await engine.deliver(
    'download',
    param: '/path',
    onNotify: (param) async {
      print(param);
    },
  );
  print(r1);
}

void _entry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  final engine = Isolatengine(receivePort, sendPort);
  _config(engine);
  await engine.receive();
}

void _config(Isolatengine engine) {
  engine.on('ping', (param, cancelable, notify) async => 'pong');
  engine.on('download', (param, cancelable, notify) async {
    return _download(param, cancelable: cancelable, notify: notify);
  });
}

Future<String> _download(
  String param, {
  Notify? notify,
  Cancelable? cancelable,
}) async {
  StreamSubscription? sub;
  Timer? timer;
  final completer = Completer<String>();
  var i = 0;
  timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    i++;
    if (i < 10) {
      notify?.call('progress=$i/10');
      return;
    }
    if (completer.isCompleted) {
      return;
    }
    timer.cancel();
    await sub?.cancel();
    completer.complete('Did download to $param');
  });
  cancelable?.whenCancel(() {
    if (completer.isCompleted) {
      return;
    }
    timer?.cancel();
    completer.completeError('cancelled');
  });
  final r = await completer.future;
  return r;
}
