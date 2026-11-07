// lib/api/news_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config_loader.dart';
import 'headers.dart';

class NewsItem {
  final String newsId;
  final String title;
  final String body;
  final String date;
  final String? expiresAt;
  final String? question;
  final List<String>? questionOptions;

  NewsItem({
    required this.newsId,
    required this.title,
    required this.body,
    required this.date,
    this.expiresAt,
    this.question,
    this.questionOptions,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) => NewsItem(
        newsId: json['newsId'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        date: json['date'] as String,
        expiresAt: json['expiresAt'] as String?,
        question: json['question'] as String?,
        questionOptions: json['questionOptions'] != null
            ? List<String>.from(json['questionOptions'] as List)
            : null,
      );
}

class NewsApi {
  final AppConfig config;
  final http.Client _client;

  NewsApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  Future<List<NewsItem>> getNews() async {
    final response = await _client.get(
      Uri.parse('${config.apiBaseUrl}/news'),
      headers: headers(config),
    );
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      return list.map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Fehler beim Laden der Neuigkeiten: ${response.statusCode}');
  }

  Future<void> createNews({
    required String title,
    required String body,
    String? expiresAt,
    String? question,
    List<String>? questionOptions,
  }) async {
    final payload = <String, dynamic>{'title': title, 'body': body};
    if (expiresAt != null) payload['expiresAt'] = expiresAt;
    if (question != null) payload['question'] = question;
    if (questionOptions != null) payload['questionOptions'] = questionOptions;

    final response = await _client.post(
      Uri.parse('${config.apiBaseUrl}/news'),
      headers: headers(config),
      body: json.encode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Erstellen: ${response.statusCode}');
    }
  }

  Future<void> deleteNews(String newsId) async {
    final response = await _client.delete(
      Uri.parse('${config.apiBaseUrl}/news/$newsId'),
      headers: headers(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Fehler beim Löschen: ${response.statusCode}');
    }
  }
}
