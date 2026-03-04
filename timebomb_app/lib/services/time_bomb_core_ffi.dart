import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show MethodChannel;

final class RustBuffer extends Struct {
  external Pointer<Uint8> ptr;

  @IntPtr()
  external int len;

  @IntPtr()
  external int cap;
}

typedef EventCallbackNative = Void Function(Uint8, Pointer<Utf8>);
typedef EventCallbackDart = void Function(int, Pointer<Utf8>);

typedef TbInitSessionNative = Int8 Function(Pointer<Utf8>);
typedef TbInitSessionDart = int Function(Pointer<Utf8>);

typedef TbRegisterEventCallbackNative =
    Int8 Function(Pointer<NativeFunction<EventCallbackNative>>);
typedef TbRegisterEventCallbackDart =
    int Function(Pointer<NativeFunction<EventCallbackNative>>);

typedef TbProcessIncomingMessageNative = Int8 Function(Pointer<Uint8>, IntPtr);
typedef TbProcessIncomingMessageDart = int Function(Pointer<Uint8>, int);

typedef TbBuildMessageNative = RustBuffer Function(Uint8, Uint8, Pointer<Utf8>);
typedef TbBuildMessageDart = RustBuffer Function(int, int, Pointer<Utf8>);

typedef TbGetSessionStateNative = Pointer<Utf8> Function();
typedef TbGetSessionStateDart = Pointer<Utf8> Function();

typedef TbResetSessionNative = Int8 Function();
typedef TbResetSessionDart = int Function();

typedef TbLastErrorMessageNative = Pointer<Utf8> Function();
typedef TbLastErrorMessageDart = Pointer<Utf8> Function();

typedef TbFreeRustBufferNative = Void Function(RustBuffer);
typedef TbFreeRustBufferDart = void Function(RustBuffer);

typedef TbFreeCStringNative = Void Function(Pointer<Utf8>);
typedef TbFreeCStringDart = void Function(Pointer<Utf8>);

class TimeBombCoreFfi {
  TimeBombCoreFfi._();

  static final TimeBombCoreFfi instance = TimeBombCoreFfi._();

  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;
  static const MethodChannel _iosChannel = MethodChannel(
    'timebomb_app/time_bomb_core',
  );

  DynamicLibrary? _library;
  late final TbInitSessionDart _tbInitSession;
  late final TbRegisterEventCallbackDart _tbRegisterEventCallback;
  late final TbProcessIncomingMessageDart _tbProcessIncomingMessage;
  late final TbBuildMessageDart _tbBuildMessage;
  late final TbGetSessionStateDart _tbGetSessionState;
  late final TbResetSessionDart _tbResetSession;
  late final TbLastErrorMessageDart _tbLastErrorMessage;
  late final TbFreeRustBufferDart _tbFreeRustBuffer;
  late final TbFreeCStringDart _tbFreeCString;

  bool _isInitialized = false;
  String? _initError;
  bool _iosHandlerRegistered = false;

  static final Pointer<NativeFunction<EventCallbackNative>> _callbackPtr =
      Pointer.fromFunction<EventCallbackNative>(_onRustEvent);

  void _bind(DynamicLibrary library) {
    final initName = Platform.isIOS ? 'tb_ios_init_session' : 'tb_init_session';
    final registerName =
        Platform.isIOS
            ? 'tb_ios_register_event_callback'
            : 'tb_register_event_callback';
    final processName =
        Platform.isIOS
            ? 'tb_ios_process_incoming_message'
            : 'tb_process_incoming_message';
    final buildName =
        Platform.isIOS ? 'tb_ios_build_message' : 'tb_build_message';
    final getStateName =
        Platform.isIOS ? 'tb_ios_get_session_state' : 'tb_get_session_state';
    final resetName =
        Platform.isIOS ? 'tb_ios_reset_session' : 'tb_reset_session';
    final lastErrorName =
        Platform.isIOS ? 'tb_ios_last_error_message' : 'tb_last_error_message';
    final freeBufferName =
        Platform.isIOS ? 'tb_ios_free_rust_buffer' : 'tb_free_rust_buffer';
    final freeCStringName =
        Platform.isIOS ? 'tb_ios_free_c_string' : 'tb_free_c_string';

    final tbInitSession = library
        .lookupFunction<TbInitSessionNative, TbInitSessionDart>(initName);
    final tbRegisterEventCallback = library.lookupFunction<
      TbRegisterEventCallbackNative,
      TbRegisterEventCallbackDart
    >(registerName);
    final tbProcessIncomingMessage = library.lookupFunction<
      TbProcessIncomingMessageNative,
      TbProcessIncomingMessageDart
    >(processName);
    final tbBuildMessage = library
        .lookupFunction<TbBuildMessageNative, TbBuildMessageDart>(buildName);
    final tbGetSessionState = library
        .lookupFunction<TbGetSessionStateNative, TbGetSessionStateDart>(
          getStateName,
        );
    final tbResetSession = library
        .lookupFunction<TbResetSessionNative, TbResetSessionDart>(resetName);
    final tbLastErrorMessage = library
        .lookupFunction<TbLastErrorMessageNative, TbLastErrorMessageDart>(
          lastErrorName,
        );
    final tbFreeRustBuffer = library
        .lookupFunction<TbFreeRustBufferNative, TbFreeRustBufferDart>(
          freeBufferName,
        );
    final tbFreeCString = library
        .lookupFunction<TbFreeCStringNative, TbFreeCStringDart>(
          freeCStringName,
        );

    _tbInitSession = tbInitSession;
    _tbRegisterEventCallback = tbRegisterEventCallback;
    _tbProcessIncomingMessage = tbProcessIncomingMessage;
    _tbBuildMessage = tbBuildMessage;
    _tbGetSessionState = tbGetSessionState;
    _tbResetSession = tbResetSession;
    _tbLastErrorMessage = tbLastErrorMessage;
    _tbFreeRustBuffer = tbFreeRustBuffer;
    _tbFreeCString = tbFreeCString;
  }

  Future<bool> initSession(String userId) async {
    if (Platform.isIOS) {
      _registerIosHandlerIfNeeded();
      try {
        final ok =
            await _iosChannel.invokeMethod<bool>('initSession', {
              'userId': userId,
            }) ??
            false;
        _isInitialized = ok;
        if (!ok) {
          _initError = 'iOS initSession returned false';
        } else {
          _initError = null;
        }
        return ok;
      } catch (error) {
        _initError = error.toString();
        _isInitialized = false;
        return false;
      }
    }

    if (!_isInitialized) {
      try {
        final library = _library ??= _openLibrary();
        _bind(library);
        _isInitialized = true;
        _initError = null;
      } catch (error) {
        _initError = error.toString();
        return false;
      }
    }

    final userPtr = userId.toNativeUtf8();
    try {
      final initOk = _tbInitSession(userPtr) != 0;
      if (!initOk) {
        return false;
      }

      final callbackOk = _tbRegisterEventCallback(_callbackPtr) != 0;
      return callbackOk;
    } finally {
      malloc.free(userPtr);
    }
  }

  void _registerIosHandlerIfNeeded() {
    if (_iosHandlerRegistered) {
      return;
    }

    _iosChannel.setMethodCallHandler((call) async {
      if (call.method != 'onRustEvent') {
        return;
      }

      final args = call.arguments;
      if (args is! Map) {
        return;
      }

      final eventType = args['eventType'];
      final payload = args['payload'];

      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(payload?.toString() ?? '{}');
        data =
            decoded is Map<String, dynamic>
                ? decoded
                : <String, dynamic>{'raw': decoded};
      } catch (_) {
        data = <String, dynamic>{'raw': payload?.toString() ?? ''};
      }

      _eventsController.add(<String, dynamic>{
        'eventType':
            eventType is int
                ? eventType
                : int.tryParse('${eventType ?? 0}') ?? 0,
        'data': data,
      });
    });

    _iosHandlerRegistered = true;
  }

  Future<Uint8List?> buildMessage({
    required int instruction,
    required int transport,
    required Map<String, dynamic> payload,
  }) async {
    if (Platform.isIOS) {
      if (!_isInitialized) {
        return null;
      }
      try {
        final typedData = await _iosChannel
            .invokeMethod<Uint8List>('buildMessage', {
              'instruction': instruction,
              'transport': transport,
              'payloadJson': jsonEncode(payload),
            });
        return typedData;
      } catch (_) {
        return null;
      }
    }

    if (!_isInitialized) {
      return null;
    }

    final payloadPtr = jsonEncode(payload).toNativeUtf8();
    try {
      final rustBuffer = _tbBuildMessage(instruction, transport, payloadPtr);
      try {
        if (rustBuffer.ptr == nullptr || rustBuffer.len == 0) {
          return null;
        }
        return Uint8List.fromList(rustBuffer.ptr.asTypedList(rustBuffer.len));
      } finally {
        _tbFreeRustBuffer(rustBuffer);
      }
    } finally {
      malloc.free(payloadPtr);
    }
  }

  Future<bool> processIncoming(Uint8List bytes) async {
    if (Platform.isIOS) {
      if (!_isInitialized || bytes.isEmpty) {
        return false;
      }
      try {
        final ok =
            await _iosChannel.invokeMethod<bool>('processIncoming', {
              'bytes': bytes,
            }) ??
            false;
        return ok;
      } catch (_) {
        return false;
      }
    }

    if (!_isInitialized || bytes.isEmpty) {
      return false;
    }
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return _tbProcessIncomingMessage(ptr, bytes.length) != 0;
    } finally {
      malloc.free(ptr);
    }
  }

  Future<String?> getSessionState() async {
    if (Platform.isIOS) {
      if (!_isInitialized) {
        return null;
      }
      try {
        return await _iosChannel.invokeMethod<String>('getSessionState');
      } catch (_) {
        return null;
      }
    }

    if (!_isInitialized) {
      return null;
    }

    final ptr = _tbGetSessionState();
    if (ptr == nullptr) {
      return null;
    }
    try {
      return ptr.toDartString();
    } finally {
      _tbFreeCString(ptr);
    }
  }

  Future<bool> resetSession() async {
    if (Platform.isIOS) {
      if (!_isInitialized) {
        return false;
      }
      try {
        return await _iosChannel.invokeMethod<bool>('resetSession') ?? false;
      } catch (_) {
        return false;
      }
    }

    if (!_isInitialized) {
      return false;
    }

    return _tbResetSession() != 0;
  }

  Future<String?> lastError() async {
    if (Platform.isIOS) {
      if (!_isInitialized) {
        return _initError;
      }
      try {
        return await _iosChannel.invokeMethod<String>('lastError');
      } catch (error) {
        return error.toString();
      }
    }

    if (!_isInitialized) {
      return _initError;
    }

    final ptr = _tbLastErrorMessage();
    if (ptr == nullptr) {
      return null;
    }
    try {
      return ptr.toDartString();
    } finally {
      _tbFreeCString(ptr);
    }
  }

  static void _onRustEvent(int eventType, Pointer<Utf8> payloadPtr) {
    final payload = payloadPtr == nullptr ? '{}' : payloadPtr.toDartString();
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      data =
          decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{'raw': decoded};
    } catch (_) {
      data = <String, dynamic>{'raw': payload};
    }

    TimeBombCoreFfi.instance._eventsController.add(<String, dynamic>{
      'eventType': eventType,
      'data': data,
    });
  }

  DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libtime_bomb_core.so');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libtime_bomb_core.dylib');
    }
    throw UnsupportedError('Plateforme non supportée pour time_bomb_core');
  }
}
