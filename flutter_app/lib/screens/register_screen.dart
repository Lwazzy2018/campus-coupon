import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';

/// Figma: "Registration Screen" - Create Your Student Account
/// Sequence Diagram 1, steps 1-4.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Edit to match CUT's real programme list (or load it from a table later).
  static const courses = [
    'Diploma in Information Technology',
    'BSc in Information Technology',
    'Diploma in Management',
    'Diploma in Civil Engineering',
    'Diploma in Electrical Engineering',
    'Other',
  ];

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _course;
  bool _busy = false;

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await CampusService.instance.register(
        fullName: _name.text,
        studentNumber: _number.text,
        course: _course!,
        email: _email.text,
        password: _password.text,
      );
      // If email confirmation is OFF, signUp also logs the user in.
      // The sequence diagram has register and login as separate steps, so sign out.
      if (Supabase.instance.client.auth.currentSession != null) {
        await CampusService.instance.logout();
      }
      if (!mounted) return;
      // Step 4: Show success message
      showMessage(context, 'Account created! Check your email to confirm, then log in.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Design: navy status bar only, then a white page with a black back arrow and the logo
      appBar: AppBar(toolbarHeight: 0, automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: CC.black, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(child: Center(child: CutLogo(height: 40))),
                const SizedBox(width: 48), // balances the back button so the logo stays centred
              ]),
              const SizedBox(height: 20),
              const Text('Create Your Student Account',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: CC.navy)),
              const SizedBox(height: 12),
              const Text('Register to access the Campus Coupon Student Portal.',
                  style: TextStyle(fontSize: 16, color: CC.labelBlue, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              CCField(
                controller: _name,
                hint: 'Full Name',
                icon: Icons.person,
                validator: (v) => (v == null || v.trim().length < 3) ? 'Enter your full name' : null,
              ),
              CCField(
                controller: _number,
                hint: 'Student Number (e.g. 220123456)',
                icon: Icons.calendar_view_month,
                keyboardType: TextInputType.number,
                validator: (v) => RegExp(r'^\d{9}$').hasMatch(v?.trim() ?? '') ? null : 'Student number must be 9 digits',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: DropdownButtonFormField<String>(
                  value: _course,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'Course', prefixIcon: Icon(Icons.account_balance)),
                  items: [for (final c in courses) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _course = v),
                  validator: (v) => v == null ? 'Select your course' : null,
                ),
              ),
              CCField(
                controller: _email,
                hint: 'Email (e.g. 220123456@stud.cut.ac.za)',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email',
              ),
              CCPasswordField(
                controller: _password,
                hint: 'Password',
                validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
              ),
              CCPasswordField(
                controller: _confirm,
                hint: 'Confirm Password',
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy ? null : _register,
                child: _busy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: CC.white))
                    : const Text('Register'),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text.rich(TextSpan(children: [
                    TextSpan(text: 'Already have an account? ',
                        style: TextStyle(color: CC.textBlue, fontWeight: FontWeight.w600, fontSize: 16)),
                    TextSpan(text: 'Login', style: TextStyle(color: CC.link, fontWeight: FontWeight.w600, fontSize: 16)),
                  ])),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
