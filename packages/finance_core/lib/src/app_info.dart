class AppInfo {
  final String name;
  final String tagline;

  const AppInfo({required this.name, required this.tagline});

  String greeting() => '$name へようこそ\n$tagline';
}
