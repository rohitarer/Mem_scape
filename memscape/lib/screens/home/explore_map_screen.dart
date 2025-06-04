import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:memscape/models/nominatim_location.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/providers/photo_provider.dart';
import 'package:memscape/screens/home/location_photos_screen.dart';
import 'package:memscape/services/firestore_service.dart';
import 'package:memscape/services/realtime_database_service.dart';

class ExploreMapScreen extends ConsumerStatefulWidget {
  const ExploreMapScreen({super.key});

  @override
  ConsumerState<ExploreMapScreen> createState() => _ExploreMapScreenState();
}

class _ExploreMapScreenState extends ConsumerState<ExploreMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FirestoreService firestoreService = FirestoreService();

  List<PhotoModel> _allPhotos = [];
  List<PhotoModel> _filteredPhotos = [];
  LatLng? _userLocation;
  LatLng? _searchLocation;
  String? _searchedCity;
  bool _showSheet = false;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  double? _userHeading;
  bool _enableMapRotation = false;
  bool _isManualSearch = false;
  String? _searchedState;

  final FocusNode _focusNode = FocusNode();
  List<NominatimLocation> _suggestions = [];
  LatLng? _suggestionSelectedMarker;

  double _calculateBearing(LatLng from, LatLng to) {
    final dLon = to.longitude - from.longitude;
    final y = sin(dLon * pi / 180) * cos(to.latitude * pi / 180);
    final x =
        cos(from.latitude * pi / 180) * sin(to.latitude * pi / 180) -
        sin(from.latitude * pi / 180) *
            cos(to.latitude * pi / 180) *
            cos(dLon * pi / 180);
    final bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360;
  }

  double _distanceInKm(LatLng a, LatLng b) {
    const earthRadius = 6371;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;

    final aCalc =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(aCalc), sqrt(1 - aCalc));
    return earthRadius * c;
  }

  @override
  void initState() {
    super.initState();
    // _startLocationTracking();
    // Defer execution until FlutterMap is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLocationTracking(); // ✅ Safe place
    });

    _loadUserLocation();
    _fetchPhotos();
    fetchAllPhotos();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
    );

    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'memscape-app'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final results =
            data.map((item) => NominatimLocation.fromJson(item)).toList();

        setState(() => _suggestions = results.cast<NominatimLocation>());
      } else {
        debugPrint("❌ Suggestion fetch failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Suggestion fetch error: $e");
    }
  }

  void _startLocationTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    // _positionStream = Geolocator.getPositionStream(
    //   locationSettings: locationSettings,
    // ).listen((Position position) {
    //   setState(() {
    //     _userLocation = LatLng(position.latitude, position.longitude);
    //     _userHeading = position.heading;
    //   });
    // });
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      final current = LatLng(position.latitude, position.longitude);

      // Optional fallback: use GPS heading if no route is selected
      double heading = position.heading;

      // if (_routePoints.isNotEmpty) {
      //   final destination = _routePoints.last;
      //   heading = _calculateBearing(current, destination);
      //   // 🔁 Rotate map only when route is active
      //   _mapController.rotate(heading);
      // }

      if (_routePoints.isNotEmpty) {
        final destination = _routePoints.last;
        heading = _calculateBearing(current, destination);

        // 🔄 Rotate map if route is selected
        _mapController.rotate(heading);
      } else {
        // Optional: reset rotation when no route
        _mapController.rotate(0);
      }

      setState(() {
        _userLocation = current;
        _userHeading = heading;
        if (_enableMapRotation) {
          _mapController.rotate(heading); // 🔁 rotate the map to heading
        }
      });
    });
  }

  Future<void> _loadUserLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    final position = await Geolocator.getCurrentPosition();
    final loc = LatLng(position.latitude, position.longitude);

    setState(() {
      _userLocation = loc;
    });

    // ✅ Don't override view if user has searched
    if (!_isManualSearch) {
      _mapController.move(loc, 15);
    }
  }

  Future<bool> _handleLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return false;
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _fetchPhotos() async {
    final data = await RealtimeDatabaseService().getAllPhotos();
    setState(() {
      _allPhotos = data.where((p) => p.lat != null && p.lng != null).toList();
    });
  }

  String normalize(String text) {
    return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _searchPlace(String query, {LatLng? forcedCoords}) async {
    try {
      // 1. Determine coordinates
      final LatLng newCenter;
      if (forcedCoords != null) {
        newCenter = forcedCoords;
      } else {
        final locations = await locationFromAddress(query);
        if (locations.isEmpty) throw Exception("Location not found");
        newCenter = LatLng(locations.first.latitude, locations.first.longitude);
      }

      debugPrint(
        "📍 Selected coordinates: ${newCenter.latitude}, ${newCenter.longitude}",
      );

      // 2. Get Place Details
      final placemarks = await placemarkFromCoordinates(
        newCenter.latitude,
        newCenter.longitude,
      );
      if (placemarks.isEmpty) throw Exception("Place details not found");

      final placemark = placemarks.first;
      final city =
          (placemark.locality ?? placemark.subAdministrativeArea ?? '')
              .toLowerCase()
              .trim();
      final state = (placemark.administrativeArea ?? '').toLowerCase().trim();
      final country = (placemark.country ?? '').toLowerCase().trim();
      final normalizedQuery = query.toLowerCase().trim();

      // 3. Fetch All Public Photos from Firestore
      final snapshot =
          await FirebaseFirestore.instance
              .collection('photos')
              .where('isPublic', isEqualTo: true)
              .get();

      final allPhotos =
          snapshot.docs
              .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
              .where(
                (photo) =>
                    (photo.imagePath != null && photo.imagePath!.isNotEmpty) &&
                    photo.location.isNotEmpty,
              )
              .toList();

      debugPrint("📸 Total public photos fetched: ${allPhotos.length}");

      // 4. Prioritize exact location match
      List<PhotoModel> matchedPhotos =
          allPhotos.where((photo) {
            final location = photo.location.toLowerCase().trim();
            return location == normalizedQuery;
          }).toList();

      // 5. Fallback to fuzzy city+state+country match if no exact match
      if (matchedPhotos.isEmpty) {
        matchedPhotos =
            allPhotos.where((photo) {
              final loc = photo.location.toLowerCase();
              return loc.contains(city) &&
                  loc.contains(state) &&
                  loc.contains(country);
            }).toList();
      }

      // 6. Decode imageBase64 only once & cache it
      for (var photo in matchedPhotos) {
        if (photo.decodedImage == null && photo.imageBase64 != null) {
          try {
            photo.decodedImage = base64Decode(photo.imageBase64!);
            debugPrint("🖼️ Base64 Image decoded for: ${photo.caption}");
          } catch (e) {
            debugPrint("⚠️ Failed to decode image for: ${photo.caption}");
          }
        }
      }

      // 7. Remove duplicate locations, keep only latest per location
      final Map<String, PhotoModel> latestPerLocation = {};
      for (final photo in matchedPhotos) {
        final locKey = photo.location.toLowerCase().trim();
        if (!latestPerLocation.containsKey(locKey)) {
          latestPerLocation[locKey] = photo;
        }
      }

      final uniquePhotos =
          latestPerLocation.values.toList()..sort(
            (a, b) => b.timestamp.compareTo(a.timestamp),
          ); // Latest first

      debugPrint("✅ Final matched photos: ${uniquePhotos.length}");

      // 8. Update UI state
      setState(() {
        _searchLocation = newCenter;
        _searchedCity = city;
        _searchedState = state;
        _filteredPhotos = uniquePhotos;
        _showSheet = uniquePhotos.isNotEmpty;
        _isManualSearch = true;
      });

      // 9. Move map to the selected location
      _mapController.move(newCenter, 12.5);
    } catch (e) {
      debugPrint("❌ Error searching location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Place not found."),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<List<LatLng>> fetchRoute(LatLng start, LatLng end, String mode) async {
    final url =
        'https://router.project-osrm.org/route/v1/$mode/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final coords = data['routes'][0]['geometry']['coordinates'] as List;
      return coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
    } else {
      throw Exception('Failed to fetch route');
    }
  }

  Future<void> fetchAllPhotos() async {
    final List<PhotoModel> allPhotos = [];

    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('photos')
              .where('isPublic', isEqualTo: true)
              .get();

      debugPrint("📁 Public Photos Count: ${snapshot.docs.length}");

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final photo = PhotoModel.fromMap(data);

        debugPrint("📸 Found photo at: ${photo.location}");

        allPhotos.add(photo);
      }

      setState(() {
        _allPhotos = allPhotos;
        debugPrint("✅ Total Public Photos Loaded: ${_allPhotos.length}");
      });
    } catch (e) {
      debugPrint("❌ Error fetching photos: $e");
    }
  }

  Future<void> _drawRoute(String mode, PhotoModel photo) async {
    if (_userLocation == null) return;

    final String baseUrl = 'https://api.openrouteservice.org/v2/directions';
    final String apiKey =
        '5b3ce3597851110001cf6248b16bba8b608b442e8723352c9672c508'; // 🔑 Replace this

    final String profile = switch (mode) {
      'walking' => 'foot-walking',
      'cycling' => 'cycling-regular',
      'driving' => 'driving-car',
      _ => 'foot-walking',
    };

    final String url =
        '$baseUrl/$profile?api_key=$apiKey&start=${_userLocation!.longitude},${_userLocation!.latitude}&end=${photo.lng},${photo.lat}';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final coordinates =
          data['features'][0]['geometry']['coordinates'] as List;

      setState(() {
        _routePoints =
            coordinates
                .map((c) => LatLng(c[1] as double, c[0] as double))
                .toList();
        _enableMapRotation = true; // 🔁 enable map rotation
      });
    } else {
      debugPrint("❌ Route fetch failed: ${response.statusCode}");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Could not fetch route.")));
    }
  }

  void _drawPublicTransitRoute(PhotoModel photo) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Public transit support coming soon.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoState = ref.watch(publicPhotosProvider); // 👈 Watch provider

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Explore Memories",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            _suggestions.isNotEmpty ? 200 : 64, // Dynamic height
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  onChanged: _fetchSuggestions,
                  onSubmitted: _searchPlace,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: "Search a city or place...",
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (_, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          title: Text(
                            suggestion.displayName,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          onTap: () {
                            _searchController.text = suggestion.displayName;
                            _focusNode.unfocus();

                            setState(() {
                              _suggestionSelectedMarker = LatLng(
                                suggestion.lat,
                                suggestion.lon,
                              );
                              _mapController.move(
                                _suggestionSelectedMarker!,
                                14.5,
                              );
                              _suggestions.clear();
                            });

                            // ✅ Trigger the search manually
                            // _searchPlace(suggestion.displayName);
                            _searchPlace(
                              suggestion.displayName,
                              forcedCoords: LatLng(
                                suggestion.lat,
                                suggestion.lon,
                              ),
                            );

                            debugPrint(
                              "📍 Selected: ${suggestion.displayName}",
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),

      body: photoState.when(
        data: (allPhotos) {
          return Stack(
            children: [
              // 🌍 MAP VIEW
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      _userLocation ?? const LatLng(20.5937, 78.9629),
                  initialZoom: 4.5,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.memscape.app',
                  ),

                  MarkerLayer(
                    markers: [
                      // 🔵 Blue user GPS marker only if not in search mode
                      if (_userLocation != null &&
                          !_showSheet &&
                          !_isManualSearch)
                        Marker(
                          point: _userLocation!,
                          width: 40,
                          height: 40,
                          child: Transform.rotate(
                            angle: (_userHeading ?? 0) * (pi / 180),
                            child: const Icon(
                              Icons.navigation,
                              size: 40,
                              color: Colors.blue,
                            ),
                          ),
                        ),

                      if (_searchLocation != null)
                        Marker(
                          point: _searchLocation!,
                          width: 40,
                          height: 40,
                          child: GestureDetector(
                            onTap: () {
                              final city =
                                  _searchedCity?.toLowerCase().trim() ?? '';
                              final state =
                                  _searchedState?.toLowerCase().trim() ?? '';

                              if (city.isEmpty || state.isEmpty) {
                                debugPrint(
                                  "❌ City or state is empty during search",
                                );
                                showDialog(
                                  context: context,
                                  builder:
                                      (_) => const AlertDialog(
                                        title: Text("Location Not Recognized"),
                                        content: Text(
                                          "We couldn't recognize the selected location.",
                                        ),
                                      ),
                                );
                                return;
                              }

                              final matchedPhotos =
                                  _filteredPhotos.where((photo) {
                                    final location =
                                        photo.location.toLowerCase();
                                    return location.contains(city) &&
                                        location.contains(state);
                                  }).toList();

                              matchedPhotos.sort(
                                (a, b) => b.timestamp.compareTo(a.timestamp),
                              );

                              if (matchedPhotos.isNotEmpty) {
                                // ✅ Directly show the latest photo
                                _showMemoryDialog(context, matchedPhotos.first);
                              } else {
                                // ❌ No matches
                                showDialog(
                                  context: context,
                                  builder:
                                      (_) => AlertDialog(
                                        title: const Text("No Memories Found"),
                                        content: Text(
                                          "No public memories found for \"$city, $state\" yet. Be the first to upload one!",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () =>
                                                    Navigator.of(context).pop(),
                                            child: const Text("OK"),
                                          ),
                                        ],
                                      ),
                                );
                              }
                            },
                            child: const Icon(
                              Icons.location_on,
                              size: 40,
                              color: Colors.red,
                            ),
                          ),
                        ),

                      // 🖼️ Public photos
                      // ..._filteredPhotos
                      //     .where((photo) {
                      //       if (_searchLocation != null) {
                      //         final photoLatLng = LatLng(photo.lat!, photo.lng!);
                      //         final distance = _distanceInKm(
                      //           photoLatLng,
                      //           _searchLocation!,
                      //         );
                      //         return distance > 0.01; // ~10 meters tolerance
                      //       }
                      //       return true;
                      //     })
                      //     .map((photo) {
                      //       debugPrint(
                      //         "🧠 Marker from photo: ${photo.location} at ${photo.lat}, ${photo.lng}",
                      //       );
                      //       return Marker(
                      //         point: LatLng(photo.lat!, photo.lng!),
                      //         width: 40,
                      //         height: 40,
                      //         child: GestureDetector(
                      //           onTap: () => _showMemoryDialog(context, photo),
                      //           child: const Icon(
                      //             Icons.location_on,
                      //             size: 40,
                      //             color: Colors.red,
                      //           ),
                      //         ),
                      //       );
                      //     }),
                    ],
                  ),
                  PolylineLayer(
                    polylines: [
                      if (_routePoints.isNotEmpty)
                        Polyline(
                          points: _routePoints,
                          strokeWidth: 5,
                          color: Colors.blueAccent,
                        ),
                    ],
                  ),
                ],
              ),

              if (_showSheet && _filteredPhotos.isNotEmpty)
                DraggableScrollableSheet(
                  initialChildSize: 0.35,
                  minChildSize: 0.2,
                  maxChildSize: 0.75,
                  builder: (context, scrollController) {
                    final theme = Theme.of(context);
                    final colorScheme = theme.colorScheme;

                    return Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Colors.black26),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "📍 Memories in '${_searchedCity?.toUpperCase() ?? '...'}'",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              controller: scrollController,
                              itemCount: _filteredPhotos.length,
                              itemBuilder: (_, index) {
                                final photo = _filteredPhotos[index];
                                final lat = photo.lat;
                                final lng = photo.lng;
                                final caption = photo.caption;
                                final location = photo.location;

                                debugPrint(
                                  "📸 Rendering card #$index for: $caption",
                                );

                                Uint8List? imageBytes = photo.decodedImage;
                                if (imageBytes == null &&
                                    photo.imageBase64 != null) {
                                  try {
                                    imageBytes = base64Decode(
                                      photo.imageBase64!,
                                    );
                                    photo.decodedImage = imageBytes; // cache it
                                    debugPrint(
                                      "🖼️ Base64 Image decoded for: $caption",
                                    );
                                  } catch (e) {
                                    debugPrint("⚠️ Error decoding image: $e");
                                  }
                                }

                                return Card(
                                  elevation: 3,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  color: colorScheme.surface,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      if (lat != null && lng != null) {
                                        setState(() {
                                          _routePoints = [];
                                          _enableMapRotation = false;
                                          _mapController.rotate(0);
                                          _mapController.move(
                                            LatLng(lat, lng),
                                            14,
                                          );
                                        });
                                      }
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        FutureBuilder<Uint8List?>(
                                          future: () async {
                                            if (photo.decodedImage != null) {
                                              return photo.decodedImage;
                                            }

                                            if (photo.imageBase64 != null &&
                                                photo.imageBase64!.isNotEmpty) {
                                              try {
                                                final decoded = base64Decode(
                                                  photo.imageBase64!,
                                                );
                                                photo.decodedImage = decoded;
                                                debugPrint(
                                                  "🖼️ Decoded from base64: $caption",
                                                );
                                                return decoded;
                                              } catch (e) {
                                                debugPrint(
                                                  "⚠️ Base64 decode failed for: $caption",
                                                );
                                              }
                                            }

                                            if (photo.imagePath != null &&
                                                photo.imagePath!.isNotEmpty) {
                                              final fetchedBase64 =
                                                  await firestoreService
                                                      .fetchImageBase64(
                                                        photo.imagePath!,
                                                      );
                                              if (fetchedBase64 != null) {
                                                final decoded = base64Decode(
                                                  fetchedBase64,
                                                );
                                                photo.decodedImage = decoded;
                                                debugPrint(
                                                  "🖼️ Fetched + decoded from Firestore: $caption",
                                                );
                                                return decoded;
                                              }
                                            }

                                            return null;
                                          }(),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState ==
                                                ConnectionState.waiting) {
                                              return const SizedBox(
                                                height: 160,
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              );
                                            } else if (snapshot.hasData &&
                                                snapshot.data != null) {
                                              // return ClipRRect(
                                              //   borderRadius:
                                              //       const BorderRadius.vertical(
                                              //         top: Radius.circular(16),
                                              //       ),
                                              //   child: Image.memory(
                                              //     snapshot.data!,
                                              //     height: 160,
                                              //     fit: BoxFit.cover,
                                              //   ),
                                              // );
                                              return GestureDetector(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder:
                                                          (
                                                            _,
                                                          ) => LocationPhotosScreen(
                                                            location:
                                                                photo.location,
                                                          ),
                                                    ),
                                                  );
                                                },
                                                child: ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(
                                                          16,
                                                        ),
                                                      ),
                                                  child: Image.memory(
                                                    snapshot.data!,
                                                    height: 160,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              );
                                            } else {
                                              return const SizedBox(
                                                height: 160,
                                                child: Center(
                                                  child: Text(
                                                    "📷 No image available",
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),

                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                caption,
                                                style: theme.textTheme.bodyLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          colorScheme.onSurface,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                location,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color:
                                                          colorScheme.outline,
                                                    ),
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 8,
                                                children: [
                                                  ElevatedButton.icon(
                                                    onPressed:
                                                        () => _drawRoute(
                                                          'walking',
                                                          photo,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.directions_walk,
                                                    ),
                                                    label: const Text('Walk'),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed:
                                                        () => _drawRoute(
                                                          'cycling',
                                                          photo,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.directions_bike,
                                                    ),
                                                    label: const Text('Bike'),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed:
                                                        () => _drawRoute(
                                                          'driving',
                                                          photo,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.directions_car,
                                                    ),
                                                    label: const Text('Car'),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed:
                                                        () =>
                                                            _drawPublicTransitRoute(
                                                              photo,
                                                            ),
                                                    icon: const Icon(
                                                      Icons.directions_transit,
                                                    ),
                                                    label: const Text(
                                                      'Transit',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // 📍 LIVE LOCATION BUTTON
              Positioned(
                top: 20,
                right: 20,
                child: FloatingActionButton(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  onPressed: () {
                    if (_userLocation != null) {
                      _mapController.move(_userLocation!, 15.0);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Live location not available"),
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showMemoryDialog(BuildContext context, PhotoModel photo) async {
    debugPrint("🖼️ Opening memory dialog for: ${photo.caption}");
    debugPrint("📍 Location: ${photo.location}");
    debugPrint("📂 Image path: ${photo.imagePath ?? '❌ Missing'}");

    String? base64Image = photo.imageBase64;

    // Fallback if imageBase64 not embedded
    if ((base64Image!.isEmpty) &&
        photo.imagePath != null &&
        photo.imagePath!.isNotEmpty) {
      try {
        final ref = FirebaseDatabase.instance.ref(photo.imagePath!);
        final snapshot = await ref.get();

        if (snapshot.exists && snapshot.value != null) {
          base64Image = snapshot.value.toString();
          debugPrint("🧾 Fetched base64 from imagePath: ${photo.imagePath}");
        } else {
          debugPrint("❌ No base64 found at path: ${photo.imagePath}");
        }
      } catch (e) {
        debugPrint("❌ Error fetching image from Realtime DB: $e");
      }
    }

    // Show dialog
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(
              photo.caption,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (base64Image != null && base64Image.isNotEmpty)
                  Image.memory(
                    base64Decode(base64Image),
                    height: 160,
                    fit: BoxFit.cover,
                  )
                else
                  const Text('🖼️ No image available'),
                const SizedBox(height: 10),
                Text("📍 ${photo.location}"),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Close",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

// import 'dart:async';
// import 'dart:convert';
// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'package:latlong2/latlong.dart';
// import 'package:memscape/models/photo_model.dart';
// import 'package:memscape/services/realtime_database_service.dart';

// class ExploreMapScreen extends StatefulWidget {
//   const ExploreMapScreen({super.key});

//   @override
//   State<ExploreMapScreen> createState() => _ExploreMapScreenState();
// }

// class _ExploreMapScreenState extends State<ExploreMapScreen> {
//   final MapController _mapController = MapController();
//   final TextEditingController _searchController = TextEditingController();

//   List<PhotoModel> _allPhotos = [];
//   List<PhotoModel> _filteredPhotos = [];
//   LatLng? _userLocation;
//   LatLng? _searchLocation;
//   String? _searchedCity;
//   bool _showSheet = false;
//   List<LatLng> _routePoints = [];
//   StreamSubscription<Position>? _positionStream;
//   double? _userHeading;
//   bool _enableMapRotation = false;

//   double _calculateBearing(LatLng from, LatLng to) {
//     final dLon = to.longitude - from.longitude;
//     final y = sin(dLon * pi / 180) * cos(to.latitude * pi / 180);
//     final x =
//         cos(from.latitude * pi / 180) * sin(to.latitude * pi / 180) -
//         sin(from.latitude * pi / 180) *
//             cos(to.latitude * pi / 180) *
//             cos(dLon * pi / 180);
//     final bearing = atan2(y, x);
//     return (bearing * 180 / pi + 360) % 360;
//   }

//   @override
//   void initState() {
//     super.initState();
//     _startLocationTracking();
//     _loadUserLocation();
//     _fetchPhotos();
//   }

//   @override
//   void dispose() {
//     _positionStream?.cancel();
//     super.dispose();
//   }

//   void _startLocationTracking() async {
//     final hasPermission = await _handleLocationPermission();
//     if (!hasPermission) return;

//     const locationSettings = LocationSettings(
//       accuracy: LocationAccuracy.high,
//       distanceFilter: 5,
//     );

//     // _positionStream = Geolocator.getPositionStream(
//     //   locationSettings: locationSettings,
//     // ).listen((Position position) {
//     //   setState(() {
//     //     _userLocation = LatLng(position.latitude, position.longitude);
//     //     _userHeading = position.heading;
//     //   });
//     // });
//     _positionStream = Geolocator.getPositionStream(
//       locationSettings: locationSettings,
//     ).listen((Position position) {
//       final current = LatLng(position.latitude, position.longitude);

//       // Optional fallback: use GPS heading if no route is selected
//       double heading = position.heading;

//       // if (_routePoints.isNotEmpty) {
//       //   final destination = _routePoints.last;
//       //   heading = _calculateBearing(current, destination);
//       //   // 🔁 Rotate map only when route is active
//       //   _mapController.rotate(heading);
//       // }

//       if (_routePoints.isNotEmpty) {
//         final destination = _routePoints.last;
//         heading = _calculateBearing(current, destination);

//         // 🔄 Rotate map if route is selected
//         _mapController.rotate(heading);
//       } else {
//         // Optional: reset rotation when no route
//         _mapController.rotate(0);
//       }

//       setState(() {
//         _userLocation = current;
//         _userHeading = heading;
//         if (_enableMapRotation) {
//           _mapController.rotate(heading); // 🔁 rotate the map to heading
//         }
//       });
//     });
//   }

//   Future<void> _loadUserLocation() async {
//     final hasPermission = await _handleLocationPermission();
//     if (!hasPermission) return;

//     final position = await Geolocator.getCurrentPosition();
//     final loc = LatLng(position.latitude, position.longitude);

//     setState(() {
//       _userLocation = LatLng(position.latitude, position.longitude);
//       _userLocation = loc;
//     });
//     // 📍 Move the map to user location with desired zoom (e.g., 12.5)
//     _mapController.move(loc, 12.5);
//     _mapController.move(_userLocation!, 15); // 🔍 Zoom in nicely
//   }

//   Future<bool> _handleLocationPermission() async {
//     LocationPermission permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.deniedForever) return false;
//     }
//     return permission == LocationPermission.always ||
//         permission == LocationPermission.whileInUse;
//   }

//   Future<void> _fetchPhotos() async {
//     final data = await RealtimeDatabaseService().getAllPhotos();
//     setState(() {
//       _allPhotos = data.where((p) => p.lat != null && p.lng != null).toList();
//     });
//   }

//   Future<void> _searchPlace(String query) async {
//     try {
//       List<Location> locations = await locationFromAddress(query);
//       if (locations.isEmpty) throw Exception("Location not found");

//       final loc = locations.first;
//       final LatLng newCenter = LatLng(loc.latitude, loc.longitude);

//       final searchLower = query.toLowerCase().trim();
//       final matchedPhotos =
//           _allPhotos.where((p) {
//             final loc = p.location.toLowerCase().trim();
//             return loc.contains(searchLower) || searchLower.contains(loc);
//           }).toList();

//       setState(() {
//         _searchLocation = newCenter;
//         _searchedCity = query; // <-- THIS was missing
//         _filteredPhotos = matchedPhotos;
//         _showSheet = matchedPhotos.isNotEmpty;
//       });

//       _mapController.move(newCenter, 12.5);
//     } catch (e) {
//       debugPrint("❌ Error searching location: $e");
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           backgroundColor: Theme.of(context).colorScheme.errorContainer,
//           content: Text(
//             "Place not found.",
//             style: TextStyle(
//               color: Theme.of(context).colorScheme.onErrorContainer,
//             ),
//           ),
//         ),
//       );
//     }
//   }

//   Future<List<LatLng>> fetchRoute(LatLng start, LatLng end, String mode) async {
//     final url =
//         'https://router.project-osrm.org/route/v1/$mode/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

//     final response = await http.get(Uri.parse(url));

//     if (response.statusCode == 200) {
//       final data = json.decode(response.body);
//       final coords = data['routes'][0]['geometry']['coordinates'] as List;
//       return coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
//     } else {
//       throw Exception('Failed to fetch route');
//     }
//   }

//   Future<void> _drawRoute(String mode, PhotoModel photo) async {
//     if (_userLocation == null) return;

//     final String baseUrl = 'https://api.openrouteservice.org/v2/directions';
//     final String apiKey =
//         '5b3ce3597851110001cf6248b16bba8b608b442e8723352c9672c508'; // 🔑 Replace this

//     final String profile = switch (mode) {
//       'walking' => 'foot-walking',
//       'cycling' => 'cycling-regular',
//       'driving' => 'driving-car',
//       _ => 'foot-walking',
//     };

//     final String url =
//         '$baseUrl/$profile?api_key=$apiKey&start=${_userLocation!.longitude},${_userLocation!.latitude}&end=${photo.lng},${photo.lat}';

//     final response = await http.get(Uri.parse(url));

//     if (response.statusCode == 200) {
//       final data = jsonDecode(response.body);
//       final coordinates =
//           data['features'][0]['geometry']['coordinates'] as List;

//       setState(() {
//         _routePoints =
//             coordinates
//                 .map((c) => LatLng(c[1] as double, c[0] as double))
//                 .toList();
//         _enableMapRotation = true; // 🔁 enable map rotation
//       });
//     } else {
//       debugPrint("❌ Route fetch failed: ${response.statusCode}");
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text("Could not fetch route.")));
//     }
//   }

//   void _drawPublicTransitRoute(PhotoModel photo) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text("Public transit support coming soon.")),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           "Explore Memories",
//           style: Theme.of(context).textTheme.titleLarge?.copyWith(
//             color: Theme.of(context).colorScheme.onPrimary,
//           ),
//         ),
//         backgroundColor: Theme.of(context).colorScheme.primary,
//         iconTheme: IconThemeData(
//           color: Theme.of(context).colorScheme.onPrimary,
//         ),
//         bottom: PreferredSize(
//           preferredSize: const Size.fromHeight(56),
//           child: Padding(
//             padding: const EdgeInsets.all(8),
//             child: TextField(
//               controller: _searchController,
//               onSubmitted: _searchPlace,
//               style: TextStyle(
//                 color: Theme.of(context).colorScheme.onBackground,
//               ),
//               decoration: InputDecoration(
//                 hintText: "Search a city or place...",
//                 hintStyle: TextStyle(
//                   color: Theme.of(
//                     context,
//                   ).colorScheme.onBackground.withOpacity(0.6),
//                 ),
//                 prefixIcon: Icon(
//                   Icons.search,
//                   color: Theme.of(context).colorScheme.onBackground,
//                 ),
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 filled: true,
//                 fillColor: Theme.of(context).colorScheme.surface,
//               ),
//             ),
//           ),
//         ),
//       ),

//       body: Stack(
//         children: [
//           FlutterMap(
//             mapController: _mapController,
//             options: MapOptions(
//               initialCenter: _userLocation ?? const LatLng(20.5937, 78.9629),
//               initialZoom: 4.5,
//               interactionOptions: const InteractionOptions(
//                 flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
//               ),
//             ),
//             children: [
//               TileLayer(
//                 urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
//                 userAgentPackageName: 'com.memscape.app',
//               ),
//               MarkerLayer(
//                 markers: [
//                   if (_userLocation != null)
//                     Marker(
//                       point: _userLocation!,
//                       width: 40,
//                       height: 40,
//                       child: Transform.rotate(
//                         angle:
//                             (_userHeading ?? 0) *
//                             (pi / 180), // Convert degrees to radians
//                         child: const Icon(
//                           Icons.navigation, // 🔺 triangle icon
//                           size: 40,
//                           color: Colors.blue,
//                         ),
//                       ),
//                     ),
//                   if (_filteredPhotos.isNotEmpty)
//                     ..._filteredPhotos.map(
//                       (photo) => Marker(
//                         point: LatLng(photo.lat!, photo.lng!),
//                         width: 40,
//                         height: 40,
//                         child: GestureDetector(
//                           onTap: () => _showMemoryDialog(context, photo),
//                           child: const Icon(
//                             Icons.location_on,
//                             size: 40,
//                             color: Colors.red,
//                           ),
//                         ),
//                       ),
//                     ),
//                 ],
//               ),
//               PolylineLayer(
//                 polylines: [
//                   if (_routePoints.isNotEmpty)
//                     Polyline(
//                       points: _routePoints,
//                       strokeWidth: 5,
//                       color: Colors.blueAccent,
//                     ),
//                 ],
//               ),
//             ],
//           ),

//           // 📜 Draggable Sheet for searched results
//           if (_showSheet && _filteredPhotos.isNotEmpty)
//             DraggableScrollableSheet(
//               initialChildSize: 0.3,
//               minChildSize: 0.2,
//               maxChildSize: 0.75,
//               builder: (context, scrollController) {
//                 final theme = Theme.of(context);
//                 final colorScheme = theme.colorScheme;

//                 return Container(
//                   decoration: BoxDecoration(
//                     color: colorScheme.background,
//                     borderRadius: const BorderRadius.vertical(
//                       top: Radius.circular(20),
//                     ),
//                     boxShadow: const [
//                       BoxShadow(blurRadius: 8, color: Colors.black26),
//                     ],
//                   ),
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Center(
//                         child: Container(
//                           width: 40,
//                           height: 4,
//                           decoration: BoxDecoration(
//                             color: colorScheme.outlineVariant,
//                             borderRadius: BorderRadius.circular(2),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 12),
//                       Text(
//                         "📍 Memories in '${_searchedCity!.toUpperCase()}'",
//                         style: theme.textTheme.titleMedium?.copyWith(
//                           fontWeight: FontWeight.bold,
//                           color: colorScheme.onBackground,
//                         ),
//                       ),
//                       const SizedBox(height: 12),
//                       Expanded(
//                         child: ListView.builder(
//                           controller: scrollController,
//                           itemCount: _filteredPhotos.length,
//                           itemBuilder: (_, index) {
//                             final photo = _filteredPhotos[index];

//                             return Card(
//                               elevation: 3,
//                               margin: const EdgeInsets.symmetric(vertical: 8),
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(16),
//                               ),
//                               color: colorScheme.surface,
//                               child: InkWell(
//                                 borderRadius: BorderRadius.circular(16),
//                                 onTap: () {
//                                   setState(() {
//                                     _routePoints = [];
//                                     _enableMapRotation =
//                                         false; // 🔁 disable map rotation
//                                   });
//                                   _mapController.rotate(0); // Reset rotation
//                                   _mapController.move(
//                                     LatLng(photo.lat!, photo.lng!),
//                                     14,
//                                   );
//                                 },
//                                 child: Column(
//                                   crossAxisAlignment:
//                                       CrossAxisAlignment.stretch,
//                                   children: [
//                                     ClipRRect(
//                                       borderRadius: const BorderRadius.vertical(
//                                         top: Radius.circular(16),
//                                       ),
//                                       child: Image.memory(
//                                         base64Decode(photo.imageBase64!),
//                                         height: 160,
//                                         fit: BoxFit.cover,
//                                       ),
//                                     ),
//                                     Padding(
//                                       padding: const EdgeInsets.all(12),
//                                       child: Column(
//                                         crossAxisAlignment:
//                                             CrossAxisAlignment.start,
//                                         children: [
//                                           Text(
//                                             photo.caption,
//                                             style: theme.textTheme.bodyLarge
//                                                 ?.copyWith(
//                                                   fontWeight: FontWeight.w600,
//                                                   color: colorScheme.onSurface,
//                                                 ),
//                                           ),
//                                           const SizedBox(height: 4),
//                                           Text(
//                                             photo.location,
//                                             style: theme.textTheme.bodyMedium
//                                                 ?.copyWith(
//                                                   color: colorScheme.outline,
//                                                 ),
//                                           ),
//                                           const SizedBox(height: 10),
//                                           SingleChildScrollView(
//                                             scrollDirection: Axis.horizontal,
//                                             child: Row(
//                                               children: [
//                                                 const SizedBox(width: 8),
//                                                 ElevatedButton.icon(
//                                                   onPressed:
//                                                       () => _drawRoute(
//                                                         'walking',
//                                                         photo,
//                                                       ),
//                                                   icon: const Icon(
//                                                     Icons.directions_walk,
//                                                   ),
//                                                   label: const Text('Walk'),
//                                                 ),
//                                                 const SizedBox(width: 8),
//                                                 ElevatedButton.icon(
//                                                   onPressed:
//                                                       () => _drawRoute(
//                                                         'cycling',
//                                                         photo,
//                                                       ),
//                                                   icon: const Icon(
//                                                     Icons.directions_bike,
//                                                   ),
//                                                   label: const Text('Bike'),
//                                                 ),
//                                                 const SizedBox(width: 8),
//                                                 ElevatedButton.icon(
//                                                   onPressed:
//                                                       () => _drawRoute(
//                                                         'driving',
//                                                         photo,
//                                                       ),
//                                                   icon: const Icon(
//                                                     Icons.directions_car,
//                                                   ),
//                                                   label: const Text('Car'),
//                                                 ),
//                                                 const SizedBox(width: 8),
//                                                 ElevatedButton.icon(
//                                                   onPressed:
//                                                       () =>
//                                                           _drawPublicTransitRoute(
//                                                             photo,
//                                                           ),
//                                                   icon: const Icon(
//                                                     Icons.directions_transit,
//                                                   ),
//                                                   label: const Text('Transit'),
//                                                 ),
//                                                 const SizedBox(width: 8),
//                                               ],
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//                       ),
//                     ],
//                   ),
//                 );
//               },
//             ),

//           // 🔵 Go to live location button (bottom right)
//           Positioned(
//             top: 20,
//             right: 20,
//             child: FloatingActionButton(
//               backgroundColor: Theme.of(context).colorScheme.primary,
//               onPressed: () {
//                 if (_userLocation != null) {
//                   _mapController.move(_userLocation!, 15.0);
//                 } else {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     const SnackBar(
//                       content: Text("Live location not available"),
//                     ),
//                   );
//                 }
//               },
//               child: const Icon(Icons.my_location, color: Colors.white),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showMemoryDialog(BuildContext context, PhotoModel photo) {
//     showDialog(
//       context: context,
//       builder:
//           (_) => AlertDialog(
//             backgroundColor: Theme.of(context).colorScheme.surface,

//             title: Text(
//               photo.caption,
//               style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
//             ),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 if (photo.imageBase64 != null && photo.imageBase64!.isNotEmpty)
//                   Image.memory(
//                     base64Decode(
//                       photo.imageBase64!,
//                     ), // safe because we checked null
//                     height: 150,
//                     fit: BoxFit.cover,
//                   ),

//                 const SizedBox(height: 10),
//                 Text("📍 ${photo.location}"),
//               ],
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(context),
//                 child: Text(
//                   "Close",
//                   style: TextStyle(
//                     color: Theme.of(context).colorScheme.primary,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//     );
//   }
// }
