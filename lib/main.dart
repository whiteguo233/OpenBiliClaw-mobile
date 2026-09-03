import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'api/client.dart';
import 'providers/auth_provider.dart';
import 'providers/recommend_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/saved_provider.dart';
import 'services/tailnet_service.dart';
import 'theme/app_theme.dart';
import 'views/login_view.dart';
import 'views/home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const OpenBiliClawApp());
}

class OpenBiliClawApp extends StatefulWidget {
  const OpenBiliClawApp({super.key, this.tailnetService});

  final TailnetService? tailnetService;

  @override
  State<OpenBiliClawApp> createState() => _OpenBiliClawAppState();
}

class _OpenBiliClawAppState extends State<OpenBiliClawApp> {
  late final TailnetService _tailnetService =
      widget.tailnetService ?? createTailnetService();
  late final ApiClient _client = ApiClient(tailnetService: _tailnetService);

  @override
  void dispose() {
    if (widget.tailnetService == null) _tailnetService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tailnetService),
        Provider.value(value: _client),
        ChangeNotifierProvider(create: (_) => AuthProvider(_client)),
        ChangeNotifierProvider(create: (_) => RecommendProvider(_client)),
        ChangeNotifierProvider(create: (_) => ChatProvider(_client)),
        ChangeNotifierProvider(create: (_) => ProfileProvider(_client)),
        ChangeNotifierProvider(create: (_) => SavedProvider(_client)),
      ],
      child: MaterialApp(
        title: 'OpenBiliClaw',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        builder: (context, child) {
          final palette = context.appColors;
          final brightness = Theme.of(context).brightness;
          final dark = brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: brightness,
              systemNavigationBarColor: palette.surface,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarDividerColor: palette.surface,
              systemNavigationBarContrastEnforced: false,
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        if (auth.needsLogin) return const LoginView();
        return const HomeView();
      },
    );
  }
}
