import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Run with: flutter run --dart-define=MAPS_KEY=YOUR_KEY
const mapsKey = String.fromEnvironment('MAPS_KEY');

void main() => runApp(const RideCompareApp());

class RideCompareApp extends StatelessWidget {
  const RideCompareApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ride Fare Compare',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0F766E), useMaterial3: true),
        home: const HomePage(),
      );
}

// ---------- Models ----------
class Place {
  final String name;
  final double lat, lng;
  Place(this.name, this.lat, this.lng);
}

class Suggestion {
  final String id, text;
  Suggestion(this.id, this.text);
}

class Rate {
  final String provider, type, key;
  final double base, perKm, perMin, minFare;
  const Rate(this.provider, this.type, this.key, this.base, this.perKm, this.perMin, this.minFare);
}

// Sample rates. Edit these to match what you see in the real apps.
const rates = [
  Rate('Uber', 'Go (cab)', 'uber', 45, 11, 1, 70),
  Rate('Uber', 'Auto', 'uber', 30, 8, 0.5, 40),
  Rate('Uber', 'Moto', 'uber', 20, 5.5, 0.4, 30),
  Rate('Ola', 'Mini (cab)', 'ola', 45, 12, 1, 75),
  Rate('Ola', 'Auto', 'ola', 30, 8.5, 0.5, 40),
  Rate('Ola', 'Bike', 'ola', 20, 5, 0.4, 30),
  Rate('Rapido', 'Cab', 'rapido', 45, 11, 0.8, 70),
  Rate('Rapido', 'Auto', 'rapido', 30, 8, 0.5, 40),
  Rate('Rapido', 'Bike', 'rapido', 20, 5, 0.4, 30),
];

// ---------- Google APIs (Places API New + Routes API) ----------
class Maps {
  static Future<List<Suggestion>> autocomplete(String input) async {
    final r = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
      headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': mapsKey},
      body: jsonEncode({'input': input, 'includedRegionCodes': ['in']}),
    );
    if (r.statusCode != 200) throw Exception('Places error ${r.statusCode}');
    final list = (jsonDecode(r.body)['suggestions'] ?? []) as List;
    return list
        .where((s) => s['placePrediction'] != null)
        .map((s) => Suggestion(s['placePrediction']['placeId'], s['placePrediction']['text']['text']))
        .toList();
  }

  static Future<Place> details(Suggestion s) async {
    final r = await http.get(
      Uri.parse('https://places.googleapis.com/v1/places/${s.id}'),
      headers: {'X-Goog-Api-Key': mapsKey, 'X-Goog-FieldMask': 'location'},
    );
    if (r.statusCode != 200) throw Exception('Place details error ${r.statusCode}');
    final loc = jsonDecode(r.body)['location'];
    return Place(s.text, loc['latitude'], loc['longitude']);
  }

  // Returns (km, minutes)
  static Future<(double, int)> route(Place a, Place b) async {
    final r = await http.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': mapsKey,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration',
      },
      body: jsonEncode({
        'origin': {'location': {'latLng': {'latitude': a.lat, 'longitude': a.lng}}},
        'destination': {'location': {'latLng': {'latitude': b.lat, 'longitude': b.lng}}},
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
      }),
    );
    if (r.statusCode != 200) throw Exception('Routes error ${r.statusCode}');
    final route = (jsonDecode(r.body)['routes'] as List).first;
    final km = (route['distanceMeters'] as num) / 1000;
    final secs = int.parse((route['duration'] as String).replaceAll('s', ''));
    return (km.toDouble(), (secs / 60).round());
  }
}

// ---------- Deep links ----------
Uri bookingLink(String key, Place a, Place b) {
  switch (key) {
    case 'uber':
      return Uri.parse('https://m.uber.com/ul/?action=setPickup'
          '&pickup[latitude]=${a.lat}&pickup[longitude]=${a.lng}&pickup[nickname]=${Uri.encodeComponent(a.name)}'
          '&dropoff[latitude]=${b.lat}&dropoff[longitude]=${b.lng}&dropoff[nickname]=${Uri.encodeComponent(b.name)}');
    case 'ola':
      return Uri.parse('https://olawebcdn.com/assets/ola-universal-link.html'
          '?lat=${a.lat}&lng=${a.lng}&drop_lat=${b.lat}&drop_lng=${b.lng}&landmark=${Uri.encodeComponent(a.name)}');
    default:
      return Uri.parse('https://www.rapido.bike/'); // no public deep link
  }
}

// ---------- UI ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Place? from, to;
  double? km;
  int? mins;
  bool loading = false;
  String? error;

  Future<void> compare() async {
    if (from == null || to == null) {
      setState(() => error = 'Choose both pickup and drop from the suggestions.');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final (d, m) = await Maps.route(from!, to!);
      setState(() { km = d; mins = m; });
    } catch (e) {
      setState(() => error = 'Could not get the route. Check your API key and internet. ($e)');
    } finally {
      setState(() => loading = false);
    }
  }

  List<(Rate, double)> get fares {
    final list = rates
        .map((r) => (r, (r.base + r.perKm * km! + r.perMin * mins!).clamp(r.minFare, double.infinity)))
        .toList();
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Fare Compare')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        PlaceField(label: 'Pickup', onPicked: (p) => from = p),
        const SizedBox(height: 12),
        PlaceField(label: 'Drop', onPicked: (p) => to = p),
        const SizedBox(height: 12),
        FilledButton(onPressed: loading ? null : compare, child: Text(loading ? 'Loading...' : 'Compare fares')),
        if (error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (km != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('${km!.toStringAsFixed(1)} km, $mins min', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final (i, f) in fares.indexed)
            Card(
              shape: i == 0
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFF5C542), width: 2))
                  : null,
              child: ListTile(
                title: Text('${f.$1.provider}${i == 0 ? "  (cheapest)" : ""}'),
                subtitle: Text(f.$1.type),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('₹${(f.$2 * 0.92 / 5).round() * 5}-${(f.$2 * 1.08 / 5).round() * 5}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => launchUrl(bookingLink(f.$1.key, from!, to!), mode: LaunchMode.externalApplication),
                    child: const Text('Book'),
                  ),
                ]),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Fares are estimates from sample rates, not live prices.', style: TextStyle(fontSize: 12)),
          ),
        ],
      ]),
    );
  }
}

class PlaceField extends StatefulWidget {
  final String label;
  final void Function(Place?) onPicked;
  const PlaceField({super.key, required this.label, required this.onPicked});
  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final ctrl = TextEditingController();
  List<Suggestion> options = [];
  Timer? debounce;

  void onChanged(String text) {
    widget.onPicked(null); // typing again clears the old pick
    debounce?.cancel();
    if (text.length < 3) { setState(() => options = []); return; }
    debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Maps.autocomplete(text);
        if (mounted) setState(() => options = r);
      } catch (_) {}
    });
  }

  Future<void> pick(Suggestion s) async {
    ctrl.text = s.text;
    setState(() => options = []);
    try {
      widget.onPicked(await Maps.details(s));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
        ),
        for (final o in options)
          ListTile(dense: true, leading: const Icon(Icons.place_outlined), title: Text(o.text), onTap: () => pick(o)),
      ]);
}
