import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../models/message.dart' as models;
import '../services/socket_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class ChatScreen extends StatefulWidget {
  final String currentUser;
  final String otherUser;
  final String jwtToken;

  const ChatScreen(
      {super.key,
      required this.currentUser,
      required this.otherUser,
      required this.jwtToken});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  late SocketService socketService;
  List<models.Message> messages = [];
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    socketService = SocketService();
    socketService.connect();
    fetchMessages();
    _focusNode.addListener(() => setState(() => _showEmojiPicker = false));
    _connectToSocket();
  }

  void _connectToSocket() {
    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    socketService.registerUser(roomId);

    socketService.onMessageReceived((data) {
      print('📨 Received message: $data');
      final newMessage = models.Message(
        sender: data['sender'] as String? ?? 'Unknown',
        receiver: data['receiver'] as String? ?? 'Unknown',
        content: data['content'] as String? ?? '[No Content]',
        timestamp: data['timestamp'] as String? ?? DateTime.now().toIso8601String(),
        isGroup: data['isGroup'] as bool? ?? false,
        emojis: (data['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
        fileUrl: data['fileUrl'] as String? ?? '',
      );

      setState(() {
        messages.add(newMessage);
      });
    });
  }

  Future<void> fetchMessages() async {
    final url = Uri.parse(
        'http://localhost:4000/messages?user1=${widget.currentUser}&user2=${widget.otherUser}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('Fetched messages: $data'); // Debug log
        setState(() {
          messages = data.map((json) {
            return models.Message(
              sender: json['sender'] as String? ?? 'Unknown',
              receiver: json['receiver'] as String? ?? 'Unknown',
              content: json['content'] as String? ?? '[No Content]',
              timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
              isGroup: json['isGroup'] as bool? ?? false,
              emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
              fileUrl: json['fileUrl'] as String? ?? '',
            );
          }).toList();
        });
      } else {
        print('Failed to fetch messages: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching messages: $error');
    }
  }

  void _sendMessage(String content) {
    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message cannot be empty')),
      );
      return;
    }

    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    final message = {
      'roomId': roomId,
      'sender': widget.currentUser,
      'receiver': widget.otherUser,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'isGroup': false,
      'emojis': <String>[], // Ensure this is a List<String>
      'fileUrl': '', // Ensure this is a String
    };

    socketService.sendMessage(message);
    print('📤 Sending message: $message');

    // No optimistic update here
    _controller.clear();
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 10),
            Text(widget.otherUser,
                style: const TextStyle(fontWeight: FontWeight.w600))
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                bool isMe = msg.sender == widget.currentUser;

                // Handle null values for fileUrl and content
                final fileUrl = msg.fileUrl ?? ''; // Default to an empty string if null
                final content = msg.content ?? '[No Content]'; // Default to '[No Content]' if null

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[200] : Colors.grey[300],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: isMe
                            ? const Radius.circular(12)
                            : const Radius.circular(0),
                        bottomRight: isMe
                            ? const Radius.circular(0)
                            : const Radius.circular(12),
                      ),
                    ),
                    child: fileUrl.isNotEmpty
                        ? Text("[Attachment] $fileUrl")
                        : Text(content,
                            style: const TextStyle(fontSize: 16)),
                  ),
                );
              },
            ),
          ),
          _chatInputField(),
        ],
      ),
    );
  }

  Widget _chatInputField() {
    return SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _showEmojiPicker = !_showEmojiPicker);
                },
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: () => _sendMessage(_controller.text.trim()),
              )
            ],
          ),
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _controller.text += emoji.emoji;
                  _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: _controller.text.length));
                },
              ),
            )
        ],
      ),
    );
  }
}
