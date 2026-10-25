import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_libusb/dart_libusb.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'protocol_transport.dart';

/// Android Auto byte transport over libusb.
///
/// USB operations run in a worker isolate. The input stream provides arbitrary
/// byte chunks to ProtocolConnection, which handles protocol frame boundaries.
///
/// Requires a libusb-1.0 native library at [libraryPath] or on the platform's
/// native library search path. On Windows, libusb uses its installed Windows
/// backend; the accessory interface must have a driver/backend that libusb can
/// claim. This code deliberately does not select the optional UsbDk backend.
class LibusbAoaProtocolTransport implements ProtocolTransport {
  LibusbAoaProtocolTransport._() {
    _eventSubscription = _events.listen(_handleWorkerEvent);
  }

  final ReceivePort _events = ReceivePort();
  final StreamController<List<int>> _inputController =
      StreamController<List<int>>();

  final Completer<void> _connected = Completer<void>();
  final Completer<void> _done = Completer<void>();
  final Map<int, Completer<void>> _pendingWrites = <int, Completer<void>>{};

  late final StreamSubscription<dynamic> _eventSubscription;
  Isolate? _worker;
  SendPort? _commandPort;

  int _nextWriteId = 0;
  bool _closeRequested = false;
  bool _finished = false;

  @override
  Stream<List<int>> get input => _inputController.stream;

  bool get isClosed => _closeRequested || _finished;

  /// Initializes libusb, enters AOA mode if needed, and opens its bulk
  /// endpoints. Completes only after the USB transport is ready.
  static Future<LibusbAoaProtocolTransport> connect({
    String? libraryPath,
    Duration startupTimeout = const Duration(seconds: 35),
    String manufacturer = 'FlutterAuto',
    String model = 'FlutterAuto Headunit',
    String description = 'Flutter Android Auto Head Unit',
    String version = '1.0',
    String uri = 'https://developer.android.com/training/cars',
    String serialNumber = 'flutter-auto-001',
  }) async {
    final transport = LibusbAoaProtocolTransport._();

    try {
      transport._worker = await Isolate.spawn<Map<String, Object?>>(
        _libusbWorkerMain,
        <String, Object?>{
          'eventPort': transport._events.sendPort,
          'libraryPath': libraryPath ?? _defaultLibraryPath(),
          'manufacturer': manufacturer,
          'model': model,
          'description': description,
          'version': version,
          'uri': uri,
          'serialNumber': serialNumber,
        },
        onError: transport._events.sendPort,
      );

      await transport._connected.future.timeout(startupTimeout);
      return transport;
    } catch (_) {
      await transport.close();
      rethrow;
    }
  }

  static String _defaultLibraryPath() {
    final String filename;

    if (Platform.isWindows) {
      filename = 'libusb-1.0.dll';
    } else if (Platform.isMacOS) {
      filename = 'libusb-1.0.dylib';
    } else if (Platform.isLinux) {
      filename = 'libusb-1.0.so.0';
    } else {
      throw UnsupportedError(
        'libusb AOA transport supports Windows, macOS and Linux.',
      );
    }

    final String localPath = p.join(
      File(Platform.resolvedExecutable).parent.path,
      filename,
    );

    if (File(localPath).existsSync()) {
      return localPath;
    }

    // Fall back to the platform dynamic-library search path.
    return filename;
  }

  void _handleWorkerEvent(dynamic message) {
    if (_finished) return;

    if (message is! Map) {
      final error = StateError('USB worker failed: $message');

      if (!_connected.isCompleted) {
        _connected.completeError(error);
      } else if (!_inputController.isClosed) {
        _inputController.addError(error);
      }
      return;
    }

    switch (message['type']) {
      case 'commandsReady':
        _commandPort = message['port'] as SendPort;
        break;

      case 'connected':
        if (!_connected.isCompleted) {
          _connected.complete();
        }
        break;

      case 'data':
        if (!_closeRequested && !_inputController.isClosed) {
          _inputController.add(message['bytes'] as Uint8List);
        }
        break;

      case 'writeResult':
        final int id = message['id'] as int;
        final Completer<void>? completer = _pendingWrites.remove(id);

        if (completer == null || completer.isCompleted) break;

        final Object? error = message['error'];
        if (error == null) {
          completer.complete();
        } else {
          completer.completeError(StateError(error.toString()));
        }
        break;

      case 'startupError':
        if (!_connected.isCompleted) {
          _connected.completeError(StateError(message['error'].toString()));
        }
        break;

      case 'transportError':
        final error = StateError(message['error'].toString());
        if (!_connected.isCompleted) {
          _connected.completeError(error);
        } else if (!_inputController.isClosed) {
          _inputController.addError(error);
        }
        break;

      case 'closed':
        _finishMain();
        break;
    }
  }

  @override
  Future<void> write(Uint8List bytes) {
    if (isClosed) {
      return Future<void>.error(
        StateError('Cannot write to a closed USB transport.'),
      );
    }

    final SendPort? commands = _commandPort;
    if (commands == null) {
      return Future<void>.error(StateError('The USB worker is not ready.'));
    }

    final int id = ++_nextWriteId;
    final completer = Completer<void>();
    _pendingWrites[id] = completer;

    // Send a copy so the caller can safely reuse its buffer afterwards.
    commands.send(<String, Object?>{
      'command': 'write',
      'id': id,
      'bytes': Uint8List.fromList(bytes),
    });

    return completer.future;
  }

  @override
  Future<void> close() => _requestClose('close');

  @override
  Future<void> abort() => _requestClose('abort');

  Future<void> _requestClose(String command) {
    if (_finished) return Future<void>.value();

    if (!_closeRequested) {
      _closeRequested = true;
      final SendPort? commands = _commandPort;
      if (commands != null) {
        commands.send(<String, Object?>{'command': command});
      }
    }

    return _done.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        // Do not leave a worker running indefinitely after a broken device.
        _worker?.kill(priority: Isolate.immediate);
        _finishMain();
      },
    );
  }

  void _finishMain() {
    if (_finished) return;
    _finished = true;

    for (final completer in _pendingWrites.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('USB transport closed before write completed.'),
        );
      }
    }
    _pendingWrites.clear();

    if (!_inputController.isClosed) {
      unawaited(_inputController.close());
    }

    if (!_connected.isCompleted) {
      _connected.completeError(
        StateError('USB transport closed before connecting.'),
      );
    }

    if (!_done.isCompleted) {
      _done.complete();
    }

    unawaited(_eventSubscription.cancel());
    _events.close();
  }
}

// ---------------------------------------------------------------------------
// Everything below this point runs in the USB worker isolate.
// ---------------------------------------------------------------------------

class _UsbWorkerState {
  Libusb? api;
  ffi.Pointer<libusb_context> context = ffi.nullptr.cast<libusb_context>();
  ffi.Pointer<libusb_device_handle>? handle;

  int? interfaceNumber;
  int endpointIn = 0;
  int endpointOut = 0;

  bool initialized = false;
  bool interfaceClaimed = false;
  bool closeRequested = false;
  final List<String> diagnostics = <String>[];
}

Future<void> _libusbWorkerMain(Map<String, Object?> arguments) async {
  final SendPort events = arguments['eventPort'] as SendPort;
  final ReceivePort commands = ReceivePort();
  final state = _UsbWorkerState();
  bool connected = false;

  try {
    final String libraryPath = arguments['libraryPath'] as String;
    state.api = Libusb(ffi.DynamicLibrary.open(libraryPath));

    final api = state.api!;
    final contextOut = calloc<ffi.Pointer<libusb_context>>();
    try {
      final int result = api.libusb_init(contextOut);
      if (result < 0) {
        throw StateError('libusb_init failed: ${_usbError(state, result)}');
      }
      state.context = contextOut.value;
      state.initialized = true;
    } finally {
      calloc.free(contextOut);
    }

    if (Platform.isWindows) {
      // Keep libusb's normal Windows backend. Do not request UsbDk.
      // This enables verbose diagnostics; it does not install or bind a driver.
      api.libusb_set_debug(state.context, 4);
      state.diagnostics.add(
        'Using libusb default Windows backend; UsbDk is not requested.',
      );
    }

    state.handle = await _openOrStartAoa(state, arguments);

    try {
      _configureBulkEndpoints(state);
    } catch (error) {
      throw StateError(
        '$error\nUSB diagnostics:\n${_formatDiagnostics(state)}',
      );
    }

    commands.listen((dynamic message) {
      if (message is! Map) return;

      switch (message['command']) {
        case 'write':
          final int id = message['id'] as int;
          try {
            if (state.closeRequested) {
              throw StateError('USB transport is closing.');
            }
            _writeBulk(state, message['bytes'] as Uint8List);
            events.send(<String, Object?>{'type': 'writeResult', 'id': id});
          } catch (error) {
            events.send(<String, Object?>{
              'type': 'writeResult',
              'id': id,
              'error': error.toString(),
            });
          }
          break;

        case 'close':
        case 'abort':
          state.closeRequested = true;
          break;
      }
    });

    events.send(<String, Object?>{
      'type': 'commandsReady',
      'port': commands.sendPort,
    });

    connected = true;
    events.send(<String, Object?>{'type': 'connected'});
    await _readBulkLoop(state, events);
  } catch (error, stackTrace) {
    events.send(<String, Object?>{
      'type': connected ? 'transportError' : 'startupError',
      'error': '$error\n$stackTrace',
    });
  } finally {
    state.closeRequested = true;
    commands.close();
    _cleanupUsb(state);
    events.send(<String, Object?>{'type': 'closed'});
  }
}

String _formatDiagnostics(_UsbWorkerState state) {
  return state.diagnostics.isEmpty
      ? 'No additional USB diagnostics recorded.'
      : state.diagnostics.join('\n');
}

const Set<int> _aoaProductIds = <int>{
  0x2D00, // Accessory
  0x2D01, // Accessory + ADB
  0x2D04, // Accessory + audio
  0x2D05, // Accessory + audio + ADB
};

bool _isAoaDevice(libusb_device_descriptor descriptor) {
  return descriptor.idVendor == 0x18D1 &&
      _aoaProductIds.contains(descriptor.idProduct);
}

Future<ffi.Pointer<libusb_device_handle>> _openOrStartAoa(
  _UsbWorkerState state,
  Map<String, Object?> arguments,
) async {
  // The device may already be in accessory mode.
  final existing = _findAoaDevice(state, recordFailures: true);
  if (existing != null) {
    state.diagnostics.add('Found a device already in AOA mode.');
    return existing;
  }

  // Otherwise, perform the Android Open Accessory handshake.
  final bool switched = _startAoaOnFirstCapableDevice(state, arguments);
  if (!switched) {
    throw StateError(
      'Could not start Android Open Accessory mode.\n'
      'USB diagnostics:\n${_formatDiagnostics(state)}',
    );
  }

  // Request 53 causes the phone to disconnect and re-enumerate.
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final handle = _findAoaDevice(state);
    if (handle != null) return handle;
  }

  throw StateError(
    'The phone accepted the AOA start request, but did not '
    're-enumerate in AOA mode within 15 seconds.\n'
    'USB diagnostics:\n${_formatDiagnostics(state)}',
  );
}

ffi.Pointer<libusb_device_handle>? _findAoaDevice(
  _UsbWorkerState state, {
  bool recordFailures = false,
}) {
  final api = state.api!;
  final descriptorOut = calloc<libusb_device_descriptor>();

  try {
    return _withDeviceList<ffi.Pointer<libusb_device_handle>?>(
      state,
      (devices, count) {
        for (int i = 0; i < count; i++) {
          final device = devices[i];
          final int result = api.libusb_get_device_descriptor(
            device,
            descriptorOut,
          );
          if (result < 0 || !_isAoaDevice(descriptorOut.ref)) continue;

          final descriptor = descriptorOut.ref;
          final String id = _formatUsbId(
            descriptor.idVendor,
            descriptor.idProduct,
          );

          if (recordFailures) {
            state.diagnostics.add('Found existing AOA device $id.');
          }

          final handle = _tryOpenDevice(
            state,
            device,
            diagnosticLabel: recordFailures ? 'existing AOA device $id' : null,
          );
          if (handle != null) {
            if (recordFailures) {
              state.diagnostics.add('Opened existing AOA device $id.');
            }
            return handle;
          }
        }
        return null;
      },
    );
  } finally {
    calloc.free(descriptorOut);
  }
}

String _formatUsbId(int vendorId, int productId) {
  final vendor = vendorId.toRadixString(16).padLeft(4, '0');
  final product = productId.toRadixString(16).padLeft(4, '0');
  return '$vendor:$product';
}

bool _startAoaOnFirstCapableDevice(
  _UsbWorkerState state,
  Map<String, Object?> arguments,
) {
  final api = state.api!;
  final descriptorOut = calloc<libusb_device_descriptor>();

  final strings = <String>[
    arguments['manufacturer'] as String,
    arguments['model'] as String,
    arguments['description'] as String,
    arguments['version'] as String,
    arguments['uri'] as String,
    arguments['serialNumber'] as String,
  ];

  try {
    return _withDeviceList<bool>(state, (devices, count) {
      for (int i = 0; i < count; i++) {
        final device = devices[i];
        final int descriptorResult = api.libusb_get_device_descriptor(
          device,
          descriptorOut,
        );
        if (descriptorResult < 0) {
          state.diagnostics.add(
            'Could not read USB device descriptor: '
            '${_usbError(state, descriptorResult)}.',
          );
          continue;
        }

        final descriptor = descriptorOut.ref;
        final String id = _formatUsbId(
          descriptor.idVendor,
          descriptor.idProduct,
        );

        // Ignore devices already checked by the AOA lookup and USB hubs.
        if (_isAoaDevice(descriptor) || descriptor.bDeviceClass == 9) {
          continue;
        }

        state.diagnostics.add(
          'Probing USB device $id, class '
          '0x${descriptor.bDeviceClass.toRadixString(16).padLeft(2, '0')}.',
        );

        final handle = _tryOpenDevice(
          state,
          device,
          diagnosticLabel: id,
        );
        if (handle == null) continue;

        try {
          // AOA request 51: GET_PROTOCOL.
          final protocolBuffer = calloc<ffi.Uint8>(2);
          try {
            final int protocolResult = api.libusb_control_transfer(
              handle,
              0xC0, // Device-to-host | vendor | device
              51, // ACCESSORY_GET_PROTOCOL
              0,
              0,
              protocolBuffer.cast<ffi.UnsignedChar>(),
              2,
              1000,
            );

            if (protocolResult != 2) {
              state.diagnostics.add(
                'GET_PROTOCOL failed for $id: result=$protocolResult'
                '${protocolResult < 0 ? ', ${_usbError(state, protocolResult)}' : ''}.',
              );
              continue;
            }

            final int protocolVersion =
                protocolBuffer[0] | (protocolBuffer[1] << 8);
            state.diagnostics.add(
              'GET_PROTOCOL succeeded for $id: version=$protocolVersion.',
            );
            if (protocolVersion < 1) {
              state.diagnostics.add(
                'Unsupported AOA protocol version $protocolVersion for $id.',
              );
              continue;
            }
          } finally {
            calloc.free(protocolBuffer);
          }

          // AOA request 52: SEND_STRING, one transfer for each string.
          for (int index = 0; index < strings.length; index++) {
            _sendAoaString(state, handle, index, strings[index]);
          }

          // AOA request 53: START_ACCESSORY.
          final int startResult = api.libusb_control_transfer(
            handle,
            0x40, // Host-to-device | vendor | device
            53, // ACCESSORY_START
            0,
            0,
            ffi.nullptr.cast<ffi.UnsignedChar>(),
            0,
            1000,
          );
          if (startResult < 0) {
            throw StateError(
              'AOA ACCESSORY_START failed for $id: '
              '${_usbError(state, startResult)}',
            );
          }

          state.diagnostics.add(
            'ACCESSORY_START succeeded for $id; waiting for re-enumeration.',
          );
          return true;
        } catch (error, stackTrace) {
          state.diagnostics.add(
            'AOA handshake failed for $id: $error\n$stackTrace',
          );
        } finally {
          // Each opened candidate is closed exactly once.
          api.libusb_close(handle);
        }
      }
      return false;
    });
  } finally {
    calloc.free(descriptorOut);
  }
}

void _sendAoaString(
  _UsbWorkerState state,
  ffi.Pointer<libusb_device_handle> handle,
  int index,
  String value,
) {
  final api = state.api!;
  final encoded = utf8.encode(value);

  // AOA strings may be at most 256 bytes including the NUL terminator.
  if (encoded.length + 1 > 256) {
    throw ArgumentError('AOA identification string exceeds 255 UTF-8 bytes.');
  }

  final buffer = calloc<ffi.Uint8>(encoded.length + 1);
  try {
    buffer.asTypedList(encoded.length + 1)
      ..setRange(0, encoded.length, encoded)
      ..[encoded.length] = 0;

    final int result = api.libusb_control_transfer(
      handle,
      0x40, // Host-to-device | vendor | device
      52, // ACCESSORY_SEND_STRING
      0,
      index, // 0 manufacturer, 1 model, ..., 5 serial
      buffer.cast<ffi.UnsignedChar>(),
      encoded.length + 1,
      1000,
    );

    if (result != encoded.length + 1) {
      throw StateError(
        'AOA SEND_STRING[$index] failed: '
        '${result < 0 ? _usbError(state, result) : 'short transfer'}',
      );
    }
  } finally {
    calloc.free(buffer);
  }
}

ffi.Pointer<libusb_device_handle>? _tryOpenDevice(
  _UsbWorkerState state,
  ffi.Pointer<libusb_device> device, {
  String? diagnosticLabel,
}) {
  final api = state.api!;
  final handleOut = calloc<ffi.Pointer<libusb_device_handle>>();
  try {
    final int result = api.libusb_open(device, handleOut);
    if (result < 0) {
      if (diagnosticLabel != null) {
        state.diagnostics.add(
          'libusb_open($diagnosticLabel) failed: '
          '${_usbError(state, result)} ($result).',
        );
      }
      return null;
    }

    if (handleOut.value == ffi.nullptr) {
      if (diagnosticLabel != null) {
        state.diagnostics.add(
          'libusb_open($diagnosticLabel) succeeded but returned a null handle.',
        );
      }
      return null;
    }
    return handleOut.value;
  } finally {
    calloc.free(handleOut);
  }
}

T _withDeviceList<T>(
  _UsbWorkerState state,
  T Function(ffi.Pointer<ffi.Pointer<libusb_device>>, int count) callback,
) {
  final api = state.api!;
  final listOut = calloc<ffi.Pointer<ffi.Pointer<libusb_device>>>();
  try {
    final int count = api.libusb_get_device_list(state.context, listOut);
    if (count < 0) {
      throw StateError(
        'Could not enumerate USB devices: ${_usbError(state, count)}',
      );
    }

    final devices = listOut.value;
    try {
      return callback(devices, count);
    } finally {
      if (devices != ffi.nullptr) {
        api.libusb_free_device_list(devices, 1);
      }
    }
  } finally {
    calloc.free(listOut);
  }
}

void _configureBulkEndpoints(_UsbWorkerState state) {
  final api = state.api!;
  final handle = state.handle!;
  final device = api.libusb_get_device(handle);
  final configOut = calloc<ffi.Pointer<libusb_config_descriptor>>();

  try {
    int result = api.libusb_get_active_config_descriptor(device, configOut);
    if (result < 0) {
      configOut.value = ffi.nullptr.cast<libusb_config_descriptor>();
      result = api.libusb_get_config_descriptor(device, 0, configOut);
    }
    if (result < 0) {
      throw StateError(
        'Could not read USB configuration: ${_usbError(state, result)}',
      );
    }

    final config = configOut.value.ref;
    final int configurationValue = config.bConfigurationValue;
    int? selectedInterface;
    int? selectedAlternate;
    int? selectedIn;
    int? selectedOut;

    for (int i = 0; i < config.bNumInterfaces; i++) {
      final usbInterface = config.interface[i];
      for (int a = 0; a < usbInterface.num_altsetting; a++) {
        final alternate = usbInterface.altsetting[a];
        int? inputEndpoint;
        int? outputEndpoint;

        for (int e = 0; e < alternate.bNumEndpoints; e++) {
          final endpoint = alternate.endpoint[e];
          // Transfer type 2 is bulk.
          if ((endpoint.bmAttributes & 0x03) != 0x02) continue;
          final int address = endpoint.bEndpointAddress;
          if ((address & 0x80) != 0) {
            inputEndpoint = address;
          } else {
            outputEndpoint = address;
          }
        }

        if (inputEndpoint != null && outputEndpoint != null) {
          selectedInterface = alternate.bInterfaceNumber;
          selectedAlternate = alternate.bAlternateSetting;
          selectedIn = inputEndpoint;
          selectedOut = outputEndpoint;
          break;
        }
      }
      if (selectedInterface != null) break;
    }

    if (selectedInterface == null ||
        selectedAlternate == null ||
        selectedIn == null ||
        selectedOut == null) {
      throw StateError(
        'No USB interface with both bulk IN and bulk OUT endpoints found.',
      );
    }

    final currentConfiguration = calloc<ffi.Int>();
    try {
      result = api.libusb_get_configuration(handle, currentConfiguration);
      if (result < 0) {
        throw StateError(
          'Could not get USB configuration: ${_usbError(state, result)}',
        );
      }
      if (currentConfiguration.value != configurationValue) {
        result = api.libusb_set_configuration(handle, configurationValue);
        if (result < 0) {
          throw StateError(
            'Could not select USB configuration: ${_usbError(state, result)}',
          );
        }
      }
    } finally {
      calloc.free(currentConfiguration);
    }

    // The call is useful on platforms that support kernel-driver detach.
    // Windows driver/interface availability still depends on the bound driver.
    api.libusb_set_auto_detach_kernel_driver(handle, 1);
    result = api.libusb_claim_interface(handle, selectedInterface);
    if (result < 0) {
      throw StateError(
        'Could not claim USB interface $selectedInterface: '
        '${_usbError(state, result)}. On Windows, check that this specific '
        'AOA interface is exposed through a libusb-compatible driver/backend.',
      );
    }

    state
      ..interfaceNumber = selectedInterface
      ..interfaceClaimed = true
      ..endpointIn = selectedIn
      ..endpointOut = selectedOut;

    if (selectedAlternate != 0) {
      result = api.libusb_set_interface_alt_setting(
        handle,
        selectedInterface,
        selectedAlternate,
      );
      if (result < 0) {
        throw StateError(
          'Could not select alternate USB setting: ${_usbError(state, result)}',
        );
      }
    }
  } finally {
    final config = configOut.value;
    if (config != ffi.nullptr) {
      api.libusb_free_config_descriptor(config);
    }
    calloc.free(configOut);
  }
}

Future<void> _readBulkLoop(_UsbWorkerState state, SendPort events) async {
  const int readBufferSize = 16 * 1024;
  final api = state.api!;
  final handle = state.handle!;
  final buffer = calloc<ffi.Uint8>(readBufferSize);
  final actualLength = calloc<ffi.Int>();

  try {
    while (!state.closeRequested) {
      actualLength.value = 0;
      final int result = api.libusb_bulk_transfer(
        handle,
        state.endpointIn,
        buffer.cast<ffi.UnsignedChar>(),
        readBufferSize,
        actualLength,
        100,
      );
      final int length = actualLength.value;

      if (length > 0) {
        events.send(<String, Object?>{
          'type': 'data',
          'bytes': Uint8List.fromList(buffer.asTypedList(length)),
        });
      }

      // LIBUSB_ERROR_TIMEOUT is -7.
      if (result < 0 && result != -7) {
        throw StateError('USB bulk read failed: ${_usbError(state, result)}');
      }
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    calloc.free(buffer);
    calloc.free(actualLength);
  }
}

void _writeBulk(_UsbWorkerState state, Uint8List bytes) {
  if (bytes.isEmpty) return;
  final api = state.api!;
  final handle = state.handle!;
  final buffer = calloc<ffi.Uint8>(bytes.length);
  final actualLength = calloc<ffi.Int>();

  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    int offset = 0;

    while (offset < bytes.length) {
      actualLength.value = 0;
      final int result = api.libusb_bulk_transfer(
        handle,
        state.endpointOut,
        // ignore: deprecated_member_use
        buffer.elementAt(offset).cast<ffi.UnsignedChar>(),
        bytes.length - offset,
        actualLength,
        5000,
      );
      final int written = actualLength.value;
      if (written > 0) offset += written;

      if (result < 0 && result != -7) {
        throw StateError('USB bulk write failed: ${_usbError(state, result)}');
      }
      if (written == 0) {
        throw StateError('USB bulk write made no progress.');
      }
    }
  } finally {
    calloc.free(buffer);
    calloc.free(actualLength);
  }
}

String _usbError(_UsbWorkerState state, int code) {
  final pointer = state.api!.libusb_error_name(code);
  if (pointer == ffi.nullptr) return 'libusb error $code';
  return pointer.cast<Utf8>().toDartString();
}

void _cleanupUsb(_UsbWorkerState state) {
  final api = state.api;
  if (api == null) return;

  final handle = state.handle;
  if (handle != null && handle != ffi.nullptr) {
    if (state.interfaceClaimed && state.interfaceNumber != null) {
      api.libusb_release_interface(handle, state.interfaceNumber!);
    }
    api.libusb_close(handle);
    state.handle = null;
  }

  if (state.initialized) {
    api.libusb_exit(state.context);
    state.initialized = false;
  }
}
