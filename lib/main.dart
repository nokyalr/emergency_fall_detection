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

  // Check if Firebase is already initialized to prevent duplicate app error
  try {
    // For Android, Firebase will be initialized automatically from google-services.json
    // For Web, we need to provide the configuration manually
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyD4X5U4LJlGJkYgC_AcOpzNjzwOuvTRqTo",
          authDomain: "emergencyfalldetection-725cb.firebaseapp.com",
          databaseURL:
              "https://emergencyfalldetection-725cb-default-rtdb.asia-southeast1.firebasedatabase.app",
          projectId: "emergencyfalldetection-725cb",
          storageBucket: "emergencyfalldetection-725cb.firebasestorage.app",
          messagingSenderId: "964017094902",
          appId: "1:964017094902:web:048ac99123e77189e06cd7",
          measurementId: "G-QNR00LVH5E",
        ),
      );
    }
  } catch (e) {
    print('Firebase initialization error: $e');
  }

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
  int stateCode = 0; // 0=Normal, 1=Abnormal, 2=Fall
  double accelMagnitude = 0.0;
  double movementVariance = 0.0;
  int lastSeenEpoch = 0;
  Timer? timer;
  StreamSubscription<DatabaseEvent>? _databaseSubscription;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    listenToFallData();

    // Update status ESP32 setiap detik
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          esp32Online = isEspOnline();
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _databaseSubscription?.cancel();
    super.dispose();
  }

  void listenToFallData() {
    final dbRef = FirebaseDatabase.instance.ref();

    _databaseSubscription = dbRef.onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        final data = event.snapshot.value as Map;

        final fall = data['fall_detection'] as Map?;
        final esp32Data = data['esp32'] as Map?;

        final double newLat = (fall?['location']['lat'] ?? 0) * 1.0;
        final double newLon = (fall?['location']['lon'] ?? 0) * 1.0;

        // Ambil last_seen dari Firebase
        lastSeenEpoch = (esp32Data?['last_seen'] ?? 0);

        setState(() {
          status = fall?['status'] ?? '';
          lat = newLat;
          lon = newLon;
          timestamp = fall?['timestamp'] ?? '';
          stateCode = fall?['state_code'] ?? 0;
          accelMagnitude = (fall?['accel_magnitude'] ?? 0.0) * 1.0;
          movementVariance = (fall?['movement_variance'] ?? 0.0) * 1.0;
          fallLocation = (newLat != 0 && newLon != 0)
              ? LatLng(newLat, newLon)
              : null;
          esp32Online = isEspOnline();
        });

        // Hanya cari rumah sakit jika ada lokasi valid
        if (fallLocation != null) {
          fetchNearbyHospitals();
        }
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

  String getTimeSinceLastSeen() {
    if (lastSeenEpoch == 0) return 'Never';

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastSeenEpoch;

    if (diff < 60) return '${diff}s ago';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    return '${diff ~/ 3600}h ago';
  }

  void fetchNearbyHospitals() async {
    if (lat == 0 && lon == 0) return; // Skip jika lokasi tidak valid

    final url = Uri.parse(
      'https://overpass-api.de/api/interpreter?data=[out:json];node[amenity=hospital](around:3000,$lat,$lon);out;',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        if (mounted) {
          setState(() {
            hospitals = elements
                .map((e) => e['tags']?['name'] ?? 'Unnamed Hospital')
                .cast<String>()
                .toList();
          });
        }
      } else {
        print('Failed to fetch hospitals: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching hospitals: $e');
    }
  }

  Color getStatusColor() {
    switch (stateCode) {
      case 0:
        return Colors.green; // Normal
      case 1:
        return Colors.orange; // Abnormal
      case 2:
        return Colors.red; // Fall
      default:
        return Colors.grey;
    }
  }

  String getStatusDisplayText() {
    switch (stateCode) {
      case 0:
        return 'NORMAL';
      case 1:
        return 'ABNORMAL MOVEMENT';
      case 2:
        return 'FALL DETECTED';
      default:
        return status.isEmpty ? 'UNKNOWN' : status;
    }
  }

  IconData getStatusIcon() {
    switch (stateCode) {
      case 0:
        return Icons.check_circle;
      case 1:
        return Icons.warning;
      case 2:
        return Icons.emergency;
      default:
        return Icons.help;
    }
  }

  void centerMapToGPS() {
    if (fallLocation != null) {
      mapController.move(fallLocation!, 16.0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Map centered to GPS location'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackLocation = LatLng(-7.2756, 112.6416); // Default to Surabaya

    return MaterialApp(
      title: 'Fall Detection Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Fall Detection Monitor'),
          actions: [
            // Manual center to GPS
            if (fallLocation != null)
              IconButton(
                onPressed: centerMapToGPS,
                icon: const Icon(Icons.my_location),
                tooltip: 'Center to GPS Location',
              ),
          ],
        ),
        body: Column(
          children: [
            // Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              color: getStatusColor().withOpacity(0.1),
              child: Row(
                children: [
                  Icon(getStatusIcon(), color: getStatusColor(), size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          getStatusDisplayText(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: getStatusColor(),
                          ),
                        ),
                        if (timestamp.isNotEmpty)
                          Text(
                            'Last update: $timestamp',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Map
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
                    userAgentPackageName: 'com.example.falldetection',
                  ),
                  if (fallLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 50.0,
                          height: 50.0,
                          point: fallLocation!,
                          child: Container(
                            decoration: BoxDecoration(
                              color: getStatusColor(),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: Icon(
                              getStatusIcon(),
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Info Panel
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ESP32 Status
                      Row(
                        children: [
                          Icon(
                            esp32Online ? Icons.wifi : Icons.wifi_off,
                            color: esp32Online ? Colors.green : Colors.red,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ESP32: ${esp32Online ? 'Online' : 'Offline'}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: esp32Online ? Colors.green : Colors.red,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Last seen: ${getTimeSinceLastSeen()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Sensor Data
                      if (esp32Online) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.speed,
                              size: 20,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Acceleration: ${accelMagnitude.toStringAsFixed(2)} m/s²',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.analytics,
                              size: 20,
                              color: Colors.purple,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Movement Variance: ${movementVariance.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Location Info
                      if (fallLocation != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 20,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Location: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Nearby Hospitals - hanya tampil saat fall detected (state code 2)
                      if (hospitals.isNotEmpty && stateCode == 2) ...[
                        const Row(
                          children: [
                            Icon(
                              Icons.local_hospital,
                              size: 20,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Nearby Hospitals:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...hospitals
                            .take(5)
                            .map(
                              (name) => Padding(
                                padding: const EdgeInsets.only(
                                  left: 28,
                                  bottom: 4,
                                ),
                                child: Text(
                                  '• $name',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            )
                            .toList(),
                        if (hospitals.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(left: 28),
                            child: Text(
                              '... and ${hospitals.length - 5} more',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],

                      // Emergency Instructions
                      if (stateCode == 2) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            border: Border.all(color: Colors.red[200]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.emergency,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'EMERGENCY PROTOCOL',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                '1. Check on the person immediately\n'
                                '2. Call emergency services if needed',
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
