import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/message.dart' as models;
import '../services/socket_service.dart';
import '../screens/call_screen.dart';
import '../services/call_service.dart';

class ChatScreen extends StatefulWidget {
  final String currentUser; // must be username
  final String otherUser; // must be username
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
  late CallService callService;
  bool _isCallScreenOpen = false;

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
        _markMessagesAsRead(); // <== ADD THIS LINE
      }
    });

    _scrollController.addListener(() {
      if (_scrollController.offset >=
          _scrollController.position.maxScrollExtent - 50) {
        _markMessagesAsRead();
      }
    });
  }

  void _openCallScreenAsCallee(Map<String, dynamic> data) {
    if (_isCallScreenOpen) return;
    _isCallScreenOpen = true;
    Navigator.of(context)
        .push(
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
    )
        .then((_) {
      _isCallScreenOpen = false;
      _connectToSocket(); // re-register listeners
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
    socketService.socket.off('missed_call');

    socketService.onMessageReceived((msg) async {
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
        await _markMessagesAsRead();
      }
    });

    // Handle incoming call: open CallScreen as callee
    print(
        'Registering onIncomingCall listener for user: ${widget.currentUser}');
    socketService.onIncomingCall((data) {
      print('[SOCKET] incoming_call event: $data');
      if (mounted) {
        _openCallScreenAsCallee(data);
      }
    });
    socketService.onMessagesRead((data) {
      final List<dynamic> messageIds = data['messageIds'] ?? [];
      final reader = data['reader'];

      setState(() {
        for (var msg in messages) {
          if (messageIds.contains(msg.id) && !msg.readBy.contains(reader)) {
            msg.readBy.add(reader);
          }
        }
      });
    });

    socketService.socket.on('missed_call', (data) {
      final newMsg = models.Message.fromJson(data);
      setState(() {
        if (!messages.any((m) =>
            m.sender == newMsg.sender &&
            m.receiver == newMsg.receiver &&
            m.content == newMsg.content &&
            m.timestamp == newMsg.timestamp)) {
          messages.add(newMsg);
        }
      });
    });

    socketService.socket.on('cancelled_call', (data) {
      print('[SOCKET] cancelled_call event received: $data');
      final newMsg = models.Message.fromJson(data);
      setState(() {
        if (!messages.any((m) =>
            m.sender == newMsg.sender &&
            m.receiver == newMsg.receiver &&
            m.content == newMsg.content &&
            m.timestamp == newMsg.timestamp)) {
          messages.add(newMsg);
        }
      });
    });

    socketService.socket.on('call_log', (data) {
      print('[SOCKET] call_log event received: $data');
      final newMsg = models.Message.fromJson(data);
      setState(() {
        if (!messages.any((m) =>
            m.sender == newMsg.sender &&
            m.receiver == newMsg.receiver &&
            m.content == newMsg.content &&
            m.timestamp == newMsg.timestamp)) {
          messages.add(newMsg);
        }
      });
    });

    socketService.socket.onAny((event, data) {
      print('[SOCKET EVENT] $event: $data');
    });
  }

  Future<void> fetchMessages() async {
    final url = Uri.parse(
        'http://localhost:4000/messages?user1=${widget.currentUser}&user2=${widget.otherUser}&currentUser=${widget.currentUser}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          messages = data.map((json) {
            return models.Message(
              id: json['_id'] ?? '', // ✅ FIXED: assign actual Mongo _id
              sender: json['sender'] ?? 'Unknown',
              receiver: json['receiver'] ?? 'Unknown',
              content: json['content'] ?? '[No Content]',
              timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
              isGroup: json['isGroup'] ?? false,
              emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
              fileUrl: json['fileUrl'] ?? '',
              readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
              type: json['type'],
              direction: json['direction'],
              duration: json['duration'] is int
                  ? json['duration']
                  : int.tryParse(json['duration']?.toString() ?? ''),
            );
          }).toList();
        });

        await _markMessagesAsRead(); // no await since it’s void

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

  Future<void> _markMessagesAsRead() async {
    socketService.socket.emit('mark_as_read', {
      'user': widget.currentUser,
      'otherUser': widget.otherUser,
    });
  }

  void _sendMessage(String content, {String fileUrl = ''}) {
    if (content.trim().isEmpty && fileUrl.isEmpty) {
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
      'sender': widget.currentUser, // <-- must be username
      'receiver': widget.otherUser, // <-- must be username
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'isGroup': false,
      'emojis': <String>[],
      'fileUrl': fileUrl,
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
    if (msg.type == 'missed_call') {
      // Only show if the current user is the receiver (callee)
      if (msg.receiver == widget.currentUser) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_missed, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Missed call',
              style: const TextStyle(
                  color: Colors.red, fontStyle: FontStyle.italic),
            ),
          ],
        );
      } else {
        return const SizedBox.shrink();
      }
    }
    if (msg.type == 'cancelled_call') {
      // Only show if the current user is the caller (who cancelled)
      if (msg.sender == widget.currentUser) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_end, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'Cancelled call',
              style: const TextStyle(
                  color: Colors.orange, fontStyle: FontStyle.italic),
            ),
          ],
        );
      } else {
        return const SizedBox.shrink();
      }
    }
    if (msg.type == 'call_log') {
      String directionText = '';
      IconData icon;
      Color color;
      if (msg.direction == 'outgoing' && msg.sender == widget.currentUser) {
        directionText = 'Outgoing call';
        icon = Icons.call_made;
        color = Colors.green;
      } else if (msg.direction == 'incoming' &&
          msg.receiver == widget.currentUser) {
        directionText = 'Incoming call';
        icon = Icons.call_received;
        color = Colors.blue;
      } else {
        return const SizedBox.shrink();
      }
      String durationStr = _formatDuration(msg.duration ?? 0);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            '$directionText ($durationStr)',
            style: TextStyle(color: color, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }
    if (msg.fileUrl.isNotEmpty) {
      if (msg.fileUrl.endsWith('.jpg') ||
          msg.fileUrl.endsWith('.jpeg') ||
          msg.fileUrl.endsWith('.png') ||
          msg.fileUrl.endsWith('.gif')) {
        // Display image
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
      } else if (msg.fileUrl.endsWith('.mp3') || msg.fileUrl.endsWith('.wav')) {
        // Display audio player (use a package like just_audio or audioplayers)
        return Text('Audio file: ${msg.fileUrl}');
      } else if (msg.fileUrl.endsWith('.mp4') ||
          msg.fileUrl.endsWith('.webm')) {
        // Display video player (use a package like chewie or video_player)
        return Text('Video file: ${msg.fileUrl}');
      } else {
        // Other file types: show as a download link
        return InkWell(
          onTap: () => launchUrl(Uri.parse(msg.fileUrl)),
          child: Text('Download file', style: TextStyle(color: Colors.blue)),
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
    if (_isCallScreenOpen) return;
    _isCallScreenOpen = true;
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
          onCallScreenClosed: () {
            // Re-register incoming call listener
            _connectToSocket();
          },
        ),
      ),
    ).then((_) {
      _isCallScreenOpen = false;
      _connectToSocket(); // re-register listeners
    });
  }

  void _onVideoCallPressed() {
    if (_isCallScreenOpen) return;
    _isCallScreenOpen = true;
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
    ).then((_) {
      _isCallScreenOpen = false;
      _connectToSocket(); // re-register listeners
    });
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final file = result.files.single;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:4000/upload'),
      );

      if (kIsWeb) {
        // On web, use bytes
        if (file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              file.bytes!,
              filename: file.name,
            ),
          );
        }
      } else {
        // On mobile/desktop, use path
        if (file.path != null) {
          request.files.add(
            await http.MultipartFile.fromPath('file', file.path!),
          );
        }
      }

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final fileUrl = jsonDecode(responseBody)['fileUrl'];
        _sendMessage('', fileUrl: fileUrl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<models.Message> filteredMessages = messages.where((msg) {
      if (msg.type == 'missed_call') {
        return msg.receiver == widget.currentUser;
      }
      if (msg.type == 'cancelled_call') {
        return msg.sender == widget.currentUser;
      }
      return true; // show all other messages
    }).toList();

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
              itemCount: filteredMessages.length,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                final msg = filteredMessages[index];
                print(
                    'Building message: ${msg.sender} -> ${msg.receiver}: ${msg.content}');
                final isMe = msg.sender == widget.currentUser;

                // The entire message row now includes:
                //  - Left icon (read/unread) only for sender's messages
                //  - Message bubble aligned right or left

                Widget readStatusIcon() {
                  if (!isMe) return const SizedBox(width: 0);
                  if (msg.readBy.contains(widget.otherUser)) {
                    return const Icon(Icons.done_all,
                        size: 16, color: Colors.green);
                  } else {
                    return const Icon(Icons.done, size: 16, color: Colors.grey);
                  }
                }

                return Row(
                  mainAxisAlignment:
                      isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildMessageContent(msg),
                          if (isMe)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: readStatusIcon(),
                            ),
                        ],
                      ),
                    ),
                  ],
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
// Attach file button
              IconButton(
                icon: Icon(Icons.attach_file),
                onPressed: _pickAndSendFile, // Implement this function below
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

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}
