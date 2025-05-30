import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String status = '';
  double lat = 0;
  double lon = 0;
  String timestamp = '';
  List<String> hospitals = [];
  late MapController mapController;
  LatLng? fallLocation;
  bool esp32Online = false;

  void listenToFallData() {
    final dbRef = FirebaseDatabase.instance.ref();

    dbRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;

        final fall = data['fall_detection'] as Map?;
        final double newLat = (fall?['location']['lat'] ?? 0) * 1.0;
        final double newLon = (fall?['location']['lon'] ?? 0) * 1.0;

        // Ambil last_seen dari Firebase
        lastSeenEpoch = (data['esp32']?['last_seen'] ?? 0);

        setState(() {
          status = fall?['status'] ?? '';
          lat = newLat;
          lon = newLon;
          timestamp = fall?['timestamp'] ?? '';
          fallLocation = LatLng(newLat, newLon);
          // Jangan set esp32Online langsung dari Firebase bool,
          // tapi dari fungsi pengecekan lastSeenEpoch
          esp32Online = isEspOnline();
        });

        mapController.move(fallLocation ?? LatLng(-7.2756, 112.6416), 16.0);
        fetchNearbyHospitals();
      }
    });
  }

  bool isEspOnline() {
    if (lastSeenEpoch == 0) return false;

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastSeenEpoch;

    // Jika data terakhir lebih baru dari 15 detik yang lalu, anggap online
    return diff < 15;
  }

  void fetchNearbyHospitals() async {
    final url = Uri.parse(
      'https://overpass-api.de/api/interpreter?data=[out:json];node[amenity=hospital](around:3000,$lat,$lon);out;',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final elements = data['elements'] as List;

      setState(() {
        hospitals = elements
            .map((e) => e['tags']?['name'] ?? 'Unnamed Hospital')
            .cast<String>()
            .toList();
      });
    } else {
      print('Failed to fetch hospitals');
    }
  }

  int lastSeenEpoch = 0; // simpan last_seen dari Firebase
  Timer? timer; // untuk update waktu realtime

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    listenToFallData();

    timer = Timer.periodic(Duration(seconds: 1), (_) {
      setState(() {
        esp32Online = isEspOnline();
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackLocation = LatLng(-7.2756, 112.6416); // Default to Surabaya

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Fall Detection UI')),
        body: Column(
          children: [
            Expanded(
              flex: 2,
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: fallLocation ?? fallbackLocation,
                  initialZoom: 16.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.app',
                  ),
                  if (fallLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 40.0,
                          height: 40.0,
                          point: fallLocation!,
                          child: const Icon(
                            Icons.location_on,
                            size: 40,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.devices, size: 30),
                        const SizedBox(width: 10),
                        Text(
                          'ESP32: ${esp32Online ? 'Online' : 'Offline'}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: esp32Online ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Nearby Hospitals:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...hospitals.map((name) => Text('- $name')).toList(),
                    const SizedBox(height: 20),
                    Text('Status: $status'),
                    Text('Waktu: $timestamp'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
