class CommandLineOptions {
  const CommandLineOptions();

  static CommandLineOptions parse(List<String> args) {
    if (args.isNotEmpty) {
      throw FormatException(
        'No command-line options are currently supported. '
        'Unexpected arguments: ${args.join(' ')}',
      );
    }

    return const CommandLineOptions();
  }
}