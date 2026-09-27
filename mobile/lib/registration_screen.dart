import 'package:flutter/material.dart';
import 'api_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  String? message;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().length < 2 || email.text.trim().length < 5 || password.text.length < 8) {
      setState(() => message = 'Enter a name, valid email, and password of at least 8 characters.');
      return;
    }
    setState(() { loading = true; message = null; });
    try {
      await widget.api.register(name: name.text.trim(), email: email.text.trim(), password: password.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User account created. You can now sign in.')));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('User registration')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Create a normal user account. Authority and administrator roles are controlled by the backend.'),
      const SizedBox(height: 20),
      TextField(controller: name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', helperText: 'At least 8 characters', border: OutlineInputBorder())),
      if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: loading ? null : submit, icon: const Icon(Icons.person_add), label: Text(loading ? 'Creating account...' : 'Create user account')),
    ]),
  );
}
