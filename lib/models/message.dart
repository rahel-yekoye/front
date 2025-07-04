class Message {
  final String id;
  final String sender;
  final String receiver;
  final String content;
  final String timestamp;
  final bool isGroup;
  final List<String> emojis;
  final String fileUrl;
  final List<String> readBy;
  final bool isFile;
  final bool deleted;
  final bool edited;
  final String? type;
  final String? direction;
  final int? duration;

  Message({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
    required this.isGroup,
    required this.emojis,
    required this.fileUrl,
    this.readBy = const [],
    required this.isFile,
    required this.deleted,
    required this.edited,
    this.type,
    this.direction,
    this.duration,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      sender: json['sender'] ?? '',
      receiver: json['receiver'] ?? '',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] ?? '',
      isGroup: json['isGroup'] ?? false,
      emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
      fileUrl: json['fileUrl'] ?? '',
      readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
      isFile: json['isFile'] ?? false,
      deleted: json['deleted'] ?? false,
      edited: json['edited'] ?? false,
      type: json['type'],
      direction: json['direction'],
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(json['duration']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'receiver': receiver,
      'content': content,
      'timestamp': timestamp,
      'isGroup': isGroup,
      'emojis': emojis,
      'fileUrl': fileUrl,
      'readBy': readBy,
      'isFile': isFile,
      'deleted': deleted,
      'edited': edited,
      'type': type,
      'direction': direction,
      'duration': duration,
    };
  }
}
