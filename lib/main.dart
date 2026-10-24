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
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 35,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();

    if (bytes.length > 450 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo is too large. Please choose another photo.',
            ),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _photoBase64 = base64Encode(bytes);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Photo selected. Tap Save Changes to save it.',
        ),
      ),
    );
  } catch (e) {
    debugPrint('DP selection failed: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not select photo. Please try again.',
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
    debugPrint('PROFILE SAVE UID: ${widget.uid}');

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

    Navigator.of(context).pop();
  } catch (e) {
    debugPrint('Profile save failed: $e');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
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
          width: 116,
          height: 116,
          fit: BoxFit.cover,
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
              onTap: () => _showComingSoon('Frames'),
            ),

            _editOption(
              icon: Icons.palette_rounded,
              title: 'Themes',
              subtitle: 'Customize your profile theme',
              onTap: () => _showComingSoon('Themes'),
            ),

            _editOption(
              icon: Icons.auto_awesome_rounded,
              title: 'Ornaments',
              subtitle: 'Explore profile ornaments',
              onTap: () => _showComingSoon('Ornaments'),
            ),

            const SizedBox(height: 22),

            _sectionTitle('Badges & Effects'),

            _editOption(
              icon: Icons.flash_on_rounded,
              title: 'Entry',
              subtitle: 'Entry effects',
              onTap: () => _showComingSoon('Entry'),
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
