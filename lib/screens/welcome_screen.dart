import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  final String email;

  const WelcomeScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.celebration, color: Colors.blue, size: 100),
            const SizedBox(height: 20),
            Text(
              'Welcome, $email!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Navigate to the home screen or another screen
                Navigator.pop(context);
              },
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
