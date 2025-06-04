class NominatimLocation {
  final String displayName;
  final double lat;
  final double lon;

  NominatimLocation({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory NominatimLocation.fromJson(Map<String, dynamic> json) {
    return NominatimLocation(
      displayName: json['display_name'],
      lat: double.parse(json['lat']),
      lon: double.parse(json['lon']),
    );
  }
}
