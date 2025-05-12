import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';
import 'search_user_screen.dart'; // Import the SearchScreen

class InboxScreen extends StatefulWidget {
  final String currentUser;
  final String jwtToken;

  const InboxScreen(
      {super.key, required this.currentUser, required this.jwtToken});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> groups = [];
  bool isLoading = true;
  late IO.Socket socket;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchConversations();
    _fetchGroups();
    _connectToSocket(); // Ensure this is called early
  }

  Future<void> _fetchConversations() async {
    final url = Uri.parse(
        'http://localhost:4000/conversations?user=${widget.currentUser}');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          conversations =
              data.map((json) => Map<String, dynamic>.from(json)).toList();
          isLoading = false;
        });
      }
    } catch (_) {
      setState(() => isLoading = false);
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
          groups = data.map((json) => Map<String, dynamic>.from(json)).toList();
        });
      }
    } catch (_) {
      // Handle errors (e.g., show a message)
    }
  }

  void _connectToSocket() {
    socket = IO.io('http://localhost:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.onConnect((_) {
      print('✅ Connected to Socket.IO server');
    });

    socket.onDisconnect((_) {
      print('❌ Disconnected from Socket.IO server');
    });

    // Listen for conversation updates (only for direct messages)
    socket.on('conversation_update', (data) {
      final updated = Map<String, dynamic>.from(data);

      // Ensure this is not a group message
      if (updated['isGroup'] == true) {
        return; // Ignore group messages
      }

      setState(() {
        final index = conversations
            .indexWhere((c) => c['otherUser'] == updated['otherUser']);
        if (index != -1) {
          conversations[index] = updated;
        } else {
          conversations.add(updated);
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    socket.disconnect();
    socket.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Groups'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(),
          _buildGroupsTab(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'searchUser',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchScreen(
                    loggedInUser: widget.currentUser, // Pass the currentUser as loggedInUser
                    jwtToken: widget.jwtToken,
                  ),
                ),
              );
            },
            child: const Icon(Icons.search), // Search icon
            tooltip: 'Search User',
          ),
          const SizedBox(height: 10), // Space between buttons
          FloatingActionButton(
            heroTag: 'createGroup',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateGroupScreen(
                    currentUser: widget.currentUser,
                    jwtToken: widget.jwtToken,
                  ),
                ),
              );
            },
            child: const Icon(Icons.group_add), // Group add icon
            tooltip: 'Create Group',
          ),
        ],
      ),
    );
  }

  Widget _buildChatsTab() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : conversations.isEmpty
            ? const Center(child: Text('No conversations yet'))
            : ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final c = conversations[index];

                  // Ensure this is not a group message
                  if (c['isGroup'] == true) {
                    return const SizedBox.shrink(); // Skip group messages
                  }

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(c['otherUser'],
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c['message'],
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(_formatTimestamp(c['timestamp']),
                        style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            currentUser: widget.currentUser,
                            otherUser: c['otherUser'],
                            jwtToken: widget.jwtToken,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
  }

  Widget _buildGroupsTab() {
    return groups.isEmpty
        ? const Center(child: Text('No groups yet'))
        : ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.group)),
                title: Text(group['name'],
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(group['description'] ?? 'No description'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupChatScreen(
                        groupId: group['_id'],
                        groupName: group['name'],
                        currentUser: widget.currentUser,
                        jwtToken: widget.jwtToken,
                      ),
                    ),
                  );
                },
              );
            },
          );
  }

  String _formatTimestamp(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
