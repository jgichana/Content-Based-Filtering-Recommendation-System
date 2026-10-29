import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';

/// Sign in or create an account with email + password, or continue with Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _isRegister = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthService>();
    _run(() => _isRegister
        ? auth.register(_name.text, _email.text, _password.text)
        : auth.signIn(_email.text, _password.text));
  }

  void _google() =>
      _run(() => context.read<AuthService>().signInWithGoogle());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.child_care,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Child Activities',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      'Activities matched to your child\'s age and interests',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sign in')),
                        ButtonSegment(
                            value: true, label: Text('Create account')),
                      ],
                      selected: {_isRegister},
                      onSelectionChanged: _busy
                          ? null
                          : (s) => setState(() {
                                _isRegister = s.first;
                                _error = null;
                              }),
                    ),
                    const SizedBox(height: 20),
                    if (_isRegister) ...[
                      TextFormField(
                        key: const Key('name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                            labelText: 'Your name',
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const Key('email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined)),
                      validator: (v) =>
                          _emailPattern.hasMatch(v?.trim() ?? '')
                              ? null
                              : 'Enter a valid email address',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: _isRegister
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autofillHints: [
                        _isRegister
                            ? AutofillHints.newPassword
                            : AutofillHints.password
                      ],
                      onFieldSubmitted: (_) => _isRegister ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        helperText:
                            _isRegister ? 'At least 8 characters' : null,
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter your password';
                        if (_isRegister && v.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('confirm'),
                        controller: _confirm,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline)),
                        validator: (v) => v == _password.text
                            ? null
                            : 'Passwords do not match',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          key: const Key('auth-error'),
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('submit'),
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isRegister ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: theme.textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      key: const Key('google'),
                      onPressed: _busy ? null : _google,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      icon: const _GoogleMark(),
                      label: const Text('Continue with Google'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple "G" mark so the app doesn't need to bundle Google's logo asset.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const Text(
        'G',
        style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF4285F4)),
      );
}
