import 'package:flutter/material.dart';
import 'package:chat_app_flutter/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // You can connect here if you know the user, or after login
  // SocketService().connect(userId: 'CURRENT_USER_ID');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(), // Set HomePage as the initial screen
    );
  }
}
