import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
//import 'dart:io' show Platform; // add this import at the top
import '../models/message.dart' as models;
import '../services/socket_service.dart';
import '../screens/call_screen.dart';
import '../services/call_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart' as ja;
//import 'dart:html' as html; // Only import if targeting web, or guard usage with kIsWeb
import 'package:audioplayers/audioplayers.dart'as ap;

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
  final List<PlatformFile> _selectedFiles = [];
bool _isRemoteFile(String fileUrl) {
  return fileUrl.startsWith('http://') || fileUrl.startsWith('https://');
}
Map<String, VideoPlayerController> _videoControllers = {};
Map<String, ap.AudioPlayer> _audioPlayers = {};
@override
void dispose() {
  for (var controller in _videoControllers.values) {
    controller.dispose();
  }
  for (var player in _audioPlayers.values) {
    player.dispose();
  }
  super.dispose();
}

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
      final List<String> messageIds =
          (data['messageIds'] as List).map((e) => e.toString()).toList();
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
        'http://192.168.20.143:4000/messages?user1=${widget.currentUser}&user2=${widget.otherUser}&currentUser=${widget.currentUser}');
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
    print('📤 Emitting mark_as_read for ${widget.currentUser}');

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
    // Missed call
    if (msg.type == 'missed_call' && msg.receiver == widget.currentUser) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_missed, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            'Missed call',
            style:
                const TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    // Cancelled call
    if (msg.type == 'cancelled_call' && msg.sender == widget.currentUser) {
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
    }

    // Call log
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

    // File-based messages
// // File-based messages
if (msg.fileUrl.isNotEmpty) {
  final ext = getFileExtension(msg.fileUrl);
  final isRemote = _isRemoteFile(msg.fileUrl);

  Widget fileWidget;

  // --- IMAGE PREVIEW ---
  if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext)) {
    fileWidget = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: isRemote
          ? Image.network(
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
            )
          : Image.file(
              File(msg.fileUrl),
              width: 150,
              height: 150,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Text('[Image file not found]'),
            ),
    );
  }

  // --- VIDEO PREVIEW ---
  else if (['.mp4', '.webm', '.mov', '.mkv'].contains(ext)) {
    fileWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          height: 150,
          child: InlineVideoPlayer(videoUrl: msg.fileUrl),
        ),
        TextButton.icon(
          icon: const Icon(Icons.download),
          label: const Text("Save Video"),
          onPressed: () async {
            final savedPath = await saveFileSmart(
              msg.fileUrl,
              'chat_video_${DateTime.now().millisecondsSinceEpoch}$ext',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(savedPath != null ? 'Video saved to $savedPath' : 'Save failed')),
            );
          },
        ),
      ],
    );
  }

  // --- AUDIO PREVIEW ---
  else if (['.mp3', '.wav', '.aac', '.m4a'].contains(ext)) {
    fileWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineAudioPlayer(audioUrl: msg.fileUrl),
        TextButton.icon(
          icon: const Icon(Icons.download),
          label: const Text("Save Audio"),
          onPressed: () async {
            final savedPath = await saveFileSmart(
              msg.fileUrl,
              'chat_audio_${DateTime.now().millisecondsSinceEpoch}$ext',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(savedPath != null ? 'Audio saved to $savedPath' : 'Save failed')),
            );
          },
        ),
      ],
    );
  }

  // --- GENERIC FILE DOWNLOAD ---
  else {
    fileWidget = InkWell(
      onTap: () async {
        final savedPath = await saveFileSmart(
          msg.fileUrl,
          'chat_file_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(savedPath != null ? 'File saved to $savedPath' : 'Save failed')),
        );
      },
      child: Row(
        children: const [
          Icon(Icons.insert_drive_file, color: Colors.blue),
          SizedBox(width: 8),
          Text('Download file', style: TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }

  // --- FINAL RETURN ---
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      fileWidget,
      if (msg.content.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          msg.content,
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
      ],
    ],
  );
}

// --- FALLBACK TEXT MESSAGE ---
return Text(
  msg.content,
  style: const TextStyle(color: Colors.black87, fontSize: 16),
);

  }
  // Call button handlers
String getFileExtension(String urlOrName) {
  try {
    final uri = Uri.parse(urlOrName);
    final segments = uri.pathSegments;
    if (segments.isEmpty) return '';
    final lastSegment = segments.last;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return lastSegment.substring(dotIndex).toLowerCase();
  } catch (_) {
    return '';
  }
}
Future<String?> _saveFileDialog(String fileUrl) async {
  try {
    final fileName = 'chat_file_${DateTime.now().millisecondsSinceEpoch}${getFileExtension(fileUrl)}';

    // Ask user where to save the file
    final savePath = await getSavePath(suggestedName: fileName);

    if (savePath == null) {
      print('User cancelled save dialog');
      return null;
    }

    final dio = Dio();
    await dio.download(fileUrl, savePath);

    return savePath;
  } catch (e) {
    print('Error saving file: $e');
    return null;
  }
}


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

Future<bool> requestStoragePermission() async {
  if (await Permission.manageExternalStorage.isGranted) return true;

  final result = await Permission.manageExternalStorage.request();
  return result.isGranted;


}


// Helper function to save file smartly based on platform
Future<String?> saveFileSmart(String url, String fileName) async {
  if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Desktop/web: Ask user where to save
    final savePath = await getSavePath(suggestedName: fileName);
    if (savePath == null) {
      print('User cancelled save dialog');
      return null;
    }
    final dio = Dio();
    await dio.download(url, savePath);
    return savePath;
  } else if (Platform.isAndroid) {
    // Android: Save automatically to public folder
    return await saveFileToPublicFolder(url, fileName);
  } else {
    // Other platforms: Save to app documents dir
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$fileName';
    final dio = Dio();
    await dio.download(url, filePath);
    return filePath;
  }
}

// Modified saveFileToPublicFolder (your original)
Future<String?> saveFileToPublicFolder(String url, String fileName) async {
  try {
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      print('Permission denied to write to external storage.');
      return null;
    }

    String? folderName;
    if (fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png')) {
      folderName = 'Pictures';
    } else if (fileName.endsWith('.mp3') || fileName.endsWith('.wav')) {
      folderName = 'Music';
    } else if (fileName.endsWith('.mp4') || fileName.endsWith('.webm')) {
      folderName = 'Movies';
    } else if (fileName.endsWith('.pdf') || fileName.endsWith('.docx')) {
      folderName = 'Documents';
    } else {
      folderName = 'Download';
    }

    final dir = Directory('/storage/emulated/0/$folderName/ChatApp');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fullPath = '${dir.path}/$fileName';

    final dio = Dio();
    await dio.download(url, fullPath);

    print('File saved to $fullPath');
    return fullPath;
  } catch (e) {
    print('❌ Error saving file: $e');
    return null;
  }
}

  Future<void> _pickAndAddFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(result.files);
      });

      FocusScope.of(context).requestFocus(_focusNode); // keep focus on text
    }
  }

Future<void> uploadAndSendFile(PlatformFile file) async {
  final tempId = DateTime.now().millisecondsSinceEpoch.toString();

  final tempMessage = models.Message(
    id: tempId,
    sender: widget.currentUser,
    receiver: widget.otherUser,
    content: '',
    timestamp: DateTime.now().toIso8601String(),
    isGroup: false,
    emojis: [],
    fileUrl: kIsWeb ? '' : (file.path ?? ''),
    readBy: [widget.currentUser],
  );

  setState(() {
    messages.add(tempMessage);
  });
  _scrollToBottomSmooth();

  try {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.20.143:4000/upload'),
    );

    if (kIsWeb && file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path!),
      );
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    setState(() {
      messages.removeWhere((m) => m.id == tempId);
    });

    if (response.statusCode == 200) {
      final fileUrl = jsonDecode(responseBody)['fileUrl'];
      _sendMessage('', fileUrl: fileUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload file')),
      );
    }
  } catch (e) {
    setState(() {
      messages.removeWhere((m) => m.id == tempId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload error: $e')),
    );
  }

  setState(() {
    _selectedFiles.remove(file);
  });
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
  Widget _buildFilesPreview() {
    if (_selectedFiles.isEmpty) return SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedFiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = _selectedFiles[index];
          final isImage = file.extension?.toLowerCase().contains('png') == true ||
              file.extension?.toLowerCase().contains('jpg') == true ||
              file.extension?.toLowerCase().contains('jpeg') == true;

          return Stack(
            children: [
              Container(
                width: 70,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage && kIsWeb && file.bytes != null
                    ? Image.memory(file.bytes!, fit: BoxFit.cover)
                    : Center(
                        child: Icon(Icons.insert_drive_file, size: 40),
                      ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFiles.removeAt(index);
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }


  void _handleSend() async {
    final text = _controller.text.trim();

    if (_selectedFiles.isNotEmpty) {
      // Upload files one by one
      for (final file in _selectedFiles) {
        final fileUrl = await _uploadFile(file);
        if (fileUrl != null) {
          _sendMessage(text.isEmpty ? '' : text, fileUrl: fileUrl);
          // Clear text only after first send to allow sending text with first file
          // or you can send message for each file separately, or batch send if backend supports.
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload file ${file.name}')),
          );
        }
      }
      setState(() {
        _selectedFiles.clear();
        _controller.clear();
      });
    } else if (text.isNotEmpty) {
      _sendMessage(text);
      _controller.clear();
    }
  }
  Future<String?> _uploadFile(PlatformFile file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.20.143:4000/upload'),
    );

    if (kIsWeb && file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path!),
      );
    }

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseBody = await response.stream.bytesToString();
      return jsonDecode(responseBody)['fileUrl'];
    } else {
      return null;
    }
  }

  // Also update _chatInputField() to call new _pickAndAddFiles()
  Widget _chatInputField() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilesPreview(),
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
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _pickAndAddFiles, // <-- changed here
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
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: _handleSend,
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
                    TextPosition(offset: _controller.text.length),
                  );
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

class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const InlineVideoPlayer({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isInitialized
        ? GestureDetector(
            onTap: _togglePlayPause,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
                if (!_controller.value.isPlaying)
                  const Icon(Icons.play_circle_fill, size: 64, color: Colors.white),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
        
  }
  
}


class InlineAudioPlayer extends StatefulWidget {
  final String audioUrl;

  const InlineAudioPlayer({required this.audioUrl, Key? key}) : super(key: key);

  @override
  _InlineAudioPlayerState createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
late final ap.AudioPlayer _audioPlayer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = ap.AudioPlayer();
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

Future<void> _togglePlayPause() async {
  try {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(ap.UrlSource(widget.audioUrl));
    }
    setState(() => _isPlaying = !_isPlaying);
  } catch (e) {
    print('Audio play error: $e');
    // Optionally show snackbar or UI error
  }
}

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isPlaying ? Icons.pause_circle : Icons.play_circle,
        color: Colors.blue,
        size: 36,
      ),
      onPressed: _togglePlayPause,
    );
  }
}