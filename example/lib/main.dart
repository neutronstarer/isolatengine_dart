import 'dart:async';
import 'dart:developer';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:isolatengine/isolatengine.dart';

void main() {
  runApp(const MyApp());
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

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Isolatengine Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _text = '';
  String _timeout = '5';
  Cancelable? _cancelable;
  final Isolatengine _engine = () {
    final receivePort = ReceivePort();
    final v = Isolatengine(receivePort);
    v.log = (name, data) {
      log(data.toString(), name: name);
    };
    Isolate.spawn(_entry, receivePort.sendPort);
    v.receive();
    return v;
  }();

  void _click() async {
    if (_cancelable != null) {
      _cancelable?.cancel();
      setState(() {
        _cancelable = null;
      });
      return;
    }
    setState(() {
      _cancelable = Cancelable();
      _text = "start download";
    });
    try {
      final r = await _engine.deliver('download',
          param: "/path",
          cancelable: _cancelable,
          timeout: Duration(seconds: int.parse(_timeout)),
          onNotify: (param) async {
        if (param is String) {
          setState(() {
            _text = param;
          });
        }
      });
      setState(() {
        _text = r.toString();
      });
    } catch (e) {
      setState(() {
        _text = e.toString();
      });
    }
    setState(() {
      _cancelable = null;
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                color: Colors.lightBlue.shade100,
                child: TextField(
                  controller: TextEditingController(text: _timeout),
                  decoration: const InputDecoration(labelText: 'Timeout:'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _timeout = value;
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                color: Colors.lightBlue.shade100,
                child: Text(
                  _text,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _click,
        tooltip: _cancelable == null ? 'download' : 'cancel',
        child: _cancelable == null
            ? const Icon(Icons.download)
            : const Icon(Icons.cancel),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
