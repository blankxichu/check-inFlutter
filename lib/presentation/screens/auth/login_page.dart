import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart';
import 'package:guardias_escolares/presentation/widgets/primary_button.dart';
import 'package:guardias_escolares/presentation/widgets/outlined_button_app.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:guardias_escolares/presentation/screens/auth/register_page.dart';
import 'package:guardias_escolares/presentation/widgets/auth_hero_header.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authViewModelProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Branded gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.08), cs.secondary.withValues(alpha: 0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AuthHeroHeader(
                          title: 'Guardias Escolares',
                          subtitle: 'Accede con tu cuenta',
                          height: 128,
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(height: 4),
                        Text('Accede con tu cuenta', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => v != null && v.contains('@') ? null : 'Email inválido',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pwdCtrl,
                          decoration: const InputDecoration(labelText: 'Contraseña'),
                          obscureText: true,
                          validator: (v) => v != null && v.length >= 6 ? null : 'Mínimo 6 caracteres',
                        ),
                        const SizedBox(height: 12),
                        if (auth is AuthError)
                          Text(auth.message, style: TextStyle(color: cs.error)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: PrimaryButton(
                                label: 'Entrar',
                                loading: auth is AuthLoading,
                                icon: Icons.login,
                                onPressed: auth is AuthLoading
                                    ? null
                                    : () async {
                                        if (_formKey.currentState!.validate()) {
                                          await ref.read(authViewModelProvider.notifier).signIn(
                                                _emailCtrl.text.trim(),
                                                _pwdCtrl.text,
                                              );
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 12),
                            AppOutlinedButton(
                              label: 'Crear cuenta',
                              icon: Icons.person_add,
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms).move(begin: const Offset(0, 8), curve: Curves.easeOut),
            ),
          ),
        ],
      ),
    );
  }
}
