import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/nearby_service_wrapper.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Joueur ${DateTime.now().millisecond}';
  }

  @override
  Widget build(BuildContext context) {
    final nearbyService = Provider.of<GameNearbyService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              Colors.grey[900]!,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'TIME BOMB',
                  style: GoogleFonts.specialElite(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[700],
                    letterSpacing: 8,
                    shadows: [
                      const Shadow(
                        blurRadius: 10,
                        color: Colors.red,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sherlock vs Moriarty',
                  style: GoogleFonts.specialElite(
                    fontSize: 20,
                    color: Colors.grey[400],
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 60),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Votre Nom',
                    labelStyle: TextStyle(color: Colors.amber[700]),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.amber[700]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                _buildMenuButton(
                  'CRÉER UNE PARTIE',
                  Colors.amber[700]!,
                  () async {
                    if (await nearbyService.requestPermissions()) {
                      await nearbyService.init(_nameController.text);
                      nearbyService.startHosting();
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LobbyScreen(isHost: true),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                _buildMenuButton(
                  'REJOINDRE UNE PARTIE',
                  Colors.blueGrey[700]!,
                  () async {
                    if (await nearbyService.requestPermissions()) {
                      await nearbyService.init(_nameController.text);
                      nearbyService.startJoining();
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LobbyScreen(isHost: false),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(String text, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 10,
        ),
        child: Text(
          text,
          style: GoogleFonts.specialElite(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
