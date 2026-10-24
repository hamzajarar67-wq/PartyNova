import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';




String _cachedProfilePhotoBase64 = '';
Uint8List? _cachedProfilePhotoBytes;

Uint8List? getCachedProfilePhoto(String encoded) {
  if (encoded.isEmpty) return null;

  if (_cachedProfilePhotoBase64 != encoded) {
    _cachedProfilePhotoBase64 = encoded;

    try {
      _cachedProfilePhotoBytes = base64Decode(encoded);
    } catch (e) {
      debugPrint('Profile photo decode failed: $e');
      _cachedProfilePhotoBytes = null;
    }
  }

  return _cachedProfilePhotoBytes;
}



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

  if (normalizedEmail == partyNovaOwnerEmail) return 'owner';
  if (normalizedEmail == partyNovaAdminEmail) return 'admin';

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
        Color(0xFF7A174A),
        Color(0xFF321024),
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
    final claimRef =
        firestore.collection('userIdClaims').doc(reservedId);

    return firestore.runTransaction<String>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final claimSnapshot = await transaction.get(claimRef);

      final claimedUid = claimSnapshot.data()?['uid'];

      if (claimSnapshot.exists && claimedUid != user.uid) {
        throw StateError(
          'Reserved ID is already assigned to another account.',
        );
      }

      transaction.set(
        userRef,
        {
          'userId': reservedId,
          'email': email,
          'name': user.displayName ?? '',
          'role': partyNovaRoleForEmail(email),
        },
        SetOptions(merge: true),
      );

      if (!claimSnapshot.exists) {
        transaction.set(claimRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return reservedId;
    });
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

      if (assignedId != null) return assignedId;
    } catch (error) {
      if (error is StateError) rethrow;
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
              child: CircularProgressIndicator(color: partyPink),
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

      if (FirebaseAuth.instance.currentUser != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const PartyNovaHome(),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const LoginPage(),
          ),
        );
      }
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
                    border: Border.all(color: partyGold, width: 2),
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
      style: const TextStyle(color: partyWhite, fontSize: 15),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Color(0xFFFFC7E2)),
        prefixIcon: Icon(widget.icon, color: partyGold),
        suffixIcon: widget.password
            ? IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () {
                  setState(() => _obscure = !_obscure);
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
          borderSide: const BorderSide(color: Color(0xFF654052)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF654052)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: partyPink, width: 1.5),
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
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = credential.user;

      if (user == null) {
        throw StateError('User session is unavailable.');
      }

      // Open Home after Firebase Authentication succeeds.
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const PartyNovaHome(),
        ),
        (route) => false,
      );

      // Set up the profile ID separately so it cannot block login.
      try {
        await assignPartyNovaUserId(user);
      } catch (e) {
        debugPrint('PartyNova profile ID setup failed: $e');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } catch (e) {
      debugPrint('PartyNova login failed: $e');

      if (mounted) {
        setState(() {
          _error = 'Login failed. Please try again.';
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
        throw StateError(
          'Account created, but user session is unavailable.',
        );
      }

      await user.updateDisplayName(_nameController.text.trim());
      await user.reload();

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw StateError('User session is unavailable.');
      }

      // Open Home after the account is created.
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const PartyNovaHome(),
        ),
        (route) => false,
      );

      // Profile ID creation is handled separately.
      try {
        await assignPartyNovaUserId(currentUser);
      } catch (e) {
        debugPrint('PartyNova signup profile setup failed: $e');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } catch (e) {
      debugPrint('PartyNova signup failed: $e');

      if (mounted) {
        setState(() {
          _error =
              'Account creation failed. Please try again.';
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

  static const List<String> _titles = [
    'Home',
    'Rooms',
    'Games',
    'Wallet',
    'Social',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: partyBlack,
      appBar: AppBar(
        backgroundColor: const Color(0xFF21101F),
        elevation: 0,
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.settings, color: Color(0xFFFFD700)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          _buildPlaceholderTab(Icons.meeting_room, 'Rooms'),
          _buildPlaceholderTab(Icons.sports_esports, 'Games'),
          _buildPlaceholderTab(Icons.account_balance_wallet, 'Wallet'),
          _buildPlaceholderTab(Icons.people, 'Social'),
          _buildProfileTab(user),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF110B19),
          border: Border(
            top: BorderSide(color: Color(0xFF3B2448)),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: List.generate(_titles.length, (index) {
              final selected = _selectedIndex == index;
              final icons = [
                Icons.home_rounded,
                Icons.meeting_room_rounded,
                Icons.sports_esports_rounded,
                Icons.account_balance_wallet_rounded,
                Icons.people_alt_rounded,
                Icons.person_rounded,
              ];

              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icons[index],
                          color: selected
                              ? const Color(0xFFFFD700)
                              : Colors.white54,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _titles[index],
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            color: selected
                                ? const Color(0xFFFFD700)
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF28123C),
                  Color(0xFF120B1B),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.55),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to PartyNova',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Connect, play and enjoy together.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _GlossySettingsBox(
            icon: Icons.campaign_rounded,
            title: 'New Update',
            subtitle: 'Check the latest updates',
            onTap: () => _showMessage('No new updates yet.'),
          ),
          _GlossySettingsBox(
            icon: Icons.event_rounded,
            title: 'Event',
            subtitle: 'Discover upcoming events',
            onTap: () => _showMessage('Events will be available soon.'),
          ),
          _GlossySettingsBox(
            icon: Icons.card_giftcard_rounded,
            title: 'Daily Free Reward',
            subtitle: 'Your daily reward',
            onTap: () => _showMessage('Daily rewards will be available soon.'),
          ),
          _GlossySettingsBox(
            icon: Icons.task_alt_rounded,
            title: 'Daily Task',
            subtitle: 'View your daily tasks',
            onTap: () => _showMessage('Daily tasks will be available soon.'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab(IconData icon, String title) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: const Color(0xFFFFD700)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coming soon',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

Widget _buildProfileTab(User? user) {
  if (user == null) {
    return const Center(
      child: Text(
        'Please log in again.',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text(
            'Could not load your profile.',
            style: TextStyle(color: Colors.white),
          ),
        );
      }

      if (!snapshot.hasData) {
        return const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFFD780),
          ),
        );
      }

      final data = snapshot.data!.data() ?? {};

      final name =
          (data['name'] ?? user.displayName ?? 'PartyNova User')
              .toString();

      final role =
          (data['role'] ?? partyNovaRoleForEmail(user.email))
              .toString()
              .toLowerCase();

      final userId = (data['userId'] ?? '').toString().trim().isNotEmpty
          ? data['userId'].toString().trim()
          : (user.email?.trim().toLowerCase() == partyNovaOwnerEmail
              ? '111111'
              : '');

      final bio = (data['bio'] ?? 'No bio added yet.').toString();

      final isOwnerOrAdmin = role == 'owner' || role == 'admin';

      return Container(
        color: const Color(0xFF09070B),
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Edit option
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfilePage(
  name: name,
  bio: bio == 'No bio added yet.' ? '' : bio,
  uid: user.uid,
  photoBase64: (data['photoBase64'] ?? '').toString(),
),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1688).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFFFF1688),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: Color(0xFFFF1688),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Profile picture placeholder
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF1688),
                      Color(0xFF7028A0),
                      Color(0xFF21102F),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFFD780),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF1688)
                          .withValues(alpha: 0.25),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Builder(
  builder: (context) {
    final photoBase64 =
        (data['photoBase64'] ?? '').toString();

    final photoBytes = getCachedProfilePhoto(photoBase64);

    if (photoBytes == null) {
      return const Icon(
        Icons.person_rounded,
        size: 64,
        color: Colors.white,
      );
    }

    return ClipOval(
      child: Image.memory(
        photoBytes,
        width: 112,
        height: 112,
        fit: BoxFit.cover,
        cacheWidth: 224,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.person_rounded,
            size: 64,
            color: Colors.white,
          );
        },
      ),
    );
    },
),
              ),

const SizedBox(height: 14),

              // Name
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // Owner / Admin badge or regular user's ID
              if (isOwnerOrAdmin) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFFE9A6),
                        Color(0xFFD6A83C),
                        Color(0xFF8A5A12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFFFD780),
                    ),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF422B0A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'ID: $userId',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFD780),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Bio
              // Bio
if (bio.trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  Text(
    bio,
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Colors.white70,
      fontSize: 18,
      fontWeight: FontWeight.w500,
    ),
  ),
],

const SizedBox(height: 20),

              
              // Profile statistics
Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(
    vertical: 14,
    horizontal: 6,
  ),
  decoration: const BoxDecoration(
    border: Border.symmetric(
      horizontal: BorderSide(
        color: Color(0xFFFFD780),
        width: 0.7,
      ),
    ),
  ),
  child: const Row(
    children: [
      Expanded(
        child: _ProfileCountItem(
          title: 'Follower',
          value: '0',
        ),
      ),
      Expanded(
        child: _ProfileCountItem(
          title: 'Following',
          value: '0',
        ),
      ),
      Expanded(
        child: _ProfileCountItem(
          title: 'Send Gift',
          value: '0',
        ),
      ),
      Expanded(
        child: _ProfileCountItem(
          title: 'Gift Received',
          value: '0',
        ),
      ),
    ],
  ),
),

              // Preserve the existing Owner/Admin Golden ID Card.
              if (isOwnerOrAdmin) ...[
                const SizedBox(height: 24),
                PartyNovaGoldenIdCard(userId: userId),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _profileStatCard({
  required IconData icon,
  required String title,
  required String value,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: 6,
      vertical: 15,
    ),
    decoration: BoxDecoration(
      color: const Color(0xFF17121D),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: const Color(0xFFFFD780).withValues(alpha: 0.45),
      ),
    ),
    child: Column(
      children: [
        Icon(
          icon,
          color: const Color(0xFFFF1688),
          size: 23,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFD780),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}
                    

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}




class EditProfilePage extends StatefulWidget {
  final String name;
  final String bio;
  final String uid;
  final String photoBase64;

  const EditProfilePage({
  super.key,
  required this.name,
  required this.bio,
  required this.uid,
  required this.photoBase64,
});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _nameController;
late final TextEditingController _bioController;

String _photoBase64 = '';
bool _saving = false;
bool _pickingPhoto = false;

  @override
void initState() {
  super.initState();
  _nameController = TextEditingController(text: widget.name);
  _bioController = TextEditingController(text: widget.bio);
  _photoBase64 = widget.photoBase64;
}
  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature functionality will be added later.'),
        backgroundColor: const Color(0xFF7028A0),
      ),
    );
  }


Future<void> _pickDP() async {
  if (_pickingPhoto || _saving) return;

  _pickingPhoto = true;

  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (picked == null || !mounted) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(
        ratioX: 1,
        ratioY: 1,
      ),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Profile Photo',
          toolbarColor: const Color(0xFF7028A0),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFF1688),
          lockAspectRatio: true,
          aspectRatioPresets: [
            CropAspectRatioPreset.square,
          ],
        ),
        IOSUiSettings(
          title: 'Adjust Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.square,
          ],
        ),
      ],
    );

    if (cropped == null || !mounted) return;

    final bytes = await cropped.readAsBytes();

    if (bytes.length > 450 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Photo is too large. Please choose another photo.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _photoBase64 = base64Encode(bytes);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo adjusted! Preview it and tap Save Changes.',
        ),
      ),
    );
  } catch (e) {
    debugPrint('DP selection or cropping failed: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not adjust photo. Please try again.',
          ),
        ),
      );
    }
  } finally {
    _pickingPhoto = false;
  }
}

  
Future<void> _saveProfile() async {
  if (_saving || _pickingPhoto) return;

  final name = _nameController.text.trim();
  final bio = _bioController.text.trim();

  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Name cannot be empty.'),
      ),
    );
    return;
  }

  _saving = true;

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .set({
      'name': name,
      'bio': bio,
      'photoBase64': _photoBase64,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully.'),
      ),
    );

    Navigator.of(context).pop(true);
  } catch (e) {
    debugPrint('Profile save failed: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save profile. Please try again.',
          ),
        ),
      );
    }
  } finally {
    _saving = false;
  }
}


  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09070B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09070B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF1688),
                      Color(0xFF7028A0),
                      Color(0xFF21102F),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFFD780),
                    width: 3,
                  ),
                ),
                child: _photoBase64.isNotEmpty
    ? ClipOval(
        child: Image.memory(
          base64Decode(_photoBase64),
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.person_rounded,
              size: 58,
              color: Colors.white,
            );
          },
        ),
      )
    : const Icon(
        Icons.person_rounded,
        size: 58,
        color: Colors.white,
      ),
              ),
            ),

            const SizedBox(height: 12),

            Center(
              child: Text(
                widget.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 26),

_sectionTitle('Basic Information'),

_editOption(
  icon: Icons.camera_alt_rounded,
  title: 'Change DP',
  subtitle: 'Update your profile picture',
  onTap: _pickDP,
),

const SizedBox(height: 16),

_inputLabel('Change Name'),

TextField(
  controller: _nameController,
  maxLength: 20,
  style: const TextStyle(color: Colors.white),
  decoration: _inputDecoration(
    hint: 'Enter your name',
    icon: Icons.person_outline_rounded,
  ),
),

            const SizedBox(height: 8),

            _inputLabel('Change Bio'),

            TextField(
              controller: _bioController,
              maxLength: 50,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                hint: 'Write something about yourself',
                icon: Icons.edit_note_rounded,
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: _saving ? null : _saveProfile,
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFFF1688),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    child: _saving
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Text(
            'Save Changes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
  ),
),

            const SizedBox(height: 28),

            _sectionTitle('Personalization'),

            _editOption(
  icon: Icons.crop_square_rounded,
  title: 'Frames',
  subtitle: 'Decorate your profile picture',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FramesGalleryPage(
          photoBase64: _photoBase64,
          userName: _nameController.text.trim(),
        ),
      ),
    );
  },
),

            _editOption(
  icon: Icons.palette_rounded,
  title: 'Themes',
  subtitle: 'Explore 100 profile themes',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemesGalleryPage(
          photoBase64: _photoBase64,
          userName: _nameController.text.trim(),
        ),
      ),
    );
  },
),
            _editOption(
  icon: Icons.auto_awesome_rounded,
  title: 'Ornaments',
  subtitle: 'Explore profile decorations',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrnamentsGalleryPage(
          photoBase64: _photoBase64,
          userName: _nameController.text.trim(),
        ),
      ),
    );
  },
),

            const SizedBox(height: 22),

            _sectionTitle('Badges & Effects'),

            _editOption(
  icon: Icons.flash_on_rounded,
  title: 'Entry',
  subtitle: 'Entry effects',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryGalleryPage(
          photoBase64: _photoBase64,
          userName: _nameController.text.trim(),
        ),
      ),
    );
  },
),

            _editOption(
              icon: Icons.workspace_premium_rounded,
              title: 'VIP',
              subtitle: 'VIP level and effects',
              onTap: () => _showComingSoon('VIP'),
            ),

            _editOption(
              icon: Icons.verified_rounded,
              title: 'Royal Badge',
              subtitle: 'Royal profile badge',
              onTap: () => _showComingSoon('Royal Badge'),
            ),

            _editOption(
              icon: Icons.sports_esports_rounded,
              title: 'Game Badge',
              subtitle: 'Your gaming badge',
              onTap: () => _showComingSoon('Game Badge'),
            ),

            _editOption(
              icon: Icons.diamond_rounded,
              title: 'Money Badge',
              subtitle: 'Your money badge',
              onTap: () => _showComingSoon('Money Badge'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFD780),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _inputLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white),
prefixIcon: Icon(icon, color: const Color(0xFFFF1688)),
counterStyle: const TextStyle(color: Colors.white),
      filled: true,
      fillColor: const Color(0xFF17121D),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: const Color(0xFFFF1688).withValues(alpha: 0.4),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFFFFD780),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _editOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF17121D),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFFFF1688).withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 5,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFF1688).withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFFFD780),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
  color: Colors.white,
  fontSize: 12,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: Color(0xFFFF1688),
          size: 17,
        ),
      ),
    );
  }
}


class FramesGalleryPage extends StatefulWidget {
  final String photoBase64;
  final String userName;

  const FramesGalleryPage({
    super.key,
    required this.photoBase64,
    required this.userName,
  });

  @override
  State<FramesGalleryPage> createState() =>
      _FramesGalleryPageState();
}

class _FramesGalleryPageState extends State<FramesGalleryPage> {
  int _selectedFrame = 1;

  static const Color _background = Color(0xFF09070B);
  static const Color _pink = Color(0xFFFF1688);
  static const Color _gold = Color(0xFFFFD780);
  static const Color _panel = Color(0xFF17121D);

  static const List<String> _frameNames = [
    'Royal King',
    'Royal Queen',
    'Golden Crown',
    'King of Kings',
    'Royal Princess',
    'Royal Prince',
    'Imperial Gold',
    'Royal Diamond',
    'Golden Throne',
    'Royal Emperor',
    'Royal Empress',
    'Crown Legend',
    'King Majesty',
    'Queen Majesty',
    'Royal Pearl',
    'Golden Royalty',
    'Royal Palace',
    'Crown Master',
    'Royal Dynasty',
    'Royal Glory',
    'King Legacy',
    'Queen Legacy',
    'Royal Elite',
    'Royal Prestige',
    'Eternal Royal',
    'Diamond Star',
    'Blue Diamond',
    'Pink Diamond',
    'Crystal Shine',
    'Diamond King',
    'Diamond Queen',
    'Crystal Crown',
    'Emerald Glow',
    'Sapphire Dream',
    'Ruby Royal',
    'Platinum Shine',
    'Crystal Legend',
    'Diamond Aura',
    'Luxury Gem',
    'Eternal Diamond',
    'VIP Gold',
    'VIP Black',
    'VIP Legend',
    'VIP Elite',
    'VIP Superstar',
    'VIP Royal',
    'VIP Diamond',
    'VIP Emperor',
    'VIP Empress',
    'VIP Platinum',
    'VIP Prestige',
    'VIP Crown',
    'VIP Luxury',
    'VIP Icon',
    'VIP Infinity',
    'Purple Neon',
    'Pink Neon',
    'Blue Neon',
    'Neon King',
    'Neon Queen',
    'Cyber Glow',
    'Electric Aura',
    'Neon Galaxy',
    'Purple Flame',
    'Neon Star',
    'Cosmic Light',
    'Electric Crown',
    'Neon Legend',
    'Rainbow Glow',
    'Galaxy Neon',
    'Fire King',
    'Ice Queen',
    'Phoenix Rise',
    'Dragon Soul',
    'Angel Wings',
    'Devil Flame',
    'Butterfly Dream',
    'Golden Rose',
    'Midnight Star',
    'Moonlight Aura',
    'Sunlight Glory',
    'Ocean Pearl',
    'Crystal Butterfly',
    'Eternal Flame',
    'Mystic Legend',
    'Money King',
    'Millionaire',
    'Billionaire Gold',
    'Golden Phoenix',
    'Royal Dragon',
    'Diamond Phoenix',
    'Cosmic King',
    'Celestial Queen',
    'Infinity Crown',
    'Legend Forever',
    'Supreme Royal',
    'Ultimate King',
    'Ultimate Queen',
    'PartyNova Legend',
    'PartyNova Supreme',
  ];

  static const List<Color> _frameColors = [
    Color(0xFFFFD700),
    Color(0xFFFF1688),
    Color(0xFF8A2BE2),
    Color(0xFF00CFFF),
    Color(0xFF20C997),
    Color(0xFFFF7043),
    Color(0xFFE5E4E2),
    Color(0xFF7C4DFF),
  ];

  Color _colorForFrame(int number) {
    return _frameColors[(number - 1) % _frameColors.length];
  }

  Widget _profileAvatar({
    required int frameNumber,
    required double size,
  }) {
    final color = _colorForFrame(frameNumber);

    Widget avatar;

    if (widget.photoBase64.isNotEmpty) {
      try {
        avatar = Image.memory(
          base64Decode(widget.photoBase64),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person_rounded,
            size: size * 0.58,
            color: Colors.white,
          ),
        );
      } catch (_) {
        avatar = Icon(
          Icons.person_rounded,
          size: size * 0.58,
          color: Colors.white,
        );
      }
    } else {
      avatar = Icon(
        Icons.person_rounded,
        size: size * 0.58,
        color: Colors.white,
      );
    }

    return Container(
      width: size + 12,
      height: size + 12,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            color,
            Colors.white,
            color,
            color.withValues(alpha: 0.45),
            color,
          ],
        ),
        border: Border.all(
          color: frameNumber == _selectedFrame ? _gold : color,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 9,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF24192D),
          child: avatar,
        ),
      ),
    );
  }

  Widget _frameCard(int number) {
    final name = _frameNames[number - 1];
    final color = _colorForFrame(number);
    final selected = _selectedFrame == number;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedFrame = number;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 3,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _gold
                : color.withValues(alpha: 0.45),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _profileAvatar(
              frameNumber: number,
              size: 43,
            ),
            const SizedBox(height: 9),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _gold : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewSection() {
    final color = _colorForFrame(_selectedFrame);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _gold.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'FRAME PREVIEW',
            style: TextStyle(
              color: _gold,
              fontSize: 14,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 22),
          _profileAvatar(
            frameNumber: _selectedFrame,
            size: 112,
          ),
          const SizedBox(height: 14),
          Text(
            widget.userName.isEmpty
                ? 'Your Name'
                : widget.userName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _frameNames[_selectedFrame - 1],
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF24192D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _pink.withValues(alpha: 0.6),
              ),
            ),
            child: const Text(
              'UI Preview Only',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Frames Gallery',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF35123F),
                    Color(0xFF17121D),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pink.withValues(alpha: 0.6),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose Your Style',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Explore 100 profile frames.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Preview moved above the gallery.
            _previewSection(),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ALL FRAMES',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Text(
                  '${_frameNames.length} Frames',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _frameNames.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 9,
                childAspectRatio: 0.69,
              ),
              itemBuilder: (context, index) {
                return _frameCard(index + 1);
              },
            ),
          ],
        ),
      ),
    );
  }
}




class ThemesGalleryPage extends StatefulWidget {
  final String photoBase64;
  final String userName;

  const ThemesGalleryPage({
    super.key,
    required this.photoBase64,
    required this.userName,
  });

  @override
  State<ThemesGalleryPage> createState() =>
      _ThemesGalleryPageState();
}

class _ThemesGalleryPageState extends State<ThemesGalleryPage> {
  int _selectedTheme = 1;

  static const Color _background = Color(0xFF09070B);
  static const Color _pink = Color(0xFFFF1688);
  static const Color _gold = Color(0xFFFFD780);
  static const Color _panel = Color(0xFF17121D);

  static const List<String> _names = [
    'Midnight Galaxy',
    'Ocean Breeze',
    'Sunset Dreams',
    'Rose Garden',
    'Arctic Aurora',
    'Emerald Forest',
    'Crimson Storm',
    'Lavender Mist',
    'Neon City',
    'Sakura Blossom',
    'Moonlit Ocean',
    'Desert Mirage',
    'Cosmic Nebula',
    'Cherry Blossom',
    'Frozen Horizon',
    'Tropical Paradise',
    'Shadow Realm',
    'Rainbow Valley',
    'Starlight Dreams',
    'Velvet Night',
    'Coral Reef',
    'Silver Rain',
    'Golden Horizon',
    'Purple Haze',
    'Blue Lagoon',
    'Autumn Leaves',
    'Spring Meadow',
    'Winter Palace',
    'Summer Glow',
    'Mystic Waterfall',
    'Cloud Nine',
    'Electric Dreams',
    'Candy World',
    'Peach Paradise',
    'Ruby Sunset',
    'Polar Lights',
    'Jade Garden',
    'Indigo Skies',
    'Amber Waves',
    'Cotton Candy',
    'Galaxy Waves',
    'Crystal Lake',
    'Flaming Sunset',
    'Secret Garden',
    'Aurora Fields',
    'Velvet Rose',
    'Ocean Pearl',
    'Blue Mirage',
    'Pink Horizon',
    'Golden Sands',
    'Thunder Sky',
    'Rainy Evening',
    'Starry Path',
    'Dreamy Clouds',
    'Lunar Eclipse',
    'Solar Flare',
    'Wild Orchid',
    'Misty Mountains',
    'Cobalt Dreams',
    'Peacock Garden',
    'Blossom Rain',
    'Northern Lights',
    'Marble Dreams',
    'Silk Sunset',
    'Electric Ocean',
    'Deep Space',
    'Opal Skies',
    'Cinnamon Glow',
    'Velvet Sky',
    'Blue Symphony',
    'Pink Stardust',
    'Green Oasis',
    'Amber Twilight',
    'Purple Paradise',
    'Scarlet Horizon',
    'Soft Serenity',
    'Mystic Garden',
    'Celestial Waves',
    'Dreamscape',
    'Enchanted Forest',
    'Ocean Twilight',
    'Golden Autumn',
    'Crystal Winter',
    'Pastel Dreams',
    'Nightfall City',
    'Stardust Valley',
    'Blush Heaven',
    'Moonstone Glow',
    'Deep Emerald',
    'Coral Sunset',
    'Indigo Dreams',
    'Silver Horizon',
    'Rainforest Glow',
    'Lavender Skies',
    'Cosmic Garden',
    'Velvet Sunset',
    'Eternal Spring',
    'PartyNova Signature',
  ];

  static const List<List<Color>> _palettes = [
    [
      Color(0xFF160E38),
      Color(0xFF692D91),
      Color(0xFFEA3C91),
    ],
    [
      Color(0xFF063B55),
      Color(0xFF087E8B),
      Color(0xFF50C9CE),
    ],
    [
      Color(0xFF812D45),
      Color(0xFFE66A52),
      Color(0xFFFFC477),
    ],
    [
      Color(0xFF56164C),
      Color(0xFFB52D73),
      Color(0xFFFFA3B8),
    ],
    [
      Color(0xFF183B65),
      Color(0xFF478BC2),
      Color(0xFFB8E7F5),
    ],
    [
      Color(0xFF123E31),
      Color(0xFF21865E),
      Color(0xFF9FD68C),
    ],
    [
      Color(0xFF511525),
      Color(0xFFB32743),
      Color(0xFFFF795E),
    ],
    [
      Color(0xFF39215E),
      Color(0xFF8064B7),
      Color(0xFFD8B8F2),
    ],
    [
      Color(0xFF101B36),
      Color(0xFF176B87),
      Color(0xFF2CE5D2),
    ],
    [
      Color(0xFF6A244F),
      Color(0xFFC85C91),
      Color(0xFFFFC8D9),
    ],
    [
      Color(0xFF092A49),
      Color(0xFF225E89),
      Color(0xFF9ACDEB),
    ],
    [
      Color(0xFF57301E),
      Color(0xFFAE6A36),
      Color(0xFFE8C17A),
    ],
    [
      Color(0xFF17113D),
      Color(0xFF413C91),
      Color(0xFFB8A0FF),
    ],
    [
      Color(0xFF672B50),
      Color(0xFFCF6D91),
      Color(0xFFFFD0D8),
    ],
    [
      Color(0xFF1C3455),
      Color(0xFF668EB6),
      Color(0xFFD7EBF8),
    ],
    [
      Color(0xFF145044),
      Color(0xFF39A987),
      Color(0xFFA8E5B5),
    ],
    [
      Color(0xFF100F20),
      Color(0xFF363044),
      Color(0xFF81718F),
    ],
    [
      Color(0xFF3D2169),
      Color(0xFF9A4DAA),
      Color(0xFFF3A5C9),
    ],
    [
      Color(0xFF101B43),
      Color(0xFF345AA3),
      Color(0xFFFFD67D),
    ],
    [
      Color(0xFF35172D),
      Color(0xFF743B63),
      Color(0xFFD9A5C7),
    ],
  ];

  List<Color> _colors(int number) {
    return _palettes[(number - 1) % _palettes.length];
  }

  Widget _avatar(double size) {
    if (widget.photoBase64.isNotEmpty) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(widget.photoBase64),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                _defaultAvatar(size),
          ),
        );
      } catch (_) {
        return _defaultAvatar(size);
      }
    }

    return _defaultAvatar(size);
  }

  Widget _defaultAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF30243B),
      ),
      child: Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: size * 0.62,
      ),
    );
  }

  Widget _themeCard(int number) {
    final colors = _colors(number);
    final selected = number == _selectedTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () {
        setState(() {
          _selectedTheme = number;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? _gold
                : colors[2].withValues(alpha: 0.8),
            width: selected ? 2 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Positioned(
                top: -18,
                right: -16,
                child: Container(
                  width: 75,
                  height: 75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: 0.09,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 45,
                left: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: 0.13,
                      ),
                      width: 9,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: 0.9,
                          ),
                          width: 2,
                        ),
                      ),
                      child: _avatar(48),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      widget.userName.isEmpty
                          ? 'Your Name'
                          : widget.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      height: 1,
                      color: Colors.white.withValues(
                        alpha: 0.45,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _names[number - 1],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 19,
                      )
                    else
                      const SizedBox(height: 19),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _largePreview() {
    final colors = _colors(_selectedTheme);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _gold.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'SELECTED THEME PREVIEW',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: Column(
              children: [
                _avatar(94),
                const SizedBox(height: 13),
                Text(
                  widget.userName.isEmpty
                      ? 'Your Name'
                      : widget.userName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _names[_selectedTheme - 1],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'Preview only — not applied to your profile.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Themes Gallery',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          14,
          12,
          14,
          30,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF35123F),
                    Color(0xFF17121D),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pink.withValues(alpha: 0.65),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find Your Theme',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '100 unique looks for your profile.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Preview moved above the gallery.
            _largePreview(),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ALL THEMES',
                    style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Text(
                  '${_names.length} Themes',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _names.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 11,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, index) {
                return _themeCard(index + 1);
              },
            ),
          ],
        ),
      ),
    );
  }
}


class OrnamentsGalleryPage extends StatefulWidget {
  final String? photoBase64;
  final String userName;

  const OrnamentsGalleryPage({
    super.key,
    required this.photoBase64,
    required this.userName,
  });

  @override
  State<OrnamentsGalleryPage> createState() =>
      _OrnamentsGalleryPageState();
}

class _OrnamentsGalleryPageState
    extends State<OrnamentsGalleryPage> {
  final Color darkBlue = const Color(0xFF071426);
  final Color boxBlue = const Color(0xFF102746);
  final Color gold = const Color(0xFFFFC857);

  int selectedIndex = 0;

  // Cache the profile image to prevent repeated decoding.
  ImageProvider? _cachedAvatarImage;
  bool _avatarImageInitialized = false;

  final List<Map<String, dynamic>> ornaments = [
    {'name': 'Golden Crown', 'emoji': '👑', 'color': Color(0xFFFFC857)},
    {'name': 'Angel Wings', 'emoji': '🪽', 'color': Color(0xFFE8EAF6)},
    {'name': 'Butterfly Dreams', 'emoji': '🦋', 'color': Color(0xFFB388FF)},
    {'name': 'Rose Garden', 'emoji': '🌹', 'color': Color(0xFFFF6688)},
    {'name': 'Diamond Aura', 'emoji': '💎', 'color': Color(0xFF80DEEA)},
    {'name': 'Love Hearts', 'emoji': '💖', 'color': Color(0xFFFF4081)},
    {'name': 'Star Sparkles', 'emoji': '✨', 'color': Color(0xFFFFD54F)},
    {'name': 'Moonlight', 'emoji': '🌙', 'color': Color(0xFF90CAF9)},
    {'name': 'Rainbow Glow', 'emoji': '🌈', 'color': Color(0xFFCE93D8)},
    {'name': 'Flame Aura', 'emoji': '🔥', 'color': Color(0xFFFF7043)},
    {'name': 'Royal Tiara', 'emoji': '👸', 'color': Color(0xFFFFD700)},
    {'name': 'Crystal Halo', 'emoji': '💠', 'color': Color(0xFF80CBC4)},
    {'name': 'Cherry Blossom', 'emoji': '🌸', 'color': Color(0xFFF48FB1)},
    {'name': 'Golden Butterfly', 'emoji': '🦋', 'color': Color(0xFFFFD54F)},
    {'name': 'Silver Wings', 'emoji': '🪽', 'color': Color(0xFFCFD8DC)},
    {'name': 'Royal Jewels', 'emoji': '💎', 'color': Color(0xFFFFC857)},
    {'name': 'Pink Aura', 'emoji': '💗', 'color': Color(0xFFF06292)},
    {'name': 'Blue Aura', 'emoji': '🩵', 'color': Color(0xFF4FC3F7)},
    {'name': 'Purple Aura', 'emoji': '💜', 'color': Color(0xFFBA68C8)},
    {'name': 'Golden Aura', 'emoji': '🌟', 'color': Color(0xFFFFD54F)},
    {'name': 'Rose Crown', 'emoji': '🌹', 'color': Color(0xFFEF5350)},
    {'name': 'Flower Crown', 'emoji': '🌺', 'color': Color(0xFFF06292)},
    {'name': 'Daisy Dreams', 'emoji': '🌼', 'color': Color(0xFFFFEE58)},
    {'name': 'Lavender Wings', 'emoji': '🦋', 'color': Color(0xFFCE93D8)},
    {'name': 'Crystal Wings', 'emoji': '🪽', 'color': Color(0xFF80DEEA)},
    {'name': 'Love Angel', 'emoji': '😇', 'color': Color(0xFFFFD180)},
    {'name': 'Heart Halo', 'emoji': '💞', 'color': Color(0xFFFF80AB)},
    {'name': 'Pearl Crown', 'emoji': '👑', 'color': Color(0xFFE0E0E0)},
    {'name': 'Emerald Crown', 'emoji': '👑', 'color': Color(0xFF66BB6A)},
    {'name': 'Ruby Crown', 'emoji': '👑', 'color': Color(0xFFEF5350)},
    {'name': 'Sapphire Crown', 'emoji': '👑', 'color': Color(0xFF42A5F5)},
    {'name': 'Golden Roses', 'emoji': '🌹', 'color': Color(0xFFFFC857)},
    {'name': 'Pink Roses', 'emoji': '🌹', 'color': Color(0xFFF48FB1)},
    {'name': 'White Roses', 'emoji': '🥀', 'color': Color(0xFFECEFF1)},
    {'name': 'Magic Stars', 'emoji': '🌟', 'color': Color(0xFFFFEE58)},
    {'name': 'Shooting Star', 'emoji': '🌠', 'color': Color(0xFFFFD54F)},
    {'name': 'Cosmic Aura', 'emoji': '🌌', 'color': Color(0xFF9575CD)},
    {'name': 'Galaxy Wings', 'emoji': '🦋', 'color': Color(0xFF7E57C2)},
    {'name': 'Snowflake Halo', 'emoji': '❄️', 'color': Color(0xFF81D4FA)},
    {'name': 'Ice Crystal', 'emoji': '💎', 'color': Color(0xFF80DEEA)},
    {'name': 'Sunshine Aura', 'emoji': '☀️', 'color': Color(0xFFFFCA28)},
    {'name': 'Moon Crown', 'emoji': '🌙', 'color': Color(0xFFB0BEC5)},
    {'name': 'Royal Phoenix', 'emoji': '🔥', 'color': Color(0xFFFF8A65)},
    {'name': 'Golden Phoenix', 'emoji': '🪶', 'color': Color(0xFFFFD54F)},
    {'name': 'Feather Wings', 'emoji': '🪽', 'color': Color(0xFFB0BEC5)},
    {'name': 'Dream Catcher', 'emoji': '🪬', 'color': Color(0xFF80CBC4)},
    {'name': 'Magic Orb', 'emoji': '🔮', 'color': Color(0xFF9575CD)},
    {'name': 'Enchanted Rose', 'emoji': '🌹', 'color': Color(0xFFEC407A)},
    {'name': 'Crystal Rose', 'emoji': '💎', 'color': Color(0xFF80DEEA)},
    {'name': 'Royal Butterfly', 'emoji': '🦋', 'color': Color(0xFFFFCA28)},
    {'name': 'Fairy Dust', 'emoji': '🧚', 'color': Color(0xFFCE93D8)},
    {'name': 'Fairy Wings', 'emoji': '🧚', 'color': Color(0xFFF48FB1)},
    {'name': 'Unicorn Magic', 'emoji': '🦄', 'color': Color(0xFFCE93D8)},
    {'name': 'Golden Horn', 'emoji': '✨', 'color': Color(0xFFFFD54F)},
    {'name': 'Ocean Pearls', 'emoji': '🫧', 'color': Color(0xFF4FC3F7)},
    {'name': 'Sea Shell Halo', 'emoji': '🐚', 'color': Color(0xFFFFCCBC)},
    {'name': 'Ocean Aura', 'emoji': '🌊', 'color': Color(0xFF29B6F6)},
    {'name': 'Coral Crown', 'emoji': '🪸', 'color': Color(0xFFFF8A65)},
    {'name': 'Golden Leaves', 'emoji': '🍂', 'color': Color(0xFFFFB74D)},
    {'name': 'Autumn Aura', 'emoji': '🍁', 'color': Color(0xFFFF8A65)},
    {'name': 'Spring Flowers', 'emoji': '🌷', 'color': Color(0xFFF48FB1)},
    {'name': 'Lotus Halo', 'emoji': '🪷', 'color': Color(0xFFF8BBD0)},
    {'name': 'Jasmine Crown', 'emoji': '🌼', 'color': Color(0xFFFFF59D)},
    {'name': 'Orchid Aura', 'emoji': '🌺', 'color': Color(0xFFCE93D8)},
    {'name': 'Floral Wings', 'emoji': '🌸', 'color': Color(0xFFF48FB1)},
    {'name': 'Golden Petals', 'emoji': '🌼', 'color': Color(0xFFFFD54F)},
    {'name': 'Crystal Butterfly', 'emoji': '🦋', 'color': Color(0xFF80DEEA)},
    {'name': 'Glitter Halo', 'emoji': '✨', 'color': Color(0xFFFFD54F)},
    {'name': 'Stardust Aura', 'emoji': '🌟', 'color': Color(0xFFFFCA28)},
    {'name': 'Diamond Halo', 'emoji': '💎', 'color': Color(0xFF80DEEA)},
    {'name': 'Heart Wings', 'emoji': '💞', 'color': Color(0xFFFF80AB)},
    {'name': 'Cupid Aura', 'emoji': '💘', 'color': Color(0xFFEC407A)},
    {'name': 'Love Angel Wings', 'emoji': '🪽', 'color': Color(0xFFF8BBD0)},
    {'name': 'Royal Hearts', 'emoji': '💖', 'color': Color(0xFFFFC857)},
    {'name': 'Pink Diamonds', 'emoji': '💎', 'color': Color(0xFFF48FB1)},
    {'name': 'Blue Diamonds', 'emoji': '💎', 'color': Color(0xFF4FC3F7)},
    {'name': 'Purple Diamonds', 'emoji': '💎', 'color': Color(0xFFBA68C8)},
    {'name': 'Emerald Aura', 'emoji': '💚', 'color': Color(0xFF66BB6A)},
    {'name': 'Ruby Aura', 'emoji': '❤️', 'color': Color(0xFFEF5350)},
    {'name': 'Sapphire Aura', 'emoji': '💙', 'color': Color(0xFF42A5F5)},
    {'name': 'Silver Sparkles', 'emoji': '✨', 'color': Color(0xFFCFD8DC)},
    {'name': 'Golden Sparkles', 'emoji': '✨', 'color': Color(0xFFFFD54F)},
    {'name': 'Pink Sparkles', 'emoji': '✨', 'color': Color(0xFFF48FB1)},
    {'name': 'Blue Sparkles', 'emoji': '✨', 'color': Color(0xFF4FC3F7)},
    {'name': 'Purple Sparkles', 'emoji': '✨', 'color': Color(0xFFBA68C8)},
    {'name': 'Royal Flame', 'emoji': '🔥', 'color': Color(0xFFFF7043)},
    {'name': 'Golden Flame', 'emoji': '🔥', 'color': Color(0xFFFFCA28)},
    {'name': 'Electric Aura', 'emoji': '⚡', 'color': Color(0xFFFFEE58)},
    {'name': 'Thunder Crown', 'emoji': '⚡', 'color': Color(0xFF90CAF9)},
    {'name': 'Mystic Halo', 'emoji': '🔮', 'color': Color(0xFF9575CD)},
    {'name': 'Royal Eclipse', 'emoji': '🌘', 'color': Color(0xFF7986CB)},
    {'name': 'Solar Crown', 'emoji': '☀️', 'color': Color(0xFFFFCA28)},
    {'name': 'Celestial Wings', 'emoji': '🪽', 'color': Color(0xFFB39DDB)},
    {'name': 'Midnight Stars', 'emoji': '🌌', 'color': Color(0xFF7986CB)},
    {'name': 'Aurora Halo', 'emoji': '🌈', 'color': Color(0xFF80CBC4)},
    {'name': 'Royal Glow', 'emoji': '👑', 'color': Color(0xFFFFD54F)},
    {'name': 'Dreamy Hearts', 'emoji': '💕', 'color': Color(0xFFF48FB1)},
    {'name': 'Magic Butterflies', 'emoji': '🦋', 'color': Color(0xFFCE93D8)},
    {'name': 'Eternal Bloom', 'emoji': '🌸', 'color': Color(0xFFF48FB1)},
    {'name': 'Heavenly Aura', 'emoji': '😇', 'color': Color(0xFFFFD180)},
    {'name': 'Imperial Crown', 'emoji': '👑', 'color': Color(0xFFFFC857)},
  ];

  // Create the image provider once and reuse it across rebuilds.
  ImageProvider? _avatarImage() {
    if (_avatarImageInitialized) {
      return _cachedAvatarImage;
    }

    _avatarImageInitialized = true;

    final data = widget.photoBase64;

    if (data == null || data.isEmpty) {
      return null;
    }

    try {
      _cachedAvatarImage = MemoryImage(base64Decode(data));
    } catch (_) {
      _cachedAvatarImage = null;
    }

    return _cachedAvatarImage;
  }

  // Refresh the cached image only if the profile photo changes.
  @override
  void didUpdateWidget(covariant OrnamentsGalleryPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.photoBase64 != widget.photoBase64) {
      _cachedAvatarImage = null;
      _avatarImageInitialized = false;
    }
  }

  Widget _avatar({
    required double size,
    required int ornamentIndex,
  }) {
    final ornament = ornaments[ornamentIndex];
    final color = ornament['color'] as Color;
    final image = _avatarImage();

    return SizedBox(
      width: size + 36,
      height: size + 42,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size + 18,
            height: size + 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: size / 2,
            backgroundColor: boxBlue,
            backgroundImage: image,
            child: image == null
                ? Icon(
                    Icons.person_rounded,
                    size: size * 0.55,
                    color: gold,
                  )
                : null,
          ),
          Positioned(
            top: 0,
            child: Text(
              ornament['emoji'] as String,
              style: TextStyle(
                fontSize: size * 0.38,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.7),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Text(
              ornament['emoji'] as String,
              style: TextStyle(
                fontSize: size * 0.25,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: color,
              size: size * 0.22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ornamentCard(int index) {
    final ornament = ornaments[index];
    final color = ornament['color'] as Color;
    final isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: boxBlue,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? gold
                : color.withValues(alpha: 0.55),
            width: isSelected ? 2.2 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: gold.withValues(alpha: 0.16),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _avatar(
              size: 64,
              ornamentIndex: index,
            ),
            const SizedBox(height: 12),
            Text(
              ornament['name'] as String,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? gold : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 7),
              Icon(
                Icons.check_circle_rounded,
                color: gold,
                size: 19,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ornaments[selectedIndex];
    final selectedColor = selected['color'] as Color;

    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: gold,
        elevation: 0,
        title: const Text(
          'ORNAMENTS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  22,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: boxBlue,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: gold,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'SELECTED PREVIEW',
                        style: TextStyle(
                          color: gold,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              selectedColor.withValues(alpha: 0.30),
                              darkBlue,
                            ],
                          ),
                        ),
                        child: Center(
                          child: _avatar(
                            size: 112,
                            ornamentIndex: selectedIndex,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        selected['name'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: gold,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.userName.isEmpty
                            ? 'Your Profile'
                            : widget.userName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: darkBlue,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selectedColor,
                          ),
                        ),
                        child: Text(
                          'Preview Only',
                          style: TextStyle(
                            color: selectedColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'EXPLORE ORNAMENTS',
                  style: TextStyle(
                    color: gold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                28,
              ),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ornamentCard(index),
                  childCount: ornaments.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 180,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}





class EntryGalleryPage extends StatefulWidget {
  final String? photoBase64;
  final String userName;

  const EntryGalleryPage({
    super.key,
    required this.photoBase64,
    required this.userName,
  });

  @override
  State<EntryGalleryPage> createState() => _EntryGalleryPageState();
}

class _EntryGalleryPageState extends State<EntryGalleryPage> {
  static const Color _background = Color(0xFF09070B);
  static const Color _card = Color(0xFF17121F);
  static const Color _gold = Color(0xFFFFC857);
  static const Color _purple = Color(0xFF8B5CF6);

  int _selectedIndex = 0;

  static const List<Map<String, dynamic>> _entries = [
    {
      'name': 'Tiger Entry',
      'emoji': '🐅',
      'color': Color(0xFFFF8A00),
      'description': 'Wild Tiger',
    },
    {
      'name': 'Lion Entry',
      'emoji': '🦁',
      'color': Color(0xFFFFC857),
      'description': 'King of the Jungle',
    },
    {
      'name': 'Cheetah Entry',
      'emoji': '🐆',
      'color': Color(0xFFFFD166),
      'description': 'Speed Legend',
    },
    {
      'name': 'Horse Entry',
      'emoji': '🐎',
      'color': Color(0xFFB77946),
      'description': 'Royal Horse',
    },
    {
      'name': 'Wolf Entry',
      'emoji': '🐺',
      'color': Color(0xFF94A3B8),
      'description': 'Shadow Wolf',
    },
    {
      'name': 'Dragon Entry',
      'emoji': '🐉',
      'color': Color(0xFF22C55E),
      'description': 'Mystic Dragon',
    },
    {
      'name': 'Eagle Entry',
      'emoji': '🦅',
      'color': Color(0xFF38BDF8),
      'description': 'Sky Legend',
    },
    {
      'name': 'Bear Entry',
      'emoji': '🐻',
      'color': Color(0xFFB45309),
      'description': 'Power Bear',
    },
    {
      'name': 'Crocodile Entry',
      'emoji': '🐊',
      'color': Color(0xFF65A30D),
      'description': 'Swamp Hunter',
    },
    {
      'name': 'Shark Entry',
      'emoji': '🦈',
      'color': Color(0xFF38BDF8),
      'description': 'Ocean Predator',
    },
    {
      'name': 'Supercar Entry',
      'emoji': '🏎️',
      'color': Color(0xFFEF4444),
      'description': 'Racing Legend',
    },
    {
      'name': 'Luxury Car Entry',
      'emoji': '🚘',
      'color': Color(0xFFE5E7EB),
      'description': 'Luxury Arrival',
    },
    {
      'name': 'Police Car Entry',
      'emoji': '🚔',
      'color': Color(0xFF60A5FA),
      'description': 'Police Arrival',
    },
    {
      'name': 'Superbike Entry',
      'emoji': '🏍️',
      'color': Color(0xFFF97316),
      'description': 'Superbike Rider',
    },
    {
      'name': 'Monster Truck Entry',
      'emoji': '🚛',
      'color': Color(0xFFA78BFA),
      'description': 'Monster Power',
    },
    {
      'name': 'Super Bus Entry',
      'emoji': '🚌',
      'color': Color(0xFFFACC15),
      'description': 'Royal Transport',
    },
    {
      'name': 'Super Flight Entry',
      'emoji': '✈️',
      'color': Color(0xFF38BDF8),
      'description': 'Sky Arrival',
    },
    {
      'name': 'Fighter Jet Entry',
      'emoji': '🛩️',
      'color': Color(0xFF94A3B8),
      'description': 'Jet Arrival',
    },
    {
      'name': 'Rocket Entry',
      'emoji': '🚀',
      'color': Color(0xFFF97316),
      'description': 'Rocket Launch',
    },
    {
      'name': 'UFO Entry',
      'emoji': '🛸',
      'color': Color(0xFF34D399),
      'description': 'Galaxy Arrival',
    },
    {
      'name': 'Golden Dragon Entry',
      'emoji': '🐲',
      'color': Color(0xFFFFC857),
      'description': 'Golden Dragon',
    },
    {
      'name': 'Angel Entry',
      'emoji': '👼',
      'color': Color(0xFFE0F2FE),
      'description': 'Heavenly Arrival',
    },
    {
      'name': 'Dark Demon Entry',
      'emoji': '😈',
      'color': Color(0xFFDC2626),
      'description': 'Dark Power',
    },
    {
      'name': 'King Entry',
      'emoji': '👑',
      'color': Color(0xFFFFC857),
      'description': 'Royal King',
    },
    {
      'name': 'Thunder Entry',
      'emoji': '⚡',
      'color': Color(0xFFFDE047),
      'description': 'Thunder Power',
    },
    {
      'name': 'Fire Dragon Entry',
      'emoji': '🔥',
      'color': Color(0xFFFB923C),
      'description': 'Fire Dragon',
    },
    {
      'name': 'Galaxy Dragon Entry',
      'emoji': '🌌',
      'color': Color(0xFFA78BFA),
      'description': 'Galaxy Dragon',
    },
    {
      'name': 'Angel Wings Entry',
      'emoji': '🪽',
      'color': Color(0xFFE0E7FF),
      'description': 'Angel Wings',
    },
    {
      'name': 'Champion Entry',
      'emoji': '🏆',
      'color': Color(0xFFFFC857),
      'description': 'Champion Arrival',
    },
    {
      'name': 'Diamond King Entry',
      'emoji': '💎',
      'color': Color(0xFF67E8F9),
      'description': 'Diamond Royal',
    },
  ];

  ImageProvider? _cachedAvatar;
  String? _cachedPhotoBase64;

  @override
  void initState() {
    super.initState();
    _prepareAvatar();
  }

  @override
  void didUpdateWidget(covariant EntryGalleryPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.photoBase64 != widget.photoBase64) {
      _cachedAvatar = null;
      _cachedPhotoBase64 = null;
      _prepareAvatar();
    }
  }

  void _prepareAvatar() {
    final data = widget.photoBase64;

    if (data == null || data.isEmpty) return;

    try {
      final cleanData = data.contains(',')
          ? data.substring(data.indexOf(',') + 1)
          : data;

      _cachedAvatar = MemoryImage(base64Decode(cleanData));
      _cachedPhotoBase64 = data;
    } catch (_) {
      _cachedAvatar = null;
      _cachedPhotoBase64 = null;
    }
  }

  ImageProvider? _avatarImage() {
    if (_cachedPhotoBase64 != widget.photoBase64) {
      _prepareAvatar();
    }

    return _cachedAvatar;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _entries[_selectedIndex];
    final selectedColor = selected['color'] as Color;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _gold,
        elevation: 0,
        title: const Text(
          'ENTRY GALLERY',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selectedColor.withValues(alpha: 0.9),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selectedColor.withValues(alpha: 0.12),
                            border: Border.all(
                              color: selectedColor,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: selectedColor.withValues(alpha: 0.3),
                                blurRadius: 25,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _background,
                            border: Border.all(
                              color: _gold,
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _avatarImage() != null
                              ? Image(
                                  image: _avatarImage()!,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white70,
                                  size: 62,
                                ),
                        ),
                        Positioned(
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: selectedColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              selected['emoji'] as String,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.userName.isEmpty
                          ? 'Your Entry Preview'
                          : widget.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selected['name'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selectedColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selected['description'] as String,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Text(
                    'Choose Your Entry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: _entries.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.12,
                ),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final color = entry['color'] as Color;
                  final isSelected = index == _selectedIndex;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? color : Colors.white12,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.75),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                entry['emoji'] as String,
                                style: const TextStyle(fontSize: 34),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                entry['name'] as String,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected ? color : Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: color,
                                size: 19,
                              )
                            else
                              const SizedBox(height: 19),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}








class _ProfileCountItem extends StatelessWidget {
  final String title;
  final String value;

  const _ProfileCountItem({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFD780),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}




class PartyNovaGoldenIdCard extends StatelessWidget {
  final String userId;

  const PartyNovaGoldenIdCard({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE9A6),
            Color(0xFFD6A83C),
            Color(0xFF8A5A12),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFFFF1BD),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.20),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.diamond_rounded, color: Color(0xFF281A08)),
              SizedBox(width: 8),
              Text(
                'PARTYNOVA',
                style: TextStyle(
                  color: Color(0xFF281A08),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              Spacer(),
              Icon(Icons.verified_rounded, color: Color(0xFF281A08)),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'YOUR GOLDEN ID',
            style: TextStyle(
              color: Color(0xFF422B0A),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            userId.isEmpty ? 'ID not assigned' : userId,
            style: const TextStyle(
              color: Color(0xFF211506),
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: userId.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: userId),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('User ID copied.'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy ID'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF211506),
                    side: const BorderSide(color: Color(0xFF422B0A)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PartyNovaDiamondPainter extends CustomPainter {
  final Color color;

  PartyNovaDiamondPainter({
    this.color = const Color(0xFFFFD700),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height * 0.35)
      ..lineTo(size.width * 0.5, size.height)
      ..lineTo(0, size.height * 0.35)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PartyNovaDiamondPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: partyBlack,
      appBar: AppBar(
        backgroundColor: const Color(0xFF21101F),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _SettingsOption(
            icon: Icons.lock_outline_rounded,
            title: 'Privacy',
            subtitle: 'Privacy settings',
            onTap: () => _showInfo(context, 'Privacy settings coming soon.'),
          ),
          _SettingsOption(
            icon: Icons.help_outline_rounded,
            title: 'Help & Support',
            subtitle: 'Get help with PartyNova',
            onTap: () => _showInfo(context, 'Help & support coming soon.'),
          ),
          _SettingsOption(
            icon: Icons.info_outline_rounded,
            title: 'About PartyNova',
            subtitle: 'App information',
            onTap: () => _showInfo(context, 'PartyNova'),
          ),
          const SizedBox(height: 14),
          _SettingsOption(
            icon: Icons.delete_forever_rounded,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account',
            onTap: () => _confirmDeleteAccount(context),
          ),
          _SettingsOption(
            icon: Icons.logout_rounded,
            title: 'Log Out',
            subtitle: 'Sign out of your account',
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF21101F),
        title: const Text(
          'Delete Account?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This permanently deletes your account. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF1688)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();

      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      final message = e.code == 'requires-recent-login'
          ? 'Please log out and log in again, then delete your account.'
          : 'Could not delete account. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete account. Please try again.')),
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1022),
        title: const Text(
          'Log Out?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }
}

class _SettingsOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GlossySettingsBox(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _GlossySettingsBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GlossySettingsBox({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6F1648),
            Color(0xFF21101F),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF9BC8).withValues(alpha: 0.75),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 5,
        ),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF9B1558),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: const Color(0xFFFFD700)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white60),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white54,
        ),
      ),
    );
  }
}
