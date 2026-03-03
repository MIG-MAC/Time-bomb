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
  SessionState state;
  final BluetoothDevice? bluetoothDevice;

  Device({
    required this.deviceId,
    required this.deviceName,
    this.state = SessionState.notConnected,
    this.bluetoothDevice,
  });
}

class GameNearbyService with ChangeNotifier {
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  List<Device> connectedDevices = [];
  List<Device> discoveredDevices = [];
  
  bool isAdvertising = false;
  bool isBrowsing = false;
  String? _myDeviceName;

  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get messages => _messageController.stream;

  StreamSubscription? _scanSubscription;
  final Map<String, StreamSubscription> _notificationSubscriptions = {};
  
  // Periphérique (Hôte)
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  GameNearbyService();

  Future<bool> requestPermissions() async {
    debugPrint("Demande de permissions...");
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      debugPrint("Permissions Android: $statuses");
      return statuses.values.every((status) => status.isGranted);
    } else {      
      debugPrint("Sur iOS, les permissions Bluetooth sont gérées nativement par le système.");
      return true;
    }
  }

  Future<void> init(String deviceName) async {
    debugPrint("Initialisation du service pour: $deviceName");
    _myDeviceName = deviceName;
    
    debugPrint("Vérification de l'état de l'adaptateur Bluetooth...");
    try {
      // On ajoute un timeout pour éviter de rester bloqué si l'état ne change pas
      var state = await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 2));
      debugPrint("État Bluetooth: $state");

      if (state != BluetoothAdapterState.on) {
        debugPrint("Le Bluetooth n'est pas activé ! État actuel: $state");
        if (Platform.isAndroid) {
          debugPrint("Tentative d'activation du Bluetooth (Android)...");
          await FlutterBluePlus.turnOn();
        }
      }
    } catch (e) {
      debugPrint("Timeout ou erreur lors de la récupération de l'état Bluetooth: $e");
      // On continue quand même, car l'état pourrait s'activer plus tard
    }
  }

  // --- LOGIQUE HÔTE (PERIPHERAL) ---

  Future<void> startHosting() async {
    debugPrint("Tentative de lancement de l'hébergement...");
    if (isAdvertising) {
      debugPrint("Déjà en train d'héberger.");
      return;
    }

    try {
      final advertiseData = AdvertiseData(
        serviceUuid: SERVICE_UUID,
        localName: _myDeviceName,
      );

      final advertiseSetParameters = AdvertiseSetParameters();

      debugPrint("Démarrage du périphérique BLE peripheral...");
      await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSetParameters: advertiseSetParameters,
      );
      debugPrint("Périphérique BLE démarré avec succès.");

      isAdvertising = true;
      notifyListeners();
    } catch (e) {
      debugPrint("ERREUR lors du lancement de l'hébergement: $e");
    }
  }

  void stopHosting() {
    _peripheral.stop();
    isAdvertising = false;
    notifyListeners();
  }

  // --- LOGIQUE CLIENT (CENTRAL) ---

  void startJoining() {
    if (isBrowsing) return;
    isBrowsing = true;
    discoveredDevices.clear();
    
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String? name = r.advertisementData.localName;
        // On filtre par notre Service UUID
        if (r.advertisementData.serviceUuids.contains(Guid(SERVICE_UUID)) || 
            (name != null && name.isNotEmpty)) {
          
          final deviceId = r.device.remoteId.str;
          if (!discoveredDevices.any((d) => d.deviceId == deviceId)) {
            discoveredDevices.add(Device(
              deviceId: deviceId,
              deviceName: name ?? "Inconnu",
              bluetoothDevice: r.device,
            ));
            notifyListeners();
          }
        }
      }
    });

    FlutterBluePlus.startScan(
      withServices: [Guid(SERVICE_UUID)],
      timeout: const Duration(seconds: 15),
    );
    notifyListeners();
  }

  void stopJoining() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    isBrowsing = false;
    notifyListeners();
  }

  Future<void> connectToDevice(Device device) async {
    if (device.bluetoothDevice == null) return;

    device.state = SessionState.connecting;
    notifyListeners();

    try {
      await device.bluetoothDevice!.connect();
      
      // Découverte des services
      List<BluetoothService> services = await device.bluetoothDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var char in service.characteristics) {
            if (char.uuid.toString() == CHARACTERISTIC_UUID) {
              // S'abonner aux notifications pour recevoir les messages de l'hôte
              await char.setNotifyValue(true);
              _notificationSubscriptions[device.deviceId] = char.onValueReceived.listen((value) {
                final message = utf8.decode(value);
                _messageController.add(message);
              });
            }
          }
        }
      }

      device.state = SessionState.connected;
      if (!connectedDevices.any((d) => d.deviceId == device.deviceId)) {
        connectedDevices.add(device);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Erreur connexion: $e");
      device.state = SessionState.notConnected;
      notifyListeners();
    }
  }

  // --- MESSAGERIE ---

  Future<void> sendMessage(String deviceId, Map<String, dynamic> data) async {
    final device = connectedDevices.firstWhere((d) => d.deviceId == deviceId);
    if (device.bluetoothDevice == null) return;

    final message = jsonEncode(data);
    final bytes = utf8.encode(message);

    List<BluetoothService> services = await device.bluetoothDevice!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString() == SERVICE_UUID) {
        for (var char in service.characteristics) {
          if (char.uuid.toString() == CHARACTERISTIC_UUID) {
            await char.write(bytes);
          }
        }
      }
    }
  }

  void broadcastMessage(Map<String, dynamic> data) {
    for (var device in connectedDevices) {
      sendMessage(device.deviceId, data);
    }
    // Si nous sommes l'hôte, nous devrions aussi pouvoir envoyer aux clients connectés
    // via les notifications sur notre propre GATT Server (implémentation avancée requise)
  }

  void disconnectAll() {
    stopHosting();
    stopJoining();
    for (var device in connectedDevices) {
      device.bluetoothDevice?.disconnect();
    }
    for (var sub in _notificationSubscriptions.values) {
      sub.cancel();
    }
    _notificationSubscriptions.clear();
    connectedDevices.clear();
    discoveredDevices.clear();
    notifyListeners();
  }
}
