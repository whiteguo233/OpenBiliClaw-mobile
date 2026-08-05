import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(body: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFFFB7299).withValues(alpha:  0.08), const Color(0xFF5AA9FF).withValues(alpha:  0.04)])),
      child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(
          color: const Color(0xFFFB7299), borderRadius: BorderRadius.circular(20)),
          child: const Center(child: Text('B', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 16),
        Text('OpenBiliClaw', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('请登录以访问后端服务', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 32),
        TextField(controller: _passwordController, obscureText: true,
          decoration: InputDecoration(labelText: '密码', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true, fillColor: theme.colorScheme.surface),
          onSubmitted: (_) => _login()),
        const SizedBox(height: 16),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFEF7A86), fontSize: 13))),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB7299), foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _submitting ? null : _login,
          child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
      ])))));
  }

  Future<void> _login() async {
    setState(() { _submitting = true; _error = null; });
    final ok = await context.read<AuthProvider>().login(_passwordController.text);
    if (!mounted) return;
    setState(() { _submitting = false; if (!ok) _error = '密码错误或无法连接后端。'; });
  }
}
