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
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    } else {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    }
  }

  Future<void> init(String deviceName) async {
    _myDeviceName = deviceName;
    // On s'assure que le Bluetooth est activé
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      // Sur Android on peut demander l'activation, sur iOS c'est à l'utilisateur
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
    }
  }

  // --- LOGIQUE HÔTE (PERIPHERAL) ---

  Future<void> startHosting() async {
    if (isAdvertising) return;

    final advertiseData = AdvertiseData(
      serviceUuid: SERVICE_UUID,
      localName: _myDeviceName,
    );

    final advertiseSetParameters = AdvertiseSetParameters();

    await _peripheral.start(
      advertiseData: advertiseData,
      advertiseSetParameters: advertiseSetParameters,
    );

    // Note: Pour un échange de données complet en tant qu'hôte (GATT Server),
    // flutter_blue_plus supporte maintenant l'ajout de services.
    
    try {
      // Configuration du GATT Server pour recevoir des messages
      // (Simplifié ici pour la structure, en BLE pur l'hôte attend que les clients écrivent)
      // flutter_blue_plus v1.34+ supporte les services GATT
    } catch (e) {
      debugPrint("Erreur init GATT Server: $e");
    }

    isAdvertising = true;
    notifyListeners();
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
