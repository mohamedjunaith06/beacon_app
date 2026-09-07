import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'graph_page.dart';

class PacketStatus {
  final int counter;
  final DateTime timestamp;
  final bool received;

  const PacketStatus({
    required this.counter,
    required this.timestamp,
    required this.received,
  });
}

class PacketHistoryProvider extends ChangeNotifier {
  final List<PacketStatus> history = [];
  int? firstBeaconCounter;
  DateTime? startTime;

  void addPacket(PacketStatus packet) {
    history.add(packet);
    notifyListeners();
  }

  void setPacket(int index, PacketStatus packet) {
    if (index >= history.length) {
      while (history.length < index) {
        history.add(PacketStatus(
          counter: firstBeaconCounter! + history.length,
          timestamp: startTime!.add(Duration(seconds: history.length * 2)),
          received: false,
        ));
      }
      history.add(packet);
    } else {
      history[index] = packet;
    }
    notifyListeners();
  }

  void clear() {
    history.clear();
    firstBeaconCounter = null;
    startTime = null;
    notifyListeners();
  }
}


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

class _BeaconHomeState extends State<BeaconHome> {
  final FlutterReactiveBle ble = FlutterReactiveBle();

  // Data for Attest
  int attestCounter = 0;
  int attestIncomingCounter = 0;
  String attestRawData = "Waiting for raw data...";
  String attestDeviceName = "Unknown";
  int attestRssi = 0;
  DateTime? attestLastSeen;
  String attestStatus = "Waiting...";

  // Packet tracking for the graph
  final PacketHistoryProvider packetHistoryProvider = PacketHistoryProvider();
  Timer? _slotCheckerTimer;

  // Timer for UI updates
  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();
    initBle();
    // Start periodic timer to update UI for timeouts
    _cleanupTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
    // Start periodic timer to check for missed packet slots (runs every 1 second)
    _slotCheckerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkSlots();
    });
  }

  void _checkSlots() {
    if (packetHistoryProvider.firstBeaconCounter == null || packetHistoryProvider.startTime == null) return;

    final now = DateTime.now();
    final elapsedMs = now.difference(packetHistoryProvider.startTime!).inMilliseconds;

    // We expect a packet every 2 seconds.
    // If the elapsed time has passed the slot expected time by more than 1 second,
    // we assume it hasn't been received and fill it as Inactive (received: false).
    int maxExpectedSlot = (elapsedMs - 1000) ~/ 2000;
    if (maxExpectedSlot < 0) maxExpectedSlot = 0;

    while (packetHistoryProvider.history.length <= maxExpectedSlot) {
      packetHistoryProvider.addPacket(PacketStatus(
        counter: packetHistoryProvider.firstBeaconCounter! + packetHistoryProvider.history.length,
        timestamp: packetHistoryProvider.startTime!.add(Duration(seconds: packetHistoryProvider.history.length * 2)),
        received: false,
      ));
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _slotCheckerTimer?.cancel();
    super.dispose();
  }

  int _simpleAuthTag(List<int> data, List<int> key) {
    int tag = 0;
    for (int i = 0; i < data.length; i++) {
      tag = (tag ^ (data[i] << ((i % 4) * 8))) & 0xFFFFFFFF;
      tag = (((tag << 5) & 0xFFFFFFFF) | (tag >> 27)) & 0xFFFFFFFF;
      tag = (tag + key[i % 4]) & 0xFFFFFFFF;
    }
    return tag;
  }

  String bytesToHex(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  final List<int> _xteaKey = [0x01020304, 0x05060708, 0x090A0B0C, 0x0D0E0F10];
  final List<int> _authKey = [0x11223344, 0x55667788, 0x99AABBCC, 0xDDEEFF00];

  void _xteaEncrypt(int numRounds, List<int> v, List<int> key) {
    int v0 = v[0] & 0xFFFFFFFF;
    int v1 = v[1] & 0xFFFFFFFF;
    int sum = 0;
    const int delta = 0x9E3779B9;
    
    for (int i = 0; i < numRounds; i++) {
      int term1 = (((v1 << 4) ^ (v1 >> 5)) + v1) & 0xFFFFFFFF;
      int term2 = (sum + key[sum & 3]) & 0xFFFFFFFF;
      v0 = (v0 + (term1 ^ term2)) & 0xFFFFFFFF;
      
      sum = (sum + delta) & 0xFFFFFFFF;
      
      int term3 = (((v0 << 4) ^ (v0 >> 5)) + v0) & 0xFFFFFFFF;
      int term4 = (sum + key[(sum >> 11) & 3]) & 0xFFFFFFFF;
      v1 = (v1 + (term3 ^ term4)) & 0xFFFFFFFF;
    }
    v[0] = v0;
    v[1] = v1;
  }

  void _xteaCtrCrypt(List<int> data, List<int> key, List<int> iv) {
    List<int> keystream = List.filled(16, 0);
    List<int> v = List.filled(2, 0);
    
    for (int block = 0; block < 2; block++) {
      v[0] = (iv[0] | (iv[1] << 8) | (iv[2] << 16) | (iv[3] << 24)) & 0xFFFFFFFF;
      v[1] = (iv[4] | (iv[5] << 8) | (iv[6] << 16) | (iv[7] << 24)) & 0xFFFFFFFF;
      v[0] = (v[0] + block) & 0xFFFFFFFF;
      
      _xteaEncrypt(32, v, key);
      
      keystream[block * 8 + 0] = (v[0] >> 0) & 0xFF;
      keystream[block * 8 + 1] = (v[0] >> 8) & 0xFF;
      keystream[block * 8 + 2] = (v[0] >> 16) & 0xFF;
      keystream[block * 8 + 3] = (v[0] >> 24) & 0xFF;
      keystream[block * 8 + 4] = (v[1] >> 0) & 0xFF;
      keystream[block * 8 + 5] = (v[1] >> 8) & 0xFF;
      keystream[block * 8 + 6] = (v[1] >> 16) & 0xFF;
      keystream[block * 8 + 7] = (v[1] >> 24) & 0xFF;
    }
    
    for (int i = 0; i < data.length; i++) {
      data[i] ^= keystream[i];
    }
  }

  Future<void> initBle() async {
    await Permission.location.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();

    ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      // Filter by manufacturer data length
      if (device.manufacturerData.isNotEmpty && device.manufacturerData.length >= 24) {
        // Strict name check - only process if name matches exactly
        bool isAttest = device.name == "Attest_0005";
        
        if (!isAttest) {
          return;
        }

        try {
          // Extract the first 20 bytes (IV + encrypted payload)
          List<int> signedData = List<int>.from(device.manufacturerData.sublist(0, 20));
          
          // Verify Authentication Tag over the first 20 bytes
          int calculatedTag = _simpleAuthTag(signedData, _authKey);
          int receivedTag = (device.manufacturerData[20] |
                            (device.manufacturerData[21] << 8) |
                            (device.manufacturerData[22] << 16) |
                            (device.manufacturerData[23] << 24)) & 0xFFFFFFFF;
          
          if (calculatedTag != receivedTag) {
            debugPrint("Auth Tag Mismatch: Calc $calculatedTag vs Recv $receivedTag");
            return;
          }

          // Extract IV (first 8 bytes)
          List<int> iv = List<int>.from(device.manufacturerData.sublist(0, 8));

          // Extract encrypted payload (next 12 bytes)
          List<int> encryptedPayload = List<int>.from(device.manufacturerData.sublist(8, 20));

          // Decrypt the payload
          List<int> decryptedPayload = List<int>.from(encryptedPayload);
          _xteaCtrCrypt(decryptedPayload, _xteaKey, iv);

          // Extract iv32 (first 4 bytes of IV)
          int iv32 = (iv[0] | (iv[1] << 8) | (iv[2] << 16) | (iv[3] << 24)) & 0xFFFFFFFF;

          // Recover beacon counter
          int counterObfuscated = (decryptedPayload[0] |
                                   (decryptedPayload[1] << 8) |
                                   (decryptedPayload[2] << 16) |
                                   (decryptedPayload[3] << 24)) & 0xFFFFFFFF;
          
          int beaconCounter = (counterObfuscated ^ iv32 ^ 0xA5A5A5A5) & 0xFFFFFFFF;

          final hex = bytesToHex(device.manufacturerData);

          setState(() {
            attestLastSeen = DateTime.now();
            attestDeviceName = device.name;
            attestRssi = device.rssi;
            attestRawData = hex;
            attestIncomingCounter = beaconCounter;

            if (beaconCounter >= attestCounter) {
              attestCounter = beaconCounter;
              attestStatus = "Valid counter";
            } else {
              attestStatus = "Invalid counter";
            }

            // Packet tracking logic
            if (packetHistoryProvider.firstBeaconCounter == null) {
              packetHistoryProvider.clear();
              packetHistoryProvider.firstBeaconCounter = beaconCounter;
              packetHistoryProvider.startTime = DateTime.now();
              packetHistoryProvider.addPacket(PacketStatus(
                counter: beaconCounter,
                timestamp: packetHistoryProvider.startTime!,
                received: true,
              ));
            } else {
              if (beaconCounter < packetHistoryProvider.firstBeaconCounter!) {
                packetHistoryProvider.clear();
                packetHistoryProvider.firstBeaconCounter = beaconCounter;
                packetHistoryProvider.startTime = DateTime.now();
                packetHistoryProvider.addPacket(PacketStatus(
                  counter: beaconCounter,
                  timestamp: packetHistoryProvider.startTime!,
                  received: true,
                ));
              } else {
                int slotIndex = beaconCounter - packetHistoryProvider.firstBeaconCounter!;
                packetHistoryProvider.setPacket(slotIndex, PacketStatus(
                  counter: beaconCounter,
                  timestamp: packetHistoryProvider.startTime!.add(Duration(seconds: slotIndex * 2)),
                  received: true,
                ));
              }
            }
          });
        } catch (e) {
          debugPrint("Error processing beacon data: $e");
        }
      }
    });
  }

  Widget _buildBeaconCard(
    String beaconTitle,
    String deviceName,
    String storedCounter,
    String incomingCounter,
    String rawData,
    int rssi,
    DateTime? lastSeen,
    String validationStatus,
  ) {
    // 1. Resolve Activity Status
    String activityText;
    Color activityColor;
    if (lastSeen == null) {
      activityText = "Waiting...";
      activityColor = Colors.grey;
    } else if (DateTime.now().difference(lastSeen).inSeconds < 8) {
      activityText = "Active";
      activityColor = Colors.green;
    } else {
      activityText = "Inactive";
      activityColor = Colors.red;
    }

    // 2. Resolve Counter Status
    String counterText;
    Color counterColor;
    if (lastSeen == null) {
      counterText = "Waiting...";
      counterColor = Colors.grey;
    } else {
      counterText = validationStatus;
      if (counterText == "Valid counter") {
        counterColor = Colors.teal;
      } else if (counterText == "Invalid counter") {
        counterColor = Colors.orange;
      } else {
        counterColor = Colors.blue;
      }
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: activityColor,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  beaconTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    // Activity Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: activityColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        activityText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Counter Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: counterColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        counterText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "Device Name:",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(deviceName),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Last Valid Counter:",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        storedCounter,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Incoming Counter:",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        incomingCounter,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "Raw Manufacturer Data (HEX):",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(rawData),
            const SizedBox(height: 12),
            const Text(
              "Signal Strength:",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text("$rssi dBm"),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Beacon_Rel_2"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'View Packet Graph',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GraphPage(
                    packetHistoryProvider: packetHistoryProvider,
                    onClear: () {
                      setState(() {
                        packetHistoryProvider.clear();
                        attestCounter = 0;
                        attestIncomingCounter = 0;
                        attestStatus = "Waiting...";
                        attestLastSeen = null;
                        attestDeviceName = "Unknown";
                        attestRawData = "Waiting for raw data...";
                        attestRssi = 0;
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBeaconCard(
              "Attest_0005",
              attestDeviceName,
              attestCounter.toString(),
              attestIncomingCounter.toString(),
              attestRawData,
              attestRssi,
              attestLastSeen,
              attestStatus,
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    attestCounter = 0;
                    attestIncomingCounter = 0;
                    attestStatus = "Waiting...";
                    attestLastSeen = null;
                    attestDeviceName = "Unknown";
                    attestRawData = "Waiting for raw data...";
                    attestRssi = 0;
                    packetHistoryProvider.clear();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text(
                  "Reset Counter",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
