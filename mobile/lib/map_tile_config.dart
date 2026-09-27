class MapTileConfig {
  static const geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');

  static String get urlTemplate {
    if (geoapifyApiKey.isNotEmpty) {
      return 'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=$geoapifyApiKey';
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  static String get sourceLabel => geoapifyApiKey.isNotEmpty ? 'Geoapify / OpenStreetMap' : 'OpenStreetMap tiles';

  static bool get isGeoapifyConfigured => geoapifyApiKey.isNotEmpty;
}
