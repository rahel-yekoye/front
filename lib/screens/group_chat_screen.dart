import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socket_io_common/src/util/event_emitter.dart';  // Add at top

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

  // Message selection for multi-delete/edit
  bool _isSelectionMode = false;
  Set<String> _selectedMessageIds = {};

  List<dynamic> groupMembers = [];
  List<Map<String, dynamic>> allUsers = [];
  File? _pendingAttachment;

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

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });

    // Scroll listener to detect near bottom and mark messages as read if needed
    _scrollController.addListener(_scrollListener);
  }
void _pickAttachment() async {
  final result = await FilePicker.platform.pickFiles();
  if (result != null && result.files.isNotEmpty) {
    setState(() {
      _pendingAttachment = File(result.files.single.path!);
    });
  }
}
  void _scrollListener() {
    if (_isNearBottom()) {
      // Mark messages as read or do other logic if needed
      // For group chat you may implement your own read logic here
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return (maxScroll - currentScroll) <
        100; // 100 pixels from bottom considered near bottom
  }

  Future<void> _fetchMessages() async {
    final url = Uri.parse(
        'http://192.168.20.145:4000/groups/${widget.groupId}/messages');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          messages =
              data.map((json) => Map<String, dynamic>.from(json)).toList();
        });
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottomSmooth());
      } else {
        print('Failed to fetch messages: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch messages')),
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
    final url =
        Uri.parse('http://192.168.20.145:4000/groups/${widget.groupId}');
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
    final url = Uri.parse('http://192.168.20.145:4000/users');
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

  void _connectToSocket() {
    socket = IO.io('http://192.168.20.145:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer ${widget.jwtToken}'},
    });

    socket.connect();
socket.on('reconnect', (attempt) {
  print('Socket reconnected after $attempt attempts');
  socket.emit('join_group', widget.groupId);
  _scrollToBottomSmooth();
});

socket.on('reconnect_attempt', (attempt) {
  print('Reconnecting attempt #$attempt');
});

socket.on('reconnect_error', (error) {
  print('Reconnect error: $error');
});

socket.on('reconnect_failed', () {
  print('Reconnect failed');
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Socket reconnection failed')),
  );
} as EventHandler);

    socket.on('connect', (_) async {
      print('Connected to Socket.IO');

      socket.emit('join_group', widget.groupId);

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

    // Clear existing listeners to avoid duplicates
    socket.off('group_message');
    socket.off('group_message_deleted');
    socket.off('group_message_edited');

    // New group message
    socket.on('group_message', (data) {
      print('Received group message: $data');
      if (data['groupId'] == widget.groupId) {
        final newMessage = Map<String, dynamic>.from(data);
        setState(() {
          messages.add(newMessage);
        });
        if (_isNearBottom()) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottomSmooth());
        }
      }
    });

    // Message deleted
    socket.on('group_message_deleted', (data) {
      print('Message deleted event: $data');
      final messageId = data['messageId'] as String?;
      if (messageId != null) {
        setState(() {
          messages.removeWhere((m) => m['id'] == messageId);
          _selectedMessageIds.remove(messageId);
          if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
        });
      }
    });

    // Message edited
    socket.on('group_message_edited', (data) {
      print('Message edited event: $data');
      final messageId = data['messageId'] as String?;
      if (messageId != null) {
        final index = messages.indexWhere((m) => m['id'] == messageId);
        if (index != -1) {
          setState(() {
            messages[index]['content'] =
                data['newContent'] ?? messages[index]['content'];
            messages[index]['edited'] = true;
          });
        }
      }
    });

    // Re-emit join if socket already connected (e.g., hot reload)
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
        Uri.parse('http://192.168.20.145:4000/upload'),
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

  Future<List<String>> _fetchUserGroupIds() async {
    final url = Uri.parse(
        'http://192.168.20.145:4000/users/${widget.currentUser}/groups');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
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

  void _showGroupSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 300,
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

  Future<void> _deleteGroupMessage(String messageId) async {
    final url = Uri.parse(
        'http://192.168.20.145:4000/groups/${widget.groupId}/messages/$messageId');
    try {
      final response = await http.delete(url, headers: {
        'Authorization': 'Bearer ${widget.jwtToken}',
      });
      if (response.statusCode == 200) {
        setState(() {
          messages.removeWhere((m) => m['id'] == messageId);
          _selectedMessageIds.remove(messageId);
          if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message deleted')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting message: $e')),
      );
    }
  }

  Future<void> _editGroupMessage(String messageId, String newContent) async {
    final url = Uri.parse(
        'http://192.168.20.145:4000/groups/${widget.groupId}/messages/$messageId');
    try {
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.jwtToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'content': newContent}),
      );
      if (response.statusCode == 200) {
        setState(() {
          final index = messages.indexWhere((m) => m['id'] == messageId);
          if (index != -1) {
            messages[index]['content'] = newContent;
            messages[index]['edited'] = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message edited')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to edit message: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error editing message: $e')),
      );
    }
  }


Future<File> _getLocalFileForUrl(String url) async {
  final filename = url.split('/').last;
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$filename');
}

Future<File?> _downloadFile(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final file = await _getLocalFileForUrl(url);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    }
  } catch (e) {
    print('Download file error: $e');
  }
  return null;
}

  void _showEditMessageDialog(Map<String, dynamic> message) {
    final TextEditingController editController =
        TextEditingController(text: message['content'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Message'),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(hintText: 'Enter new message'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newText = editController.text.trim();
                if (newText.isNotEmpty) {
                  Navigator.of(context).pop();
                  _editGroupMessage(message['id'], newText);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Scroll to bottom smoothly
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
    socket.emit('leave_group', widget.groupId);
    socket.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    final isSender = msg['sender'] == widget.currentUser;
    final messageId = msg['id'] ?? '';
    final formattedTime = msg['timestamp'] != null
        ? DateFormat('hh:mm a').format(DateTime.parse(msg['timestamp']))
        : '';
    final fileUrl = msg['fileUrl'] ?? '';
    final isFile = msg['isFile'] == true || fileUrl.isNotEmpty;
    final bool isDeleted = msg['deleted'] == true;
    final bool isEdited = msg['edited'] == true;

    final bool isSelected = _selectedMessageIds.contains(messageId);

    Color backgroundColor;
    if (isSelected) {
      backgroundColor = Colors.red.shade100;
    } else {
      backgroundColor = isSender ? Colors.blue[100]! : Colors.grey[200]!;
    }

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _isSelectionMode = true;
          _selectedMessageIds.add(messageId);
        });
      },
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (_selectedMessageIds.contains(messageId)) {
              _selectedMessageIds.remove(messageId);
              if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
            } else {
              _selectedMessageIds.add(messageId);
            }
          });
        }
      },
      child: Align(
        alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment:
                isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isSender) // Show sender name only for others
                Text(
                  _getUsername(msg['sender']),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              if (isDeleted)
                const Text(
                  '[Message deleted]',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey),
                )
else if (isFile)
  GestureDetector(
    onTap: () async {
      // Try open local cached file first
      final localFile = await _getLocalFileForUrl(fileUrl);
      if (await localFile.exists()) {
        await OpenFile.open(localFile.path);
      } else {
        // Download file and open
        final downloadedFile = await _downloadFile(fileUrl);
        if (downloadedFile != null) {
          await OpenFile.open(downloadedFile.path);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to open file')),
          );
        }
      }
    },
    child: Text(
      '📎 File: ${fileUrl.split('/').last}',
      style: const TextStyle(
        color: Colors.blue,
        decoration: TextDecoration.underline,
      ),
    ),
  )

              else
                Text.rich(
                  TextSpan(
                    text: msg['content'],
                    children: isEdited
                        ? [
                            const TextSpan(
                              text: ' (edited)',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey),
                            )
                          ]
                        : [],
                  ),
                ),
              Text(
                formattedTime,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedActionBar() {
    if (!_isSelectionMode) return const SizedBox.shrink();
    return Container(
      color: Colors.grey.shade300,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              bool confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete selected messages?'),
                      content: Text(
                          'Are you sure you want to delete ${_selectedMessageIds.length} messages?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (confirm) {
                for (String msgId in _selectedMessageIds.toList()) {
                  await _deleteGroupMessage(msgId);
                }
                setState(() {
                  _isSelectionMode = false;
                  _selectedMessageIds.clear();
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _selectedMessageIds.length == 1
                ? () {
                    final msgId = _selectedMessageIds.first;
                    final msg = messages.firstWhere((m) => m['id'] == msgId);
                    _showEditMessageDialog(msg);
                    setState(() {
                      _isSelectionMode = false;
                      _selectedMessageIds.clear();
                    });
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _isSelectionMode = false;
                _selectedMessageIds.clear();
              });
            },
          ),
          Expanded(
            child: Text(
              '${_selectedMessageIds.length} selected',
              textAlign: TextAlign.center,
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
            icon:
                Icon(_showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions),
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
              minLines: 1,
              maxLines: 5,
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
bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Widget _buildDateDivider(DateTime date) {
  String text;
  final now = DateTime.now();
  if (_isSameDay(date, now)) {
    text = 'Today';
  } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
    text = 'Yesterday';
  } else {
    text = DateFormat('MMMM dd, yyyy').format(date);
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ),
    ),
  );
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
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedMessageIds.clear();
                });
              },
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSelectedActionBar(),
                Expanded(
                  child: messages.isEmpty
                      ? const Center(child: Text('No messages yet.'))
                      :ListView.builder(
  controller: _scrollController,
  itemCount: messages.length,
  itemBuilder: (context, index) {
    final msg = messages[index];
    final DateTime msgDate = DateTime.parse(msg['timestamp']);
    bool showDateHeader = false;
    if (index == 0) {
      showDateHeader = true;
    } else {
      final prevMsgDate = DateTime.parse(messages[index - 1]['timestamp']);
      if (!_isSameDay(msgDate, prevMsgDate)) {
        showDateHeader = true;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateHeader)
          _buildDateDivider(msgDate),
        _buildMessageItem(msg),
      ],
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
                        _messageController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: _messageController.text.length),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
