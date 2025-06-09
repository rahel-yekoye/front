import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final Function(String, String, List<String>) onCreate;

  const CreateGroupPage({
    super.key,
    required this.users,
    required this.onCreate,
  });

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  List<String> selectedUsers = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Group')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Select Members', style: TextStyle(fontWeight: FontWeight.bold)),
            ...widget.users.map((user) {
              final isSelected = selectedUsers.contains(user['_id']);
              return CheckboxListTile(
                title: Text(user['username']),
                value: isSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      selectedUsers.add(user['_id']);
                    } else {
                      selectedUsers.remove(user['_id']);
                    }
                  });
                },
              );
            }),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                widget.onCreate(
                  _nameController.text.trim(),
                  _descController.text.trim(),
                  selectedUsers,
                );
                Navigator.pop(context);
              },
              child: const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }
}
