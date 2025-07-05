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
import 'package:audioplayers/audioplayers.dart' as ap;

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

  List<models.Message> filteredMessages =
      []; // The list you show in UI (possibly filtered or same as messages)

  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ap.AudioPlayer> _audioPlayers = {};
  Set<String> selectedMessageIds = {};
  bool isSelecting = false;
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
    messages = []; // fetch from your backend or socket
    filteredMessages = List.from(messages);
    print('🔵 ChatScreen initState for user: ${widget.currentUser}');

    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    socketService.connect(userId: widget.currentUser).then((_) {
      print('Socket connected: ${socketService.socket.connected}');
      print('Joining room: $roomId');
      socketService.socket.emit('join_room', roomId);

      // 🧹 Listen for delete events
      socketService.socket.on('message_deleted', (data) {
        final deletedId = data['messageId'] as String?;
        if (deletedId != null) {
          setState(() {
            messages.removeWhere((msg) => msg.id == deletedId);
            selectedMessageIds.remove(deletedId);
            if (selectedMessageIds.isEmpty) isSelecting = false;
          });
          print('🗑️ Message deleted via socket: $deletedId');
        }
      });
    });

    fetchMessages();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmojiPicker = false;
        });
        _markMessagesAsRead(); // ✅ Mark as read when input gets focus
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

    socketService.socket.on('new_message', (data) {
      final newMsg =
          models.Message.fromJson(data); // adapt to your Message.fromJson
      if ((newMsg.sender == widget.otherUser &&
              newMsg.receiver == widget.currentUser) ||
          (newMsg.sender == widget.currentUser &&
              newMsg.receiver == widget.otherUser)) {
        setState(() {
          messages.add(newMsg);
          filteredMessages.add(newMsg); // update filtered as well
        });
        _scrollToBottomSmooth();
      }
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
      'http://10.202.42.143:4000/messages?user1=${widget.currentUser}&user2=${widget.otherUser}&currentUser=${widget.currentUser}',
    );

    try {
      final response = await http.get(url);
      print('FetchMessages response status: ${response.statusCode}');
      print('FetchMessages response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('Parsed messages count (raw): ${data.length}');

        final filtered = data.where((json) => json['deleted'] != true).toList();
        print('Messages after filtering deleted: ${filtered.length}');

        setState(() {
          messages = filtered.map((json) {
            print('✅ Parsing message: $json');
            return models.Message(
              id: json['id'] ?? '',
              sender: json['sender'] ?? 'Unknown',
              receiver: json['receiver'] ?? 'Unknown',
              content: json['content'] ?? '[No Content]',
              timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
              isGroup: json['isGroup'] ?? false,
              emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
              fileUrl: json['fileUrl'] ?? '',
              isFile: json['isFile'] ??
                  (json['fileUrl'] != null &&
                      json['fileUrl'].toString().isNotEmpty),
              deleted: json['deleted'] ?? false,
              edited: json['edited'] ?? false,
              readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
              type: json['type'],
              direction: json['direction'],
              duration: json['duration'] is int
                  ? json['duration']
                  : int.tryParse(json['duration']?.toString() ?? ''),
            );
          }).toList();
        });

        await _markMessagesAsRead();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottomSmooth();
        });
      } else {
        print('❌ Failed to fetch messages: ${response.statusCode}');
      }
    } catch (error) {
      print('❌ Error fetching messages: $error');
    }
  }
void _onMessageLongPress(int index) {
  setState(() {
    isSelecting = true;
    selectedMessageIndices.add(index);
  });
}
void _onMessageTap(int index) {
  if (isSelecting) {
    setState(() {
      if (selectedMessageIndices.contains(index)) {
        selectedMessageIndices.remove(index);
        if (selectedMessageIndices.isEmpty) {
          isSelecting = false;
        }
      } else {
        selectedMessageIndices.add(index);
      }
    });
  } else {
    // Your normal tap action (like open message, reply, etc)
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
      'sender': widget.currentUser,
      'receiver': widget.otherUser,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'isGroup': false,
      'emojis': <String>[],
      'fileUrl': fileUrl,
    };

    // ✅ Locally show message immediately
    final localMessage = models.Message(
      id: UniqueKey().toString(), // temporary unique id
      sender: widget.currentUser,
      receiver: widget.otherUser,
      content: content,
      timestamp: DateTime.now().toIso8601String(),
      isGroup: false,
      emojis: [],
      fileUrl: fileUrl,
      readBy: [widget.currentUser],
      deleted: false,
      edited: false,
    );

    setState(() {
      messages.add(localMessage); // ✅ Add to UI immediately
    });

    socketService.sendMessage(message); // 📤 Send to server
    _controller.clear();
    _scrollToBottomSmooth();
  }

  void _scrollToBottomSmooth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
    // --- Missed Call ---
    print(
        '📩 Building message: content="${msg.content}", fileUrl="${msg.fileUrl}", type="${msg.type}"');

    if (msg.type == 'missed_call' && msg.receiver == widget.currentUser) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.call_missed, color: Colors.red),
          SizedBox(width: 8),
          Text(
            'Missed call',
            style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    // --- Cancelled Call ---
    if (msg.type == 'cancelled_call' && msg.sender == widget.currentUser) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.call_end, color: Colors.orange),
          SizedBox(width: 8),
          Text(
            'Cancelled call',
            style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    // --- Call Log ---
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

    // --- Handle File or Text or Both ---
    final bool hasFile = msg.fileUrl != null && msg.fileUrl.trim().isNotEmpty;
    final bool hasText = msg.content.trim().isNotEmpty;

    List<Widget> children = [];

    if (hasFile) {
      final ext = getFileExtension(msg.fileUrl);
      final isRemote = _isRemoteFile(msg.fileUrl);

      Widget fileWidget;

      if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext)) {
        fileWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isRemote
              ? Image.network(
                  msg.fileUrl,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
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
      } else if (['.mp4', '.webm', '.mov', '.mkv'].contains(ext)) {
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
                  SnackBar(
                      content: Text(savedPath != null
                          ? 'Video saved to $savedPath'
                          : 'Save failed')),
                );
              },
            ),
          ],
        );
      } else if (['.mp3', '.wav', '.aac', '.m4a'].contains(ext)) {
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
                  SnackBar(
                      content: Text(savedPath != null
                          ? 'Audio saved to $savedPath'
                          : 'Save failed')),
                );
              },
            ),
          ],
        );
      } else {
        fileWidget = InkWell(
          onTap: () async {
            final savedPath = await saveFileSmart(
              msg.fileUrl,
              'chat_file_${DateTime.now().millisecondsSinceEpoch}$ext',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(savedPath != null
                      ? 'File saved to $savedPath'
                      : 'Save failed')),
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

      children.add(fileWidget);
    }

    if (hasText) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Text(
          msg.content.trim(),
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
      final fileName =
          'chat_file_${DateTime.now().millisecondsSinceEpoch}${getFileExtension(fileUrl)}';

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
        Uri.parse('http://10.202.42.143:4000/upload'),
      );

      if (kIsWeb && file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes('file', file.bytes!,
              filename: file.name),
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
  Set<int> selectedMessageIndices = {};

  @override
  Widget build(BuildContext context) {
    print(
        'All messages: ${messages.map((m) => '${m.content} | ${m.fileUrl}').toList()}');

    // Filter deleted messages (if you still want this)
    List<models.Message> filteredMessages = messages;

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
          actions: isSelecting
              ? [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        isSelecting = false;
                        selectedMessageIndices.clear();
                      });
                    },
                  ),
                 IconButton(
  icon: const Icon(Icons.delete, color: Colors.red),
  onPressed: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Messages?'),
        content: Text(
          'Are you sure you want to delete ${selectedMessageIndices.length} message(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      print('All messages in filteredMessages with IDs:');
      for (int i = 0; i < filteredMessages.length; i++) {
        print('Index $i -> id: "${filteredMessages[i].id}" content: "${filteredMessages[i].content}"');
      }

      final messagesToDelete = selectedMessageIndices
          .map((i) => filteredMessages[i])
          .toList();

      for (final message in messagesToDelete) {
        await _deleteMessage(message);
      }

      setState(() {
        selectedMessageIndices.clear();
        isSelecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected messages deleted')),
      );
    }
  },
),

                ]
              : [
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
        body: Column(children: [
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

                Widget readStatusIcon() {
                  if (!isMe) return const SizedBox(width: 0);
                  if (msg.readBy.contains(widget.otherUser)) {
                    return const Icon(Icons.done_all,
                        size: 16, color: Colors.green);
                  } else {
                    return const Icon(Icons.done, size: 16, color: Colors.grey);
                  }
                }

                return GestureDetector(
                  onLongPress: () {
                    setState(() {
                      isSelecting = true;
                      selectedMessageIndices = {index};
                      print('Selected message index: $index');
                    });
                  },
                  onTap: () {
                    if (!isSelecting) return;
                    setState(() {
                      if (selectedMessageIndices.contains(index)) {
                        selectedMessageIndices.remove(index);
                        if (selectedMessageIndices.isEmpty) {
                          isSelecting = false;
                        }
                      } else {
                        selectedMessageIndices.add(index);
                      }
                      print(
                          'Tapped message index: $index, selected indices: $selectedMessageIndices');
                    });
                  },
                  child: Container(
                    color: selectedMessageIndices.contains(index)
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.transparent,
                    child: Row(
                      mainAxisAlignment: isMe
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          decoration: BoxDecoration(
                            color: selectedMessageIndices.contains(index)
                                ? Colors.lightBlueAccent.withOpacity(0.5)
                                : (isMe ? Colors.blue[200] : Colors.grey[300]),
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
                    ),
                  ),
                );
              },
            ),
          ),
          _chatInputField(),
        ]));
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
          final isImage =
              file.extension?.toLowerCase().contains('png') == true ||
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
      Uri.parse('http://10.202.42.143:4000/upload'),
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

  Future<void> deleteSelectedMessages() async {
    print('🚀 deleteSelectedMessages() called');

    if (selectedMessageIds.isEmpty) {
      print('⚠️ No message IDs selected to delete');
      return;
    }

    print('🛰️ Deleting selected message IDs: $selectedMessageIds');

    for (final msgId in selectedMessageIds) {
      if (msgId.isEmpty ||
          msgId.length != 24 ||
          !RegExp(r'^[a-f\d]{24}$').hasMatch(msgId)) {
        print('❌ Skipping invalid message ID: "$msgId"');
        continue;
      }

      final url = Uri.parse('http://10.202.42.143:4000/messages/$msgId');
      print('📡 DELETE request to: $url');

      try {
        print('📡 ABOUT TO SEND DELETE → $url');

        final response = await http.delete(url);
        print('🔽 Response ${response.statusCode} — ${response.body}');
        if (response.statusCode == 200) {
          print('✅ Deleted message $msgId');
        } else {
          print('❌ Failed to delete message $msgId');
        }
      } catch (e) {
        print('🔥 Exception while deleting $msgId: $e');
      }
    }

    setState(() {
      messages.removeWhere((m) => selectedMessageIds.contains(m.id));
      selectedMessageIds.clear();
      isSelecting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Selected messages deleted')),
    );
  }

  Future<void> _deleteMessage(models.Message message) async {
    final messageId = message.id;
    print('🧾 Message ID to delete: "$messageId"');
    print('🚀 deleteSelectedMessages() called');

    if (messageId.isEmpty ||
        messageId.length != 24 ||
        !RegExp(r'^[a-f\d]{24}$').hasMatch(messageId)) {
      print('❌ Invalid message ID format: "$messageId"');
      return;
    }

    final url = Uri.parse('http://10.202.42.143:4000/messages/$messageId');
    print('📡 Sending DELETE to: $url');

    try {
      print('📡 ABOUT TO SEND DELETE → $url');

      final response = await http.delete(url);

      print('🔽 Status code: ${response.statusCode}');
      print('📨 Response body: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          messages.removeWhere((m) => m.id == messageId);
        });
        print('✅ Message $messageId removed from UI');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message deleted')),
        );
      } else {
        print('❌ Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      print('🔥 DELETE request failed: $e');
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

  const InlineVideoPlayer({super.key, required this.videoUrl});

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
                  const Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

class InlineAudioPlayer extends StatefulWidget {
  final String audioUrl;

  const InlineAudioPlayer({required this.audioUrl, super.key});

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
