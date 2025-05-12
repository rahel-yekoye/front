import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart'; // For formatting timestamps
import '../services/api_service.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUser;
  final String jwtToken;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUser,
    required this.jwtToken,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<Map<String, dynamic>> messages = [];
  List<String> groupIds = [];
  late IO.Socket socket;
  final TextEditingController _messageController = TextEditingController();
  bool isLoading = true; // For loading indicator

  @override
  void initState() {
    super.initState();
    _fetchGroupIds();
    _connectToSocket();
    _fetchMessages().then((_) {
      setState(() {
        isLoading = false;
      });
    });
  }

  Future<void> _fetchGroupIds() async {
    try {
      final ids = await ApiService.fetchGroupIds(widget.jwtToken);
      print('Raw group IDs: $ids');

      setState(() {
        groupIds = ids;
      });
      print('Fetched group IDs: $groupIds');

      // Join the group rooms via Socket.IO
      if (groupIds.isNotEmpty) {
        socket.emit('join_groups', groupIds);
      }
    } catch (error) {
      print('Error fetching group IDs: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch group IDs: $error')),
      );
    }
  }

  Future<void> _fetchMessages() async {
    final url = Uri.parse('http://localhost:4000/groups/${widget.groupId}/messages');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          messages = data.map((json) => Map<String, dynamic>.from(json)).toList();
        });
      } else {
        print('Failed to fetch messages: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch messages: ${response.statusCode}')),
        );
      }
    } catch (error) {
      print('Error fetching messages: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred while fetching messages')),
      );
    }
  }

  void _connectToSocket() {
    socket = IO.io('http://localhost:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer ${widget.jwtToken}'},
    });

    socket.connect();

    socket.on('connect', (_) {
      print('Connected to Socket.IO server');
    });

    socket.on('connect_error', (error) {
      print('Socket.IO connection error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect to chat server')),
      );
    });

    socket.on('disconnect', (_) {
      print('Disconnected from Socket.IO server');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from chat server')),
      );
    });

    // Listen for group messages
    socket.on('group_message', (data) {
      print('Received group message: $data');
      final newMessage = Map<String, dynamic>.from(data);
      setState(() {
        messages.add(newMessage);
      });
    });
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message cannot be empty')),
      );
      return;
    }

    print('Sending message: groupId=${widget.groupId}, sender=${widget.currentUser}, content=$content');

    // Emit the message to the backend
    socket.emit('send_group_message', {
      'groupId': widget.groupId,
      'sender': widget.currentUser,
      'content': content,
    });

    // Add the message to the local UI
    setState(() {
      messages.add({
        'sender': widget.currentUser,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });

    _messageController.clear();
  }

  @override
  void dispose() {
    socket.disconnect();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.groupName)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet. Start the conversation!',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final formattedTime = DateFormat('hh:mm a')
                                .format(DateTime.parse(msg['timestamp']));
                            return ListTile(
                              title: Text(msg['sender']),
                              subtitle: Text(msg['content']),
                              trailing: Text(formattedTime),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(hintText: 'Type a message'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}