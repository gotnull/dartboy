class DynamicLibrary {
  static DynamicLibrary? open(String path) => null;
  T lookup<T>(String symbol) =>
      throw UnsupportedError('FFI not supported on web');
}

class Pointer<T> {
  List<int> asTypedList(int length) => <int>[];
}

class Uint8 {}

class Int32 {}

class Uint32 {}

class Void {}

typedef NativeFunction<T> = T;

// Stub types that match expected signatures
typedef InitAudioNative = int Function(int, int, int);
typedef StreamAudioNative = void Function(Pointer<Uint8>, int);
typedef TerminateAudioNative = void Function();
typedef GetQueuedAudioSizeNative = int Function();
typedef ClearQueuedAudioNative = void Function();

class _Malloc {
  Pointer<T> allocate<T>(int count) => Pointer<T>();
  void free(Pointer pointer) {}
}

final malloc = _Malloc();
