// lib/api/feedback_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class FeedbackItem {
  final String applicationId;
  final String feedbackId;
  final String memberId;
  final String memberName;
  final String message;
  final String date;
  final String? newsId;
  final String? newsTitle;
  final String? newsQuestion;
  final String? reply;
  final String? repliedAt;

  FeedbackItem({
    required this.applicationId,
    required this.feedbackId,
    required this.memberId,
    required this.memberName,
    required this.message,
    required this.date,
    this.newsId,
    this.newsTitle,
    this.newsQuestion,
    this.reply,
    this.repliedAt,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) => FeedbackItem(
        applicationId: json['applicationId'] as String,
        feedbackId: json['feedbackId'] as String,
        memberId: json['memberId'] as String,
        memberName: json['memberName'] as String? ?? '',
        message: json['message'] as String,
        date: json['date'] as String,
        newsId: json['newsId'] as String?,
        newsTitle: json['newsTitle'] as String?,
        newsQuestion: json['newsQuestion'] as String?,
        reply: json['reply'] as String?,
        repliedAt: json['repliedAt'] as String?,
      );

  bool get hasReply => reply != null && reply!.isNotEmpty;
  bool get isFromNews => newsId != null;
}

class FeedbackApi {
  final AppConfig config;
  final http.Client _client;

  FeedbackApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<FeedbackItem>> getFeedback() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/feedback'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Fehler beim Laden: ${response.statusCode}');
  }

  Future<void> postFeedback({
    required String message,
    String? newsId,
    String? newsTitle,
    String? newsQuestion,
  }) async {
    final payload = <String, dynamic>{'message': message};
    if (newsId != null) payload['newsId'] = newsId;
    if (newsTitle != null) payload['newsTitle'] = newsTitle;
    if (newsQuestion != null) payload['newsQuestion'] = newsQuestion;

    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/feedback'),
      headers: headers(config),
      body: json.encode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Senden: ${response.statusCode}');
    }
  }

  Future<void> postReply({
    required String feedbackId,
    required String reply,
  }) async {
    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/feedback/$feedbackId/reply'),
      headers: headers(config),
      body: json.encode({'reply': reply}),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Antworten: ${response.statusCode}');
    }
  }
}
