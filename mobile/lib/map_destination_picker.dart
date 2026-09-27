import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'destination_search_service.dart';
import 'api_service.dart';
import 'map_tile_config.dart';

class MapDestinationPicker extends StatefulWidget {
  const MapDestinationPicker({super.key, this.initial});

  final DestinationSuggestion? initial;

  @override
  State<MapDestinationPicker> createState() => _MapDestinationPickerState();
}

class _MapDestinationPickerState extends State<MapDestinationPicker> {
  late LatLng selected;
  String? placeName;
  bool resolving = false;
  final searchService = DestinationSearchService(baseUrl: ApiService().baseUrl);

  @override
  void initState() {
    super.initState();
    selected = widget.initial == null ? const LatLng(0, 0) : LatLng(widget.initial!.latitude, widget.initial!.longitude);
    placeName = widget.initial?.displayName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose destination'), actions: [IconButton(onPressed: () => Navigator.pop(context), tooltip: 'Cancel', icon: const Icon(Icons.close))]),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: selected, initialZoom: 13, onTap: (_, point) => selectPoint(point)),
            children: [
              TileLayer(urlTemplate: MapTileConfig.urlTemplate, userAgentPackageName: 'com.example.disaster_routing_mobile'),
              MarkerLayer(markers: [Marker(point: selected, width: 48, height: 48, child: const Icon(Icons.location_pin, size: 48, color: Colors.red))]),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(resolving ? 'Resolving selected address...' : placeName ?? 'Tap the map to choose a destination', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${selected.latitude.toStringAsFixed(5)}, ${selected.longitude.toStringAsFixed(5)}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () => Navigator.pop(context, DestinationSuggestion(name: placeName ?? 'Map destination', displayName: placeName ?? 'Map destination', latitude: selected.latitude, longitude: selected.longitude)), icon: const Icon(Icons.check), label: const Text('Use This Location')),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> selectPoint(LatLng point) async {
    setState(() { selected = point; placeName = null; resolving = true; });
    try {
      final result = await searchService.reverse(point.latitude, point.longitude);
      if (mounted && selected == point) setState(() => placeName = result.displayName);
    } catch (_) {
      // Coordinates remain usable when reverse geocoding is unavailable.
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  void dispose() {
    searchService.dispose();
    super.dispose();
  }
}
