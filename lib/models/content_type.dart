enum ContentType {
  TV,
  SERIES,
  MOVIES,
}

extension ContentTypeExt on ContentType {
  String get label => name[0] + name.substring(1).toLowerCase();

  String get plural => switch (this) {
        ContentType.TV => 'Canales',
        ContentType.SERIES => 'Series',
        ContentType.MOVIES => 'Películas',
      };
}
