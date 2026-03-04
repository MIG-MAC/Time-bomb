import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'time_bomb_core_ffi.dart';

enum SessionState { notConnected, connecting, connected }

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

  List<Device> connectedDevices =
      []; // En mode Broadcast, ce sont les joueurs détectés
  List<Device> discoveredDevices = [];

  bool isAdvertising = false;
  bool isScanning = false;
  String? _myDeviceName;
  String _currentPayload = "IDLE";

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _rustEventsSubscription;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final TimeBombCoreFfi _core = TimeBombCoreFfi.instance;

  bool rustCoreReady = false;

  GameNearbyService();

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses =
          await [
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
    rustCoreReady = await _core.initSession(deviceName);

    _rustEventsSubscription?.cancel();
    _rustEventsSubscription = _core.events.listen((event) {
      final eventType = event['eventType'];
      final data = event['data'];
      debugPrint('Rust event type=$eventType data=$data');

      if (eventType == 0 && data is Map<String, dynamic>) {
        final instruction = data['instruction']?.toString().toLowerCase();
        if (instruction == 'start') {
          _messageController.add(
            jsonEncode({
              'type': 'rust_start_received',
              'eventType': eventType,
              'data': data,
            }),
          );
        }
      }

      _messageController.add(
        jsonEncode({
          'type': 'rust_event',
          'eventType': eventType,
          'data': data,
        }),
      );
    });

    if (!rustCoreReady) {
      debugPrint('Rust core init failed: ${await _core.lastError()}');
    } else {
      debugPrint('Rust core session state: ${await _core.getSessionState()}');
    }

    // On s'assure que le Bluetooth est prêt
    try {
      await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}
  }

  // --- LOGIQUE BROADCAST (ÉMISSION) ---

  Future<void> _updateAdvertising() async {
    if (!isAdvertising) return;

    // Format du nom: TB:[Type]:[Nom]:[Payload]
    // Note: Le nom local est limité en longueur sur iOS (~28 octets au total)
    // On va faire court: TB:[H/C]:[Nom]:[Payload]
    final type = isScanning ? "C" : "H"; // H=Hôte, C=Client
    final shortName =
        _myDeviceName!.length > 8
            ? _myDeviceName!.substring(0, 8)
            : _myDeviceName;
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
        final name = r.advertisementData.advName;
        if (name.startsWith(APP_PREFIX)) {
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
    final existingIdx = connectedDevices.indexWhere(
      (d) => d.deviceId == deviceId,
    );
    if (existingIdx != -1) {
      // Si le payload a changé, on déclenche un événement
      if (connectedDevices[existingIdx].lastMessage != payload) {
        debugPrint("Nouveau message de $deviceName: $payload");
        unawaited(_handleIncomingPayload(payload));
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
      connectedDevices.add(
        Device(
          deviceId: deviceId,
          deviceName: deviceName,
          lastMessage: payload,
          lastSeen: DateTime.now(),
        ),
      );
    }

    // Nettoyage des joueurs déconnectés (pas vus depuis 10s)
    connectedDevices.removeWhere(
      (d) => DateTime.now().difference(d.lastSeen).inSeconds > 10,
    );

    notifyListeners();
  }

  Future<void> _handleIncomingPayload(String payload) async {
    if (rustCoreReady) {
      final int instruction;
      final Map<String, dynamic> rustPayload;

      if (payload == 'START') {
        instruction = 1;
        rustPayload = {'type': 'game_start'};
      } else if (payload.startsWith('CUT')) {
        instruction = 4;
        rustPayload = {'wireIndex': payload.substring(3)};
      } else if (payload == 'JOIN' || payload == 'WAIT') {
        instruction = 0;
        rustPayload = {'name': _myDeviceName ?? 'unknown'};
      } else {
        instruction = 3;
        rustPayload = {'raw': payload};
      }

      final bytes = await _core.buildMessage(
        instruction: instruction,
        transport: 0,
        payload: rustPayload,
      );

      if (bytes != null) {
        await _core.processIncoming(bytes);
      }
    }

    // On convertit les payloads simples en messages JSON pour rester compatible avec le reste de l'app
    if (payload == "START") {
      _messageController.add(jsonEncode({'type': 'game_start'}));
    } else if (payload.startsWith("CUT")) {
      _messageController.add(
        jsonEncode({'type': 'cut_wire', 'wireIndex': payload.substring(3)}),
      );
    }
  }

  // --- ACTIONS ---

  Future<void> broadcastMessage(Map<String, dynamic> data) async {
    if (rustCoreReady) {
      final int instruction;
      final Map<String, dynamic> payload;

      if (data['type'] == 'game_start') {
        instruction = 1;
        payload = {'type': 'game_start'};
      } else if (data['type'] == 'cut_wire') {
        instruction = 4;
        payload = {'wireIndex': data['wireIndex']};
      } else {
        instruction = 3;
        payload = data;
      }

      final bytes = await _core.buildMessage(
        instruction: instruction,
        transport: 0,
        payload: payload,
      );

      if (bytes != null) {
        await _core.processIncoming(bytes);
      } else {
        debugPrint('Rust buildMessage failed: ${await _core.lastError()}');
      }
    }

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
    unawaited(_core.resetSession());
    notifyListeners();
  }

  void disconnectAll() => stopAll();

  @override
  void dispose() {
    _rustEventsSubscription?.cancel();
    _scanSubscription?.cancel();
    _messageController.close();
    super.dispose();
  }
}
