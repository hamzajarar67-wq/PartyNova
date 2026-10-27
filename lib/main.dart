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
  int _selectedRoomFilter = 0;
  int _selectedMyRoomFilter = 0;

    final TextEditingController _roomSearchController =
      TextEditingController();

  String _roomSearchQuery = '';

  @override
  void dispose() {
    _roomSearchController.dispose();
    super.dispose();
  }

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
          _buildRoomsTab(),
          _buildGamesTab(),
          _buildPlaceholderTab(Icons.account_balance_wallet, 'Wallet'),
          _buildSocialTab(),
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

Widget _buildGamesTab() {
  const gold = Color(0xFFFFD700);
  const panel = Color(0xFF21101F);

    final games = [
    {
      'title': 'ONE VS ONE',
      'subtitle': 'BATTLE',
      'image': 'assets/games/1792928262794.jpg',
      'colors': [Color(0xFFFFD700), Colors.white],
    },
    {
      'title': 'PRIVATE',
      'subtitle': 'MATCH',
      'image': 'assets/games/51a253a0f1625ec50129f8e42b47d04f.jpg',
      'colors': [Colors.white, Color(0xFFFFD700)],
    },
    {
      'title': 'TEAM',
      'subtitle': 'BATTLE',
      'image': 'assets/games/c7af476b6d7b192bab7a4669bcdf984a.jpg',
      'colors': [Color(0xFFFF4F65), Color(0xFFFFD700)],
    },
    {
      'title': 'CARD',
      'subtitle': 'TOURNAMENT',
      'image': 'assets/games/f8d8884d16186cdc6997747d5c695a48.jpg',
      'colors': [Color(0xFF65C7FF), Color(0xFFB58CFF)],
    },
  ];

  return SingleChildScrollView(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'GAME ARENA',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: gold,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Choose Your Battle',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: games.length,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (context, index) {
            final game = games[index];
            final colors = game['colors'] as List<Color>;

            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                _showMessage(
                  '${game['title']} ${game['subtitle']} will be available soon.',
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: gold.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gold.withValues(alpha: 0.10),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              game['image'] as String,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) {
                                return Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF33233C),
                                        Color(0xFF080A12),
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.style_rounded,
                                      size: 58,
                                      color: gold,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xEE08070D),
                                  ],
                                  stops: [0.35, 1.0],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 13,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF281A31),
                              Color(0xFF100B17),
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              game['title'] as String,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: colors[0],
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              game['subtitle'] as String,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: colors[1],
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Container(
                              height: 2,
                              width: 45,
                              decoration: BoxDecoration(
                                color: gold,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}



Widget _buildSocialTab() {
  const pink = Color(0xFFFF1688);
  const black = Color(0xFF09070B);

  return DefaultTabController(
    length: 3,
    child: Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              indicatorColor: black,
              indicatorWeight: 3,
              labelColor: black,
              unselectedLabelColor: Colors.black54,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              tabs: [
                Tab(text: 'Friend'),
                Tab(text: 'Message'),
                Tab(text: 'Friend Request'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _socialDesignSection(
                  title: 'Friends',
                  subtitle: 'Your friends will appear here',
                  icon: Icons.people_rounded,
                  pink: pink,
                ),
                _socialDesignSection(
                  title: 'Messages',
                  subtitle: 'Your conversations will appear here',
                  icon: Icons.chat_bubble_rounded,
                  pink: pink,
                ),
                _socialDesignSection(
                  title: 'Friend Requests',
                  subtitle: 'Incoming requests will appear here',
                  icon: Icons.person_add_alt_1_rounded,
                  pink: pink,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _socialDesignSection({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color pink,
}) {
  return Container(
    color: const Color(0xFFEAF8FF),
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: const Color(0xFF09070B),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: pink, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF09070B),
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
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
        Icon(
          icon,
          size: 64,
          color: const Color(0xFFFFD700),
        ),
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

   Widget _buildRoomsTab() {
  const gold = Color(0xFFFFD700);
  const pink = Color(0xFFFF4FA3);
  const panel = Color(0xFF21101F);
  const purple = Color(0xFF392047);

  const filters = ['All Room', 'Popular Room', 'My Room'];

  const myRoomFilters = [
    'Recent Join',
    'Join Room',
    'Following Room',
    'Friends',
  ];

  final rooms = [
    {'name': 'Hamza Room', 'uid': '123456', 'members': 5},
    {'name': 'Ali Room', 'uid': '234567', 'members': 8},
    {'name': 'Friends Room', 'uid': '345678', 'members': 3},
    {'name': 'Party Room', 'uid': '456789', 'members': 12},
    {'name': 'Music Room', 'uid': '567890', 'members': 6},
    {'name': 'Fun Room', 'uid': '678901', 'members': 4},
    {'name': 'Chill Room', 'uid': '789012', 'members': 7},
    {'name': 'Vibe Room', 'uid': '890123', 'members': 9},
  ];


  final searchQuery = _roomSearchQuery.trim().toLowerCase();

  final filteredRooms = rooms.where((room) {
    final roomName = room['name'].toString().toLowerCase();
    final roomUid = room['uid'].toString();

    return roomName.contains(searchQuery) ||
        roomUid.contains(searchQuery);
  }).toList(); 


Widget buildUserSearchResult() {
  final query = _roomSearchQuery.trim();

  if (!RegExp(r'^\d{6,10}$').hasMatch(query)) {
    return const SizedBox.shrink();
  }

  return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance
        .collection('users')
        .where('userId', isEqualTo: query)
        .limit(1)
        .get(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'User search failed. Please try again.',
            style: TextStyle(color: Colors.white70),
          ),
        );
      }

      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'No user found with this UID.',
            style: TextStyle(color: Colors.white70),
          ),
        );
      }

      final userData = snapshot.data!.docs.first.data();
      final name = (userData['name'] ?? 'PartyNova User').toString();
      final uid = (userData['userId'] ?? '').toString();
      final photoBase64 = (userData['photoBase64'] ?? '').toString();
      final photoBytes = getCachedProfilePhoto(photoBase64);

      return Container(
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pink, width: 1.2),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: purple,
              backgroundImage:
                  photoBytes != null ? MemoryImage(photoBytes) : null,
              child: photoBytes == null
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 30,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'UID: $uid',
                    style: const TextStyle(
                      color: Color(0xFFFFB9DD),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}




     
  Widget buildTopFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF59304F),
            width: 1.2,
          ),
        ),
        child: Row(
          children: List.generate(filters.length, (index) {
            final selected = _selectedRoomFilter == index;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedRoomFilter = index;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? pink.withOpacity(0.20)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? pink : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      filters[index],
                      style: TextStyle(
                        color: selected ? pink : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget buildMyRoomContent() {
    final titles = [
      'Recent Join',
      'Join Room',
      'Following Room',
      'Friends',
    ];

    final descriptions = [
      'Your recently visited rooms will appear here.',
      'Rooms you have joined will appear here.',
      'Rooms you follow will appear here.',
      'See which rooms your friends are in.',
    ];

    final icons = [
      Icons.history_rounded,
      Icons.meeting_room_rounded,
      Icons.favorite_rounded,
      Icons.people_alt_rounded,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Create Room box
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 20),
          child: Container(
            width: double.infinity,
            height: 112,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF54244F),
                  Color(0xFF21101F),
                  Color(0xFF392047),
                ],
              ),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: gold,
                width: 1.5,
              ),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_rounded,
                  color: gold,
                  size: 35,
                ),
                SizedBox(height: 7),
                Text(
                  'CREATE ROOM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        // My Room heading
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'MY ROOM',
            style: TextStyle(
              color: gold,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Four options in one box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF59304F),
                width: 1.2,
              ),
            ),
            child: Row(
              children: List.generate(myRoomFilters.length, (index) {
                final selected = _selectedMyRoomFilter == index;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMyRoomFilter = index;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      constraints: const BoxConstraints(
                        minHeight: 68,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? pink.withOpacity(0.20)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? pink : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[index],
                            color: selected ? pink : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              myRoomFilters[index],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    selected ? pink : Colors.white70,
                                fontSize: 10,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
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

        const SizedBox(height: 24),

        // Selected option content placeholder
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Column(
              children: [
                Icon(
                  icons[_selectedMyRoomFilter],
                  size: 48,
                  color: pink.withOpacity(0.85),
                ),
                const SizedBox(height: 12),
                Text(
                  titles[_selectedMyRoomFilter],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  descriptions[_selectedMyRoomFilter],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  
   Widget buildRoomCards() {
    return Expanded(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
        itemCount: filteredRooms.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 18,
          childAspectRatio: 0.76,
        ),
        itemBuilder: (context, index) {
          final room = filteredRooms[index];

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PartyRoomScreen(
                    roomName: room['name'].toString(),
                    roomUid: room['uid'].toString(),
                  ),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF59304F),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.none,
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF54244F),
                                  Color(0xFF21101F),
                                  Color(0xFF392047),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.groups_rounded,
                                size: 66,
                                color: Color(0xFFFFB9DD),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 9,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: pink,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.people_alt_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${room['members']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, 5),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      padding: const EdgeInsets.fromLTRB(5, 9, 5, 10),
                      decoration: BoxDecoration(
                        color: purple,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: pink,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            room['name'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'UID: ${room['uid']}',
                            style: const TextStyle(
                              color: Color(0xFFFFB9DD),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  return Container(
    color: partyBlack,
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          // Search disappears only on My Room
          if (_selectedRoomFilter != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: pink,
                    width: 1.3,
                  ),
                ),
                child: TextField(
  controller: _roomSearchController,
  readOnly: true,
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PartyNovaSearchPage(),
      ),
    );
  },
  style: const TextStyle(
    color: Colors.white,
    fontSize: 14,
  ),
  cursorColor: pink,
  decoration: const InputDecoration(
    hintText: 'Search UID and Room',
    hintStyle: TextStyle(
      color: Colors.white60,
      fontSize: 14,
    ),
    prefixIcon: Icon(
      Icons.search_rounded,
      color: gold,
      size: 25,
    ),
    border: InputBorder.none,
    contentPadding: EdgeInsets.symmetric(vertical: 14),
  ),
),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  cursorColor: pink,
                  decoration: InputDecoration(
                    hintText: 'Search UID and Room',
                    hintStyle: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: gold,
                      size: 25,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          
          buildUserSearchResult(),
          buildTopFilters(),

          if (_selectedRoomFilter == 2)
            Expanded(
              child: SingleChildScrollView(
                child: buildMyRoomContent(),
              ),
            )
          else ...[
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ROOMS',
                  style: TextStyle(
                    color: gold,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            buildRoomCards(),
          ],
        ],
      ),
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
                child: Stack(
  alignment: Alignment.center,
  children: [
    Builder(
      builder: (context) {
        final photoBase64 =
            (data['photoBase64'] ?? '').toString();

        final photoBytes = getCachedProfilePhoto(photoBase64);

        if (photoBytes == null) {
          return const SizedBox(
            width: 112,
            height: 112,
            child: Icon(
              Icons.person_rounded,
              size: 64,
              color: Colors.white,
            ),
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
              return const SizedBox(
                width: 112,
                height: 112,
                child: Icon(
                  Icons.person_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              );
            },
          ),
        );
      },
    ),

    if ((data['profileFrameAsset'] ?? '').toString().isNotEmpty)
      Positioned.fill(
        child: Image.asset(
          data['profileFrameAsset'].toString(),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        ),
      ),
  ],
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
  title: 'PVIP',
  subtitle: 'PVIP levels and effects',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PvipPage(),
      ),
    );
  },
),

            _editOption(
  icon: Icons.workspace_premium_rounded,
  title: 'CROWN',
  subtitle: 'Royal crown collection',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CrownGalleryPage(),
      ),
    );
  },
),

            _editOption(
  icon: Icons.sports_esports_rounded,
  title: 'Game Badge',
  subtitle: 'Your gaming badge collection',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GameBadgeGalleryPage(),
      ),
    );
  },
),

            _editOption(
  icon: Icons.diamond_rounded,
  title: 'Money Badge',
  subtitle: 'Your money badge collection',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MoneyBadgeGalleryPage(),
      ),
    );
  },
),

            _editOption(
              icon: Icons.card_giftcard_rounded,
              title: 'Gift Badge',
              subtitle: 'Your gift badge collection',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GiftBadgeGalleryPage(),
                  ),
                );
              },
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
  State<ThemesGalleryPage> createState() => _ThemesGalleryPageState();
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



class PvipPage extends StatefulWidget {
  const PvipPage({super.key});

  @override
  State<PvipPage> createState() => _PvipPageState();
}

class _PvipPageState extends State<PvipPage> {
  static const Color _background = Color(0xFF050913);
  static const Color _panel = Color(0xFF0C1424);
  static const Color _gold = Color(0xFFFFC857);

  int _selectedLevel = 1;

  final Set<String> _selectedOptions = {};

  static const List<Color> _levelColors = [
    Color(0xFFFFC857),
    Color(0xFF20A7FF),
    Color(0xFF16E59A),
    Color(0xFFB56BFF),
    Color(0xFFFF438A),
    Color(0xFF20D9E8),
    Color(0xFFFF8A24),
  ];

  static const List<Map<String, dynamic>> _baseOptions = [
    {
      'name': 'Special Frame',
      'icon': Icons.crop_free_rounded,
    },
    {
      'name': 'Special Theme',
      'icon': Icons.palette_rounded,
    },
    {
      'name': 'Ornaments',
      'icon': Icons.diamond_rounded,
    },
    {
      'name': 'Special Entry',
      'icon': Icons.flash_on_rounded,
    },
    {
      'name': 'Name Colour',
      'icon': Icons.format_color_text_rounded,
    },
    {
      'name': 'Special Badge',
      'icon': Icons.workspace_premium_rounded,
    },
    {
      'name': 'Mic Glow',
      'icon': Icons.mic_rounded,
    },
  ];

  static const List<Map<String, dynamic>> _extraOptions = [
    {
      'name': 'Name Shine',
      'icon': Icons.auto_awesome_rounded,
    },
    {
      'name': 'Chat Colour',
      'icon': Icons.chat_bubble_rounded,
    },
    {
      'name': 'Profile Aura',
      'icon': Icons.blur_on_rounded,
    },
    {
      'name': 'Royal Crown',
      'icon': Icons.emoji_events_rounded,
    },
    {
      'name': 'VIP Halo',
      'icon': Icons.flare_rounded,
    },
    {
      'name': 'Legend Effect',
      'icon': Icons.stars_rounded,
    },
  ];

  Color get _currentColor => _levelColors[_selectedLevel - 1];

  List<Map<String, dynamic>> get _currentOptions {
    final count = _selectedLevel - 1;

    return [
      ..._baseOptions,
      ..._extraOptions.take(count),
    ];
  }

  String _levelTitle(int level) {
    const titles = [
      'STARTER',
      'BRONZE',
      'SILVER',
      'GOLD',
      'PLATINUM',
      'DIAMOND',
      'ROYAL LEGEND',
    ];

    return titles[level - 1];
  }

  @override
  Widget build(BuildContext context) {
    final color = _currentColor;
    final options = _currentOptions;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _gold,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              color: _gold,
              size: 23,
            ),
            SizedBox(width: 8),
            Text(
              'PLAYVIBE PVIP',
              style: TextStyle(
                color: _gold,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 17,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  children: [
                    const SizedBox(height: 12),

                    // Main PVIP badge
                    SizedBox(
                      width: 240,
                      height: 218,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 195,
                            height: 195,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  color.withOpacity(0.25),
                                  color.withOpacity(0.08),
                                  _background,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.20),
                                  blurRadius: 45,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 158,
                            height: 158,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withOpacity(0.75),
                                  _background,
                                  color.withOpacity(0.35),
                                ],
                              ),
                              border: Border.all(
                                color: color,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.40),
                                  blurRadius: 22,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 135,
                            height: 135,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _background,
                              border: Border.all(
                                color: color.withOpacity(0.85),
                                width: 2,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 20,
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              color: color,
                              size: 44,
                              shadows: [
                                Shadow(
                                  color: color.withOpacity(0.8),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 79,
                            child: Column(
                              children: [
                                Text(
                                  'PVIP',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                Text(
                                  '$_selectedLevel',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 43,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 4,
                            child: Icon(
                              Icons.star_rounded,
                              color: color,
                              size: 25,
                            ),
                          ),
                          Positioned(
                            bottom: 13,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _background,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: color,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                _levelTitle(_selectedLevel),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Horizontal level selector
                    SizedBox(
                      height: 83,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        itemCount: 7,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 9),
                        itemBuilder: (context, index) {
                          final level = index + 1;
                          final levelColor = _levelColors[index];
                          final isSelected =
                              level == _selectedLevel;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedLevel = level;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(
                                milliseconds: 200,
                              ),
                              width: 70,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? levelColor.withOpacity(0.13)
                                    : _panel,
                                borderRadius:
                                    BorderRadius.circular(15),
                                border: Border.all(
                                  color: isSelected
                                      ? levelColor
                                      : levelColor.withOpacity(0.45),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: levelColor
                                              .withOpacity(0.25),
                                          blurRadius: 14,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.workspace_premium_rounded,
                                    color: levelColor,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'PVIP $level',
                                    style: TextStyle(
                                      color: levelColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Selected level options heading
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 23,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'PVIP $_selectedLevel OPTIONS',
                              style: TextStyle(
                                color: color,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.diamond_rounded,
                            color: color,
                            size: 21,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 13),

                    // Three options per row
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        itemCount: options.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 9,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.94,
                        ),
                        itemBuilder: (context, index) {
                          final option = options[index];
                          final name = option['name'] as String;
                          final icon = option['icon'] as IconData;
                          final optionKey =
                              '$_selectedLevel-$name';
                          final isSelected =
                              _selectedOptions.contains(optionKey);

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedOptions.remove(optionKey);
                                } else {
                                  _selectedOptions.add(optionKey);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(
                                milliseconds: 180,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.14)
                                    : _panel,
                                borderRadius:
                                    BorderRadius.circular(13),
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : color.withOpacity(0.42),
                                  width: isSelected ? 1.8 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(
                                      isSelected ? 0.19 : 0.06,
                                    ),
                                    blurRadius: isSelected ? 13 : 6,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    icon,
                                    color: color,
                                    size: 31,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Level footer
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: color.withOpacity(0.75),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              color: color,
                              size: 25,
                            ),
                          ),
                          Text(
                            'PVIP $_selectedLevel',
                            style: TextStyle(
                              color: color,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              color: color,
                              size: 25,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: color.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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



class CrownGalleryPage extends StatefulWidget {
  const CrownGalleryPage({super.key});

  @override
  State<CrownGalleryPage> createState() => _CrownGalleryPageState();
}

class _CrownGalleryPageState extends State<CrownGalleryPage> {
  static const Color darkBlue = Color(0xFF071426);
  static const Color boxBlue = Color(0xFF102746);
  static const Color gold = Color(0xFFFFC857);

  int selectedLevel = 0;
  int previewLevel = 0;

  final List<Map<String, dynamic>> crowns = [
    {
      'name': 'Bronze Crown',
      'metal': const Color(0xFFCD8B48),
      'dark': const Color(0xFF633817),
      'gem': const Color(0xFFFFD28A),
      'glow': const Color(0xFFCD8B48),
    },
    {
      'name': 'Silver Crown',
      'metal': const Color(0xFFE0E8F2),
      'dark': const Color(0xFF65788F),
      'gem': const Color(0xFF9FEAFF),
      'glow': const Color(0xFFB9D9F5),
    },
    {
      'name': 'Golden Crown',
      'metal': const Color(0xFFFFD65C),
      'dark': const Color(0xFF85570B),
      'gem': const Color(0xFFFFF2B0),
      'glow': const Color(0xFFFFD65C),
    },
    {
      'name': 'Purple Royal Crown',
      'metal': const Color(0xFFD6A5FF),
      'dark': const Color(0xFF54217D),
      'gem': const Color(0xFFFFC6F5),
      'glow': const Color(0xFFB56BFF),
    },
    {
      'name': 'Diamond Crown',
      'metal': const Color(0xFF8BEAFF),
      'dark': const Color(0xFF15547A),
      'gem': const Color(0xFFFFFFFF),
      'glow': const Color(0xFF55DFFF),
    },
    {
      'name': 'Flame Crown',
      'metal': const Color(0xFFFFA45E),
      'dark': const Color(0xFF7D2518),
      'gem': const Color(0xFFFFE16C),
      'glow': const Color(0xFFFF633D),
    },
    {
      'name': 'Legendary Crown',
      'metal': const Color(0xFFFFE7A0),
      'dark': const Color(0xFF65460C),
      'gem': const Color(0xFFFF4E8A),
      'glow': const Color(0xFFFFD45C),
    },
  ];

  Map<String, dynamic> get currentCrown => crowns[previewLevel];

  @override
  Widget build(BuildContext context) {
    final crown = currentCrown;
    final Color metal = crown['metal'] as Color;
    final Color crownGlow = crown['glow'] as Color;

    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: gold,
          ),
        ),
        title: const Text(
          'CROWN COLLECTION',
          style: TextStyle(
            color: gold,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('ROYAL PREVIEW'),
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF132C49),
                      Color(0xFF09172A),
                      Color(0xFF102441),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: metal.withOpacity(0.75),
                    width: 1.4,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 150,
                      height: 135,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: crownGlow.withOpacity(0.06),
                        boxShadow: [
                          BoxShadow(
                            color: crownGlow.withOpacity(0.22),
                            blurRadius: 35,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: _CrownPainter(
                          metal: metal,
                          darkMetal: crown['dark'] as Color,
                          gem: crown['gem'] as Color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'CROWN ${previewLevel + 1}',
                      style: TextStyle(
                        color: metal,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      crown['name'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ROYAL EDITION',
                      style: TextStyle(
                        color: metal.withOpacity(0.85),
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _sectionLabel('CHOOSE YOUR CROWN'),
              const SizedBox(height: 12),

              SizedBox(
                height: 47,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: crowns.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final bool active = previewLevel == index;
                    final item = crowns[index];

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          previewLevel = index;
                          selectedLevel = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? gold : boxBlue,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: active
                                ? gold
                                : (item['metal'] as Color)
                                    .withOpacity(0.6),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          'CROWN ${index + 1}',
                          style: TextStyle(
                            color: active ? darkBlue : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 22),
              _sectionLabel('PREVIEW ON YOUR PROFILE'),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: boxBlue,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: metal.withOpacity(0.55),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: metal,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: crownGlow.withOpacity(0.3),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF263A52),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 42,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profile DP Frame',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'CROWN ${previewLevel + 1} colour preview',
                            style: TextStyle(
                              color: metal,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Demo preview only',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: boxBlue,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: crownGlow.withOpacity(0.65),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: crownGlow.withOpacity(0.09),
                        border: Border.all(
                          color: crownGlow,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: crownGlow.withOpacity(0.3),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.mic_rounded,
                        size: 31,
                        color: crownGlow,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Room Mic Glow',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'CROWN ${previewLevel + 1} colour preview',
                            style: TextStyle(
                              color: crownGlow,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Room connection comes later',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      selectedLevel = previewLevel;
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'CROWN ${selectedLevel + 1} selected for demo only',
                        ),
                        backgroundColor: boxBlue,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: darkBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    'SELECT CROWN ${previewLevel + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'UI DEMO • FEATURES WILL BE CONNECTED LATER',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 17,
          decoration: BoxDecoration(
            color: gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: gold,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _CrownPainter extends CustomPainter {
  final Color metal;
  final Color darkMetal;
  final Color gem;

  _CrownPainter({
    required this.metal,
    required this.darkMetal,
    required this.gem,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 150;

    canvas.save();
    canvas.scale(scale);

    final crownPath = Path()
      ..moveTo(25, 45)
      ..lineTo(12, 18)
      ..lineTo(43, 35)
      ..lineTo(58, 8)
      ..lineTo(75, 32)
      ..lineTo(98, 7)
      ..lineTo(108, 35)
      ..lineTo(138, 18)
      ..lineTo(125, 45)
      ..lineTo(116, 94)
      ..quadraticBezierTo(75, 106, 34, 94)
      ..close();

    final metalPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.85),
          metal,
          darkMetal,
          metal,
          Colors.white.withOpacity(0.55),
        ],
        stops: const [0, 0.22, 0.52, 0.78, 1],
      ).createShader(
        const Rect.fromLTWH(10, 5, 130, 105),
      );

    canvas.drawPath(crownPath, metalPaint);

    final outlinePaint = Paint()
      ..color = metal.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(crownPath, outlinePaint);

    final bandPath = Path()
      ..moveTo(34, 79)
      ..quadraticBezierTo(75, 91, 116, 79)
      ..lineTo(120, 95)
      ..quadraticBezierTo(75, 108, 30, 95)
      ..close();

    canvas.drawPath(
      bandPath,
      Paint()
        ..shader = LinearGradient(
          colors: [metal, darkMetal, metal],
        ).createShader(
          const Rect.fromLTWH(25, 78, 100, 30),
        ),
    );

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      const Offset(25, 45),
      const Offset(125, 45),
      linePaint,
    );

    final gemPaint = Paint()
  ..shader = RadialGradient(
    colors: [
      Colors.white,
      gem,
      darkMetal,
    ],
  ).createShader(
    Rect.fromCircle(
      center: const Offset(75, 60),
      radius: 12,
    ),
  );

    canvas.drawCircle(
      const Offset(75, 60),
      11,
      gemPaint,
    );

    final smallGemPaint = Paint()..color = gem;

    for (final point in const [
      Offset(44, 72),
      Offset(106, 72),
      Offset(58, 84),
      Offset(92, 84),
    ]) {
      canvas.drawCircle(point, 4, smallGemPaint);

      canvas.drawCircle(
        point.translate(-1, -1),
        1.4,
        Paint()..color = Colors.white.withOpacity(0.85),
      );
    }

    final sparklePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (final point in const [
      Offset(18, 35),
      Offset(132, 35),
      Offset(58, 19),
      Offset(99, 19),
    ]) {
      canvas.drawLine(
        Offset(point.dx - 4, point.dy),
        Offset(point.dx + 4, point.dy),
        sparklePaint,
      );

      canvas.drawLine(
        Offset(point.dx, point.dy - 4),
        Offset(point.dx, point.dy + 4),
        sparklePaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) {
    return oldDelegate.metal != metal ||
        oldDelegate.darkMetal != darkMetal ||
        oldDelegate.gem != gem;
  }
}



class GameBadgeGalleryPage extends StatefulWidget {
  const GameBadgeGalleryPage({super.key});

  @override
  State<GameBadgeGalleryPage> createState() =>
      _GameBadgeGalleryPageState();
}

class _GameBadgeGalleryPageState
    extends State<GameBadgeGalleryPage> {
  static const Color darkBlue = Color(0xFF071426);
  static const Color boxBlue = Color(0xFF102746);
  static const Color gold = Color(0xFFFFC857);

  int selectedBadge = 0;

  final List<Map<String, dynamic>> badges = [
    {
      'name': 'Bronze Champion',
      'requirement': '100,000 Tokens',
      'icon': Icons.emoji_events_rounded,
      'colors': [
        Color(0xFFFFD09A),
        Color(0xFFB87333),
        Color(0xFF613515),
      ],
      'symbol': 'I',
    },
    {
      'name': 'Silver Champion',
      'requirement': '300,000 Tokens',
      'icon': Icons.emoji_events_rounded,
      'colors': [
        Color(0xFFFFFFFF),
        Color(0xFFB8C5D6),
        Color(0xFF536579),
      ],
      'symbol': 'II',
    },
    {
      'name': 'Golden Champion',
      'requirement': '500,000 Tokens',
      'icon': Icons.emoji_events_rounded,
      'colors': [
        Color(0xFFFFFFB0),
        Color(0xFFFFC107),
        Color(0xFF9A5700),
      ],
      'symbol': 'III',
    },
    {
      'name': 'Star Champion',
      'requirement': '100 Stars',
      'icon': Icons.star_rounded,
      'colors': [
        Color(0xFFFFF6B0),
        Color(0xFFFFC857),
        Color(0xFFB76B00),
      ],
      'symbol': '100',
    },
    {
      'name': 'Super Star',
      'requirement': '500 Stars',
      'icon': Icons.stars_rounded,
      'colors': [
        Color(0xFFFFF4D0),
        Color(0xFFFFB300),
        Color(0xFF9C4300),
      ],
      'symbol': '500',
    },
    {
      'name': 'Diamond Star',
      'requirement': '800 Stars',
      'icon': Icons.diamond_rounded,
      'colors': [
        Color(0xFFE5FFFF),
        Color(0xFF51D8FF),
        Color(0xFF145A9E),
      ],
      'symbol': '800',
    },
    {
      'name': 'Legendary Star',
      'requirement': '1,000 Stars',
      'icon': Icons.auto_awesome_rounded,
      'colors': [
        Color(0xFFFFF8C8),
        Color(0xFFFFD54F),
        Color(0xFF8E44AD),
      ],
      'symbol': '1000',
    },
    {
      'name': 'Master Gamer',
      'requirement': 'Game Achievement',
      'icon': Icons.sports_esports_rounded,
      'colors': [
        Color(0xFFB9F6CA),
        Color(0xFF00A878),
        Color(0xFF064E45),
      ],
      'symbol': 'M',
    },
    {
      'name': 'Elite Champion',
      'requirement': 'Special Achievement',
      'icon': Icons.shield_rounded,
      'colors': [
        Color(0xFFFFE5A0),
        Color(0xFFDA9B22),
        Color(0xFF7B3216),
      ],
      'symbol': 'E',
    },
    {
      'name': 'Ultimate Legend',
      'requirement': 'Legendary Achievement',
      'icon': Icons.workspace_premium_rounded,
      'colors': [
        Color(0xFFFFFFFF),
        Color(0xFFFFC857),
        Color(0xFF7139A8),
      ],
      'symbol': '★',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final badge = badges[selectedBadge];
    final colors = badge['colors'] as List<Color>;

    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: gold,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'GAME BADGES',
          style: TextStyle(
            color: gold,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // TOP PREVIEW
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF18385B),
                    Color(0xFF0B192C),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: gold,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'BADGE PREVIEW',
                    style: TextStyle(
                      color: gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Selected badge artwork
                  _GameBadgeArtwork(
                    icon: badge['icon'] as IconData,
                    colors: colors,
                    symbol: badge['symbol'] as String,
                    size: 138,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    badge['name'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: darkBlue,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: gold,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      badge['requirement'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Select a badge below to preview it',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // COLLECTION HEADING
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: gold,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'BADGE COLLECTION',
                    style: TextStyle(
                      color: gold,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '10 BADGES',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // TWO LARGE BADGES PER ROW
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  20,
                ),
                itemCount: badges.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.66,
                ),
                itemBuilder: (context, index) {
                  final item = badges[index];
                  final itemColors =
                      item['colors'] as List<Color>;
                  final isSelected = selectedBadge == index;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(19),
                      onTap: () {
                        setState(() {
                          selectedBadge = index;
                        });
                      },
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF142D4B),
                              Color(0xFF09182B),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: isSelected
                                ? gold
                                : const Color(0xFF294360),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            8,
                            12,
                            8,
                            10,
                          ),
                          child: Column(
                            children: [
                              // Large badge artwork
                              Expanded(
                                child: Center(
                                  child: _GameBadgeArtwork(
                                    icon: item['icon'] as IconData,
                                    colors: itemColors,
                                    symbol: item['symbol'] as String,
                                    size: 140,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              Text(
                                item['name'] as String,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 9),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: darkBlue,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? gold
                                        : const Color(0xFF294360),
                                  ),
                                ),
                                child: Text(
                                  item['requirement'] as String,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 6),

                              if (isSelected)
                                const Text(
                                  'PREVIEWING',
                                  style: TextStyle(
                                    color: gold,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                )
                              else
                                const SizedBox(height: 11),
                            ],
                          ),
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

class _GameBadgeArtwork extends StatelessWidget {
  const _GameBadgeArtwork({
    required this.icon,
    required this.colors,
    required this.symbol,
    required this.size,
  });

  final IconData icon;
  final List<Color> colors;
  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool isStar =
        icon == Icons.star_rounded ||
        icon == Icons.stars_rounded ||
        icon == Icons.auto_awesome_rounded;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer metallic body
          Container(
            width: size * 0.94,
            height: size * 0.94,
            decoration: BoxDecoration(
              shape: isStar
                  ? BoxShape.circle
                  : BoxShape.rectangle,
              borderRadius: isStar
                  ? null
                  : BorderRadius.circular(size * 0.24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              border: Border.all(
                color: const Color(0xFFFFF0B0),
                width: size * 0.025,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors[1].withValues(alpha: 0.38),
                  blurRadius: size * 0.12,
                  spreadRadius: size * 0.01,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: size * 0.08,
                  offset: Offset(0, size * 0.04),
                ),
              ],
            ),
          ),

          // Inner jewel surface
          Container(
            width: size * 0.78,
            height: size * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.6),
                radius: 1.2,
                colors: [
                  colors[0],
                  colors[1],
                  colors[2],
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.8),
                width: size * 0.012,
              ),
            ),
          ),

          // Top-left shine
          Positioned(
            top: size * 0.12,
            left: size * 0.15,
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white.withValues(alpha: 0.95),
              size: size * 0.12,
            ),
          ),

          // Top-right shine
          Positioned(
            top: size * 0.12,
            right: size * 0.15,
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white.withValues(alpha: 0.75),
              size: size * 0.09,
            ),
          ),

          // Main badge symbol
          Icon(
            icon,
            size: size * 0.47,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: size * 0.06,
                offset: Offset(0, size * 0.025),
              ),
            ],
          ),

          // Badge level plate
          Positioned(
            bottom: size * 0.11,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.09,
                vertical: size * 0.025,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF071426)
                    .withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(size * 0.08),
                border: Border.all(
                  color: const Color(0xFFFFD56A),
                  width: size * 0.009,
                ),
              ),
              child: Text(
                symbol,
                style: TextStyle(
                  color: const Color(0xFFFFD56A),
                  fontSize: size * 0.085,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MoneyBadgeGalleryPage extends StatelessWidget {
  const MoneyBadgeGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RoyalBadgeGallery(
      isGift: false,
    );
  }
}

class GiftBadgeGalleryPage extends StatelessWidget {
  const GiftBadgeGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RoyalBadgeGallery(
      isGift: true,
    );
  }
}

class _RoyalBadgeGallery extends StatefulWidget {
  const _RoyalBadgeGallery({
    required this.isGift,
    super.key,
  });

  final bool isGift;

  @override
  State<_RoyalBadgeGallery> createState() =>
      _RoyalBadgeGalleryState();
}

class _RoyalBadgeGalleryState
    extends State<_RoyalBadgeGallery> {
  static const Color darkBlue = Color(0xFF071426);
  static const Color panelBlue = Color(0xFF102746);
  static const Color gold = Color(0xFFFFC857);

  int selectedIndex = 0;

  static const List<int> points = [
    100000,
    200000,
    300000,
    400000,
    500000,
    600000,
    700000,
    800000,
    900000,
    1000000,
  ];

  static const List<String> names = [
    'Bronze Royal',
    'Silver Royal',
    'Golden Royal',
    'Platinum Royal',
    'Ruby Royal',
    'Sapphire Royal',
    'Diamond Royal',
    'Royal Emperor',
    'Royal King',
    'Ultimate Legend',
  ];

  static const List<List<Color>> palettes = [
    [
      Color(0xFFFFD2A0),
      Color(0xFFB87333),
      Color(0xFF613515),
    ],
    [
      Color(0xFFFFFFFF),
      Color(0xFFBFCBDA),
      Color(0xFF526477),
    ],
    [
      Color(0xFFFFFFC2),
      Color(0xFFFFC107),
      Color(0xFF925000),
    ],
    [
      Color(0xFFE9FFFF),
      Color(0xFF9DB7D5),
      Color(0xFF425E85),
    ],
    [
      Color(0xFFFFE0E8),
      Color(0xFFE34267),
      Color(0xFF74152F),
    ],
    [
      Color(0xFFD9FFFF),
      Color(0xFF29C7E8),
      Color(0xFF124E91),
    ],
    [
      Color(0xFFFFFFFF),
      Color(0xFF73E8FF),
      Color(0xFF4536B5),
    ],
    [
      Color(0xFFFFF3B0),
      Color(0xFFFFB52E),
      Color(0xFF913F15),
    ],
    [
      Color(0xFFFFFFFF),
      Color(0xFFFFD45A),
      Color(0xFF7A3FBD),
    ],
    [
      Color(0xFFFFFFFF),
      Color(0xFFFFD45A),
      Color(0xFF9B42E8),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final String pageTitle =
        widget.isGift ? 'GIFT BADGES' : 'MONEY BADGES';

    final String selectedName =
        names[selectedIndex];

    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: gold,
        elevation: 0,
        centerTitle: true,
        title: Text(
          pageTitle,
          style: const TextStyle(
            color: gold,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // LARGE PREVIEW AT THE TOP
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                14,
                4,
                14,
                14,
              ),
              padding: const EdgeInsets.fromLTRB(
                12,
                14,
                12,
                16,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A3A60),
                    Color(0xFF0B172A),
                    Color(0xFF132A46),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: gold,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gold.withValues(alpha: 0.10),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    widget.isGift
                        ? 'GIFT BADGE COLLECTION'
                        : 'RECHARGE BADGE COLLECTION',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Royal metallic preview
                  SizedBox(
                    width: 188,
                    height: 188,
                    child: CustomPaint(
                      painter: _RoyalBadgePainter(
                        colors: palettes[selectedIndex],
                        level: selectedIndex,
                        isGift: widget.isGift,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    selectedName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: darkBlue,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: gold,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      points[selectedIndex].toString(),
                      style: const TextStyle(
                        color: gold,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Tap any badge below to preview',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // COLLECTION HEADER
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                12,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isGift
                        ? Icons.card_giftcard_rounded
                        : Icons.diamond_rounded,
                    color: gold,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ROYAL COLLECTION',
                      style: TextStyle(
                        color: gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                  const Text(
                    '10 BADGES',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // TWO LARGE BADGES PER ROW
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  20,
                ),
                itemCount: points.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
                itemBuilder: (context, index) {
                  final bool selected =
                      selectedIndex == index;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          selectedIndex = index;
                        });
                      },
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF173252),
                              Color(0xFF091629),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? gold
                                : const Color(0xFF304660),
                            width: selected ? 2 : 1,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: gold.withValues(
                                      alpha: 0.12,
                                    ),
                                    blurRadius: 12,
                                  ),
                                ]
                              : [],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            8,
                            12,
                            8,
                            10,
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: SizedBox(
                                    width: 145,
                                    height: 145,
                                    child: CustomPaint(
                                      painter: _RoyalBadgePainter(
                                        colors: palettes[index],
                                        level: index,
                                        isGift: widget.isGift,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              Text(
                                names[index],
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),

                              const SizedBox(height: 9),

                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 9,
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: darkBlue,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? gold
                                        : const Color(0xFF304660),
                                  ),
                                ),
                                child: Text(
                                  points[index].toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 7),

                              Text(
                                selected
                                    ? 'PREVIEWING'
                                    : 'VIEW BADGE',
                                style: TextStyle(
                                  color: selected
                                      ? gold
                                      : Colors.white54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
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

class _RoyalBadgePainter extends CustomPainter {
  _RoyalBadgePainter({
    required this.colors,
    required this.level,
    required this.isGift,
  });

  final List<Color> colors;
  final int level;
  final bool isGift;

  static const Color gold = Color(0xFFFFD780);
  static const Color dark = Color(0xFF071426);

  @override
  void paint(Canvas canvas, Size size) {
    final double unit =
        size.shortestSide / 180;

    canvas.save();

    canvas.translate(
      (size.width - 180 * unit) / 2,
      (size.height - 180 * unit) / 2,
    );

    canvas.scale(unit);

    final Rect bounds = const Rect.fromLTWH(
      8,
      8,
      164,
      164,
    );

    // Outer shadow
    canvas.drawOval(
      bounds.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          8,
        ),
    );

    // Outer metallic ring
    canvas.drawOval(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFFD76C),
            Color(0xFF9D570C),
            Color(0xFFFFF0B0),
          ],
        ).createShader(bounds),
    );

    // Dark inset ring
    canvas.drawOval(
      const Rect.fromLTWH(15, 15, 150, 150),
      Paint()..color = dark,
    );

    // Jewel ring
    canvas.drawOval(
      const Rect.fromLTWH(20, 20, 140, 140),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(bounds),
    );

    // Main badge face
    canvas.drawOval(
      const Rect.fromLTWH(27, 27, 126, 126),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.6),
          radius: 1.2,
          colors: [
            colors[0],
            colors[1],
            colors[2],
          ],
        ).createShader(bounds),
    );

    // Inner metallic border
    canvas.drawOval(
      const Rect.fromLTWH(31, 31, 118, 118),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = gold.withValues(alpha: 0.9),
    );

    // Royal crown silhouette
    final Path crown = Path()
      ..moveTo(49, 69)
      ..lineTo(40, 47)
      ..lineTo(61, 59)
      ..lineTo(76, 34)
      ..lineTo(91, 59)
      ..lineTo(112, 47)
      ..lineTo(103, 69)
      ..close();

    canvas.drawPath(
      crown,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFE0),
            Color(0xFFFFD24D),
            Color(0xFF9E5700),
          ],
        ).createShader(
          const Rect.fromLTWH(40, 34, 72, 35),
        ),
    );

    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFF2B3),
    );

    // Crown base
    final Rect crownBase = const Rect.fromLTWH(
      48,
      66,
      56,
      9,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        crownBase,
        const Radius.circular(2),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFFF3B0),
            Color(0xFFFFBF32),
            Color(0xFF9B5200),
          ],
        ).createShader(crownBase),
    );

    // Crown jewels
    for (final Offset gem in const [
      Offset(50, 47),
      Offset(76, 35),
      Offset(102, 47),
    ]) {
      canvas.drawCircle(
        gem,
        3.5,
        Paint()
          ..shader = const RadialGradient(
            colors: [
              Colors.white,
              Color(0xFF56E8FF),
              Color(0xFF1350A0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: gem,
              radius: 3.5,
            ),
          ),
      );
    }

    // Category symbol
    final IconData symbol = isGift
        ? Icons.card_giftcard_rounded
        : Icons.diamond_rounded;

    final TextPainter iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(symbol.codePoint),
        style: TextStyle(
          fontFamily: symbol.fontFamily,
          package: symbol.fontPackage,
          fontSize: 31,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    iconPainter.layout();

    iconPainter.paint(
      canvas,
      Offset(
        90 - iconPainter.width / 2,
        79,
      ),
    );

    // Number plate
    final Rect plate = const Rect.fromLTWH(
      34,
      116,
      112,
      25,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        plate,
        const Radius.circular(7),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF253A51),
            Color(0xFF050D18),
          ],
        ).createShader(plate),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        plate,
        const Radius.circular(7),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = gold,
    );

    // Only the number is written on the badge.
    final String number = (level + 1) == 10
        ? '1000000'
        : '${(level + 1) * 100000}';

    final TextPainter numberPainter = TextPainter(
      text: TextSpan(
        text: number,
        style: const TextStyle(
          color: Color(0xFFFFD780),
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    numberPainter.layout(maxWidth: 106);

    numberPainter.paint(
      canvas,
      Offset(
        90 - numberPainter.width / 2,
        121.5,
      ),
    );

    // Decorative side studs
    for (int i = 0; i < 8; i++) {
      final double angle =
          (i * 3.141592653589793) / 4;

      final Offset point = Offset(
        90 + 72 * _cos(angle),
        90 + 72 * _sin(angle),
      );

      canvas.drawCircle(
        point,
        2.3,
        Paint()..color = gold,
      );

      canvas.drawCircle(
        point,
        1,
        Paint()..color = Colors.white,
      );
    }

    // Higher levels get extra diamond-shaped decorations.
    if (level >= 4) {
      final Path jewel = Path()
        ..moveTo(90, 11)
        ..lineTo(96, 19)
        ..lineTo(90, 27)
        ..lineTo(84, 19)
        ..close();

      canvas.drawPath(
        jewel,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Colors.white,
              Color(0xFF65E7FF),
              Color(0xFF2254B7),
            ],
          ).createShader(
            const Rect.fromLTWH(84, 11, 12, 16),
          ),
      );
    }

    // Extra royal ornament for the top levels.
    if (level >= 7) {
      final Path ornament = Path()
        ..moveTo(90, 1)
        ..lineTo(94, 8)
        ..lineTo(102, 9)
        ..lineTo(96, 14)
        ..lineTo(98, 21)
        ..lineTo(90, 17)
        ..lineTo(82, 21)
        ..lineTo(84, 14)
        ..lineTo(78, 9)
        ..lineTo(86, 8)
        ..close();

      canvas.drawPath(
        ornament,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Colors.white,
              Color(0xFFFFD65A),
              Color(0xFFB56C00),
            ],
          ).createShader(
            const Rect.fromLTWH(78, 1, 24, 20),
          ),
      );
    }

    canvas.restore();
  }

  double _cos(double value) {
    // Small angle helper for the decorative studs.
    return _trig(value, true);
  }

  double _sin(double value) {
    return _trig(value, false);
  }

  double _trig(double value, bool cosine) {
    return cosine
        ? _cosValue(value)
        : _sinValue(value);
  }

  double _cosValue(double value) {
    // Convert angle to radians for the circular ornament.
    return _TaylorTrig.cos(value);
  }

  double _sinValue(double value) {
    return _TaylorTrig.sin(value);
  }

  @override
  bool shouldRepaint(
    covariant _RoyalBadgePainter oldDelegate,
  ) {
    return oldDelegate.level != level ||
        oldDelegate.isGift != isGift ||
        oldDelegate.colors != colors;
  }
}

class _TaylorTrig {
  static double sin(double x) {
    double result = 0;
    double term = x;

    for (int n = 0; n < 8; n++) {
      result += term;
      term *=
          -(x * x) / ((2 * n + 2) * (2 * n + 3));
    }

    return result;
  }

  static double cos(double x) {
    double result = 0;
    double term = 1;

    for (int n = 0; n < 8; n++) {
      result += term;
      term *=
          -(x * x) / ((2 * n + 1) * (2 * n + 2));
    }

    return result;
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

class PartyRoomScreen extends StatefulWidget {
  final String roomName;
  final String roomUid;

  const PartyRoomScreen({
    super.key,
    required this.roomName,
    required this.roomUid,
  });

  @override
  State<PartyRoomScreen> createState() => _PartyRoomScreenState();
}

class _PartyRoomScreenState extends State<PartyRoomScreen> {
  static const Color darkBlue = Color(0xFF100810);
  static const Color gold = Color(0xFFFFD700);
  static const Color pink = Color(0xFFFF4FA3);
  static const Color panelBlue = Color(0xFF24101F);

  final TextEditingController _messageController =
      TextEditingController();

  final FocusNode _messageFocusNode = FocusNode();

  bool _messageOpen = false;

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _openMessageBoard() {
    setState(() {
      _messageOpen = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _messageOpen) {
        _messageFocusNode.requestFocus();
      }
    });
  }

  void _closeMessageBoard() {
    _messageFocusNode.unfocus();

    setState(() {
      _messageOpen = false;
    });
  }

  // Empty seat: 65 x 65 pixels.
  Widget _buildSeat(int number) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.22),
                    blurRadius: 5,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.chair_rounded,
                  color: pink,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'NO. $number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Five seats in each row.
  Widget _buildSeatRow(int firstNumber) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        5,
        (index) => _buildSeat(firstNumber + index),
      ),
    );
  }

  // Bottom action icons.
  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required double size,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 46,
      ),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        color: color,
        size: size,
      ),
    );
  }

  // SMS opens a large multiline typing board.
  // When open, all other bottom icons are hidden.
  Widget _buildBottomBar() {
    final keyboardOpen =
        MediaQuery.of(context).viewInsets.bottom > 0;

    if (_messageOpen) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          10,
          10,
          10,
          keyboardOpen ? 5 : 10,
        ),
        decoration: const BoxDecoration(
          color: panelBlue,
          border: Border(
            top: BorderSide(
              color: pink,
              width: 1.5,
            ),
            bottom: BorderSide(
              color: pink,
              width: 1.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sms_rounded,
                  color: pink,
                  size: 32,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Message',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _closeMessageBoard,
                  tooltip: 'Close message board',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: pink,
                    size: 30,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Large multiline text area.
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: 100,
                maxHeight: 180,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: darkBlue,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: pink,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                ),
                cursorColor: pink,
                decoration: const InputDecoration(
                  hintText: 'Write your message...',
                  hintStyle: TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Normal bottom row: SMS, Mic, Speaker, Emoji, Gift, More.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 8,
      ),
      decoration: const BoxDecoration(
        color: panelBlue,
        border: Border(
          top: BorderSide(
            color: pink,
            width: 1.5,
          ),
          bottom: BorderSide(
            color: pink,
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionIcon(
            icon: Icons.sms_rounded,
            color: pink,
            size: 32,
            tooltip: 'Open messages',
            onPressed: _openMessageBoard,
          ),
          _buildActionIcon(
            icon: Icons.mic_rounded,
            color: gold,
            size: 33,
            tooltip: 'Microphone',
            onPressed: () {},
          ),
          _buildActionIcon(
            icon: Icons.volume_up_rounded,
            color: Colors.white,
            size: 32,
            tooltip: 'Speaker',
            onPressed: () {},
          ),
          _buildActionIcon(
            icon: Icons.emoji_emotions_rounded,
            color: gold,
            size: 32,
            tooltip: 'Emoji',
            onPressed: () {},
          ),
          _buildActionIcon(
            icon: Icons.card_giftcard_rounded,
            color: pink,
            size: 33,
            tooltip: 'Gift',
            onPressed: () {},
          ),
          _buildActionIcon(
            icon: Icons.more_horiz_rounded,
            color: Colors.white,
            size: 34,
            tooltip: 'More',
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Room header.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 116,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: panelBlue,
                        border: Border.all(
                          color: pink,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          // Room DP placeholder.
                          Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              color: const Color(0xFF301426),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: pink,
                                width: 1.8,
                              ),
                            ),
                            child: const Icon(
                              Icons.groups_rounded,
                              color: gold,
                              size: 48,
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Room name and UID.
                          Expanded(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.roomName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  'UID: ${widget.roomUid}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),

                          // JOIN button.
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: darkBlue,
                              minimumSize: const Size(58, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'JOIN',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),

                  // Room options and leave buttons.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {},
                        tooltip: 'Room options',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 42,
                        ),
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                          size: 29,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Leave room',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 42,
                        ),
                        icon: const Icon(
                          Icons.power_settings_new_rounded,
                          color: gold,
                          size: 27,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Fifteen seats: three rows of five.
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 14, 5, 0),
              child: Column(
                children: [
                  _buildSeatRow(1),
                  const SizedBox(height: 13),
                  _buildSeatRow(6),
                  const SizedBox(height: 13),
                  _buildSeatRow(11),
                ],
              ),
            ),

            // Remaining room chat area.
            const Expanded(
              child: SizedBox.expand(),
            ),

            // Bottom controls or SMS typing board.
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }
}
  


class PartyNovaSearchPage extends StatefulWidget {
  const PartyNovaSearchPage({super.key});

  @override
  State<PartyNovaSearchPage> createState() =>
      _PartyNovaSearchPageState();
}

class _PartyNovaSearchPageState extends State<PartyNovaSearchPage> {
  static const Color darkBlue = Color(0xFF100810);
  static const Color gold = Color(0xFFFFD700);
  static const Color pink = Color(0xFFFF4FA3);
  static const Color panel = Color(0xFF24101F);
  static const Color purple = Color(0xFF703B91);

  final TextEditingController _searchController =
      TextEditingController();

  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSearchResult() {
    final query = _query.trim();

    if (query.isEmpty) {
      return const Center(
        child: Text(
          'Search by PartyNova UID',
          style: TextStyle(color: Colors.white70, fontSize: 15),
        ),
      );
    }

    if (!RegExp(r'^\d{6,10}$').hasMatch(query)) {
      return const Center(
        child: Text(
          'Enter a valid PartyNova UID.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(query),
      future: FirebaseFirestore.instance
          .collection('users')
          .where('userId', isEqualTo: query)
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Search failed. Please try again.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No user found with this UID.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final userData = snapshot.data!.docs.first.data();

        // Use PartyNova UID, never the Firebase document ID.
        final partyNovaUid = (userData['userId'] ?? '').toString();
        final name = (userData['name'] ?? 'PartyNova User').toString();
        final photoBase64 = (userData['photoBase64'] ?? '').toString();
        final photoBytes = getCachedProfilePhoto(photoBase64);

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pink, width: 1.4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: purple,
                backgroundImage:
                    photoBytes != null ? MemoryImage(photoBytes) : null,
                child: photoBytes == null
                    ? const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 32,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // PartyNova UID appears only inside this box.
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: darkBlue,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: gold, width: 1),
                      ),
                      child: Text(
                        'UID: $partyNovaUid',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFB9DD),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Friend request is not connected yet.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'Send Request',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: darkBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      appBar: AppBar(
        backgroundColor: panel,
        foregroundColor: gold,
        elevation: 0,
        title: const Text(
          'Search Users',
          style: TextStyle(
            color: gold,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Separate search box at the top.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pink, width: 1.3),
              ),
              child: TextField(
                controller: _searchController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
                cursorColor: pink,
                decoration: const InputDecoration(
                  hintText: 'Enter PartyNova UID',
                  hintStyle: TextStyle(color: Colors.white60),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: gold,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                ),
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
              ),
            ),
          ),
          Expanded(child: _buildSearchResult()),
        ],
      ),
    );
  }
}


                              
