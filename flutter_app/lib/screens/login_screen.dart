import 'package:flutter/material.dart';

import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';
import 'register_screen.dart';

/// Figma: "Login Screen" - CAMPUS COUPON Student Portal
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await CampusService.instance.login(_id.text, _password.text);
      // AuthGate swaps to the Home screen automatically (Seq 1 step 8: show dashboard)
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _id.text.trim();
    if (!email.contains('@')) {
      showMessage(context, 'Type your email address above first, then tap "Forgot password?"', error: true);
      return;
    }
    try {
      await CampusService.instance.sendPasswordReset(email);
      if (mounted) showMessage(context, 'Password reset link sent to $email');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = TextStyle(color: CC.labelBlue, fontSize: 16, fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(toolbarHeight: 64),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _form,
            child: Column(children: [
              const CutLogo(height: 80),
              const SizedBox(height: 36),
              const Text('CAMPUS COUPON',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: CC.navy)),
              const SizedBox(height: 12),
              const Text('Student Portal',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: CC.navy)),
              const SizedBox(height: 12),
              // Tagline: #3878B4, as in the design
              const Text('Manage  |  Monitor  |  Empower',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: CC.textBlue)),
              const SizedBox(height: 50),
              CCField(
                controller: _id,
                hint: 'Student Number or Email',
                icon: Icons.person,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your student number or email' : null,
              ),
              CCPasswordField(
                controller: _password,
                hint: 'Password',
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot password?',
                      style: TextStyle(color: CC.link, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: CC.white))
                    : const Text('Login'),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account? ", style: blue),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Register',
                      style: TextStyle(color: CC.link, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
