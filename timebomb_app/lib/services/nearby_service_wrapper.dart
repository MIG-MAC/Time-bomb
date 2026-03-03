import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

enum SessionState {
  notConnected,
  connecting,
  connected,
}

class Device {
  final String deviceId;
  final String deviceName;
  final String lastMessage;
  final DateTime lastSeen;

  Device({
    required this.deviceId,
    required this.deviceName,
    this.lastMessage = "",
    required this.lastSeen,
  });
}

class GameNearbyService with ChangeNotifier {
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String APP_PREFIX = "TB"; // Time Bomb Prefix

  List<Device> connectedDevices = []; // En mode Broadcast, ce sont les joueurs détectés
  List<Device> discoveredDevices = [];
  
  bool isAdvertising = false;
  bool isScanning = false;
  String? _myDeviceName;
  String _currentPayload = "IDLE";

  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  StreamSubscription? _scanSubscription;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  GameNearbyService();

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    }
    return true; // Géré nativement sur iOS
  }

  Future<void> init(String deviceName) async {
    _myDeviceName = deviceName;
    // On s'assure que le Bluetooth est prêt
    try {
      await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // --- LOGIQUE BROADCAST (ÉMISSION) ---

  Future<void> _updateAdvertising() async {
    if (!isAdvertising) return;

    // Format du nom: TB:[Type]:[Nom]:[Payload]
    // Note: Le nom local est limité en longueur sur iOS (~28 octets au total)
    // On va faire court: TB:[H/C]:[Nom]:[Payload]
    final type = isScanning ? "C" : "H"; // H=Hôte, C=Client
    final shortName = _myDeviceName!.length > 8 ? _myDeviceName!.substring(0, 8) : _myDeviceName;
    final advName = "${APP_PREFIX}_${type}_${shortName}_$_currentPayload";

    debugPrint("Mise à jour Advertising: $advName");

    final advertiseData = AdvertiseData(
      serviceUuid: SERVICE_UUID,
      localName: advName,
    );

    await _peripheral.stop();
    await _peripheral.start(advertiseData: advertiseData);
  }

  Future<void> startHosting() async {
    isAdvertising = true;
    _currentPayload = "WAIT"; // L'hôte attend
    await _updateAdvertising();
    _startScanning(); // L'hôte doit aussi scanner pour voir les joueurs
    notifyListeners();
  }

  Future<void> startJoining() async {
    isAdvertising = true;
    _currentPayload = "JOIN"; // Le client veut rejoindre
    await _updateAdvertising();
    _startScanning();
    notifyListeners();
  }

  // --- LOGIQUE SCAN (RÉCEPTION) ---

  void _startScanning() {
    if (isScanning) return;
    isScanning = true;
    discoveredDevices.clear();
    connectedDevices.clear();

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String? name = r.advertisementData.localName;
        if (name != null && name.startsWith(APP_PREFIX)) {
          _processBroadcastName(name, r.device.remoteId.str);
        }
      }
    });

    FlutterBluePlus.startScan();
  }

  void _processBroadcastName(String name, String deviceId) {
    // Format: TB_TYPE_NOM_PAYLOAD
    final parts = name.split('_');
    if (parts.length < 4) return;

    final type = parts[1];
    final deviceName = parts[2];
    final payload = parts[3];

    // Mise à jour de la liste des joueurs
    final existingIdx = connectedDevices.indexWhere((d) => d.deviceId == deviceId);
    if (existingIdx != -1) {
      // Si le payload a changé, on déclenche un événement
      if (connectedDevices[existingIdx].lastMessage != payload) {
        debugPrint("Nouveau message de $deviceName: $payload");
        _handleIncomingPayload(payload);
      }
      
      connectedDevices[existingIdx] = Device(
        deviceId: deviceId,
        deviceName: deviceName,
        lastMessage: payload,
        lastSeen: DateTime.now(),
      );
    } else {
      // Nouveau joueur détecté
      debugPrint("Joueur détecté: $deviceName (Type: $type)");
      connectedDevices.add(Device(
        deviceId: deviceId,
        deviceName: deviceName,
        lastMessage: payload,
        lastSeen: DateTime.now(),
      ));
    }

    // Nettoyage des joueurs déconnectés (pas vus depuis 10s)
    connectedDevices.removeWhere((d) => 
      DateTime.now().difference(d.lastSeen).inSeconds > 10);

    notifyListeners();
  }

  void _handleIncomingPayload(String payload) {
    // On convertit les payloads simples en messages JSON pour rester compatible avec le reste de l'app
    if (payload == "START") {
      _messageController.add(jsonEncode({'type': 'game_start'}));
    } else if (payload.startsWith("CUT")) {
      _messageController.add(jsonEncode({'type': 'cut_wire', 'wireIndex': payload.substring(3)}));
    }
  }

  // --- ACTIONS ---

  void broadcastMessage(Map<String, dynamic> data) {
    if (data['type'] == 'game_start') {
      _currentPayload = "START";
    } else if (data['type'] == 'cut_wire') {
      _currentPayload = "CUT${data['wireIndex']}";
    }
    _updateAdvertising();
  }

  void stopAll() {
    _peripheral.stop();
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    isAdvertising = false;
    isScanning = false;
    connectedDevices.clear();
    notifyListeners();
  }

  void disconnectAll() => stopAll();
}
