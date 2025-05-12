import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'verification_screen.dart'; // Import the actual VerificationScreen

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final phoneNumber = _phoneNumberController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty ||
        email.isEmpty ||
        phoneNumber.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('http://localhost:4000/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'phoneNumber': phoneNumber,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code sent to your email')),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VerificationScreen(
                email: email), // Navigate to the actual VerificationScreen
          ),
        );
      } else {
        final error = jsonDecode(response.body)['error'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _phoneNumberController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _register,
                    child: const Text('Register'),
                  ),
          ],
        ),
      ),
    );
  }
}
