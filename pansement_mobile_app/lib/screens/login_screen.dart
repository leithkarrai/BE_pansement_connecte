import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'settings_screen.dart';

/// Écran de connexion
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      // Le notifier gère l'état loading + erreurs et persiste la session.
      await ref.read(authProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text,
          );

      if (mounted) {
        // HomeScreen applique ensuite la navigation/tabbar selon le rôle.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Erreur de connexion';
        String errorTitle = 'Erreur de connexion';

        final errorStr = e.toString();

        if (errorStr.contains('Impossible de se connecter au serveur')) {
          errorTitle = 'Connexion au serveur impossible';
          errorMessage = errorStr.replaceFirst('Exception: ', '');
        } else if (errorStr.contains('Email ou mot de passe')) {
          errorTitle = 'Identifiants incorrects';
          errorMessage = errorStr.replaceFirst('Exception: ', '');
        } else if (errorStr.contains('Timeout')) {
          errorTitle = 'Timeout de connexion';
          errorMessage = errorStr.replaceFirst('Exception: ', '');
        } else {
          errorMessage = errorStr.replaceFirst('Exception: ', '');
        }

        // Message utilisateur orienté action (ex: ouvrir les paramètres d'URL backend).
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    errorTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                errorMessage,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            actions: [
              if (errorStr.contains('Timeout') ||
                  errorStr.contains('Impossible de se connecter') ||
                  errorStr.contains('serveur'))
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  child: const Text('Configurer l\'URL'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        backgroundColor: Colors.black,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: ColoredBox(
        color: const Color(0xFF000000),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // Logo E-PATCH (bandage + circuits + texte)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _buildLogo(context),
              ),
              // Formulaire : scroll possible quand le clavier est ouvert (évite l'overflow)
              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 4.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.shade700,
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Connexion',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                              ),
                              const SizedBox(height: 8),

                              // Email
                              TextFormField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(color: Colors.grey.shade400),
                                  prefixIcon: Icon(Icons.email, color: Colors.grey.shade400),
                                  filled: true,
                                  fillColor: const Color(0xFF252525),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade600),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade600),
                                  ),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Veuillez entrer votre email';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Email invalide';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),

                              // Password
                              TextFormField(
                                controller: _passwordController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Mot de passe',
                                  labelStyle: TextStyle(color: Colors.grey.shade400),
                                  prefixIcon: Icon(Icons.lock, color: Colors.grey.shade400),
                                  filled: true,
                                  fillColor: const Color(0xFF252525),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade600),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade600),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: Colors.grey.shade400,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Veuillez entrer votre mot de passe';
                                  }
                                  if (value.length < 6) {
                                    return 'Minimum 6 caractères';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),

                              // Bouton Login
                              ElevatedButton(
                                onPressed: authState.isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF26A69A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: authState.isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Se connecter',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                              ),
                              const SizedBox(height: 6),

                              Align(
                                alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ForgotPasswordScreen(),
                                        ),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.grey.shade400,
                                    ),
                                    child: const Text('Mot de passe oublié ?'),
                                  ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Pas encore de compte ? '),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue[200],
                            ),
                            child: const Text('Créer un compte'),
                          ),
                        ],
                      ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 160),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildLogoPlaceholder(),
        ),
      ),
    );
  }

  /// Placeholder bandage + circuits quand logo.png est absent (plus d’icône mallette).
  Widget _buildLogoPlaceholder() {
    return CustomPaint(
      size: const Size(120, 80),
      painter: _EPatchLogoPainter(),
    );
  }
}

class _EPatchLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * 0.5;
    final bandageWidth = size.width * 0.85;
    final bandageHeight = size.height * 0.35;
    final left = (size.width - bandageWidth) / 2;
    final top = centerY - bandageHeight / 2;

    // Bandage (rectangle arrondi gris avec compresse blanche)
    final bandageR = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, bandageWidth, bandageHeight),
      const Radius.circular(8),
    );
    canvas.drawRRect(bandageR, Paint()..color = Colors.grey[400]!);
    final padW = bandageWidth * 0.4;
    final padLeft = left + (bandageWidth - padW) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(padLeft, top + 4, padW, bandageHeight - 8),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white,
    );

    // Traits type “circuits” bleu clair
    final circuitPaint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(left - 8, centerY), Offset(left, centerY), circuitPaint);
    canvas.drawLine(Offset(left + bandageWidth, centerY), Offset(left + bandageWidth + 8, centerY), circuitPaint);
    canvas.drawCircle(Offset(left - 8, centerY), 3, Paint()..color = const Color(0xFF4FC3F7));
    canvas.drawCircle(Offset(left + bandageWidth + 8, centerY), 3, Paint()..color = const Color(0xFF4FC3F7));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
