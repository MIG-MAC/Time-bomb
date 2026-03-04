import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/nearby_service_wrapper.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final bool isHost;

  const LobbyScreen({super.key, required this.isHost});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late StreamSubscription _subscription;
  bool _didShowRustStartPopup = false;
  bool _didShowClientStartPopup = false;

  @override
  void initState() {
    super.initState();
    final service = Provider.of<GameNearbyService>(context, listen: false);
    _subscription = service.messages.listen((msg) async {
      if (!mounted) {
        return;
      }

      final data = jsonDecode(msg);

      if (!widget.isHost &&
          data['type'] == 'rust_start_received' &&
          !_didShowRustStartPopup) {
        _didShowRustStartPopup = true;
        final rustData = data['data'];
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Event Rust reçu'),
              content: Text('START reçu via callback Rust\n\n$rustData'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );

        if (!mounted) {
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GameScreen()),
        );
        return;
      }

      if (data['type'] == 'game_start') {
        if (!widget.isHost && !_didShowClientStartPopup) {
          _didShowClientStartPopup = true;
          await showDialog<void>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('Start reçu'),
                content: const Text(
                  'Le client a reçu le START.\nLa partie va démarrer.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );

          if (!mounted) {
            return;
          }
        }

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GameScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nearbyService = Provider.of<GameNearbyService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.isHost ? "SALLE D'ATTENTE (HÔTE)" : 'RECHERCHE DE PARTIE',
          style: GoogleFonts.specialElite(
            color: Colors.amber[700],
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.amber),
          onPressed: () {
            nearbyService.disconnectAll();
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            if (widget.isHost)
              Text(
                'Attendez que les autres joueurs vous rejoignent...',
                textAlign: TextAlign.center,
                style: GoogleFonts.specialElite(
                  color: Colors.white,
                  fontSize: 16,
                ),
              )
            else
              Text(
                'Sélectionnez une partie pour rejoindre...',
                textAlign: TextAlign.center,
                style: GoogleFonts.specialElite(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            const SizedBox(height: 30),
            Expanded(
              child: ListView.builder(
                itemCount: nearbyService.connectedDevices.length,
                itemBuilder: (context, index) {
                  final device = nearbyService.connectedDevices[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: ListTile(
                      title: Text(
                        device.deviceName,
                        style: GoogleFonts.specialElite(color: Colors.white),
                      ),
                      subtitle: Text(
                        "Prêt (Vu il y a ${DateTime.now().difference(device.lastSeen).inSeconds}s)",
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.isHost && nearbyService.connectedDevices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        nearbyService.connectedDevices.length >=
                                1 // Min 2 total for testing
                            ? () async {
                              await nearbyService.broadcastMessage({
                                'type': 'game_start',
                              });
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const GameScreen(),
                                ),
                              );
                            }
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      disabledBackgroundColor: Colors.grey[800],
                    ),
                    child: Text(
                      'LANCER LA BOMBE (${nearbyService.connectedDevices.length + 1} Joueurs)',
                      style: GoogleFonts.specialElite(
                        fontSize: 18,
                        color: Colors.white,
                      ),
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
