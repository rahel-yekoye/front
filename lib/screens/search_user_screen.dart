import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';

class SearchScreen extends StatefulWidget {
  final String loggedInUser;
  final String jwtToken;

  const SearchScreen(
      {required this.loggedInUser, required this.jwtToken, super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _phoneNumberController = TextEditingController();
  Map<String, dynamic>? _searchResult;
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _searchUser() async {
    final phone = _phoneNumberController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Please enter a phone number.');
      return;
    }
    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('http://10.202.42.143:4000/search?phoneNumber=$phone'),
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _searchResult = jsonDecode(response.body)['user'];
          _errorMessage = null;
        });
      } else {
        setState(() {
          _searchResult = null;
          _errorMessage = jsonDecode(response.body)['error'];
        });
      }
    } catch (_) {
      setState(() {
        _searchResult = null;
        _errorMessage = 'An error occurred. Please try again.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search User')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextField(
                  controller: _phoneNumberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Enter phone number',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _searchUser,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
                const SizedBox(height: 16),
                if (_isLoading) const CircularProgressIndicator(),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                if (_searchResult != null)
                  Card(
                    margin: const EdgeInsets.only(top: 20),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(_searchResult!['username'] ?? ''),
                      subtitle: Text(_searchResult!['phoneNumber'] ?? ''),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                currentUser: widget.loggedInUser,
                                otherUser: _searchResult!['username'],
                                jwtToken: widget.jwtToken,
                              ),
                            ),
                          );
                        },
                        child: const Text('Chat'),
                      ),
                    ),
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SearchUserScreen extends StatelessWidget {
  final String loggedInUser;
  final String jwtToken;

  const SearchUserScreen(
      {required this.loggedInUser, required this.jwtToken, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Users')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.search),
          label: const Text('Search User'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchScreen(
                  loggedInUser: loggedInUser,
                  jwtToken: jwtToken,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
