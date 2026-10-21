import 'package:flutter/material.dart';
import 'package:flutter_auto/screens/adb_terminal_screen.dart';
import 'package:flutter_auto/screens/headunit_screen.dart';
import 'package:flutter_auto/services/adb_manager.dart';

// Replace this import with the actual path to your AdbManager file.

class DeviceSelectionScreen extends StatefulWidget {
  const DeviceSelectionScreen({super.key});

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  final AdbManager _adbManager = AdbManager();

  List<AdbDevice> _devices = <AdbDevice>[];
  String? _selectedSerial;
  bool _isLoading = false;
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _startHeadunitServer(AdbDevice device) async {
    if (!device.isAuthorized) {
      setState(() {
        _errorMessage =
            'Authorize this device before starting the Head Unit Server.';
      });
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            HeadunitServerScreen(deviceSerial: device.serial),
      ),
    );
  }

  Future<void> _connectAndForward(String serial) async {
    final dynamic result = await _adbManager.executeCommand(<String>[
      '-s',
      serial,
      'forward',
      'tcp:5277',
      'tcp:5277',
    ]);

    if (result.exitCode != 0) {
      throw Exception('Failed to connect: ${result.stderr}');
    }
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<AdbDevice> devices = await _adbManager.listDevices();

      if (!mounted) {
        return;
      }

      setState(() {
        _devices = devices;

        // Keep the current selection if the device is still connected.
        if (!_devices.any(
          (AdbDevice device) => device.serial == _selectedSerial,
        )) {
          _selectedSerial = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connectToDevice() async {
    final String? serial = _selectedSerial;

    if (serial == null) {
      return;
    }

    final AdbDevice selectedDevice = _devices.firstWhere(
      (AdbDevice device) => device.serial == serial,
    );

    if (!selectedDevice.isAuthorized) {
      setState(() {
        _errorMessage =
            'This device is not authorized. Accept the ADB debugging prompt '
            'on your Android device first.';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      await _connectAndForward(serial);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              AdbTerminalScreen(adbManager: _adbManager, deviceSerial: serial),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Auto'),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh devices',
            onPressed: _isLoading ? null : _loadDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                'Select a device',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose an authorized Android device to connect.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: _isLoading && _devices.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _devices.isEmpty
                  ? const Center(child: Text('No ADB devices found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _devices.length,
                      separatorBuilder: (BuildContext context, int index) {
                        return const SizedBox(height: 8);
                      },
                      itemBuilder: (BuildContext context, int index) {
                        final AdbDevice device = _devices[index];
                        final bool isSelected =
                            device.serial == _selectedSerial;

                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.smartphone,
                                    color: device.isAuthorized
                                        ? colors.primary
                                        : colors.error,
                                  ),
                                  title: Text(device.serial),
                                  subtitle: Text(
                                    device.isAuthorized
                                        ? 'Authorized'
                                        : device.state,
                                  ),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: colors.primary,
                                        )
                                      : const Icon(Icons.chevron_right),
                                  selected: isSelected,
                                  onTap: () {
                                    setState(() {
                                      _selectedSerial = device.serial;
                                      _errorMessage = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed:
                                            device.isAuthorized &&
                                                !_isConnecting
                                            ? () async {
                                                setState(() {
                                                  _selectedSerial =
                                                      device.serial;
                                                  _errorMessage = null;
                                                  _isConnecting = true;
                                                });

                                                try {
                                                  await _connectAndForward(
                                                    device.serial,
                                                  );

                                                  if (!mounted) {
                                                    return;
                                                  }

                                                  await Navigator.of(
                                                    context,
                                                  ).push(
                                                    MaterialPageRoute<void>(
                                                      builder:
                                                          (
                                                            BuildContext
                                                            context,
                                                          ) =>
                                                              AdbTerminalScreen(
                                                                adbManager:
                                                                    _adbManager,
                                                                deviceSerial:
                                                                    device
                                                                        .serial,
                                                              ),
                                                    ),
                                                  );
                                                } catch (error) {
                                                  if (mounted) {
                                                    setState(() {
                                                      _errorMessage = error
                                                          .toString();
                                                    });
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(() {
                                                      _isConnecting = false;
                                                    });
                                                  }
                                                }
                                              }
                                            : null,
                                        icon: const Icon(Icons.terminal),
                                        label: const Text('Connect'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: device.isAuthorized
                                            ? () => _startHeadunitServer(device)
                                            : null,
                                        icon: const Icon(Icons.directions_car),
                                        label: const Text('Start Head Unit'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed:
                    _selectedSerial == null || _isConnecting || _isLoading
                    ? null
                    : _connectToDevice,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
