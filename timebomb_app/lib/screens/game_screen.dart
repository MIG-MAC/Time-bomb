import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/nearby_service_wrapper.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late StreamSubscription _subscription;
  String _gameStatus = "La partie commence !";

  @override
  void initState() {
    super.initState();
    final service = Provider.of<GameNearbyService>(context, listen: false);
    _subscription = service.messages.listen((msg) {
      final data = jsonDecode(msg);
      if (data['type'] == 'game_start') {
        setState(() {
          _gameStatus = "La partie commence !";
        });
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text('TIME BOMB', style: GoogleFonts.specialElite()),
        backgroundColor: Colors.red[900],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer, size: 100, color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              _gameStatus,
              style: GoogleFonts.specialElite(
                fontSize: 20,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
