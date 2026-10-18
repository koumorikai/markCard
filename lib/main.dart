import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Файл .env не найден или не удалось загрузить: $e");
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MarkCardApp());
}

final supabase = Supabase.instance.client;

class MarkCardApp extends StatelessWidget {
  const MarkCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarkCard',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0B14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF9333EA),
          surface: Color(0xFF13101E),
          onSurface: Color(0xFFF9FAFB),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF13101E),
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              width: 1.0,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final session = supabase.auth.currentSession;
      setState(() {
        _isLoggedIn = session != null;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }
    return _isLoggedIn ? const MainNavigationScreen() : const AuthScreen();
  }
}

class Flashcard {
  final String id;
  final String front;
  final String back;
  final String? contextExample;
  final String category;

  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.contextExample,
    required this.category,
  });
}

class GroqService {
  static const String _endpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _originalModel = 'openai/gpt-oss-20b';
  static const int _targetCardCount = 20;

  static String _normalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isValidCard(Map<String, dynamic> card) {
    final front = card['front']?.toString().trim();
    final back = card['back']?.toString().trim();
    final contextExample = card['contextExample']?.toString().trim();

    return front != null &&
        front.isNotEmpty &&
        back != null &&
        back.isNotEmpty &&
        contextExample != null &&
        contextExample.isNotEmpty;
  }

  static String _buildSystemPrompt() {
    return '''
You are the AI flashcard generation engine for MarkCard.

Your task is to create exactly 20 high-quality educational
flashcards for the topic provided by the user.

Generation requirements:

1. Generate exactly 20 flashcards.
2. Every flashcard must teach one distinct learning objective.
3. Avoid duplicate and nearly identical flashcards.
4. Use the requested source language for the front field.
5. Use the requested target language for the back field.
6. Provide an accurate, concise, and useful definition or translation.
7. Include a relevant contextual example in every card.
8. Adapt the complexity to the requested difficulty.
9. Do not invent facts or provide misleading definitions.
10. Avoid unnecessary information and excessively long explanations.
11. Return valid JSON only.
12. Do not include Markdown fences or introductory text.
13. Do not include properties outside the required schema.

Return this exact JSON structure:

{
  "flashcards": [
    {
      "front": "Term, question, or concept",
      "back": "Definition or translation",
      "contextExample": "Example sentence or practical context"
    }
  ]
}

The flashcards array must contain exactly 20 objects.

All three properties must be non-empty strings.
Every card must be meaningfully different from the others.

Return only the JSON object.
''';
  }

  static Future<List<Flashcard>> generate20Cards({
    required String topic,
    required String sourceLanguage,
    required String targetLanguage,
    required String difficulty,
  }) async {
    final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('GROQ_API_KEY не найден в файле .env');
    }

    final List<Flashcard> validCards = [];
    final Set<String> seenFronts = {};

    int attempts = 0;
    const int maxAttempts = 3;

    while (validCards.length < _targetCardCount && attempts < maxAttempts) {
      attempts++;
      final neededCount = _targetCardCount - validCards.length;

      String userPrompt;
      if (validCards.isEmpty) {
        userPrompt = '''
Topic: $topic
Source Language: $sourceLanguage
Target Language: $targetLanguage
Difficulty: $difficulty
Generate exactly $_targetCardCount flashcards.
''';
      } else {
        final existingConcepts =
            validCards.map((c) => c.front).take(15).join(', ');
        userPrompt = '''
Topic: $topic
Source Language: $sourceLanguage
Target Language: $targetLanguage
Difficulty: $difficulty
Generate exactly $neededCount additional unique flashcards.
Do not duplicate any of these existing terms: $existingConcepts.
''';
      }

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': _originalModel,
              'temperature': 0.5,
              'messages': [
                {'role': 'system', 'content': _buildSystemPrompt()},
                {'role': 'user', 'content': userPrompt},
              ],
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception(
            'Ошибка Groq API (${response.statusCode}): ${response.body}');
      }

      final decodedResponse = jsonDecode(utf8.decode(response.bodyBytes));
      final choices = decodedResponse['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('Groq API вернул пустой ответ');
      }

      String rawContent = choices[0]['message']['content'] ?? '';
      rawContent = rawContent
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      Map<String, dynamic> parsedJson;
      try {
        parsedJson = jsonDecode(rawContent);
      } catch (e) {
        throw Exception('Не удалось разобрать JSON ответа Groq');
      }

      final cardsArray = parsedJson['flashcards'] as List?;
      if (cardsArray == null) {
        continue;
      }

      for (var item in cardsArray) {
        if (item is Map<String, dynamic> && _isValidCard(item)) {
          final front = item['front'].toString().trim();
          final normalizedFront = _normalize(front);

          if (!seenFronts.contains(normalizedFront)) {
            seenFronts.add(normalizedFront);
            validCards.add(Flashcard(
              id: DateTime.now().microsecondsSinceEpoch.toString() +
                  math.Random().nextInt(1000).toString(),
              front: front,
              back: item['back'].toString().trim(),
              contextExample: item['contextExample'].toString().trim(),
              category: topic,
            ));
          }
        }
        if (validCards.length == _targetCardCount) break;
      }
    }

    if (validCards.length < _targetCardCount) {
      throw Exception(
          'Не удалось сгенерировать ровно 20 уникальных карточек (получено ${validCards.length}). Попробуйте еще раз.');
    }

    return validCards.sublist(0, _targetCardCount);
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignUp = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final nickname = _nicknameController.text.trim();

      if (_isSignUp) {
        if (nickname.isEmpty) {
          throw 'Введите уникальный никнейм!';
        }

        final response = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        final user = response.user;
        if (user != null) {
          await supabase.from('profiles').insert({
            'id': user.id,
            'email': email,
            'nickname': nickname,
            'avatar_url':
                'https://i.pravatar.cc/150?img=${math.Random().nextInt(70)}',
            'total_words_learned': 0,
          });
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Ошибка: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.style_rounded,
                    size: 64, color: Color(0xFF7C3AED)),
                const SizedBox(height: 16),
                Text(
                  _isSignUp ? 'Регистрация в MarkCard' : 'Вход в MarkCard',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 32),
                if (_isSignUp) ...[
                  TextField(
                    controller: _nicknameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Уникальный никнейм',
                      labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      filled: true,
                      fillColor: const Color(0xFF13101E),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Gmail',
                    labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFF13101E),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: const Color(0xFF13101E),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isSignUp ? 'Зарегистрироваться' : 'Войти',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Уже есть аккаунт? Войти'
                        : 'Нет аккаунта? Зарегистрироваться',
                    style: const TextStyle(color: Color(0xFFA78BFA)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  int _streakDays = 0;
  int _wordsLearnedToday = 0;
  final Set<int> _activeDaysInMonth = {};

  final List<String> _todayCategories = ['Business IT'];
  String _dailyEssay =
      'Напиши размышление о технологиях на основе изученных тем.';
  bool _essayCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadUserProgress();
  }

  Future<void> _loadUserProgress() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      final todayStr = now.toIso8601String().split('T')[0];

      final todayResponse = await supabase
          .from('daily_progress')
          .select()
          .eq('user_id', user.id)
          .eq('date', todayStr)
          .maybeSingle();

      final firstDayOfMonth =
          DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
      final monthRecords = await supabase
          .from('daily_progress')
          .select('date, words_count')
          .eq('user_id', user.id)
          .gte('date', firstDayOfMonth);

      final Set<int> activeDays = {};
      for (var record in monthRecords) {
        if ((record['words_count'] ?? 0) > 0) {
          final date = DateTime.parse(record['date']);
          activeDays.add(date.day);
        }
      }

      setState(() {
        _activeDaysInMonth.clear();
        _activeDaysInMonth.addAll(activeDays);
        _streakDays = activeDays.length;

        if (todayResponse != null) {
          _wordsLearnedToday = todayResponse['words_count'] ?? 0;
          _essayCompleted = todayResponse['essay_completed'] ?? false;
          if (todayResponse['categories'] != null) {
            _todayCategories.clear();
            for (var cat in todayResponse['categories']) {
              _todayCategories.add(cat.toString());
            }
          }
          if (_todayCategories.isNotEmpty) {
            _dailyEssay =
                'На основе категорий за сегодня (${_todayCategories.join(', ')}): напиши короткое эссе.';
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _onWordReviewed(String category) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _wordsLearnedToday++;
      if (!_todayCategories.contains(category)) {
        _todayCategories.add(category);
        _dailyEssay =
            'На основе категорий за сегодня (${_todayCategories.join(', ')}): напиши короткое эссе.';
      }
      _activeDaysInMonth.add(DateTime.now().day);
      _streakDays = _activeDaysInMonth.length;
    });

    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    try {
      await supabase.from('daily_progress').upsert({
        'user_id': user.id,
        'date': todayStr,
        'words_count': _wordsLearnedToday,
        'categories': _todayCategories,
      }, onConflict: 'user_id,date');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MainReviewTab(onWordLearned: _onWordReviewed),
      StreakTab(
        streakDays: _streakDays,
        wordsToday: _wordsLearnedToday,
        activeDays: _activeDaysInMonth,
        congratulationText: _streakDays > 0
            ? 'Отличный темп! Твоя серия растет 🔥'
            : 'Начни изучать карточки сегодня, чтобы зажечь серию!',
      ),
      EssayTab(
        categories: _todayCategories,
        essayPrompt: _dailyEssay,
        isCompleted: _essayCompleted,
        onCompleted: () => setState(() => _essayCompleted = true),
      ),
      const ProfileTab(),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D0B14),
              Color(0xFF160F2B),
              Color(0xFF3B1863),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: pages[_selectedIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0B14).withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFF7C3AED).withValues(alpha: 0.3),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: Color(0xFF9CA3AF)),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFFA78BFA)),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_fire_department_outlined,
                  color: Color(0xFF9CA3AF)),
              selectedIcon: Icon(Icons.local_fire_department_rounded,
                  color: Colors.orangeAccent),
              label: 'Серия',
            ),
            NavigationDestination(
              icon: Icon(Icons.edit_note_rounded, color: Color(0xFF9CA3AF)),
              selectedIcon: Icon(Icons.edit_note, color: Color(0xFFA78BFA)),
              label: 'Эссе',
            ),
            NavigationDestination(
              icon:
                  Icon(Icons.person_outline_rounded, color: Color(0xFF9CA3AF)),
              selectedIcon:
                  Icon(Icons.person_rounded, color: Color(0xFFA78BFA)),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}

class MainReviewTab extends StatefulWidget {
  final Function(String) onWordLearned;
  const MainReviewTab({super.key, required this.onWordLearned});

  @override
  State<MainReviewTab> createState() => _MainReviewTabState();
}

class _MainReviewTabState extends State<MainReviewTab>
    with SingleTickerProviderStateMixin {
  final List<Flashcard> _deck = [
    Flashcard(
      id: 'intro_1',
      front: '⚡ Welcome to MarkCard!',
      back: 'Твой умный карманный помощник для запоминания терминов.',
      contextExample: 'Используй стрелочки внизу для навигации.',
      category: 'Приветствие',
    ),
    Flashcard(
      id: 'intro_2',
      front: '🔮 Что такое MarkCard?',
      back: 'Приложение с генерацией карточек через Groq AI и базой Supabase.',
      contextExample: 'Строгий минималистичный дизайн.',
      category: 'О приложении',
    ),
    Flashcard(
      id: 'intro_3',
      front: '📖 Инструкция по использованию',
      back:
          '1. Нажми на ✨ вверху, чтобы сгенерировать 20 карточек по любой теме через ИИ.\n2. Переворачивай карточки тапом.\n3. Пиши ежедневное эссе во вкладке «Эссе».',
      contextExample: 'Учись каждый день, чтобы растить свою серию 🔥',
      category: 'Инструкция',
    ),
    Flashcard(
      id: 'intro_4',
      front: '🌐 Наши Социальные сети',
      back:
          'Следи за обновлениями проекта, делись фидбеком и присоединяйся к нашему сообществу разработчиков!',
      contextExample: 'Telegram: @markelxvvv\nGitHub: github.com/koumorikai',
      category: 'Сообщество',
    ),
  ];

  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _isLoading = false;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    setState(() {
      _isFlipped = !_isFlipped;
      if (_isFlipped) {
        _flipController.forward();
      } else {
        _flipController.reverse();
      }
    });
  }

  void _nextCard({bool countAsLearned = false}) {
    if (countAsLearned) {
      widget.onWordLearned(_deck[_currentIndex].category);
    }
    setState(() {
      _isFlipped = false;
      _flipController.value = 0.0;
      if (_currentIndex < _deck.length - 1) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }
    });
  }

  void _prevCard() {
    setState(() {
      _isFlipped = false;
      _flipController.value = 0.0;
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        _currentIndex = _deck.length - 1;
      }
    });
  }

  Future<void> _showAIGeneratorDialog() async {
    final topicController = TextEditingController();
    String sourceLang = 'English';
    String targetLang = 'Russian';
    String difficulty = 'Intermediate';

    final languages = ['English', 'Russian', 'Spanish', 'German', 'French'];
    final difficulties = ['Beginner', 'Intermediate', 'Advanced'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF13101E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
          ),
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFFA78BFA)),
              SizedBox(width: 10),
              Text('Генерация (20 карточек)',
                  style: TextStyle(color: Color(0xFFF9FAFB), fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: topicController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Тема (Topic)',
                    labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                    hintText: 'Напр. English Idioms, Data Structures',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Color(0xFF7C3AED), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: sourceLang,
                  dropdownColor: const Color(0xFF13101E),
                  decoration: const InputDecoration(
                      labelText: 'Исходный язык (Front)'),
                  items: languages
                      .map((lang) =>
                          DropdownMenuItem(value: lang, child: Text(lang)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => sourceLang = val ?? sourceLang),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: targetLang,
                  dropdownColor: const Color(0xFF13101E),
                  decoration:
                      const InputDecoration(labelText: 'Язык перевода (Back)'),
                  items: languages
                      .map((lang) =>
                          DropdownMenuItem(value: lang, child: Text(lang)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => targetLang = val ?? targetLang),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: difficulty,
                  dropdownColor: const Color(0xFF13101E),
                  decoration: const InputDecoration(labelText: 'Сложность'),
                  items: difficulties
                      .map((diff) =>
                          DropdownMenuItem(value: diff, child: Text(diff)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => difficulty = val ?? difficulty),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final topic = topicController.text.trim();
                if (topic.isEmpty) return;
                Navigator.pop(context);
                await _generateAndPreviewCards(
                  topic: topic,
                  sourceLanguage: sourceLang,
                  targetLanguage: targetLang,
                  difficulty: difficulty,
                );
              },
              child: const Text('Сгенерировать',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAndPreviewCards({
    required String topic,
    required String sourceLanguage,
    required String targetLanguage,
    required String difficulty,
  }) async {
    setState(() => _isLoading = true);

    try {
      final newCards = await GroqService.generate20Cards(
        topic: topic,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        difficulty: difficulty,
      );

      setState(() => _isLoading = false);

      if (mounted) {
        _showPreviewDialog(newCards);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Ошибка генерации: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showPreviewDialog(List<Flashcard> generatedCards) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13101E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
        ),
        title: Text(
          'Предпросмотр (${generatedCards.length} карточек)',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.separated(
            itemCount: generatedCards.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white24),
            itemBuilder: (context, index) {
              final card = generatedCards[index];
              return ListTile(
                dense: true,
                title: Text('${index + 1}. ${card.front}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('${card.back}\nContext: ${card.contextExample}',
                    style: const TextStyle(color: Colors.white70)),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            onPressed: () {
              setState(() {
                _deck.addAll(generatedCards);
                _currentIndex = _deck.length - generatedCards.length;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Успешно добавлено 20 карточек в колоду!'),
                  backgroundColor: Color(0xFF7C3AED),
                ),
              );
            },
            child: const Text('Сохранить в колоду',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_deck.isEmpty) {
      return const Scaffold(body: Center(child: Text('Колода пуста')));
    }
    final currentCard = _deck[_currentIndex];
    final bool isIntroCard = _currentIndex < 4;

    return SafeArea(
      child: Column(
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: const Text('MarkCard',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    fontSize: 20)),
            actions: [
              IconButton(
                icon: const Icon(Icons.auto_awesome,
                    color: Color(0xFFA78BFA), size: 24),
                onPressed: _isLoading ? null : _showAIGeneratorDialog,
              ),
              const SizedBox(width: 8),
            ],
          ),
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF9333EA)),
                            SizedBox(height: 16),
                            Text(
                                'Groq AI генерирует ровно 20 уникальных карточек...',
                                style: TextStyle(color: Color(0xFFA78BFA))),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: (_currentIndex + 1) / _deck.length,
                              minHeight: 5,
                              backgroundColor: const Color(0xFF13101E),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF9333EA)),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: const Color(0xFF7C3AED)
                                      .withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '${currentCard.category} (${_currentIndex + 1}/${_deck.length})',
                              style: const TextStyle(
                                  color: Color(0xFFD8B4FE),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: GestureDetector(
                              onTap: _toggleFlip,
                              child: AnimatedBuilder(
                                animation: _flipAnimation,
                                builder: (context, child) {
                                  final angle = _flipAnimation.value * math.pi;
                                  final isBack = angle >= (math.pi / 2);

                                  return Transform(
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.001)
                                      ..rotateY(angle),
                                    alignment: Alignment.center,
                                    child: isBack
                                        ? Transform(
                                            transform: Matrix4.identity()
                                              ..rotateY(math.pi),
                                            alignment: Alignment.center,
                                            child: Card(
                                                child: _buildCardContent(
                                                    currentCard.back,
                                                    currentCard.contextExample,
                                                    true)),
                                          )
                                        : Card(
                                            child: _buildCardContent(
                                                currentCard.front,
                                                null,
                                                false)),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (isIntroCard)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildNavigationButton('Назад', _prevCard),
                                Text('${_currentIndex + 1} / 4',
                                    style: const TextStyle(
                                        color: Color(0xFF9CA3AF))),
                                _buildNavigationButton(
                                    'Вперед', () => _nextCard()),
                              ],
                            )
                          else if (_isFlipped)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildActionButton('Снова', Colors.redAccent,
                                    () => _nextCard(countAsLearned: true)),
                                _buildActionButton(
                                    'Хорошо',
                                    const Color(0xFF9333EA),
                                    () => _nextCard(countAsLearned: true)),
                                _buildActionButton('Легко', Colors.greenAccent,
                                    () => _nextCard(countAsLearned: true)),
                              ],
                            )
                          else
                            const SizedBox(height: 48),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContent(String text, String? example, bool isBackSide) {
    bool hasEmojiPrefix = text.startsWith('🌐') ||
        text.startsWith('📖') ||
        text.startsWith('⚡') ||
        text.startsWith('🔮');

    String titleText = text;
    String? emojiPart;

    if (hasEmojiPrefix) {
      List<String> parts = text.split(' ');
      emojiPart = parts[0];
      titleText = text.substring(emojiPart.length).trim();
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(24.0),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasEmojiPrefix && emojiPart != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emojiPart, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      titleText,
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF9FAFB),
                          height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                text,
                style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF9FAFB),
                    height: 1.3),
                textAlign: TextAlign.center,
              ),
            ],
            if (example != null && example.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                example,
                style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xFFF9FAFB).withValues(alpha: 0.65),
                    fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
        foregroundColor: const Color(0xFFA78BFA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _buildActionButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(text),
    );
  }
}

class StreakTab extends StatelessWidget {
  final int streakDays;
  final int wordsToday;
  final Set<int> activeDays;
  final String congratulationText;

  const StreakTab(
      {super.key,
      required this.streakDays,
      required this.wordsToday,
      required this.activeDays,
      required this.congratulationText});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.local_fire_department_rounded,
                size: 72, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            Text('$streakDays Дней Подряд!',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 10),
            Text(congratulationText,
                style: const TextStyle(color: Color(0xFFD8B4FE), fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: const Color(0xFF13101E),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Изучено за сегодня',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                  Text('$wordsToday слов',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Календарь Занятий',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white))),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: 31,
              itemBuilder: (context, index) {
                final day = index + 1;
                final isActive = activeDays.contains(day);
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF13101E),
                  ),
                  child: Center(
                      child: Text('$day',
                          style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xFF9CA3AF)))),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class EssayTab extends StatefulWidget {
  final List<String> categories;
  final String essayPrompt;
  final bool isCompleted;
  final VoidCallback onCompleted;

  const EssayTab({
    super.key,
    required this.categories,
    required this.essayPrompt,
    required this.isCompleted,
    required this.onCompleted,
  });

  @override
  State<EssayTab> createState() => _EssayTabState();
}

class _EssayTabState extends State<EssayTab> {
  final TextEditingController _essayController = TextEditingController();
  bool _isAnalyzing = false;

  Future<void> _submitAndAnalyzeEssay() async {
    final essayText = _essayController.text.trim();
    if (essayText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Эссе не может быть пустым!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          "model": "openai/gpt-oss-20b",
          "messages": [
            {
              "role": "system",
              "content":
                  "You are a strict and objective AI instructor and linguistic mentor. "
                      "Analyze the student's submitted essay and evaluate it according to the following criteria:\n"
                      "1. Relevance to the question/topic (how accurately the topic is covered).\n"
                      "2. Structure and logic (introduction, body paragraphs, conclusion).\n"
                      "3. Grammar and vocabulary (errors, style).\n\n"
                      "Provide constructive feedback in Russian, highlight strengths and areas for growth, and give an approximate score from 1 to 10."
            },
            {
              "role": "user",
              "content":
                  "Essay Question/Topic: \"${widget.essayPrompt}\"\n\nStudent's Essay:\n$essayText"
            }
          ],
          "temperature": 0.5,
          "max_tokens": 1500
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String feedback = data['choices'][0]['message']['content'];

        setState(() => _isAnalyzing = false);

        final user = supabase.auth.currentUser;
        if (user != null) {
          final todayStr = DateTime.now().toIso8601String().split('T')[0];
          await supabase.from('daily_progress').update({
            'essay_text': essayText,
            'essay_completed': true,
          }).match({
            'user_id': user.id,
            'date': todayStr,
          });
        }

        widget.onCompleted();

        if (mounted) {
          _showFeedbackDialog(feedback);
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка анализа: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showFeedbackDialog(String feedback) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13101E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFFA78BFA)),
            SizedBox(width: 10),
            Text('Результат анализа ИИ',
                style: TextStyle(color: Color(0xFFF9FAFB), fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              feedback,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ежедневное Эссе 📝',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFF13101E),
                  borderRadius: BorderRadius.circular(16)),
              child: Text(widget.essayPrompt,
                  style: const TextStyle(color: Colors.white, height: 1.4)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _essayController,
              maxLines: 6,
              enabled: !widget.isCompleted && !_isAnalyzing,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: widget.isCompleted
                    ? 'Эссе уже сдано и проверено!'
                    : 'Напиши свое эссе здесь...',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                filled: true,
                fillColor: const Color(0xFF13101E),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: (widget.isCompleted || _isAnalyzing)
                    ? null
                    : _submitAndAnalyzeEssay,
                child: _isAnalyzing
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('ИИ анализирует эссе...',
                              style: TextStyle(color: Colors.white)),
                        ],
                      )
                    : Text(
                        widget.isCompleted
                            ? '✓ Выполнено и проверено'
                            : 'Отправить и проверить',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFF7C3AED),
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              user?.email ?? 'Пользователь',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'ID: ${user?.id.substring(0, 8) ?? '---'}',
                style: const TextStyle(color: Color(0xFFD8B4FE), fontSize: 12),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () async {
                  await supabase.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  }
                },
                child: const Text('Выйти из аккаунта',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}