import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  final String currentUser;
  final String jwtToken;

  const CreateGroupScreen({
    super.key,
    required this.currentUser,
    required this.jwtToken,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescriptionController =
      TextEditingController();
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> groups = [];
  List<String> selectedUsers = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchGroups();
  }

  Future<void> _fetchUsers() async {
    final url = Uri.parse('http://localhost:4000/users');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          users = data.map((user) => Map<String, dynamic>.from(user)).toList();
        });
      } else {
        print('Failed to fetch users: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching users: $error');
    }
  }

Future<void> _fetchGroups() async {
  final url = Uri.parse('http://localhost:4000/groups');
  try {
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      setState(() {
        groups = data.map((group) => {
          'id': group['_id'],
          'name': group['name'],
          'members': group['members'],
        }).toList();
      });
      print('Fetched groups: $groups'); // Debug the fetched groups
    } else {
      print('Failed to fetch groups: ${response.statusCode}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch groups: ${response.statusCode}')),
      );
    }
  } catch (error) {
    print('Error fetching groups: $error');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('An error occurred while fetching groups')),
    );
  }
}

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    final groupDescription = _groupDescriptionController.text.trim();

    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    final url = Uri.parse('http://localhost:4000/groups');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.jwtToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': groupName,
          'description': groupDescription,
          'members': selectedUsers,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully')),
        );
        _fetchGroups(); // Refresh the group list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create group')),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Create Group'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _groupNameController,
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _groupDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Group Description (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Select Members',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final isSelected = selectedUsers.contains(user['_id']);
                        return CheckboxListTile(
                          title: Text(user['username']),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                selectedUsers.add(user['_id']);
                              } else {
                                selectedUsers.remove(user['_id']);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _createGroup();
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateGroupDialog(),
          ),
        ],
      ),
      body: groups.isEmpty
          ? const Center(
              child: Text(
                'No groups found. Create a new group!',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return ListTile(
                  title: Text(group['name']),
                  subtitle: Text('Members: ${group['members'].length}'),
                  onTap: () {
                    // Navigate to the group chat screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupChatScreen(
                          groupId: group['id'],
                          groupName: group['name'],
                          currentUser: widget.currentUser,
                          jwtToken: widget.jwtToken,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroupDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}