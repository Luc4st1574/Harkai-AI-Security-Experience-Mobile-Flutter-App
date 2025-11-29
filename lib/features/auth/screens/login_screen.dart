// ignore_for_file: use_build_context_synchronously, avoid_print

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import '../../home/screens/home.dart';

// Import the generated localizations file
import '../../../l10n/app_localizations.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  LoginState createState() => LoginState();
}

class LoginState extends State<Login> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // FIX: Use the singleton instance
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  @override
  void initState() {
    super.initState();
    // FIX: Initialize the singleton with configuration once
    final webClientId = dotenv.env['WEB_CLIENT_ID'];
    _googleSignIn.initialize(
      serverClientId: webClientId,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      if (Firebase.apps.isEmpty) {
        throw Exception('Firebase is not initialized. Check main.dart setup.');
      }

      // FIX: Use authenticate() instead of signIn()
      // This method throws an exception if the user cancels
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // FIX: authentication returns a Future, so keep 'await'
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // FIX: accessToken is removed in v7+, pass null.
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: null,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.googleSignInSuccess)),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Home()),
      );
    } catch (e) {
      // In v7, if the user cancels the modal, it throws an error.
      // You can filter the error message here if you don't want to show a snackbar for cancellations.
      print('Error during Google Sign-In: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${localizations.googleSignInErrorPrefix}$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showForgotPasswordModal(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF011935),
          title: Text(
            localizations.loginForgotPasswordDialogTitle,
            style: const TextStyle(color: Color(0xFF57D463)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.loginForgotPasswordDialogContent,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: localizations.emailHint,
                  // FIX: Use .withValues(alpha: ...)
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF57D463)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF57D463)),
                  ),
                ),
                cursorColor: const Color(0xFF57D463),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (emailController.text.trim().isEmpty) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(localizations.emailHint)),
                    );
                  }
                  return;
                }
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(
                    email: emailController.text.trim(),
                  );
                  if (!mounted) return;

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(localizations.loginPasswordResetEmailSent)),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('${localizations.commonErrorPrefix}$e')),
                  );
                }
              },
              child: Text(
                localizations.loginSendButton,
                style: const TextStyle(color: Colors.green),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleLogin(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.loginEmptyFieldsPrompt)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = AuthService();
      await authService.signin(
        email: email,
        password: password,
        context: context,
        localizations: localizations,
      );
    } catch (e) {
      // Error is handled by AuthService
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      body: Stack(
        children: [
          _buildBackgroundImage(),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 30),
                    Text(
                      localizations.loginTitle,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 40),
                    CustomTextField(
                      controller: _emailController,
                      hintText: localizations.emailHint,
                      icon: Icons.person,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      controller: _passwordController,
                      hintText: localizations.passwordHint,
                      icon: Icons.lock,
                      obscureText: !_isPasswordVisible,
                      enabled: !_isLoading,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: const Color(0xFF57D463),
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildForgotPassword(context, localizations),
                    const SizedBox(height: 40),
                    _buildSignInButton(context, localizations),
                    const SizedBox(height: 20),
                    _buildGoogleSignInButton(context, localizations),
                    const SizedBox(height: 20),
                    _buildRegisterLink(context, localizations),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              // FIX: Use .withValues(alpha: ...)
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF57D463)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundImage() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/background.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/images/logo.png',
      width: 150,
      height: 150,
    );
  }

  Widget _buildForgotPassword(
      BuildContext context, AppLocalizations localizations) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: _isLoading ? null : () => _showForgotPasswordModal(context),
        child: Text(
          localizations.loginForgotPasswordLink,
          style: const TextStyle(color: Color(0xFF57D463)),
        ),
      ),
    );
  }

  Widget _buildSignInButton(
      BuildContext context, AppLocalizations localizations) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _handleLogin(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF011935),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          localizations.loginSignInButton,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF57D463),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton(
      BuildContext context, AppLocalizations localizations) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : () => _handleGoogleSignIn(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        icon: Image.asset(
          'assets/images/google_logo.png',
          height: 24,
        ),
        label: Text(
          localizations.loginSignInWithGoogleButton,
          style: const TextStyle(fontSize: 18, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildRegisterLink(
      BuildContext context, AppLocalizations localizations) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(localizations.loginDontHaveAccountPrompt),
        GestureDetector(
          onTap: _isLoading
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const Register()),
                  );
                },
          child: Text(
            localizations.registerTitle,
            style: const TextStyle(color: Color(0xFF57D463)),
          ),
        ),
      ],
    );
  }
}

// Reusing the CustomTextField from the previous file if it's not defined globally
// Assuming it exists in register_screen.dart or similar, but including it here for safety
// if this file is standalone, otherwise remove this class if it causes duplication errors.
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool enabled;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF57D463)),
        hintText: hintText,
        // FIX: Use .withValues(alpha: ...)
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF57D463)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF57D463)),
        ),
        suffixIcon: suffixIcon,
      ),
      keyboardAppearance: Brightness.dark,
      cursorColor: const Color(0xFF57D463),
    );
  }
}
