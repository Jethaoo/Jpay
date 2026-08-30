import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'backend/backend_config.dart';
import 'network_status.dart';
import 'services/jpay_auth_service.dart';
import 'supabase_home_screen.dart';
import 'widgets/app_ui.dart';

Future<void> runSupabaseJpay() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await BackendConfig.initializeSupabase();
    runApp(const SupabaseJpayApp());
  } catch (error) {
    runApp(_BackendStartupErrorApp(message: error.toString()));
  }
}

class _BackendStartupErrorApp extends StatelessWidget {
  final String message;

  const _BackendStartupErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jpay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: AppErrorState(
            message: message.replaceFirst('Bad state: ', ''),
          ),
        ),
      ),
    );
  }
}

class SupabaseJpayApp extends StatelessWidget {
  final JpayAuthService? authService;

  const SupabaseJpayApp({super.key, this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jpay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, child) =>
          ConnectivityBannerHost(child: child ?? const SizedBox.shrink()),
      home: SupabaseAuthGate(authService: authService),
    );
  }
}

class SupabaseAuthGate extends StatefulWidget {
  final JpayAuthService? authService;

  const SupabaseAuthGate({super.key, this.authService});

  @override
  State<SupabaseAuthGate> createState() => _SupabaseAuthGateState();
}

class _SupabaseAuthGateState extends State<SupabaseAuthGate> {
  late final JpayAuthService _authService;
  StreamSubscription<JpayAuthState>? _subscription;
  late bool _hasSession;
  bool _recoveringPassword = false;

  @override
  void initState() {
    super.initState();
    _authService =
        widget.authService ?? SupabaseJpayAuthService(Supabase.instance.client);
    _hasSession = _authService.hasActiveSession;
    _subscription = _authService.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _hasSession = state.hasSession;
        if (state.event == JpayAuthEvent.passwordRecovery) {
          _recoveringPassword = state.hasSession;
        } else if (state.event == JpayAuthEvent.signedOut) {
          _recoveringPassword = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _cancelRecovery() async {
    await _authService.signOut();
    if (mounted) {
      setState(() {
        _recoveringPassword = false;
        _hasSession = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recoveringPassword) {
      return SupabaseUpdatePasswordScreen(
        authService: _authService,
        onComplete: () {
          if (mounted) {
            setState(() {
              _recoveringPassword = false;
              _hasSession = true;
            });
          }
        },
        onCancel: _cancelRecovery,
      );
    }
    if (_hasSession) return const SupabaseHomeScreen();
    return SupabaseLoginScreen(authService: _authService);
  }
}

class SupabaseLoginScreen extends StatefulWidget {
  final JpayAuthService? authService;
  final bool? passwordRecoveryEnabled;

  const SupabaseLoginScreen({
    super.key,
    this.authService,
    this.passwordRecoveryEnabled,
  });

  @override
  State<SupabaseLoginScreen> createState() => _SupabaseLoginScreenState();
}

class _SupabaseLoginScreenState extends State<SupabaseLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  String? _formError;

  JpayAuthService get _authService =>
      widget.authService ?? SupabaseJpayAuthService(Supabase.instance.client);

  bool get _recoveryEnabled =>
      widget.passwordRecoveryEnabled ?? BackendConfig.enablePasswordRecovery;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _emailError = email.isEmpty
          ? 'Enter your email address.'
          : (!email.contains('@') ? 'Enter a valid email address.' : null);
      _passwordError = password.isEmpty ? 'Enter your password.' : null;
      _formError = null;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _signIn() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = NetworkStatus.isOffline.value
            ? networkAwareErrorMessage(error, action: 'sign in')
            : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = networkAwareErrorMessage(error, action: 'sign in');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openRecovery() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PasswordRecoverySheet(
        authService: _authService,
        initialEmail: _emailController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121820), AppPalette.background],
            stops: [0, 0.62],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: AutofillGroup(
                  child: Column(
                    children: [
                      Semantics(
                        image: true,
                        label: 'Jpay logo',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.hero),
                          child: Image.asset(
                            'assets/branding/jpay_app_icon_1024.png',
                            width: 92,
                            height: 92,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Jpay',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Welcome back · Sign in to keep expenses settled.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppPalette.secondaryLabel),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppSectionCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              enableSuggestions: false,
                              onChanged: (_) {
                                if (_emailError != null || _formError != null) {
                                  setState(() {
                                    _emailError = null;
                                    _formError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Email',
                                errorText: _emailError,
                                prefixIcon: const Icon(
                                  Icons.mail_outline_rounded,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _isLoading ? null : _signIn(),
                              onChanged: (_) {
                                if (_passwordError != null ||
                                    _formError != null) {
                                  setState(() {
                                    _passwordError = null;
                                    _formError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Password',
                                errorText: _passwordError,
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (_formError != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _formError!,
                                  style: const TextStyle(
                                    color: AppPalette.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                            if (_recoveryEnabled)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading ? null : _openRecovery,
                                  child: const Text('Forgot password?'),
                                ),
                              )
                            else
                              const SizedBox(height: AppSpacing.lg),
                            FilledButton(
                              onPressed: _isLoading ? null : _signIn,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                              child: AnimatedSwitcher(
                                duration: AppMotion.fast,
                                child: _isLoading
                                    ? const SizedBox(
                                        key: ValueKey('loading'),
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                        ),
                                      )
                                    : const Text(
                                        'Log In',
                                        key: ValueKey('label'),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'Your existing Jpay account uses secure Supabase sign-in.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppPalette.tertiaryLabel,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PasswordRecoverySheet extends StatefulWidget {
  final JpayAuthService authService;
  final String initialEmail;

  const PasswordRecoverySheet({
    super.key,
    required this.authService,
    this.initialEmail = '',
  });

  @override
  State<PasswordRecoverySheet> createState() => _PasswordRecoverySheetState();
}

class _PasswordRecoverySheetState extends State<PasswordRecoverySheet> {
  late final TextEditingController _emailController;
  bool _sending = false;
  bool _sent = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorText = 'Enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _errorText = null;
    });
    try {
      await widget.authService.sendPasswordReset(
        email: email,
        redirectTo: BackendConfig.passwordRecoveryRedirectUrl,
      );
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = networkAwareErrorMessage(
          error,
          action: 'send a reset link',
        );
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: AnimatedSwitcher(
          duration: AppMotion.standard,
          child: _sent
              ? Column(
                  key: const ValueKey('sent'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mark_email_read_outlined,
                      size: 48,
                      color: AppPalette.green,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Check your email',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'If an account exists for that address, a password reset link is on its way.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppPalette.secondaryLabel),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                )
              : Column(
                  key: const ValueKey('form'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSectionHeader(
                      title: 'Reset your password',
                      subtitle:
                          'We will email a secure link that opens Jpay so you can choose a new password.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofocus: widget.initialEmail.isEmpty,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _sending ? null : _send(),
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() => _errorText = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Email',
                        errorText: _errorText,
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(_sending ? 'Sending…' : 'Send reset link'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      onPressed: _sending ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class SupabaseUpdatePasswordScreen extends StatefulWidget {
  final JpayAuthService authService;
  final VoidCallback onComplete;
  final Future<void> Function() onCancel;

  const SupabaseUpdatePasswordScreen({
    super.key,
    required this.authService,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<SupabaseUpdatePasswordScreen> createState() =>
      _SupabaseUpdatePasswordScreenState();
}

class _SupabaseUpdatePasswordScreenState
    extends State<SupabaseUpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_saving) return;
    await widget.onCancel();
  }

  Future<void> _save() async {
    final password = _passwordController.text;
    final confirmation = _confirmController.text;
    setState(() {
      _passwordError = password.length < 8
          ? 'Use at least 8 characters.'
          : null;
      _confirmError = confirmation != password
          ? 'Passwords do not match.'
          : null;
      _formError = null;
    });
    if (_passwordError != null || _confirmError != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.authService.updatePassword(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
      widget.onComplete();
    } on AuthException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } catch (error) {
      if (mounted) {
        setState(() {
          _formError = networkAwareErrorMessage(
            error,
            action: 'update your password',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _saving ? null : _cancel,
            tooltip: 'Cancel password reset',
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text('Choose a new password'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: AppSectionCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.lock_reset_rounded,
                          size: 48,
                          color: AppPalette.blue,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Create a password you do not use elsewhere.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppPalette.secondaryLabel),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {
                            _passwordError = null;
                            _formError = null;
                          }),
                          decoration: InputDecoration(
                            labelText: 'New password',
                            errorText: _passwordError,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _confirmController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saving ? null : _save(),
                          onChanged: (_) => setState(() {
                            _confirmError = null;
                            _formError = null;
                          }),
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            errorText: _confirmError,
                            prefixIcon: const Icon(
                              Icons.verified_user_outlined,
                            ),
                          ),
                        ),
                        if (_formError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _formError!,
                              style: const TextStyle(color: AppPalette.red),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : const Text('Update password'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
