import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'api/client.dart';
import 'providers/auth_provider.dart';
import 'providers/recommend_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/saved_provider.dart';
import 'theme/app_theme.dart';
import 'views/login_view.dart';
import 'views/home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: AppColors.surface,
    ),
  );
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
        theme: AppTheme.light(),
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
    final auth = context.read<AuthProvider>();
    await client.loadSettings();
    if (!mounted) return;
    await auth.checkStatus();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.needsLogin) return const LoginView();
        return const HomeView();
      },
    );
  }
}
