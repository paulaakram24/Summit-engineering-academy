import 'dart:async';

import 'package:flutter/material.dart';

import '../content/content_repository.dart';
import '../content/admin_content_screen.dart';
import '../content/course_image_selector.dart';
import '../content/material_repository.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_screen.dart';
import '../bookmarks/bookmark_repository.dart';

import 'auth_controller.dart';
import 'auth_repository.dart';

class AuthPanel extends StatefulWidget {
  const AuthPanel({
    super.key,
    required this.controller,
    this.contentRepository,
    this.materialRepository,
    this.catalogRepository,
    this.catalogCoverLoader,
    this.bookmarkRepository,
  });
  final AuthController controller;
  final ContentRepository? contentRepository;
  final MaterialRepository? materialRepository;
  final CatalogRepository? catalogRepository;
  final CatalogCoverLoader? catalogCoverLoader;
  final BookmarkRepository? bookmarkRepository;
  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _university = TextEditingController();
  final _code = TextEditingController();
  String _mode = 'login';
  bool _editing = false;
  AuthStage? _lastStage;
  AuthController get auth => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (CourseImageSelection.active(auth)) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(auth.checkAccess());
    } else {
      auth.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final field in [
      _email,
      _password,
      _confirm,
      _name,
      _phone,
      _university,
      _code,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void _switch(String mode) {
    setState(() {
      _mode = mode;
      _password.clear();
      _confirm.clear();
      _form.currentState?.reset();
    });
  }

  AccountProfile get _details => AccountProfile(
    name: _name.text,
    phone: _phone.text,
    university: _university.text,
  );
  void _loadProfile() {
    _name.text = auth.profile?.name ?? '';
    _phone.text = auth.profile?.phone ?? '';
    _university.text = auth.profile?.university ?? '';
  }

  Future<void> _submit(Future<void> Function() action) async {
    if (_form.currentState?.validate() != true) {
      return;
    }
    await action();
    _password.clear();
    _confirm.clear();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool password = false,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    Iterable<String>? autofill,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !auth.busy,
      obscureText: password,
      autocorrect: !password,
      enableSuggestions: !password,
      keyboardType: keyboard,
      autofillHints: autofill,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) => (value ?? '').trim().isEmpty ? 'Enter $label.' : null,
    ),
  );
  Widget _emailField() => _field(
    'Email',
    _email,
    keyboard: TextInputType.emailAddress,
    autofill: const [AutofillHints.email],
    validator: (value) =>
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((value ?? '').trim())
        ? null
        : 'Enter a valid email address.',
  );
  Widget _passwordField({bool newPassword = false}) => _field(
    newPassword ? 'New password' : 'Password',
    _password,
    password: true,
    autofill: [
      newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: (value) => (value ?? '').length < (newPassword ? 12 : 1)
        ? (newPassword ? 'Use at least 12 characters.' : 'Enter your password.')
        : null,
  );
  List<Widget> _profileFields() => [
    _field(
      'Name (required)',
      _name,
      autofill: const [AutofillHints.name],
      validator: AccountProfile.validateName,
    ),
    _field(
      'Phone (required)',
      _phone,
      keyboard: TextInputType.phone,
      autofill: const [AutofillHints.telephoneNumber],
      validator: AccountProfile.validatePhone,
    ),
    _field(
      'University (required)',
      _university,
      validator: AccountProfile.validateUniversity,
    ),
  ];
  Widget _button(
    String text,
    Future<void> Function() action, {
    bool validate = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: FilledButton(
      onPressed: auth.busy ? null : () => validate ? _submit(action) : action(),
      child: Text(text),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: auth,
    builder: (context, _) {
      if (_lastStage != auth.stage) {
        if (auth.stage == AuthStage.recovery ||
            auth.stage == AuthStage.signedOut) {
          _password.clear();
          _confirm.clear();
          _editing = false;
          _mode = 'login';
        }
        if (auth.stage == AuthStage.completeProfile) {
          _loadProfile();
        }
        if (auth.stage != AuthStage.ready) {
          _editing = false;
        }
        _lastStage = auth.stage;
      }
      final children = <Widget>[];
      String title;
      switch (auth.stage) {
        case AuthStage.checking:
          title = 'Checking account access';
          children.add(const Center(child: CircularProgressIndicator()));
        case AuthStage.blocked:
          title = 'Account access unavailable';
          children.add(
            _button('Retry access check', auth.checkAccess, validate: false),
          );
          children.add(
            _button('Back to sign in', auth.logout, validate: false),
          );
        case AuthStage.recovery:
          title = 'Choose a new password';
          children.addAll([
            _passwordField(newPassword: true),
            _field(
              'Confirm password',
              _confirm,
              password: true,
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match.',
            ),
            _button(
              'Update password',
              () => auth.changePassword(_password.text),
            ),
            _button('Cancel and sign out', auth.logout, validate: false),
          ]);
        case AuthStage.verification:
          title = 'Verify your email';
          children.addAll([
            Text(
              'Open the verification link sent to ${auth.verificationEmail}, or enter the code from the email.',
            ),
            const SizedBox(height: 16),
            _field('Verification code', _code, keyboard: TextInputType.number),
            _button('Verify email', () => auth.verify(_code.text)),
            OutlinedButton(
              onPressed: auth.busy || auth.resendSeconds > 0
                  ? null
                  : auth.resend,
              child: Text(
                auth.resendSeconds > 0
                    ? 'Resend in ${auth.resendSeconds}s'
                    : 'Resend verification email',
              ),
            ),
            TextButton(
              onPressed: auth.busy ? null : auth.showLogin,
              child: const Text('Back to sign in'),
            ),
          ]);
        case AuthStage.completeProfile:
          title = 'Complete your profile';
          children.addAll([
            const Text(
              'Your name, phone number, and university are required before you '
              'can enter your learning space. Review any details filled in '
              'from Google, add the missing information, then save your profile.',
            ),
            const SizedBox(height: 16),
            ..._profileFields(),
            _button('Save profile', () => auth.saveProfile(_details)),
            _button('Log out', auth.logout, validate: false),
          ]);
        case AuthStage.ready:
          title = _editing ? 'Edit profile' : 'Welcome, ${auth.profile!.name}';
          if (_editing) {
            children.addAll([
              ..._profileFields(),
              _button('Save profile', () => auth.saveProfile(_details)),
              TextButton(
                onPressed: auth.busy
                    ? null
                    : () => setState(() => _editing = false),
                child: const Text('Cancel'),
              ),
            ]);
          } else {
            children.addAll([
              Text(
                auth.access!.role == 'admin'
                    ? 'Administrator account'
                    : 'Student account',
              ),
              Text(auth.repository.email ?? ''),
              Text(auth.profile!.phone),
              Text(auth.profile!.university),
              const SizedBox(height: 12),
              const Text('Your learning space is ready for the next phase.'),
              if (widget.catalogRepository != null)
                FilledButton.icon(
                  onPressed: auth.busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CatalogScreen(
                              auth: auth,
                              repository: widget.catalogRepository!,
                              loadCover: widget.catalogCoverLoader,
                              bookmarkRepository: widget.bookmarkRepository,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Browse courses'),
                ),
              if (widget.catalogRepository != null &&
                  widget.bookmarkRepository != null)
                FilledButton.icon(
                  onPressed: auth.busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CatalogScreen(
                              auth: auth,
                              repository: widget.catalogRepository!,
                              bookmarkRepository: widget.bookmarkRepository,
                              savedOnly: true,
                              loadCover: widget.catalogCoverLoader,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.bookmark_outline),
                  label: const Text('Saved courses'),
                ),
              if (auth.access!.role == 'admin' &&
                  widget.contentRepository != null)
                FilledButton.icon(
                  onPressed: auth.busy
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AdminContentScreen(
                                repository: widget.contentRepository!,
                                authController: auth,
                                materialRepository: widget.materialRepository,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.library_books),
                  label: const Text('Manage courses'),
                ),
              TextButton(
                onPressed: () => setState(() {
                  _loadProfile();
                  _editing = true;
                }),
                child: const Text('Edit profile'),
              ),
            ]);
          }
          children.add(_button('Log out', auth.logout, validate: false));
        case AuthStage.signedOut:
          title = switch (_mode) {
            'signup' => 'Create your account',
            'forgot' => 'Reset your password',
            _ => 'Sign in',
          };
          children.add(_emailField());
          if (_mode == 'forgot') {
            children.add(
              _button('Send reset link', () => auth.sendRecovery(_email.text)),
            );
          } else {
            if (_mode == 'signup') {
              children.addAll(_profileFields());
            }
            children.add(_passwordField(newPassword: _mode == 'signup'));
            children.add(
              _button(
                _mode == 'signup' ? 'Create account' : 'Sign in',
                () => _mode == 'signup'
                    ? auth.signUp(_email.text, _password.text, _details)
                    : auth.signIn(_email.text, _password.text),
              ),
            );
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: auth.busy ? null : auth.googleSignIn,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff1f1f1f),
                    side: const BorderSide(color: Color(0xff747775)),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  icon: Image.asset(
                    'assets/google-g.png',
                    width: 20,
                    height: 20,
                    excludeFromSemantics: true,
                  ),
                  label: const Text('Continue with Google'),
                ),
              ),
            );
            if (_mode == 'login') {
              children.add(
                TextButton(
                  onPressed: auth.busy ? null : () => _switch('forgot'),
                  child: const Text('Forgot password?'),
                ),
              );
              children.add(
                TextButton(
                  onPressed: auth.busy
                      ? null
                      : () {
                          if (_email.text.trim().isNotEmpty) {
                            auth.showVerification(_email.text);
                          }
                        },
                  child: const Text('Verify an existing account'),
                ),
              );
            }
          }
          children.add(
            TextButton(
              onPressed: auth.busy
                  ? null
                  : () => _switch(_mode == 'login' ? 'signup' : 'login'),
              child: Text(
                _mode == 'login' ? 'Create an account' : 'Back to sign in',
              ),
            ),
          );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                if (auth.message != null) ...[
                  Semantics(liveRegion: true, child: Text(auth.message!)),
                  const SizedBox(height: 16),
                ],
                if (auth.busy) const LinearProgressIndicator(),
                ...children,
              ],
            ),
          ),
        ),
      );
    },
  );
}
