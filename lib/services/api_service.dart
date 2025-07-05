import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart'; 


class ApiService {
static const String baseUrl = 'http://10.202.42.143:4000';


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

 
  static Future<List<Message>> getMessages(String sender, String receiver) async {
    final url = Uri.parse('$baseUrl/messages?sender=$sender&receiver=$receiver');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Fetched messages: $data');

      List<Message> messages = (data['data'] as List)
          .map((msgJson) {
            print('Processing message: $msgJson'); 
            return Message.fromJson(msgJson);
          })
          .toList();
      return messages;
    } else {
      print('❌ Failed to fetch messages: ${response.body}');
      return [];
    }
  }

  static Future<List<String>> fetchGroupIds(String jwtToken) async {
    final url = Uri.parse('$baseUrl/groups');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $jwtToken'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((group) => group['_id'].toString()).toList();
    } else {
      print('❌ Failed to fetch group IDs: ${response.statusCode}');
      throw Exception('Failed to fetch group IDs');
    }
  }
}
