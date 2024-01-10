import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dio = Dio(
    BaseOptions(baseUrl: 'https://gpt-demo.julianhartl.dev'),
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    MyApp(
      dio: dio,
    ),
  );
}

final baseTheme = ThemeData.from(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF00A180),
    onPrimary: Colors.white,
    secondary: Color(0xFF4A56B8),
    onSecondary: Colors.white,
    surface: Color(0xFF2C3E50),
    onSurface: Colors.white,
    background: Color(0xFF121212),
    onBackground: Colors.white,
    error: Colors.redAccent,
    onError: Colors.white,
  ),
  textTheme: const TextTheme(),
);

final gptTheme = baseTheme.copyWith(
  appBarTheme: AppBarTheme(
    backgroundColor: baseTheme.colorScheme.background,
    foregroundColor: baseTheme.colorScheme.onBackground,
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
    ),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.dio});

  final Dio dio;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatProvider(dio),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(dio),
        ),
      ],
      child: MaterialApp(
        home: const Home(),
        title: 'GDSC GPT',
        debugShowCheckedModeBanner: false,
        theme: gptTheme,
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      VoidCallback? listener;
      listener = () {
        if (authProvider.currentUser == null) {
          return;
        }
        final chatProvider = context.read<ChatProvider>();
        chatProvider.loadCurrentOrCreateChat();
        authProvider.removeListener(listener!);
      };
      authProvider.addListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    if (authProvider.currentUser == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    final chatProvider = context.watch<ChatProvider>();
    final chat = chatProvider.currentChat;
    return Scaffold(
      appBar: buildAppBar(chat, context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Expanded(
                child: chat == null
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : ChatDisplay(chat: chat),
              ),
              const ChatInput(),
            ],
          ),
        ),
      ),
    );
  }

  AppBar buildAppBar(Chat? chat, BuildContext context) {
    return AppBar(
      title: Text(chat?.title ?? 'ChatGPT'),
      actions: [
        IconButton(
          onPressed: () async {
            await context.read<ChatProvider>().startNewChat();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class ChatDisplay extends StatelessWidget {
  const ChatDisplay({super.key, required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    if (chat.messages.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 300,
          ),
          child: const FractionallySizedBox(
            widthFactor: 0.5,
            child: Image(
              image: AssetImage('assets/images/chatgpt.png'),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemBuilder: (context, index) {
        final message = chat.messages[index];
        return ChatMessageTile(message: message);
      },
      itemCount: chat.messages.length,
    );
  }
}

class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.sender == Sender.user)
            const Icon(Icons.person)
          else
            const Icon(Icons.chat_bubble),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.sender.displayText,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(message.text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatInput extends StatefulWidget {
  const ChatInput({super.key});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    super.dispose();
    _inputController.dispose();
  }

  bool _isSending = false;

  void onSendPressed() async {
    try {
      setState(() {
        _isSending = true;
      });
      final chatProvider = context.read<ChatProvider>();
      await chatProvider.sendMessage(
        _inputController.text.trim(),
      );
      _inputController.clear();
      await chatProvider.requestResponse();
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _inputController,
            decoration: const InputDecoration(
              hintText: 'Type a message',
            ),
          ),
        ),
        const SizedBox(
          width: 10,
        ),
        if (_isSending)
          const CircularProgressIndicator()
        else
          ListenableBuilder(
            listenable: _inputController,
            builder: (context, _) {
              return IconButton(
                onPressed: _inputController.text.isEmpty ? null : onSendPressed,
                icon: const Icon(Icons.send),
              );
            },
          ),
      ],
    );
  }
}

class AuthProvider extends ChangeNotifier {
  User? currentUser;
  final _auth = FirebaseAuth.instance;

  late StreamSubscription<User?> _subscription;

  AuthProvider(Dio dio) {
    _subscription = _auth.idTokenChanges().listen((user) async {
      currentUser = user;
      if (user == null) {
        notifyListeners();
        return;
      }
      final token = await user.getIdToken();
      dio.options.headers['Authorization'] = 'Bearer ${token!}';
      notifyListeners();
    });
    signIn();
  }

  @override
  void dispose() {
    super.dispose();
    _subscription.cancel();
  }

  Future<void> signIn() async {
    await _auth.signInAnonymously().then((value) => value.user);
  }
}

class ChatProvider extends ChangeNotifier {
  final Dio _dio;

  ChatProvider(Dio dio) : _dio = dio;

  Chat? _currentChat;

  Chat? get currentChat => _currentChat;

  Future<void> loadCurrentOrCreateChat() async {
    final sp = await SharedPreferences.getInstance();
    final chatId = sp.getString('chatId');
    if (chatId == null) {
      await startNewChat();
      return;
    }
    try {
      await loadChat(chatId);
    } catch (e) {
      debugPrint(e.toString());
      await startNewChat();
    }
  }

  Future<void> loadChat(String chatId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/chat/$chatId/',
    );
    final chat = Chat.fromJson(response.data!);
    _currentChat = chat;
    notifyListeners();
  }

  Future<void> startNewChat() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/',
    );
    final chat = Chat.fromJson(response.data!);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('chatId', chat.id);
    _currentChat = chat;
    notifyListeners();
  }

  Future<ChatMessage?> sendMessage(String text) async {
    if (_currentChat == null) {
      return null;
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/${_currentChat!.id}/messages/',
      data: {
        'text': text,
      },
    );
    final message = ChatMessage.fromJson(response.data!);
    _currentChat!.messages.add(message);
    notifyListeners();
    return message;
  }

  Future<ChatMessage?> requestResponse() async {
    if (_currentChat == null) {
      return null;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/chat/${_currentChat!.id}/response/',
    );
    final message = ChatMessage.fromJson(response.data!);
    _currentChat!.messages.add(message);
    notifyListeners();
    return message;
  }
}

class Chat {
  final String id;
  final String title;
  final List<ChatMessage> messages;

  const Chat({
    required this.id,
    required this.title,
    required this.messages,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      title: json['title'],
      messages: (json['messages'])
          .map<ChatMessage>(
            (e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

enum Sender {
  user,
  bot;

  factory Sender.fromJson(String json) {
    switch (json) {
      case 'user':
        return Sender.user;
      case 'bot':
        return Sender.bot;
      default:
        throw Exception('Invalid sender');
    }
  }

  String get displayText {
    switch (this) {
      case Sender.user:
        return 'You';
      case Sender.bot:
        return 'ChatGPT';
    }
  }
}

class ChatMessage {
  final String id;

  final String text;
  final DateTime createdAt;
  final Sender sender;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.sender,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      text: json['text'],
      createdAt: DateTime.parse(json['createdAt']),
      sender: Sender.fromJson(json['sender']),
    );
  }
}
