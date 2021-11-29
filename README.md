## Usage

```dart
void _entry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  final engine = Isolatengine(receivePort, sendPort);
  // register method
  await engine.receive();
}

void main(){
    final receivePort = ReceivePort();
    final engine = Isolatengine(receivePort);
    // register method
    await Isolate.spawn(_entry, receivePort.sendPort);
    await engine.receive();
}
```
### And now you can call emit or deliver function.

```dart

engine.emit("your_method", param: null);

final res = await engine.deliver("your_method", param: null);

```