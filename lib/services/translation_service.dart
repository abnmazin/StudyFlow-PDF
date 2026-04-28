import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../providers/app_state.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._();
  TranslationService._();
  factory TranslationService() => _instance;

  Future<String> translate(String text, AppProvider app) async {
    if (text.trim().isEmpty) return "";

    app.resetFallbackAttempts();

    while (true) {
      try {
        final result = app.aiProvider == 'gemini'
            ? await _translateGemini(text, app)
            : await _translateGroq(text, app);
        return result;
      } catch (e) {
        debugPrint(
          '[TranslationService] Failed with ${app.aiProvider} '
          '(${app.currentModel}): $e',
        );
        final canRetry = app.triggerAiFallback();
        if (!canRetry) {
          debugPrint('[TranslationService] All providers exhausted.');
          return 'فشلت الترجمة: تحقق من مفاتيح API أو الاتصال بالإنترنت.';
        }
        // Brief pause before retrying the next model/provider
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<String> _translateGemini(String text, AppProvider app) async {
    final settingsKey = app.geminiApiKey.trim();
    final envKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();
    final apiKey = settingsKey.isNotEmpty ? settingsKey : envKey;

    if (apiKey.isEmpty) {
      return "فشل: GEMINI_API_KEY غير موجود في الإعدادات أو .env";
    }

    final prompt = "Translate the following text to Arabic (or English if it is already Arabic). Only return the translated text without any conversational filler:\n\n$text";
    final modelName = app.geminiModel;

    final model = GenerativeModel(model: modelName, apiKey: apiKey);
    final response = await model.generateContent([Content.text(prompt)]);
    final translated = (response.text ?? '').trim();
    return translated.isEmpty ? "لم أتمكن من الترجمة." : translated;
  }

  Future<String> _translateGroq(String text, AppProvider app) async {
    final settingsKey = app.groqApiKey.trim();
    final envKey = (dotenv.env['GROQ_API_KEY'] ?? '').trim();
    final apiKey = settingsKey.isNotEmpty ? settingsKey : envKey;

    if (apiKey.isEmpty) {
      return "فشل: GROQ_API_KEY غير موجود في الإعدادات أو .env";
    }

    final prompt = "Translate the following text to Arabic (or English if it is already Arabic). Only return the translated text without any conversational filler:\n\n$text";
    final modelName = app.groqModel;

    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': modelName,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.1,
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Groq HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Groq empty response');
    }

    final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    final content = (message?['content'] ?? '').toString().trim();
    return content.isEmpty ? "لم أتمكن من الترجمة." : content;
  }
}
