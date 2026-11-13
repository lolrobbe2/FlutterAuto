String validateProductPackagePath(String path, {String? requiredExtension}) {
  final List<String> segments = path.split('/');

  if (path.isEmpty ||
      path != path.trim() ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':') ||
      segments.any(
        (String segment) =>
            segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw ArgumentError.value(
      path,
      'path',
      'Expected a safe relative package path.',
    );
  }

  if (requiredExtension != null && !path.endsWith(requiredExtension)) {
    throw ArgumentError.value(
      path,
      'path',
      'Expected a package with extension $requiredExtension.',
    );
  }

  return path;
}
