import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String status = '';
  double lat = 0;
  double lon = 0;
  String timestamp = '';

  void getFallData() async {
    final dbRef = FirebaseDatabase.instance.ref('fall_detection');
    final snapshot = await dbRef.get();

    if (snapshot.exists) {
      final data = snapshot.value as Map;

      setState(() {
        status = data['status'];
        lat = data['location']['lat'] * 1.0;
        lon = data['location']['lon'] * 1.0;
        timestamp = data['timestamp'];
      });
    } else {
      print('Data not found!');
    }
  }

  @override
  void initState() {
    super.initState();
    getFallData(); // Load data saat app dijalankan
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Fall Detection Data')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: $status'),
              Text('Latitude: $lat'),
              Text('Longitude: $lon'),
              Text('Timestamp: $timestamp'),
            ],
          ),
        ),
      ),
    );
  }
}
