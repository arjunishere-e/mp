
import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const KeralaClimateApp());
}

class KeralaClimateApp extends StatelessWidget {
  const KeralaClimateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kerala Climate Twin',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F8FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087E75),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F8FA),
          foregroundColor: Color(0xFF102A43),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E3EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E3EA)),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 84,
                  width: 84,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF4ED),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.public,
                    size: 46,
                    color: Color(0xFF087E75),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Kerala Climate Twin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF102A43),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Climate intelligence for Kerala',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF627D98),
                  ),
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(
                  color: Color(0xFF087E75),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your climate dashboard starts here',
                  style: TextStyle(color: Color(0xFF627D98)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
