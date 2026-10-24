import 'dart:async';

import '../../generated/oaa/control/ChannelDescriptorData.pb.dart';
import '../message_router.dart';
import '../protocol_message.dart';
import '../protocol_message_sender.dart';
import 'package:logging/logging.dart';

import 'channel_service.dart';

class ChannelServiceRegistry {
  ChannelServiceRegistry({
    required this.router,
    required this.sender,
  });

  final MessageRouter router;
  final ProtocolMessageSender sender;
  final Logger _log = Logger('ChannelServiceRegistry');

  final Map<int, ChannelService> _services = {};

  StreamSubscription<ProtocolMessage>? _subscription;
  Future<void> _dispatchQueue = Future<void>.value();
  bool _disposed = false;

  List<ChannelService> get services =>
      List.unmodifiable(_services.values);

  void register(ChannelService service) {
    if (_disposed) {
      throw StateError('Registry is disposed.');
    }

    if (_services.containsKey(service.channelId)) {
      throw StateError(
        'Channel ${service.channelId} is already registered.',
      );
    }

    service.attachSender(sender);
    _services[service.channelId] = service;

    _log.info(
      'Registered ${service.runtimeType} on channel ${service.channelId}.',
    );
  }

  ChannelService? serviceForChannel(int channelId) =>
      _services[channelId];

  List<ChannelDescriptor> buildDescriptors() {
    final descriptors = <ChannelDescriptor>[];

    for (final service in _services.values) {
      if (service.channelId == 0) continue;

      final descriptor = service.buildDescriptor(service.channelId);
      if (descriptor == null) continue;

      descriptor.channelId = service.channelId;
      descriptors.add(descriptor);
    }

    return List.unmodifiable(descriptors);
  }

  void start() {
    if (_disposed) {
      throw StateError('Registry is disposed.');
    }
    if (_subscription != null) return;

    _subscription = router.messages.listen(
      _route,
      onError: (Object error, StackTrace stackTrace) {
        _log.severe('Inbound message routing failed.', error, stackTrace);
      },
    );
  }

  void _route(ProtocolMessage message) {
    final service = _services[message.channel];

    if (service == null) {
      _log.warning(
        'Received message on unregistered channel ${message.channel}.',
      );
      return;
    }

    // Preserve message ordering, but keep failures from stopping later routing.
    _dispatchQueue = _dispatchQueue
        .then((_) => service.dispatch(message))
        .catchError((Object error, StackTrace stackTrace) {
          _log.severe(
            'Service ${service.runtimeType} failed on '
            'channel ${message.channel}.',
            error,
            stackTrace,
          );
        });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}