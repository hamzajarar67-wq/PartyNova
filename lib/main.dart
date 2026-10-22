import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

const String partyNovaOwnerEmail = 'hamzajarar76@gmail.com';
const String partyNovaAdminEmail = 'hamzajarar67@gmail.com';

const Map<String, String> partyNovaReservedIds = {
  'hamzajarar76@gmail.com': '111111',
  'hamzajarar67@gmail.com': '111112',
};

const Color partyPink = Color(0xFFFF1688);
const Color partyBlack = Color(0xFF09070B);
const Color partyGold = Color(0xFFFFD780);
const Color partyWhite = Color(0xFFFFFFFF);

String partyNovaRoleForEmail(String? email) {
  final normalizedEmail = email?.trim().toLowerCase();

  if (normalizedEmail == partyNovaOwnerEmail) {
    return 'owner';
  }

  if (normalizedEmail == partyNovaAdminEmail) {
    return 'admin';
  }

  return 'user';
}

String partyNovaRoleLabel(String role) {
  switch (role.toLowerCase()) {
    case 'owner':
      return 'OWNER';
    case 'admin':
      return 'ADMIN';
    default:
      return 'MEMBER';
  }
}

BoxDecoration partyNightDecoration() {
  return const BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0.0, -0.45),
      radius: 1.25,
      colors: [
        Color(0xFF42152F),
        Color(0xFF21101F),
        Color(0xFF09070B),
      ],
      stops: [0.0, 0.48, 1.0],
    ),
  );
}

Future<String> assignPartyNovaUserId(User user) async {
  final firestore = FirebaseFirestore.instance;
  final userRef = firestore.collection('users').doc(user.uid);
  final email = user.email?.trim().toLowerCase();

  final existingSnapshot = await userRef.get();

  if (existingSnapshot.exists) {
    final data = existingSnapshot.data();
    final existingId = data?['userId'];

    if (existingId is String && existingId.isNotEmpty) {
      final expectedReservedId =
          email == null ? null : partyNovaReservedIds[email];

      if (expectedReservedId != null &&
          existingId != expectedReservedId) {
        throw StateError(
          'Reserved account ID does not match its assigned ID.',
        );
      }

      return existingId;
    }
  }

  final reservedId =
      email == null ? null : partyNovaReservedIds[email];

  if (reservedId != null) {
    throw StateError(
      'Owner/Admin ID setup is required in Firestore.',
    );
  }

  final random = Random.secure();

  for (var attempt = 0; attempt < 60; attempt++) {
    final String id;

    if (attempt < 30) {
      id = (10000000 + random.nextInt(90000000)).toString();
    } else {
      id = List.generate(
        10,
        (index) => index == 0
            ? (1 + random.nextInt(9)).toString()
            : random.nextInt(10).toString(),
      ).join();
    }

    final claimRef = firestore.collection('userIdClaims').doc(id);

    try {
      final assignedId =
          await firestore.runTransaction<String?>((transaction) async {
        final userSnapshot = await transaction.get(userRef);

        if (userSnapshot.exists) {
          final savedId = userSnapshot.data()?['userId'];

          if (savedId is String && savedId.isNotEmpty) {
            return savedId;
          }
        }

        final claimSnapshot = await transaction.get(claimRef);

        if (claimSnapshot.exists) {
          return null;
        }

        transaction.set(claimRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          userRef,
          {
            'userId': id,
            'email': email,
            'name': user.displayName ?? '',
            'role': 'user',
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return id;
      });

      if (assignedId != null) {
        return assignedId;
      }
    } catch (error) {
      if (error is StateError) rethrow;
      // Retry if an ID claim could not be completed.
    }
  }

  throw StateError(
    'Could not assign a unique ID. Please try again.',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const PartyNovaApp());
}

class PartyNovaApp extends StatelessWidget {
  const PartyNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PartyNova',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: partyBlack,
        colorScheme: ColorScheme.fromSeed(
          seedColor: partyPink,
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: partyBlack,
            body: Center(
              child: CircularProgressIndicator(
                color: partyPink,
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return const PartyNovaHome();
        }

        return const SplashGate();
      },
    );
  }
}


class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SplashPage();
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: partyBlack,
      body: Container(
        width: double.infinity,
        decoration: partyNightDecoration(),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 105,
                  height: 105,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF9BC8),
                        partyPink,
                        Color(0xFF9B1558),
                      ],
                    ),
                    border: Border.all(
                      color: partyGold,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: partyPink.withValues(alpha: 0.35),
                        blurRadius: 30,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 52,
                    color: partyWhite,
                  ),
                ),
                const SizedBox(height: 28),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'PARTY',
                        style: TextStyle(
                          color: partyPink,
                          fontSize: 35,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      TextSpan(
                        text: 'NOVA',
                        style: TextStyle(
                          color: partyWhite,
                          fontSize: 35,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Connect, Chat and Make Friends',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFC7E2),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 45),
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    color: partyPink,
                    strokeWidth: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PartyButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool outlined;

  const PartyButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: outlined
              ? null
              : const LinearGradient(
                  colors: [
                    Color(0xFFFF9BC8),
                    partyPink,
                    Color(0xFF9B1558),
                  ],
                ),
          border: Border.all(
            color: const Color(0xFFFFC7E2),
            width: 1.2,
          ),
          color: outlined ? const Color(0xFF21101F) : null,
          boxShadow: [
            BoxShadow(
              color: partyPink.withValues(alpha: 0.18),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: partyWhite),
                const SizedBox(width: 10),
                Text(
                  text,
                  style: const TextStyle(
                    color: partyWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PartyTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType keyboardType;
  final bool password;
  final TextInputAction textInputAction;

  const PartyTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.password = false,
    this.textInputAction = TextInputAction.next,
  });

  @override
  State<PartyTextField> createState() => _PartyTextFieldState();
}

class _PartyTextFieldState extends State<PartyTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: widget.password && _obscure,
      textInputAction: widget.textInputAction,
      autocorrect: !widget.password,
      enableSuggestions: !widget.password,
      style: const TextStyle(
        color: partyWhite,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(
          color: Color(0xFFFFC7E2),
        ),
        prefixIcon: Icon(
          widget.icon,
          color: partyGold,
        ),
        suffixIcon: widget.password
            ? IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() {
                    _obscure = !_obscure;
                  });
                },
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: partyGold,
                ),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF171017),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF654052),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF654052),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: partyPink,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}



class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return e.message ?? 'Login failed. Please try again.';
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw StateError('User session is unavailable.');
      }

      await assignPartyNovaUserId(user);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const PartyNovaHome(),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError
              ? e.message
              : 'Could not load your profile. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: partyBlack,
      appBar: AppBar(
        backgroundColor: partyBlack,
        foregroundColor: partyWhite,
        title: const Text('Login'),
      ),
      body: Container(
        width: double.infinity,
        decoration: partyNightDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_open_rounded,
                    color: partyGold,
                    size: 62,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: partyWhite,
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),
                  PartyTextField(
                    label: 'Email',
                    controller: _emailController,
                    icon: Icons.email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 18),
                  PartyTextField(
                    label: 'Password',
                    controller: _passwordController,
                    icon: Icons.lock_rounded,
                    password: true,
                    textInputAction: TextInputAction.done,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF8A9B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  PartyButton(
                    text: _loading ? 'Please wait...' : 'Login',
                    icon: Icons.login_rounded,
                    onTap: _loading ? () {} : _login,
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => const SignupPage(),
                              ),
                            );
                          },
                    child: const Text(
                      "Don't have an account? Create Account",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: partyGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled in Firebase.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return e.message ?? 'Account creation failed. Please try again.';
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = credential.user;

      if (user == null) {
        throw StateError('Account created, but user session is unavailable.');
      }

      await user.updateDisplayName(_nameController.text.trim());
      await user.reload();

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw StateError('User session is unavailable.');
      }

      await assignPartyNovaUserId(currentUser);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const PartyNovaHome(),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError
              ? e.message
              : 'Account created, but profile setup failed. Please try logging in again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: partyBlack,
      appBar: AppBar(
        backgroundColor: partyBlack,
        foregroundColor: partyWhite,
        title: const Text('Create Account'),
      ),
      body: Container(
        width: double.infinity,
        decoration: partyNightDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: partyGold,
                    size: 58,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Join PartyNova',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: partyWhite,
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 26),
                  PartyTextField(
                    label: 'Full Name',
                    controller: _nameController,
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 16),
                  PartyTextField(
                    label: 'Email',
                    controller: _emailController,
                    icon: Icons.email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  PartyTextField(
                    label: 'Password',
                    controller: _passwordController,
                    icon: Icons.lock_rounded,
                    password: true,
                  ),
                  const SizedBox(height: 16),
                  PartyTextField(
                    label: 'Confirm Password',
                    controller: _confirmController,
                    icon: Icons.lock_outline_rounded,
                    password: true,
                    textInputAction: TextInputAction.done,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF8A9B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  PartyButton(
                    text: _loading ? 'Please wait...' : 'Create Account',
                    icon: Icons.person_add_alt_1_rounded,
                    onTap: _loading ? () {} : _signup,
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                    child: const Text(
                      'Already have an account? Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: partyGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class PartyNovaHome extends StatefulWidget {
  const PartyNovaHome({super.key});

  @override
  State<PartyNovaHome> createState() => _PartyNovaHomeState();
}

class _PartyNovaHomeState extends State<PartyNovaHome> {
  int _selectedIndex = 0;

  static const Color pink = Color(0xFFFF1688);
  static const Color black = Color(0xFF09070B);
  static const Color white = Color(0xFFFFFFFF);
  static const Color gold = Color(0xFFFFD780);

  static const List<String> _pageTitles = [
    'Home',
    'Rooms',
    'Games',
    'Wallet',
    'Social',
    'Profile',
  ];

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  Widget _buildEmptyPage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.45),
          radius: 1.25,
          colors: [
            Color(0xFF42152F),
            Color(0xFF21101F),
            Color(0xFF09070B),
          ],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 70,
            left: -65,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pink.withValues(alpha: 0.08),
                boxShadow: [
                  BoxShadow(
                    color: pink.withValues(alpha: 0.12),
                    blurRadius: 100,
                    spreadRadius: 25,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: -75,
            bottom: 55,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB52B76)
                    .withValues(alpha: 0.08),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB52B76)
                        .withValues(alpha: 0.12),
                    blurRadius: 110,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            top: 55,
            right: 35,
            child: Icon(
              Icons.auto_awesome,
              color: Color(0xFFCF789F),
              size: 17,
            ),
          ),
          const Positioned(
            top: 165,
            left: 38,
            child: Icon(
              Icons.star_rounded,
              color: Color(0xFFB96A91),
              size: 13,
            ),
          ),
          const Positioned(
            bottom: 115,
            left: 75,
            child: Icon(
              Icons.favorite_rounded,
              color: Color(0x55FF1688),
              size: 18,
            ),
          ),
          const Positioned(
            bottom: 185,
            right: 48,
            child: Icon(
              Icons.auto_awesome,
              color: Color(0xFFB96A91),
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const ColoredBox(
        color: white,
        child: Center(
          child: Text(
            'Please log in to view your profile.',
            style: TextStyle(color: black),
          ),
        ),
      );
    }

    return ColoredBox(
      color: white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Could not load your profile.',
                style: TextStyle(color: black),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: pink),
            );
          }

          final data = snapshot.data?.data() ??
              <String, dynamic>{};

          final name = (data['name'] as String?)?.trim().isNotEmpty ==
                  true
              ? (data['name'] as String).trim()
              : (user.displayName?.trim().isNotEmpty == true
                  ? user.displayName!.trim()
                  : 'PartyNova User');

          final email = user.email?.trim().toLowerCase();
          final role = partyNovaRoleForEmail(email);
          final userId = data['userId'] is String
              ? data['userId'] as String
              : '';

          final photoUrl = data['photoURL'] is String
              ? data['photoURL'] as String
              : user.photoURL;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
              children: [
                Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: partyGold,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: partyPink.withValues(alpha: 0.15),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: photoUrl != null &&
                              photoUrl.trim().isNotEmpty
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(
                                Icons.person_rounded,
                                size: 62,
                                color: pink,
                              ),
                            )
                          : const Icon(
                              Icons.person_rounded,
                              size: 62,
                              color: pink,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: black,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFE8A0),
                          Color(0xFFFFC94F),
                          Color(0xFFB87919),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF9A681A),
                      ),
                    ),
                    child: Text(
                      partyNovaRoleLabel(role),
                      style: const TextStyle(
                        color: Color(0xFF5C2C15),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'YOUR PARTY NOVA ID',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B5360),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 14),
                if (userId.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: partyGold),
                    ),
                    child: const Text(
                      'Your ID is being set up. Please sign in again later if it does not appear.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: black,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  PartyNovaGoldenIdCard(
                    userId: userId,
                    role: role,
                  ),
                const SizedBox(height: 18),
                if (userId.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: const Color(0xFFFFF8E7),
                          title: const Text(
                            'PartyNova ID',
                            style: TextStyle(color: black),
                          ),
                          content: SelectableText(
                            userId,
                            style: const TextStyle(
                              color: black,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext),
                              child: const Text(
                                'Close',
                                style: TextStyle(color: pink),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('View / Copy ID'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pink,
                      side: const BorderSide(color: pink),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8FB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFD5E8),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account Information',
                        style: TextStyle(
                          color: black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Email',
                        style: TextStyle(
                          color: Color(0xFF806B77),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        user.email ?? 'No email available',
                        style: const TextStyle(
                          color: black,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavigationIcon(IconData icon, bool selected) {
    return Icon(
      icon,
      size: 25,
      color: selected ? gold : const Color(0xFFC9A66B),
      shadows: [
        Shadow(
          color: selected
              ? gold.withValues(alpha: 0.35)
              : Colors.transparent,
          blurRadius: selected ? 10 : 0,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isProfile = _selectedIndex == 5;

    return Scaffold(
      backgroundColor: isProfile ? white : black,
      appBar: AppBar(
        backgroundColor: isProfile ? white : black,
        foregroundColor: isProfile ? pink : white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          _pageTitles[_selectedIndex],
          style: TextStyle(
            color: isProfile ? pink : white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              onPressed: _openSettings,
              tooltip: 'Settings',
              icon: const Icon(
                Icons.settings_rounded,
                color: gold,
                size: 27,
              ),
            ),
        ],
      ),
      body: _selectedIndex == 5
          ? _buildProfilePage()
          : _buildEmptyPage(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isProfile ? white : const Color(0xFF111014),
          border: Border(
            top: BorderSide(
              color: isProfile
                  ? const Color(0xFFFFD5E8)
                  : const Color(0xFF49313F),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: isProfile ? pink : gold,
            unselectedItemColor:
                isProfile ? const Color(0xFF777777) : white,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            showUnselectedLabels: true,
            items: [
              BottomNavigationBarItem(
                icon: _buildNavigationIcon(
                  Icons.home_rounded,
                  _selectedIndex == 0,
                ),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: _buildNavigationIcon(
                  Icons.meeting_room_rounded,
                  _selectedIndex == 1,
                ),
                label: 'Rooms',
              ),
              BottomNavigationBarItem(
                icon: _buildNavigationIcon(
                  Icons.sports_esports_rounded,
                  _selectedIndex == 2,
                ),
                label: 'Games',
              ),
              BottomNavigationBarItem(
                icon: _buildNavigationIcon(
                  Icons.account_balance_wallet_rounded,
                  _selectedIndex == 3,
                ),
                label: 'Wallet',
              ),
              BottomNavigationBarItem(
                icon: _buildNavigationIcon(
                  Icons.people_alt_rounded,
                  _selectedIndex == 4,
                ),
                label: 'Social',
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  Icons.person_rounded,
                  color: isProfile ? pink : const Color(0xFFC9A66B),
                  size: 25,
                ),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class PartyNovaGoldenIdCard extends StatelessWidget {
  final String userId;
  final String role;

  const PartyNovaGoldenIdCard({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.65,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF0A8),
              Color(0xFFB87916),
              Color(0xFFFFD966),
              Color(0xFF70420C),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 7),
            ),
            BoxShadow(
              color: Color(0x66FFD700),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFE9A0),
              width: 1.5,
            ),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF3A1731),
                Color(0xFF170D20),
                Color(0xFF492817),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: PartyNovaDiamondPainter(),
                ),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: Icon(
                  Icons.auto_awesome,
                  color: const Color(0xFFFFE8A0).withValues(alpha: 0.8),
                  size: 19,
                ),
              ),
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFE9A0),
                          Color(0xFFB47718),
                          Color(0xFFFFD966),
                        ],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFFD91F36),
                            Color(0xFF720A21),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'ID',
                          style: TextStyle(
                            color: Color(0xFFFFE7A0),
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 3,
                                offset: Offset(1, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 76,
                right: 8,
                top: 8,
                bottom: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'PARTYNOVA',
                      maxLines: 1,
                      style: TextStyle(
                        color: Color(0xFFFFE7A0),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFFFFF),
                              Color(0xFFFFEAA0),
                              Color(0xFFFFB51B),
                              Color(0xFFB86C0B),
                            ],
                          ).createShader(bounds);
                        },
                        child: Text(
                          userId,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 2,
                                offset: Offset(2, 3),
                              ),
                              Shadow(
                                color: Color(0xFFFFD75E),
                                blurRadius: 5,
                                offset: Offset(0, -1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role.toUpperCase(),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFFFFE9B0),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                bottom: 5,
                child: Icon(
                  Icons.diamond_rounded,
                  size: 15,
                  color: const Color(0xFFFFD65A).withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PartyNovaDiamondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD76A).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const spacing = 18.0;
    const radius = 6.0;

    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final path = Path()
          ..moveTo(x, y - radius)
          ..lineTo(x + radius, y)
          ..lineTo(x, y + radius)
          ..lineTo(x - radius, y)
          ..close();

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PartyNovaDiamondPainter oldDelegate) => false;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF100B16),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF24112F),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: partyNightDecoration(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const SizedBox(height: 8),
              _GlossySettingsBox(
                child: Column(
                  children: [
                    _SettingsOption(
                      icon: Icons.lock_outline_rounded,
                      title: 'Privacy',
                      onTap: () {
                        _showSettingsMessage(
                          context,
                          'Privacy settings will be available here.',
                        );
                      },
                    ),
                    const Divider(color: Color(0x33FFD700)),
                    _SettingsOption(
                      icon: Icons.manage_accounts_rounded,
                      title: 'Account',
                      onTap: () {
                        _showSettingsMessage(
                          context,
                          'Account settings will be available here.',
                        );
                      },
                    ),
                    const Divider(color: Color(0x33FFD700)),
                    _SettingsOption(
                      icon: Icons.help_outline_rounded,
                      title: 'Help Center',
                      onTap: () {
                        _showSettingsMessage(
                          context,
                          'Help Center will be available here.',
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _GlossySettingsBox(
                child: _SettingsOption(
                  icon: Icons.logout_rounded,
                  title: 'Log Out',
                  color: const Color(0xFFFFD76A),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: const Color(0xFF24112F),
                        title: const Text(
                          'Log Out',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: const Text(
                          'Are you sure you want to log out?',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext, false);
                            },
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext, true);
                            },
                            child: const Text('Log Out'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await FirebaseAuth.instance.signOut();

                      if (context.mounted) {
                        Navigator.of(context).popUntil(
                          (route) => route.isFirst,
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 18),
              _GlossySettingsBox(
                child: _SettingsOption(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete Account',
                  color: Colors.redAccent,
                  onTap: () {
                    _showSettingsMessage(
                      context,
                      'Contact support to request account deletion.',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _SettingsOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color color;

  const _SettingsOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color, size: 25),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFFFFD76A),
      ),
    );
  }
}

class _GlossySettingsBox extends StatelessWidget {
  final Widget child;

  const _GlossySettingsBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3A173E),
            Color(0xFF1A1022),
            Color(0xFF48223C),
          ],
        ),
        border: Border.all(
          color: const Color(0x66FFD76A),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}



