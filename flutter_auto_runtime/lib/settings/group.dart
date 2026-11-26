class SettingGroup {
  const SettingGroup({
    required this.key,
    required this.title,
    this.description,
    this.parentKey,
  });

  final String key;
  final String title;
  final String? description;
  final String? parentKey;
}
