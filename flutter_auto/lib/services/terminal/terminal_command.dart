typedef TerminalCommandHandler =
    Future<String> Function(List<String> arguments);

class TerminalCommand {
  final String name;
  final String description;
  final String usage;
  final List<String> examples;
  final List<String> suggestions;
  final TerminalCommandHandler? handler;

  const TerminalCommand({
    required this.name,
    required this.description,
    required this.usage,
    this.examples = const <String>[],
    this.suggestions = const <String>[],
    this.handler,
  });
}
