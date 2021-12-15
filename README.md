# Isolate procedure call engine.
## Usage

```dart
void _entry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  final engine = Isolatengine(receivePort, sendPort);
  engine['ping'] = (param, cancelable, notify) async{
    return 'pong';
  };
  await engine.receiveContinuously();
}

void startEngine(){
    final receivePort = ReceivePort();
    this.engine = Isolatengine(receivePort);
    Isolate.spawn(_entry, receivePort.sendPort);
    engine.receiveContinuously();
}
```
### And now you can call emit or deliver function.

```dart
final r = await engine.deliver('ping');
```

### Try the example for more usage.