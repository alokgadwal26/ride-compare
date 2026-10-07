import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
  final String text;
  final double lat, lng;
  Suggestion(this.text, this.lat, this.lng);
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

// ---------- Free map services (no API key, no billing) ----------
// Photon + Nominatim (OpenStreetMap) for address search, OSRM for road distance.
class Maps {
  static const headers = {'User-Agent': 'RideCompareApp/1.0 (personal use)'};

  static Future<List<Suggestion>> _photon(String input) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {'q': input, 'limit': '10'});
    final r = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Photon ${r.statusCode}');
    final feats = (jsonDecode(r.body)['features'] ?? []) as List;
    final out = <Suggestion>[];
    for (final f in feats) {
      final p = f['properties'] as Map<String, dynamic>;
      if (p['countrycode'] != null && p['countrycode'] != 'IN') continue;
      final c = f['geometry']['coordinates'] as List;
      final parts = <String>[
        for (final k in ['name', 'street', 'district', 'city', 'state'])
          if (p[k] != null && '${p[k]}'.isNotEmpty) '${p[k]}'
      ];
      out.add(Suggestion(parts.toSet().join(', '), (c[1] as num).toDouble(), (c[0] as num).toDouble()));
    }
    return out.take(6).toList();
  }

  static Future<List<Suggestion>> _nominatim(String input) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search',
        {'q': input, 'format': 'jsonv2', 'limit': '6', 'countrycodes': 'in'});
    final r = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Nominatim ${r.statusCode}');
    return (jsonDecode(r.body) as List)
        .map((e) => Suggestion(e['display_name'], double.parse(e['lat']), double.parse(e['lon'])))
        .toList();
  }

  // Tries Photon first, then Nominatim if Photon fails or finds nothing.
  static Future<List<Suggestion>> search(String input) async {
    String? err;
    try {
      final r = await _photon(input);
      if (r.isNotEmpty) return r;
    } catch (e) {
      err = '$e';
    }
    try {
      return await _nominatim(input);
    } catch (e) {
      throw Exception('${err ?? ""} / $e');
    }
  }

  // Returns (km, minutes)
  static Future<(double, int)> route(Place a, Place b) async {
    final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '${a.lng},${a.lat};${b.lng},${b.lat}?overview=false');
    final r = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Route error ${r.statusCode}');
    final route = (jsonDecode(r.body)['routes'] as List).first;
    final km = (route['distance'] as num) / 1000;
    final mins = ((route['duration'] as num) / 60).round();
    return (km.toDouble(), mins < 1 ? 1 : mins);
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
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  Place? from, to;
  double? km;
  int? mins;
  bool loading = false;
  String? error;

  // If the user typed but did not tap a suggestion, use the best match.
  Future<Place?> resolve(TextEditingController c, Place? picked) async {
    if (picked != null) return picked;
    final t = c.text.trim();
    if (t.length < 3) return null;
    final r = await Maps.search(t);
    if (r.isEmpty) return null;
    c.text = r.first.text;
    return Place(r.first.text, r.first.lat, r.first.lng);
  }

  Future<void> compare() async {
    FocusScope.of(context).unfocus();
    setState(() { loading = true; error = null; km = null; });
    try {
      final a = await resolve(fromCtrl, from);
      final b = await resolve(toCtrl, to);
      if (a == null || b == null) {
        setState(() => error = 'Could not find one of the places. Type a fuller name, like "Hawa Mahal Jaipur".');
        return;
      }
      from = a; to = b;
      final (d, m) = await Maps.route(a, b);
      setState(() { km = d; mins = m; });
    } catch (e) {
      setState(() => error = 'Could not get the route. Check your internet and try again. ($e)');
    } finally {
      setState(() => loading = false);
    }
  }

  List<(Rate, double)> get fares {
    final list = rates
        .map((r) => (r, (r.base + r.perKm * km! + r.perMin * mins!).clamp(r.minFare, double.infinity).toDouble()))
        .toList();
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Fare Compare')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        PlaceField(label: 'Pickup', controller: fromCtrl, onPicked: (p) => from = p),
        const SizedBox(height: 12),
        PlaceField(label: 'Drop', controller: toCtrl, onPicked: (p) => to = p),
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
  final TextEditingController controller;
  final void Function(Place?) onPicked;
  const PlaceField({super.key, required this.label, required this.controller, required this.onPicked});
  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  List<Suggestion> options = [];
  String? status;
  Timer? debounce;

  void onChanged(String text) {
    widget.onPicked(null); // typing again clears the old pick
    debounce?.cancel();
    if (text.trim().length < 3) { setState(() { options = []; status = null; }); return; }
    debounce = Timer(const Duration(milliseconds: 700), () async {
      if (mounted) setState(() => status = 'Searching...');
      try {
        final r = await Maps.search(text.trim());
        if (!mounted) return;
        setState(() { options = r; status = r.isEmpty ? 'No results. Try a fuller name.' : null; });
      } catch (e) {
        if (mounted) setState(() { options = []; status = 'Search failed. Check internet. ($e)'; });
      }
    });
  }

  void pick(Suggestion s) {
    widget.controller.text = s.text;
    setState(() { options = []; status = null; });
    widget.onPicked(Place(s.text, s.lat, s.lng));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
          controller: widget.controller,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
        ),
        if (status != null)
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.all(6), child: Text(status!, style: const TextStyle(fontSize: 12)))),
        for (final o in options)
          ListTile(dense: true, leading: const Icon(Icons.place_outlined), title: Text(o.text), onTap: () => pick(o)),
      ]);
}
