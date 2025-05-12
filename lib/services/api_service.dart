import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart'; // Import Message model


class ApiService {
  static const String baseUrl = 'http://127.0.0.1:4000'; // ⚠️ Note: use 10.0.2.2 for Android Emulator

  // Send a message
  static Future<bool> sendMessage(String sender, String receiver, String content) async {
    final url = Uri.parse('$baseUrl/messages');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender': sender,
        'receiver': receiver,
        'content': content,
      }),
    );

    if (response.statusCode == 200) {
      print('✅ Message sent: ${response.body}');
      return true;
    } else {
      print('❌ Failed to send message: ${response.body}');
      return false;
    }
  }

  // Fetch messages between two users
  static Future<List<Message>> getMessages(String sender, String receiver) async {
    final url = Uri.parse('$baseUrl/messages?sender=$sender&receiver=$receiver');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Fetched messages: $data'); // Debug log

      List<Message> messages = (data['data'] as List)
          .map((msgJson) {
            print('Processing message: $msgJson'); // Debug log
            return Message.fromJson(msgJson);
          })
          .toList();
      return messages;
    } else {
      print('❌ Failed to fetch messages: ${response.body}');
      return [];
    }
  }

  // Fetch group IDs for the current user
  static Future<List<String>> fetchGroupIds(String jwtToken) async {
    final url = Uri.parse('$baseUrl/groups');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $jwtToken'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      // Extract group IDs from the response
      return data.map((group) => group['_id'].toString()).toList();
    } else {
      print('❌ Failed to fetch group IDs: ${response.statusCode}');
      throw Exception('Failed to fetch group IDs');
    }
  }
}
