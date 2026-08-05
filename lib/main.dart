import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/client.dart';
import 'providers/auth_provider.dart';
import 'providers/recommend_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/saved_provider.dart';
import 'views/login_view.dart';
import 'views/home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenBiliClawApp());
}

class OpenBiliClawApp extends StatelessWidget {
  const OpenBiliClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    final client = ApiClient();

    return MultiProvider(
      providers: [
        Provider.value(value: client),
        ChangeNotifierProvider(create: (_) => AuthProvider(client)),
        ChangeNotifierProvider(create: (_) => RecommendProvider(client)),
        ChangeNotifierProvider(create: (_) => ChatProvider(client)),
        ChangeNotifierProvider(create: (_) => ProfileProvider(client)),
        ChangeNotifierProvider(create: (_) => SavedProvider(client)),
      ],
      child: MaterialApp(
        title: 'OpenBiliClaw',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFFB7299),
          brightness: Brightness.light,
          fontFamily: '-apple-system, "PingFang SC", "Microsoft YaHei", sans-serif',
          scaffoldBackgroundColor: const Color(0xFFFFFAFC),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Color(0xFFFFFAFC),
          ),
        ),
        home: const AppEntry(),
      ),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final client = context.read<ApiClient>();
    await client.loadSettings();
    await context.read<AuthProvider>().checkStatus();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Consumer<AuthProvider>(builder: (context, auth, _) {
      if (auth.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (auth.needsLogin) return const LoginView();
      return const HomeView();
    });
  }
}
