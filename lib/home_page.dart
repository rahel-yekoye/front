import 'package:flutter/material.dart';
import '../screens/register_screen.dart';
import '../screens/login_screen.dart';

class HomePage extends StatelessWidget {
  final String? loggedInUser;

  const HomePage({super.key, this.loggedInUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(loggedInUser != null
            ? 'Welcome, $loggedInUser'
            : 'Welcome to Chat App'),
        centerTitle: true,
      ),
      body: Center(
        child: Card(
          elevation: 4,
          margin: const EdgeInsets.all(20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 72, color: Theme.of(context).primaryColor),
                const SizedBox(height: 20),
                Text(
                  loggedInUser != null
                      ? 'Hello, $loggedInUser 👋'
                      : 'Join the conversation!',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                if (loggedInUser == null) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Register'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => RegisterScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Login'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  )
                ] else ...[
                  const Text('You are logged in! Enjoy chatting ✨'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
