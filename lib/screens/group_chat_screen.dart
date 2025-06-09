import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupDescription;
  final String currentUser;
  final String jwtToken;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupDescription,
    required this.currentUser,
    required this.jwtToken,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<Map<String, dynamic>> messages = [];
  late IO.Socket socket;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool isLoading = true;
  bool _showEmojiPicker = false;

  List<dynamic> groupMembers = [];
  List<Map<String, dynamic>> allUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchAllUsers().then((_) {
      _fetchGroupMembers();
    });
    _connectToSocket();
    _fetchMessages().then((_) {
      setState(() {
        isLoading = false;
      });
    });
    _focusNode.addListener(() => setState(() => _showEmojiPicker = false));
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
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottomSmooth());
      } else {
        print('Failed to fetch messages: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch messages')),
        );
      }
    } catch (error) {
      print('Error fetching messages: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error loading messages')),
      );
    }
  }

  Future<void> _fetchGroupMembers() async {
    final url = Uri.parse('http://localhost:4000/groups/${widget.groupId}');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          groupMembers = data['members'] ?? [];
        });
      }
    } catch (e) {
      print('Error fetching group members: $e');
    }
  }

  Future<void> _fetchAllUsers() async {
    final url = Uri.parse('http://localhost:4000/users');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          allUsers = data.map((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    } catch (e) {
      print('Error fetching users: $e');
    }
  }

  String _getUsername(String userId) {
    final user = allUsers.firstWhere(
      (u) => u['_id'] == userId,
      orElse: () => {},
    );
    return user.isNotEmpty ? user['username'] ?? userId : userId;
  }

  // Entire updated GroupChatScreen.dart

// ✅ Already fully included in your provided code — you do not need to change much here
// The issue is likely from socket not emitting `join_group` correctly when the socket is reused or connection is late.

void _connectToSocket() {
  socket = IO.io('http://localhost:4000', <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': false,
    'extraHeaders': {'Authorization': 'Bearer ${widget.jwtToken}'},
  });

  socket.connect();

  socket.on('connect', (_) async {
    print('Connected to Socket.IO');

    // Join the group explicitly
    socket.emit('join_group', widget.groupId);

    // Optionally join all groups for notifications (e.g., if this is reused across groups)
    final groupIds = await _fetchUserGroupIds();
    socket.emit('join_groups', groupIds);
  });

  socket.on('connect_error', (error) {
    print('Socket connection error: $error');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Socket connection failed')),
    );
  });

  socket.on('disconnect', (_) {
    print('Disconnected from Socket.IO');
  });

  // 🔄 This is crucial: listen for group messages always
  socket.off('group_message'); // clear existing to avoid duplicate triggers
  socket.on('group_message', (data) {
    print('Received group message: $data');
    if (data['groupId'] == widget.groupId) {
      final newMessage = Map<String, dynamic>.from(data);
      setState(() {
        messages.add(newMessage);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottomSmooth());
    }
  });

  // In case socket is already connected (e.g., hot reload or reuse)
  if (socket.connected) {
    socket.emit('join_group', widget.groupId);
  }
}

  void _sendMessage({String? content, String? fileUrl}) {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty && (fileUrl == null || fileUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message cannot be empty')),
      );
      return;
    }

    final message = {
      'groupId': widget.groupId,
      'sender': widget.currentUser,
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
      'fileUrl': fileUrl ?? '',
      'isFile': fileUrl != null && fileUrl.isNotEmpty,
    };

    socket.emit('send_group_message', message);

 
    _scrollToBottomSmooth();

    _messageController.clear();
  }

  Future<void> _pickFileAndSend() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      PlatformFile file = result.files.first;
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:4000/upload'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var fileUrl = jsonDecode(responseData)['fileUrl'];
        _sendMessage(content: '[Attachment]', fileUrl: fileUrl);
      }
    }
  }

  void _showGroupSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 300, // or MediaQuery.of(context).size.height * 0.5
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  'Group Members',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const Divider(),
                Expanded(
                  child: groupMembers.isEmpty
                      ? const Center(child: Text('No members found'))
                      : ListView.builder(
                          itemCount: groupMembers.length,
                          itemBuilder: (context, index) {
                            final memberId = groupMembers[index].toString();
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(_getUsername(memberId)),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToBottomSmooth() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    socket.emit('leave_group', widget.groupId); // <-- send just the groupId
    socket.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _showGroupSettings,
          child: Text(
            widget.groupDescription.isNotEmpty
                ? '${widget.groupName} (${widget.groupDescription})'
                : widget.groupName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const Center(child: Text('No messages yet.'))
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isSender = msg['sender'] == widget.currentUser;
                            final formattedTime = msg['timestamp'] != null
                                ? DateFormat('hh:mm a').format(DateTime.parse(msg['timestamp']))
                                : '';
                            final fileUrl = msg['fileUrl'] ?? '';
                            final isFile = msg['isFile'] == true || fileUrl.isNotEmpty;

                            return Align(
                              alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSender ? Colors.blue[100] : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getUsername(msg['sender']),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                    isFile
                                        ? GestureDetector(
                                            onTap: () {
                                              // Open file URL
                                              // You can use url_launcher package for this
                                            },
                                            child: Text(
                                              '📎 File: $fileUrl',
                                              style: const TextStyle(
                                                color: Colors.blue,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          )
                                        : Text(msg['content']),
                                    Text(
                                      formattedTime,
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                _groupChatInputField(),
                if (_showEmojiPicker)
                  SizedBox(
                    height: 250,
                    child: EmojiPicker(
                      onEmojiSelected: (category, emoji) {
                        _messageController.text += emoji.emoji;
                        _messageController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _messageController.text.length),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _groupChatInputField() {
    return SafeArea(
      child: Row(
        children: [
          IconButton(
            icon: Icon(_showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions),
            onPressed: () {
              FocusScope.of(context).unfocus();
              setState(() => _showEmojiPicker = !_showEmojiPicker);
            },
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _pickFileAndSend,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              decoration: const InputDecoration(hintText: 'Type a message'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _fetchUserGroupIds() async {
    final url = Uri.parse('http://localhost:4000/users/${widget.currentUser}/groups');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        // Assuming the response is a list of group objects with an '_id' field
        return data.map<String>((group) => group['_id'].toString()).toList();
      } else {
        print('Failed to fetch user group IDs: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching user group IDs: $e');
      return [];
    }
  }
}
