import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'group_chat_screen.dart';
import 'create_group_page.dart';

class CreateGroupScreen extends StatefulWidget {
  final String currentUser; // This should be the user ID
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
  final TextEditingController _groupDescriptionController = TextEditingController();
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
    final url = Uri.parse('http://10.202.42.143:4000/users');
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
    final url = Uri.parse('http://10.202.42.143:4000/groups');
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
            'description': group['description'],
            'members': group['members'],
            'adminUsername': group['adminUsername'] ?? '', // for display
          }).toList();
        });
        print('Fetched groups: $groups');
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

  // Helper to get username by user ID
  String getUsernameById(String id) {
    final user = users.firstWhere((u) => u['_id'] == id, orElse: () => {});
    return user.isNotEmpty ? user['username'] ?? 'Unknown' : 'Unknown';
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

    final url = Uri.parse('http://10.202.42.143:4000/groups');
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
          'members': selectedUsers, // list of user IDs
          'memberUsernames': selectedUsers.map((id) => getUsernameById(id)).toList(), // for display
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully')),
        );
        _fetchGroups();
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

  Future<String> _fetchLastGroupMessage(String groupId) async {
    final url = Uri.parse('http://10.202.42.143:4000/groups/$groupId/last-message');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final lastMsg = data.last;
          final sender = lastMsg['sender']?.toString() ?? 'Unknown';
          final content = lastMsg['content']?.toString() ?? '';
          if (content.isEmpty) return 'No messages yet.';
          return '$sender: $content';
        }
      }
    } catch (_) {}
    return 'No messages yet.';
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
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateGroupPage(
                    users: users,
                    onCreate: (name, desc, members) {
                      _groupNameController.text = name;
                      _groupDescriptionController.text = desc;
                      selectedUsers = members;
                      _createGroup();
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
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
                    return FutureBuilder<String>(
                      future: _fetchLastGroupMessage(group['id']),
                      builder: (context, snapshot) {
                        final lastMessage = snapshot.connectionState == ConnectionState.done
                            ? (snapshot.data ?? 'No messages yet.')
                            : 'Loading...';
                        return ListTile(
                          leading: const Icon(Icons.group, size: 36),
                          title: Text(group['name']),
                          subtitle: Text(
                            lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GroupChatScreen(
                                  groupId: group['id'],
                                  groupName: group['name'],
                                  groupDescription: group['description'] ?? '',
                                  currentUser: widget.currentUser,
                                  jwtToken: widget.jwtToken,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateGroupPage(
                users: users,
                onCreate: (name, desc, members) {
                  _groupNameController.text = name;
                  _groupDescriptionController.text = desc;
                  selectedUsers = members;
                  _createGroup();
                },
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}