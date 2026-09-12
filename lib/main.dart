import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() {
  runApp(const BeaconApp());
}

class BeaconApp extends StatelessWidget {
  const BeaconApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BeaconHome(),
    );
  }
}

class BeaconHome extends StatefulWidget {
  const BeaconHome({super.key});

  @override
  State<BeaconHome> createState() => _BeaconHomeState();
}

// Holds all data for one beacon device
class BeaconData {
  String data;
  String rawData;
  String deviceName;
  int rssi;
  DateTime? lastSeen;

  BeaconData({
    required String waitingName,
  })  : data = "Waiting for $waitingName...",
        rawData = "Waiting for raw data...",
        deviceName = "Unknown",
        rssi = 0,
        lastSeen = null;
}

class _BeaconHomeState extends State<BeaconHome> {
  final FlutterReactiveBle ble = FlutterReactiveBle();

  // Total number of beacon devices
  static const int _beaconCount = 10;

  // Device names: Attest_0000 .. Attest_0009
  static List<String> get _beaconNames => List.generate(
        _beaconCount,
        (i) => 'Attest_${i.toString().padLeft(4, '0')}',
      );

  // Map: device name -> BeaconData
  late final Map<String, BeaconData> _beacons;

  // Timer for UI updates
  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();

    // Initialise beacon map
    _beacons = {
      for (final name in _beaconNames) name: BeaconData(waitingName: name),
    };

    initBle();

    // Start periodic timer to update UI for timeouts
    _cleanupTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  int _crc16Ccitt(List<int> data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= (byte << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  String bytesToHex(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  Future<void> initBle() async {
    await Permission.location.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();

    ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      // Filter by manufacturer data with company ID 0x0A0B
      if (device.manufacturerData.isNotEmpty &&
          device.manufacturerData.length >= 22) {
        // Check if company ID is 0x0A0B (first 2 bytes)
        if (device.manufacturerData[0] == 0x0A &&
            device.manufacturerData[1] == 0x0B) {
          // Strict name check - only process known beacon names
          if (!_beacons.containsKey(device.name)) {
            return;
          }

          // Validate CRC
          try {
            // Manufacturer data structure:
            // Byte 0-1:  Company ID (0x0A0B)
            // Byte 2-19: Payload (ID:XX T:YYYYYYYYYY) - 18 bytes
            // Byte 20-21: CRC16 (Low byte, High byte)
            //
            // CRC is calculated over the first 20 bytes (incl. Company ID)

            List<int> dataForCrc = device.manufacturerData.sublist(0, 20);
            int calculatedCrc = _crc16Ccitt(dataForCrc);

            int receivedCrc =
                device.manufacturerData[20] | (device.manufacturerData[21] << 8);

            if (calculatedCrc != receivedCrc) {
              // CRC mismatch, ignore packet
              print("CRC Mismatch: Calc $calculatedCrc vs Recv $receivedCrc");
              return;
            }

            // CRC is valid, process data
            // Payload starts at byte 2, length 18 bytes
            String payload =
                String.fromCharCodes(device.manufacturerData.sublist(2, 20));
            final hex = bytesToHex(device.manufacturerData);

            setState(() {
              final beacon = _beacons[device.name]!;
              beacon.data = payload;
              beacon.rawData = hex;
              beacon.deviceName = device.name;
              beacon.rssi = device.rssi;
              beacon.lastSeen = DateTime.now();
            });
          } catch (e) {
            print("Error processing beacon data: $e");
          }
        }
      }
    });
  }

  /// Returns status text and colour for a beacon based on last-seen time.
  (String, Color) _beaconStatus(BeaconData beacon) {
    if (beacon.lastSeen == null) {
      return ("Waiting...", Colors.grey);
    } else if (DateTime.now().difference(beacon.lastSeen!).inSeconds < 12) {
      return ("Active", Colors.green);
    } else {
      return ("Inactive", Colors.red);
    }
  }

  /// Builds one collapsible section (ExpansionTile) for a single beacon.
  Widget _buildBeaconSection(String beaconTitle, BeaconData beacon) {
    final (statusText, statusColor) = _beaconStatus(beacon);

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: statusColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // ── Header (always visible) ──────────────────────────────────────
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          beaconTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Default expand/collapse arrow is still rendered by ExpansionTile
          ],
        ),
        // ── Expanded body ────────────────────────────────────────────────
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          _infoRow("Device Name", beacon.deviceName),
          const SizedBox(height: 8),
          _infoRow("Decoded Data", beacon.data),
          const SizedBox(height: 8),
          _infoRow("Raw HEX", beacon.rawData),
          const SizedBox(height: 8),
          _infoRow("Signal Strength", "${beacon.rssi} dBm"),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// Helper: label + value row used inside an expanded section.
  Widget _infoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label:",
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Beacon App"),
        centerTitle: true,
      ),
      // ListView.builder keeps only visible tiles in memory
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _beaconNames.length,
        itemBuilder: (context, index) {
          final name = _beaconNames[index];
          return _buildBeaconSection(name, _beacons[name]!);
        },
      ),
    );
  }
}
