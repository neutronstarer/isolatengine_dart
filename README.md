## Usage

```dart
void _entry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  final engine = Isolatengine(receivePort, sendPort);
  engine['ping'] = (param, cancelable, notify) async{
    return 'pong';
  };
  await engine.receive();
}

void startEngine(){
    final receivePort = ReceivePort();
    this.engine = Isolatengine(receivePort);
    Isolate.spawn(_entry, receivePort.sendPort);
    engine.receive();
}
```
### And now you can call emit or deliver function.

```dart
final r = await this.engine.deliver('ping');
```

### For more usage, please run the example app.