import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_auto/services/adb_manager.dart';
import 'package:flutter_auto/services/terminal/terminal_command.dart';

class AdbTerminalScreen extends StatefulWidget {
  final AdbManager adbManager;
  final String deviceSerial;

  const AdbTerminalScreen({
    super.key,
    required this.adbManager,
    required this.deviceSerial,
  });

  @override
  State<AdbTerminalScreen> createState() => _AdbTerminalScreenState();
}

class _AdbTerminalScreenState extends State<AdbTerminalScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<String> _output = <String>[];
  late final List<TerminalCommand> _commands;

  List<String> _suggestions = <String>[];
  bool _isExecuting = false;

  Process? _streamingProcess;
  bool _isStreaming = false;

  final Map<String, List<String>> _completionCache = <String, List<String>>{};

  int _completionRequestId = 0;

  @override
  void initState() {
    super.initState();
    _commands = _buildCommands();
  }


  Future<void> _startLogcat(List<String> arguments) async {
    if (_streamingProcess != null) {
      _appendOutput('Logcat is already running.');
      return;
    }

    try {
      final Process process = await widget.adbManager.startStreamingCommand(
        <String>['-s', widget.deviceSerial, 'logcat', ...arguments],
      );

      if (!mounted) {
        process.kill();
        return;
      }

      setState(() {
        _streamingProcess = process;
        _isStreaming = true;
        _output.add('Started logcat on ${widget.deviceSerial}.');
      });

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
            _appendOutput(line);
          });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((String line) {
            _appendOutput('[stderr] $line');
          });

      final int exitCode = await process.exitCode;

      if (!mounted) {
        return;
      }

      setState(() {
        if (identical(_streamingProcess, process)) {
          _streamingProcess = null;
          _isStreaming = false;
        }

        _output.add('Logcat exited with code $exitCode.');
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _streamingProcess = null;
        _isStreaming = false;
        _output.add('Failed to start logcat: $error');
      });
    }
  }

  void _stopLogcat() {
    final Process? process = _streamingProcess;

    if (process == null) {
      _appendOutput('No logcat process is running.');
      return;
    }

    _appendOutput('Stopping logcat...');

    final bool killed = process.kill();

    if (!killed) {
      _appendOutput('Could not terminate the logcat process.');
    }
  }

  void _appendOutput(String line) {
    if (!mounted) {
      return;
    }

    setState(() {
      _output.add(line);
    });
  }
  void _completeInput() {
    if (_suggestions.isEmpty) {
      return;
    }

    _applySuggestion(_suggestions.first);
  }

  Future<List<String>> _discoverAdbCommands() async {
    const String cacheKey = 'adb-commands';

    if (_completionCache.containsKey(cacheKey)) {
      return _completionCache[cacheKey]!;
    }

    final ProcessResult result = await widget.adbManager.executeCommand(
      <String>['help'],
    );

    final Set<String> commands = <String>{};

    // Parse command names from the ADB help output.
    final RegExp pattern = RegExp(
      r'^\s{2,}([a-z][a-z0-9_-]*)\s{2,}',
      multiLine: true,
    );

    for (final RegExpMatch match in pattern.allMatches(
      result.stdout.toString(),
    )) {
      commands.add(match.group(1)!);
    }

    final List<String> discovered = commands.toList()..sort();
    _completionCache[cacheKey] = discovered;

    return discovered;
  }

  Future<List<String>> _discoverShellCommands() async {
    const String cacheKey = 'shell-commands';

    if (_completionCache.containsKey(cacheKey)) {
      return _completionCache[cacheKey]!;
    }

    final ProcessResult result = await widget.adbManager.executeCommand(
      <String>['-s', widget.deviceSerial, 'shell', 'ls', '/system/bin'],
    );

    final List<String> commands = result.exitCode == 0
        ? result.stdout
              .toString()
              .split(RegExp(r'\s+'))
              .where((String item) => item.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];

    commands.sort();
    _completionCache[cacheKey] = commands;

    return commands;
  }

  Future<List<String>> _discoverSubcommands(List<String> arguments) async {
    if (arguments.isEmpty) {
      return <String>[];
    }

    final String tool = arguments.first;
    final String cacheKey = 'subcommands:$tool';

    if (_completionCache.containsKey(cacheKey)) {
      return _completionCache[cacheKey]!;
    }

    final List<List<String>> helpAttempts = <List<String>>[
      <String>['shell', tool, 'help'],
      <String>['shell', tool, '--help'],
    ];

    final Set<String> discovered = <String>{};

    for (final List<String> attempt in helpAttempts) {
      try {
        final ProcessResult result = await widget.adbManager.executeCommand(
          <String>['-s', widget.deviceSerial, ...attempt],
        );

        final String output = '${result.stdout}\n${result.stderr}';

        // Discover command-like words from help output.
        final RegExp pattern = RegExp(
          r'^\s{0,8}([a-z][a-z0-9_-]*)\s{2,}',
          multiLine: true,
        );

        for (final RegExpMatch match in pattern.allMatches(output)) {
          discovered.add(match.group(1)!);
        }

        if (discovered.isNotEmpty) {
          break;
        }
      } catch (_) {
        // Some Android commands do not implement help.
      }
    }

    final List<String> commands = discovered.toList()..sort();
    _completionCache[cacheKey] = commands;

    return commands;
  }

  Future<void> _updateDynamicSuggestions(String input) async {
    final int requestId = ++_completionRequestId;
    final String trimmed = input.trimLeft();
    final List<String> suggestions = <String>[];

    if (trimmed.isEmpty) {
      suggestions.addAll(
        _commands.map((TerminalCommand command) => command.name),
      );
    } else {
      final List<String> parts = trimmed.split(RegExp(r'\s+'));
      final bool trailingSpace = input.endsWith(' ');
      final String first = parts.first;

      if (parts.length == 1 && !trailingSpace) {
        final List<String> adbCommands = await _discoverAdbCommands();

        suggestions.addAll(
          adbCommands
              .where(
                (String command) =>
                    command.startsWith(first) && command != first,
              )
              .map((String command) => command),
        );

        suggestions.addAll(
          _commands
              .map((TerminalCommand command) => command.name)
              .where(
                (String command) =>
                    command.startsWith(first) && command != first,
              ),
        );
      } else if (first == 'shell') {
        final String shellInput = input.substring('shell'.length).trimLeft();
        final List<String> shellParts = shellInput.split(RegExp(r'\s+'));
        final bool shellTrailingSpace = input.endsWith(' ');

        if (shellParts.length == 1 &&
            shellInput.isNotEmpty &&
            !shellTrailingSpace) {
          final List<String> shellCommands = await _discoverShellCommands();

          suggestions.addAll(
            shellCommands.where(
              (String command) =>
                  command.startsWith(shellParts.first) &&
                  command != shellParts.first,
            ),
          );
        } else if (shellParts.isNotEmpty && shellParts.first.isNotEmpty) {
          final List<String> subcommands = await _discoverSubcommands(
            shellParts,
          );

          if (subcommands.isNotEmpty) {
            final String prefix = shellParts.length > 1 ? shellParts.last : '';

            suggestions.addAll(
              subcommands.where(
                (String command) =>
                    command.startsWith(prefix) && command != prefix,
              ),
            );
          }
        }
      }
    }

    if (!mounted || requestId != _completionRequestId) {
      return;
    }

    final List<String> uniqueSuggestions = suggestions
        .toSet()
        .take(12)
        .toList();

    setState(() {
      _suggestions = uniqueSuggestions;
    });
  }

  List<TerminalCommand> _buildCommands() {
    return <TerminalCommand>[
      TerminalCommand(
        name: 'help',
        description: 'Show available commands or command details.',
        usage: 'help [command]',
        examples: <String>['help', 'help devices'],
        suggestions: <String>['help ', 'help devices', 'help shell'],
        handler: _handleHelp,
      ),
      TerminalCommand(
        name: 'devices',
        description: 'List connected ADB devices.',
        usage: 'devices',
        examples: <String>['devices'],
        suggestions: <String>['devices'],
        handler: _handleDevices,
      ),
      TerminalCommand(
        name: 'forward-list',
        description: 'List active ADB port forwards.',
        usage: 'forward-list',
        examples: <String>['forward-list'],
        suggestions: <String>['forward-list'],
        handler: (List<String> args) async {
          return await _runAdb(<String>['forward', '--list']);
        },
      ),
      TerminalCommand(
        name: 'android-version',
        description: 'Get the Android version.',
        usage: 'android-version',
        examples: <String>['android-version'],
        suggestions: <String>['android-version'],
        handler: (List<String> args) async {
          return await _runAdb(<String>[
            'shell',
            'getprop',
            'ro.build.version.release',
          ]);
        },
      ),
      TerminalCommand(
        name: 'clear',
        description: 'Clear the terminal output.',
        usage: 'clear',
        examples: <String>['clear'],
        suggestions: <String>['clear'],
        handler: (List<String> args) async {
          if (mounted) {
            setState(() {
              _output.clear();
            });
          }
          return '';
        },
      ),
      TerminalCommand(
        name: 'shell',
        description: 'Execute a command in the Android shell.',
        usage: 'shell <command> [arguments...]',
        examples: <String>[
          'shell getprop ro.build.version.release',
          'shell pm list packages',
        ],
        suggestions: <String>[
          'shell ',
          'shell getprop ',
          'shell pm ',
          'shell pm list packages',
          'shell dumpsys ',
          'shell input keyevent ',
        ],
      ),
      TerminalCommand(
        name: 'forward',
        description: 'Manage ADB port forwarding.',
        usage: 'forward <local> <remote>',
        examples: <String>['forward tcp:5277 tcp:5277', 'forward --list'],
        suggestions: <String>[
          'forward ',
          'forward tcp:5277 tcp:5277',
          'forward --list',
        ],
      ),
      TerminalCommand(
        name: 'logcat',
        description: 'Read Android system logs.',
        usage: 'logcat [arguments...]',
        examples: <String>['logcat -d', 'logcat -t 100'],
        suggestions: <String>['logcat', 'logcat -d', 'logcat -t 100'],
      ),
    ];
  }

  Future<String> _handleHelp(List<String> args) async {
    if (args.isNotEmpty) {
      final String requestedName = args.first;
      TerminalCommand? command;

      for (final TerminalCommand item in _commands) {
        if (item.name == requestedName) {
          command = item;
          break;
        }
      }

      if (command == null) {
        return 'Unknown command: $requestedName\n'
            'Type "help" to see available commands.';
      }

      final String examples = command.examples.isEmpty
          ? 'None'
          : command.examples.map((String e) => '  $e').join('\n');

      return '${command.name}\n'
          '${command.description}\n\n'
          'Usage: ${command.usage}\n\n'
          'Examples:\n$examples';
    }

    final StringBuffer buffer = StringBuffer()
      ..writeln('Available commands:')
      ..writeln('');

    for (final TerminalCommand command in _commands) {
      buffer.writeln('${command.name.padRight(18)} ${command.description}');
    }

    buffer
      ..writeln('')
      ..writeln('Raw ADB commands are also supported.')
      ..writeln('Use "help <command>" for details.');

    return buffer.toString();
  }

  Future<String> _handleDevices(List<String> args) async {
    final List<AdbDevice> devices = await widget.adbManager.listDevices();

    if (devices.isEmpty) {
      return 'No ADB devices found.';
    }

    return devices
        .map((AdbDevice device) {
          return '${device.serial} [${device.state}]';
        })
        .join('\n');
  }

  Future<String> _runAdb(List<String> arguments) async {
    final ProcessResult result = await widget.adbManager.executeCommand(
      <String>['-s', widget.deviceSerial, ...arguments],
    );

    final String stdoutText = result.stdout.toString().trimRight();
    final String stderrText = result.stderr.toString().trimRight();

    final StringBuffer buffer = StringBuffer();

    if (stdoutText.isNotEmpty) {
      buffer.writeln(stdoutText);
    }

    if (stderrText.isNotEmpty) {
      buffer.writeln(stderrText);
    }

    if (result.exitCode != 0) {
      buffer.writeln('Exit code: ${result.exitCode}');
    }

    return buffer.toString().trimRight();
  }

  List<String> _parseArguments(String input) {
    final RegExp pattern = RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''');

    return pattern.allMatches(input).map((RegExpMatch match) {
      return match.group(1) ?? match.group(2) ?? match.group(3)!;
    }).toList();
  }

  void _updateSuggestions(String input) {
    final String trimmed = input.trimLeft();
    final List<String> suggestions = <String>[];

    if (trimmed.isEmpty) {
      suggestions.addAll(
        _commands.map((TerminalCommand command) => command.name),
      );
    } else {
      final List<String> parts = trimmed.split(RegExp(r'\s+'));
      final String first = parts.first;
      final bool hasTrailingSpace = input.endsWith(' ');

      if (parts.length == 1 && !hasTrailingSpace) {
        for (final TerminalCommand command in _commands) {
          if (command.name.startsWith(first) && command.name != first) {
            suggestions.add(command.name);
          }
        }
      }

      for (final TerminalCommand command in _commands) {
        for (final String suggestion in command.suggestions) {
          if (suggestion.startsWith(input) &&
              suggestion != input &&
              !suggestions.contains(suggestion)) {
            suggestions.add(suggestion);
          }
        }
      }

      // Offer raw ADB command completion when no custom command matches.
      if (suggestions.isEmpty && parts.length == 1) {
        for (final String rawCommand in <String>[
          'shell',
          'forward',
          'connect',
          'disconnect',
          'logcat',
          'install',
          'uninstall',
          'push',
          'pull',
          'reboot',
        ]) {
          if (rawCommand.startsWith(first) &&
              !suggestions.contains(rawCommand)) {
            suggestions.add(rawCommand);
          }
        }
      }
    }

    setState(() {
      _suggestions = suggestions.take(8).toList();
    });
  }

  void _applySuggestion(String suggestion) {
    _controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );

    _updateSuggestions(suggestion);
  }

  Future<void> _executeCommand() async {
    final String input = _controller.text.trim();

    if (input.isEmpty || _isExecuting) {
      return;
    }

    _controller.clear();

    setState(() {
      _isExecuting = true;
      _suggestions.clear();
      _output.add('\$ $input');
    });

    _scrollToBottom();

    try {
      final List<String> arguments = _parseArguments(input);

      if (arguments.isEmpty) {
        return;
      }
      if (arguments.first == 'logcat') {
        await _startLogcat(arguments.skip(1).toList());
        return;
      }
      final String commandName = arguments.first;
      final List<String> commandArguments = arguments.sublist(1);

      TerminalCommand? command;

      for (final TerminalCommand item in _commands) {
        if (item.name == commandName) {
          command = item;
          break;
        }
      }

      final String result;

      if (command != null && command.handler != null) {
        result = await command.handler!(commandArguments);
      } else {
        // Pass unrecognized commands directly to ADB.
        result = await _runAdb(arguments);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        if (result.isNotEmpty) {
          _output.addAll(result.split('\n'));
        }
        _output.add('');
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _output.add('Error: $error');
        _output.add('');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExecuting = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _streamingProcess?.kill();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ADB Terminal'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Clear terminal',
            onPressed: () {
              setState(() {
                _output.clear();
              });
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          ListTile(
            dense: true,
            leading: const Icon(Icons.smartphone),
            title: Text(widget.deviceSerial),
            subtitle: const Text('Selected device'),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF111318),
              padding: const EdgeInsets.all(12),
              child: _output.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'Welcome to ADB Terminal.\n'
                        'Type help to see available commands.',
                        style: TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _output.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String line = _output[index];

                        return SelectableText(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: line.startsWith('\$ ')
                                ? const Color(0xFF80CBC4)
                                : line.startsWith('Error:')
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFFE0E0E0),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              color: colors.surfaceContainerLow,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (BuildContext context, int index) {
                  final String suggestion = _suggestions[index];

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(
                      suggestion,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    onTap: () => _applySuggestion(suggestion),
                  );
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Focus(
                      onKeyEvent: (FocusNode node, KeyEvent event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.tab) {
                          _completeInput();
                          return KeyEventResult.handled;
                        }

                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _controller,
                        onChanged: _updateDynamicSuggestions,
                        onSubmitted: (_) => _executeCommand(),
                        decoration: const InputDecoration(
                          hintText: 'Type an ADB command...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Execute command',
                    onPressed: _isExecuting ? null : _executeCommand,
                    icon: _isExecuting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                  ),
                  if (_isStreaming)
                    IconButton.filled(
                      tooltip: 'Stop logcat',
                      onPressed: _stopLogcat,
                      icon: const Icon(Icons.stop),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
