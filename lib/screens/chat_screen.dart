import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/message.dart' as models;
import '../services/socket_service.dart';
import '../screens/call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String currentUser; // must be username
  final String otherUser;   // must be username
  final String jwtToken;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.otherUser,
    required this.jwtToken,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final SocketService socketService = SocketService();
  List<models.Message> messages = [];
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    print('🔵 ChatScreen initState for user: ${widget.currentUser}');
    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';
    socketService.connect(userId: widget.currentUser).then((_) {
      print('Socket connected: ${socketService.socket.connected}');
      print('Joining room: $roomId');
      _connectToSocket();
    });
    fetchMessages();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
  }

  void _connectToSocket() {
    print('Registering listeners for user: ${widget.currentUser}');
    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    socketService.joinRoom(roomId);

    // Remove previous listeners to avoid duplicates
    socketService.offMessageReceived();
    socketService.offIncomingCall();

    socketService.onMessageReceived((msg) {
      print('[SOCKET] receive_message event: ${msg.content}');
      if (mounted) {
        setState(() {
          // Only add if not already present (avoid duplicates)
          if (!messages.any((m) =>
              m.sender == msg.sender &&
              m.receiver == msg.receiver &&
              m.content == msg.content &&
              m.timestamp == msg.timestamp)) {
            messages.add(msg);
            print('Messages in UI after add: ${messages.length}');
          }
        });
        _scrollToBottomSmooth();
      }
    });

    // Handle incoming call: open CallScreen as callee
    print('Registering onIncomingCall listener for user: ${widget.currentUser}');
    socketService.onIncomingCall((data) {
      print('[SOCKET] incoming_call event: $data');
      print('[CALL] Current user: ${widget.currentUser}');
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              selfId: widget.currentUser,
              peerId: data['from'],
              isCaller: false,
              voiceOnly: data['voiceOnly'] ?? false,
              callerName: data['callerName'] ?? data['from'],
              socketService: socketService,
            ),
          ),
        );
      }
    });

    socketService.socket.onAny((event, data) {
      print('[SOCKET EVENT] $event: $data');
    });
  }

  Future<void> fetchMessages() async {
    final url = Uri.parse(
        'http://localhost:4000/messages?user1=${widget.currentUser}&user2=${widget.otherUser}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          messages = data.map((json) {
            return models.Message(
              sender: json['sender'] ?? 'Unknown',
              receiver: json['receiver'] ?? 'Unknown',
              content: json['content'] ?? '[No Content]',
              timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
              isGroup: json['isGroup'] ?? false,
              emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
              fileUrl: json['fileUrl'] ?? '',
            );
          }).toList();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottomSmooth();
        });
      } else {
        debugPrint('Failed to fetch messages: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('Error fetching messages: $error');
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
      'sender': widget.currentUser,      // <-- must be username
      'receiver': widget.otherUser,      // <-- must be username
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'isGroup': false,
      'emojis': <String>[],
      'fileUrl': '',
    };

    socketService.sendMessage(message);
    _controller.clear();
    _scrollToBottomSmooth();
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

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp');
  }

  Widget _buildMessageContent(models.Message msg) {
    if (msg.fileUrl.isNotEmpty) {
      if (_isImageUrl(msg.fileUrl)) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            msg.fileUrl,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                width: 150,
                height: 150,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                const Text('[Image not available]'),
            width: 150,
            height: 150,
            fit: BoxFit.cover,
          ),
        );
      } else {
        return InkWell(
          onTap: () {
            // TODO: Add file download/open feature
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg.fileUrl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      return RichText(
        text: TextSpan(
          text: msg.content,
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
      );
    }
  }

  // Call button handlers
  void _onVoiceCallPressed() {
    print('[CALL] Emitting call_initiate: from=${widget.currentUser}, to=${widget.otherUser}');
    socketService.socket.emit('call_initiate', {
      'from': widget.currentUser,
      'to': widget.otherUser,
      'voiceOnly': true,
      'callerName': widget.currentUser,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          selfId: widget.currentUser,
          peerId: widget.otherUser,
          isCaller: true,
          voiceOnly: true,
          callerName: widget.currentUser,
          socketService: socketService,
        ),
      ),
    );
  }

  void _onVideoCallPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          selfId: widget.currentUser,
          peerId: widget.otherUser,
          isCaller: true,
          voiceOnly: false,
          callerName: widget.currentUser,
          socketService: socketService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.person)),
            const SizedBox(width: 10),
            Text(
              widget.otherUser,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            tooltip: 'Voice Call',
            onPressed: _onVoiceCallPressed,
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.blue),
            tooltip: 'Video Call',
            onPressed: _onVideoCallPressed,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: messages.length,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                final msg = messages[index];
                print('Building message: ${msg.sender} -> ${msg.receiver}: ${msg.content}');
                final isMe = msg.sender == widget.currentUser;

                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
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
                    child: _buildMessageContent(msg),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions,
                ),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _showEmojiPicker = !_showEmojiPicker;
                  });
                },
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (value) => _sendMessage(value.trim()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: () => _sendMessage(_controller.text.trim()),
              ),
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
            ),
        ],
      ),
    );
  }
}