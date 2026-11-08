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




// Keep multiple profile photos cached at the same time. A single-photo cache
// caused different users' avatars to replace one another during list rebuilds.
const int _maxCachedProfilePhotos = 64;
final Map<String, Uint8List> _profilePhotoBytesCache = {};
final Map<String, MemoryImage> _profilePhotoImageCache = {};

String _normalizedProfilePhotoData(String encoded) {
  var value = encoded.trim();
  if (value.isEmpty) return '';

  final comma = value.indexOf(',');
  if (value.startsWith('data:') && comma >= 0) {
    value = value.substring(comma + 1);
  }
  return value;
}

void _trimProfilePhotoCache() {
  while (_profilePhotoBytesCache.length > _maxCachedProfilePhotos) {
    final oldestKey = _profilePhotoBytesCache.keys.first;
    _profilePhotoBytesCache.remove(oldestKey);
    _profilePhotoImageCache.remove(oldestKey);
  }

  while (_profilePhotoImageCache.length > _maxCachedProfilePhotos) {
    _profilePhotoImageCache.remove(_profilePhotoImageCache.keys.first);
  }
}

Uint8List? getCachedProfilePhoto(String encoded) {
  final key = _normalizedProfilePhotoData(encoded);
  if (key.isEmpty) return null;

  final cached = _profilePhotoBytesCache.remove(key);
  if (cached != null) {
    _profilePhotoBytesCache[key] = cached;
    return cached;
  }

  try {
    final bytes = base64Decode(key);
    _profilePhotoBytesCache[key] = bytes;
    _trimProfilePhotoCache();
    return bytes;
  } catch (e) {
    debugPrint('Profile photo decode failed: $e');
    return null;
  }
}

ImageProvider? getCachedProfilePhotoImage(String encoded) {
  final key = _normalizedProfilePhotoData(encoded);
  if (key.isEmpty) return null;

  final cached = _profilePhotoImageCache.remove(key);
  if (cached != null) {
    _profilePhotoImageCache[key] = cached;
    return cached;
  }

  final bytes = getCachedProfilePhoto(key);
  if (bytes == null) return null;

  final image = MemoryImage(bytes);
  _profilePhotoImageCache[key] = image;
  _trimProfilePhotoCache();
  return image;
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

String resolvePartyNovaRole({
  String? email,
  String? userId,
  String? storedRole,
}) {
  final emailRole = partyNovaRoleForEmail(email);
  if (emailRole != 'user') return emailRole;

  if (userId == partyNovaReservedIds[partyNovaOwnerEmail]) return 'owner';
  if (userId == partyNovaReservedIds[partyNovaAdminEmail]) return 'admin';

  final savedRole = (storedRole ?? '').trim().toLowerCase();
  return savedRole.isEmpty ? 'user' : savedRole;
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
      // Use the full available device width. Individual pages use responsive
      // padding and flexible layouts instead of forcing the whole app into a
      // fixed-width column. Keep text scaling consistent with the existing UI.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child ?? const SizedBox.shrink(),
        );
      },
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


Future<void> syncPartyNovaPublicProfile(User user) async {
  final firestore = FirebaseFirestore.instance;

  // Read the signed-in user's existing profile.
  final userDoc = await firestore
      .collection('users')
      .doc(user.uid)
      .get();

  if (!userDoc.exists) {
    debugPrint('Public profile sync skipped: user profile not found.');
    return;
  }

  final data = userDoc.data()!;

  final userId = (data['userId'] ?? '').toString();
  final name = (data['name'] ?? user.displayName ?? 'PartyNova User')
      .toString();
  final photoBase64 = (data['photoBase64'] ?? '').toString();
  final bio = (data['bio'] ?? '').toString();
  final profileFrameAsset = (data['profileFrameAsset'] ?? '').toString();
  final role = resolvePartyNovaRole(
    email: user.email,
    userId: userId,
    storedRole: data['role']?.toString(),
  );

  if (!RegExp(r'^(?:\d{6}|\d{8}|\d{10})$').hasMatch(userId)) {
    debugPrint('Public profile sync skipped: invalid PartyNova ID.');
    return;
  }

  // Store only fields intended for public profile search.
  await firestore
      .collection('publicProfiles')
      .doc(user.uid)
      .set({
    'userId': userId,
    'name': name,
    'photoBase64': photoBase64,
    'bio': bio,
    'profileFrameAsset': profileFrameAsset,
    'role': role,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
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
  await syncPartyNovaPublicProfile(user);
} catch (e) {
  debugPrint('PartyNova profile setup failed: $e');
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
        await syncPartyNovaPublicProfile(currentUser);
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
                  onTap: () {
  if (_selectedIndex == index) return;
  setState(() {
    _selectedIndex = index;
  });
},
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (index == 4)
                          _SocialBottomNavIcon(
                            icon: icons[index],
                            selected: selected,
                          )
                        else
                          Icon(
                            icons[index],
                            color: selected
                                ? const Color(0xFFFFD700)
                                : Colors.white54,
                          ),
                        const SizedBox(height: 4),
                        if (index == 4)
                          _SocialBottomNavLabel(selected: selected)
                        else
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




Widget _buildSocialTab() => const PartyNovaSocialTab();

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

   Future<void> _createRoom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first.')),
      );
      return;
    }

    final nameController = TextEditingController();
    final roomName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF21101F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFFFD780), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.meeting_room_rounded,
                    color: Color(0xFFFFD780), size: 46),
                const SizedBox(height: 14),
                const Text(
                  'CREATE YOUR ROOM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFD780),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 30,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Type your room name',
                    hintStyle: TextStyle(color: Colors.white54),
                    counterStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('CANCEL',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF1688),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          nameController.text.trim(),
                        ),
                        child: const Text('SAVE'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    nameController.dispose();

    if (roomName == null || !mounted) return;
    if (roomName.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room name must be at least 3 characters.')),
      );
      return;
    }
    if (roomName.length > 30) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final userSnapshot = await firestore.collection('users').doc(user.uid).get();
      if (!userSnapshot.exists) {
        throw StateError('Your user profile was not found.');
      }
      final data = userSnapshot.data()!;
      final ownerUserId = (data['userId'] ?? '').toString();
      final ownerName = (data['name'] ?? 'PartyNova User').toString();
      final ownerPhotoBase64 = (data['photoBase64'] ?? '').toString();
      if (ownerUserId.isEmpty || ownerName.isEmpty) {
        throw StateError('Your profile information is incomplete.');
      }

      // One room per account: the claim document is the transaction lock.
      // Older rooms are reused (not deleted); the newest existing room wins.
      final claimRef = firestore.collection('roomOwnerClaims').doc(user.uid);
      final existingRooms = await firestore
          .collection('rooms')
          .where('ownerUid', isEqualTo: user.uid)
          .get();
      final oldRoomDocs = existingRooms.docs.toList()
        ..sort((a, b) {
          final aDate = a.data()['createdAt'];
          final bDate = b.data()['createdAt'];
          if (aDate is Timestamp && bDate is Timestamp) {
            return bDate.compareTo(aDate);
          }
          return 0;
        });

      final newRoomRef = firestore.collection('rooms').doc();
      DocumentReference<Map<String, dynamic>>? selectedRoomRef;

      await firestore.runTransaction((transaction) async {
        final claimSnapshot = await transaction.get(claimRef);

        if (claimSnapshot.exists) {
          final claimedRoomId =
              (claimSnapshot.data()?['roomId'] ?? '').toString();
          if (claimedRoomId.isEmpty) {
            throw StateError('Your room claim is invalid. Please contact support.');
          }
          final claimedRoomRef = firestore.collection('rooms').doc(claimedRoomId);
          final claimedRoomSnapshot = await transaction.get(claimedRoomRef);
          if (!claimedRoomSnapshot.exists) {
            throw StateError('Your saved room could not be found.');
          }
          selectedRoomRef = claimedRoomRef;
          return;
        }

        if (oldRoomDocs.isNotEmpty) {
          // Adopt an existing room instead of creating another one.
          selectedRoomRef = oldRoomDocs.first.reference;
          transaction.set(claimRef, {
            'ownerUid': user.uid,
            'roomId': oldRoomDocs.first.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        final now = FieldValue.serverTimestamp();
        final memberRef = newRoomRef.collection('members').doc(user.uid);
        transaction.set(claimRef, {
          'ownerUid': user.uid,
          'roomId': newRoomRef.id,
          'createdAt': now,
        });
        transaction.set(newRoomRef, {
          'roomId': newRoomRef.id,
          'roomName': roomName,
          'ownerUid': user.uid,
          'leaderUid': user.uid,
          'deputyLeaderUid': '',
          'ownerUserId': ownerUserId,
          'ownerName': ownerName,
          'roomPhotoBase64': ownerPhotoBase64,
          'roomDescription': '',
          'clubName': '',
          'memberCount': 1,
          'createdAt': now,
          'updatedAt': now,
          'isActive': true,
        });
        transaction.set(memberRef, {
          'firebaseUid': user.uid,
          'userId': ownerUserId,
          'name': ownerName,
          'photoBase64': ownerPhotoBase64,
          'clubName': '',
          'role': 'Leader',
          'isRoomLeader': true,
          'joinedAt': now,
        });
        selectedRoomRef = newRoomRef;
      });

      if (selectedRoomRef == null) {
        throw StateError('Room could not be selected.');
      }
      final selectedRoomSnapshot = await selectedRoomRef!.get();
      final selectedRoomData = selectedRoomSnapshot.data() ?? <String, dynamic>{};
      final selectedRoomName =
          (selectedRoomData['roomName'] ?? roomName).toString();
      final selectedRoomUid =
          (selectedRoomData['ownerUserId'] ?? ownerUserId).toString();
      final selectedRoomPhoto =
          (selectedRoomData['roomPhotoBase64'] ?? ownerPhotoBase64).toString();

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PartyRoomScreen(
            roomName: selectedRoomName,
            roomUid: selectedRoomUid,
            roomPhotoBase64: selectedRoomPhoto,
            roomDocumentId: selectedRoomRef!.id,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Create room failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Room creation failed: $error')),
      );
    }
  }

  Widget _buildMyCreatedRoomCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .where('ownerUid', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final ownedRooms = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aDate = a.data()['createdAt'];
            final bDate = b.data()['createdAt'];
            if (aDate is Timestamp && bDate is Timestamp) {
              return bDate.compareTo(aDate);
            }
            return 0;
          });
        final room = ownedRooms.first;
        final data = room.data();
        final roomName = (data['roomName'] ?? '').toString();
        final roomDescription = (data['roomDescription'] ?? '').toString().trim();
        final roomPhoto = (data['roomPhotoBase64'] ?? '').toString();
        final ownerUid = (data['leaderUid'] ?? data['ownerUid'] ?? '').toString();
        final roomImage = getCachedProfilePhotoImage(roomPhoto);

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 38, 14, 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PartyRoomScreen(
                    roomName: roomName,
                    roomUid: (data['ownerUserId'] ?? '').toString(),
                    roomPhotoBase64: roomPhoto,
                    roomDocumentId: room.id,
                  ),
                ),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF152E50),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF3C78B8),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 88),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE0FFF7),
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              roomName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF174B40),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (roomDescription.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  roomDescription.split(RegExp(r'\r?\n')).first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF39766A),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -34,
                  left: 18,
                  right: 18,
                  height: 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: roomImage != null
                        ? Image(image: roomImage, fit: BoxFit.cover)
                        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: ownerUid.isEmpty
                                ? null
                                : FirebaseFirestore.instance
                                    .collection('publicProfiles')
                                    .doc(ownerUid)
                                    .snapshots(),
                            builder: (context, profileSnapshot) {
                              final profileData = profileSnapshot.data?.data();
                              final profilePhoto =
                                  (profileData?['photoBase64'] ?? '').toString();
                              final fallbackImage =
                                  getCachedProfilePhotoImage(profilePhoto);
                              if (fallbackImage != null) {
                                return Image(
                                  image: fallbackImage,
                                  fit: BoxFit.cover,
                                );
                              }
                              return const ColoredBox(
                                color: Color(0xFF392047),
                                child: Icon(
                                  Icons.groups_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Positioned(
                  top: -34,
                  left: 18,
                  child: Container(
                    width: 42,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2477D4),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeRoomsStream =
    FirebaseFirestore.instance
        .collection('rooms')
        .snapshots();


  
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

Widget buildUserSearchResult() {
  final query = _roomSearchQuery.trim();

  if (!RegExp(r'^\d{6,10}$').hasMatch(query)) {
    return const SizedBox.shrink();
  }

  return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance
        .collection('publicProfiles')
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
      final receiverFirebaseUid = snapshot.data!.docs.first.id;
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
        // Show the Create Room banner until this user has created a room.
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseAuth.instance.currentUser == null
              ? null
              : FirebaseFirestore.instance
                  .collection('rooms')
                  .where('ownerUid', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                  .limit(1)
                  .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
              return _buildMyCreatedRoomCard();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 22, 14, 20),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _createRoom,
                child: Container(
                  width: double.infinity,
                  height: 190,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF54244F), Color(0xFF21101F), Color(0xFF392047)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: gold, width: 1.5),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_rounded, color: gold, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'CREATE ROOM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _activeRoomsStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Expanded(
          child: Center(
            child: Text(
              'Unable to load rooms: ${snapshot.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        );
      }

        if (!snapshot.hasData) {
          return const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            ),
          );
        }

        final searchQuery = _roomSearchQuery.trim().toLowerCase();
        final allRooms = snapshot.data!.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'docId': doc.id,
            'name': (data['roomName'] ?? '').toString(),
            'uid': (data['ownerUserId'] ?? data['leaderUserId'] ?? '').toString(),
            'ownerUid': (data['ownerUid'] ?? '').toString(),
            'leaderUid': (data['leaderUid'] ?? '').toString(),
            'members': data['memberCount'] ?? 0,
            'photo': (data['roomPhotoBase64'] ?? '').toString(),
            'description': (data['roomDescription'] ?? '').toString(),
            'isActive': data['isActive'],
            'createdAt': data['createdAt'],
          };
        }).toList();

        // Keep only the newest visible room for each owner. Older duplicate
        // documents remain untouched in Firestore and are not deleted.
        final latestRoomByOwner = <String, Map<String, dynamic>>{};
        for (final room in allRooms) {
          final ownerKey = room['ownerUid'].toString().isEmpty
              ? room['docId'].toString()
              : room['ownerUid'].toString();
          final previous = latestRoomByOwner[ownerKey];
          final currentDate = room['createdAt'];
          final previousDate = previous?['createdAt'];
          if (previous == null ||
              (currentDate is Timestamp &&
                  (previousDate is! Timestamp ||
                      currentDate.compareTo(previousDate) > 0))) {
            latestRoomByOwner[ownerKey] = room;
          }
        }

        final rooms = latestRoomByOwner.values.where((room) {
          if (room['isActive'] == false) return false;
          final name = room['name'].toString().toLowerCase();
          final uid = room['uid'].toString();
          return name.contains(searchQuery) || uid.contains(searchQuery);
        }).toList();

        if (_selectedRoomFilter == 1) {
          rooms.sort((a, b) {
            final aMembers = int.tryParse(a['members'].toString()) ?? 0;
            final bMembers = int.tryParse(b['members'].toString()) ?? 0;
            return bMembers.compareTo(aMembers);
          });
        } else {
          rooms.sort((a, b) {
            final aDate = a['createdAt'];
            final bDate = b['createdAt'];
            if (aDate is Timestamp && bDate is Timestamp) {
              return bDate.compareTo(aDate);
            }
            return 0;
          });
        }

        if (rooms.isEmpty) {
          return const Expanded(
            child: Center(
              child: Text('No rooms found', style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        return Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
            itemCount: rooms.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
              childAspectRatio: 0.76,
            ),
            itemBuilder: (context, index) {
              final room = rooms[index];
              final roomPhoto = room['photo'].toString();
              final roomOwnerUid = (room['leaderUid'].toString().isNotEmpty
                  ? room['leaderUid']
                  : room['ownerUid']).toString();
              final roomImage = getCachedProfilePhotoImage(roomPhoto);

              return InkWell(
                key: ValueKey(room['docId']),
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PartyRoomScreen(
                        roomName: room['name'].toString(),
                        roomUid: room['uid'].toString(),
                        roomPhotoBase64: roomPhoto,
                        roomDocumentId: room['docId'].toString(),
                      ),
                    ),
                  );
                },
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0FFF7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (roomImage != null)
                              Image(image: roomImage, fit: BoxFit.cover)
                            else
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: roomOwnerUid.isEmpty
                                    ? null
                                    : FirebaseFirestore.instance
                                        .collection('publicProfiles')
                                        .doc(roomOwnerUid)
                                        .snapshots(),
                                builder: (context, profileSnapshot) {
                                  final profileData = profileSnapshot.data?.data();
                                  final profilePhoto =
                                      (profileData?['photoBase64'] ?? '').toString();
                                  final fallbackImage =
                                      getCachedProfilePhotoImage(profilePhoto);
                                  if (fallbackImage != null) {
                                    return Image(
                                      image: fallbackImage,
                                      fit: BoxFit.cover,
                                    );
                                  }
                                  return const ColoredBox(
                                    color: Color(0xFF392047),
                                    child: Icon(
                                      Icons.groups_rounded,
                                      size: 55,
                                      color: Color(0xFFFFB9DD),
                                    ),
                                  );
                                },
                              ),
                            Positioned(
                              top: 9,
                              right: 8,
                              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                stream: FirebaseFirestore.instance
                                    .collection('rooms')
                                    .doc(room['docId'].toString())
                                    .collection('presence')
                                    .snapshots(),
                                builder: (context, presenceSnapshot) {
                                  final inRoom = (presenceSnapshot.data?.docs.isNotEmpty ?? false);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.58),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.bar_chart_rounded, color: Color(0xFF18D6C0), size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          inRoom ? '1' : '0',
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE0FFF7),
                          border: Border(
                            top: BorderSide(color: Colors.white, width: 2),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room['name'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF174B40),
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (room['description'].toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                room['description'].toString().trim().split(RegExp(r'\r?\n')).first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF39766A),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
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
    ),
  ),

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

      final savedUserId = (data['userId'] ?? '').toString().trim();
      final userId = savedUserId.isNotEmpty
          ? savedUserId
          : (partyNovaReservedIds[user.email?.trim().toLowerCase()] ?? '');

      final role = resolvePartyNovaRole(
        email: user.email,
        userId: userId,
        storedRole: data['role']?.toString(),
      );

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

              // Regular users keep their UID above the DP. Owner/Admin
              // UIDs are shown only inside the Golden ID Card below.
              if (!isOwnerOrAdmin) ...[
                const SizedBox(height: 12),
                Text(
                  'ID: ${userId.isEmpty ? 'Not available' : userId}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFD780),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
              ] else ...[
                const SizedBox(height: 10),
              ],

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

        final photoImage = getCachedProfilePhotoImage(photoBase64);

        if (photoImage == null) {
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
          child: Image(
            image: photoImage,
            width: 112,
            height: 112,
            fit: BoxFit.cover,
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE8A6), Color(0xFFD9A43B), Color(0xFFB51F25), Color(0xFF650B16), Color(0xFFFFD780)]),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFFFE6B8), width: 1.4),
                    boxShadow: const [BoxShadow(color: Color(0xAAFFB45A), blurRadius: 16, spreadRadius: 1), BoxShadow(color: Color(0x99FF2424), blurRadius: 18, spreadRadius: 1)],
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned.fill(child: CustomPaint(painter: _FourCornerFramePainter(color: const Color(0xFFFFF1D2)))),
                    Text(role.toUpperCase(), style: const TextStyle(color: Color(0xFFFFF4D6), fontWeight: FontWeight.w900, letterSpacing: 1.5, shadows: [Shadow(color: Color(0xFFFFD780), blurRadius: 9), Shadow(color: Color(0xFFFF2424), blurRadius: 12)])),
                  ]),
                ),
              ] else ...[
                const SizedBox.shrink(),
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
    final firestore = FirebaseFirestore.instance;

    // Update the original private profile.
    await firestore
        .collection('users')
        .doc(widget.uid)
        .set({
      'name': name,
      'bio': bio,
      'photoBase64': _photoBase64,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Read the existing PartyNova ID without changing it.
    final userSnapshot = await firestore
        .collection('users')
        .doc(widget.uid)
        .get();

    final userData = userSnapshot.data();
    final userId = (userData?['userId'] ?? '').toString();
    final role = resolvePartyNovaRole(
      email: FirebaseAuth.instance.currentUser?.email,
      userId: userId,
      storedRole: userData?['role']?.toString(),
    );
    final profileFrameAsset =
        (userData?['profileFrameAsset'] ?? '').toString();

    // Keep the public profile in sync with the latest saved profile fields.
    if (RegExp(r'^(?:\d{6}|\d{8}|\d{10})$')
        .hasMatch(userId)) {
      try {
        await firestore
    .collection('publicProfiles')
    .doc(widget.uid)
    .set({
  'userId': userId,
  'name': name,
  'bio': bio,
  'photoBase64': _photoBase64,
  'profileFrameAsset': profileFrameAsset,
  'role': role,
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
      } catch (syncError) {
        debugPrint(
          'Public profile sync failed: $syncError',
        );
      }
    } else {
      debugPrint(
        'Public profile sync skipped: invalid PartyNova ID.',
      );
    }

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
                child: getCachedProfilePhotoImage(_photoBase64) != null
    ? ClipOval(
        child: Image(
          image: getCachedProfilePhotoImage(_photoBase64)!,
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

final photoImage = getCachedProfilePhotoImage(widget.photoBase64);
final Widget avatar = photoImage == null
    ? Icon(
        Icons.person_rounded,
        size: size * 0.58,
        color: Colors.white,
      )
    : Image(
        image: photoImage,
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
    final photoImage = getCachedProfilePhotoImage(widget.photoBase64);
    if (photoImage == null) return _defaultAvatar(size);

    return ClipOval(
      child: Image(
        image: photoImage,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _defaultAvatar(size),
      ),
    );
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
      _cachedAvatarImage = getCachedProfilePhotoImage(data);
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

      _cachedAvatar = getCachedProfilePhotoImage(cleanData);
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


class RoomDetailsOverview extends StatefulWidget {
  final String roomName;
  final String roomUid;
  final String roomPhotoBase64;
  final String roomDescription;
  final String roomDocumentId;
  final String memberPoint;
  final String clubPoint;
  final String giftPoint;

  const RoomDetailsOverview({
    super.key,
    required this.roomName,
    required this.roomUid,
    this.roomPhotoBase64 = '',
    this.roomDescription = '',
    required this.roomDocumentId,
    this.memberPoint = '0',
    this.clubPoint = '0',
    this.giftPoint = '0',
  });

  @override
  State<RoomDetailsOverview> createState() =>
      _RoomDetailsOverviewState();
}

class _RoomDetailsOverviewState extends State<RoomDetailsOverview> {
  static const Color bg = Color(0xFF100810);
  static const Color gold = Color(0xFFFFD700);
  static const Color pink = Color(0xFFFF4FA3);
  static const Color panel = Color(0xFF24101F);

  final List<String> _languages = [
    'Pashto',
    'Urdu',
    'Punjabi',
    'English',
    'Arabic',
    'Hindi',
    'Chinese',
    'French',
    'Turkish',
    'Vietnamese',
    'Bengali',
    'Persian',
  ];

  final Set<String> _selectedLanguages = {};
  late String _currentRoomName;
  late String _currentRoomPhotoBase64;
  late String _currentRoomDescription;
  late String _currentClubName;
  bool _savingRoomDetails = false;
  bool _pickingRoomPhoto = false;

  int _selectedTab = 0;
  final TextEditingController _memberSearchController = TextEditingController();
  String _memberSearchQuery = '';
  // Room permission switch values are stored on the room document.
  final Map<String, bool> _leaderPermissionUiState = {};
  bool _leaderMemberBackfillStarted = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomDetailsSubscription;

  Future<void> _ensureLeaderMemberRecord() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _leaderMemberBackfillStarted) return;
    _leaderMemberBackfillStarted = true;
    try {
      final firestore = FirebaseFirestore.instance;
      final roomRef = firestore.collection('rooms').doc(widget.roomDocumentId);
      final roomSnapshot = await roomRef.get();
      if (!roomSnapshot.exists) return;
      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      final ownerUid = (roomData['ownerUid'] ?? '').toString();
      var leaderUid = (roomData['leaderUid'] ?? '').toString();

      // Older rooms may not have leaderUid. In that case only the owner
      // is treated as the Leader; do not rewrite room ownership fields.
      final isLeader = leaderUid.isNotEmpty
          ? leaderUid == user.uid
          : ownerUid == user.uid;
      if (!isLeader) return;

      final profileSnapshot = await firestore.collection('users').doc(user.uid).get();
      final profile = profileSnapshot.data() ?? <String, dynamic>{};
      await syncPartyNovaPublicProfile(user);
      var partyNovaUid = (profile['userId'] ?? '').toString().trim();
      if (partyNovaUid.isEmpty) {
        partyNovaUid = await assignPartyNovaUserId(user);
      }
      final memberRef = roomRef.collection('members').doc(user.uid);
      final memberSnapshot = await memberRef.get();
      // The room document is authoritative: its creator is always Leader.
      // Merge keeps an existing join date and any extra member fields intact.
      final leaderRecord = <String, dynamic>{
        'firebaseUid': user.uid,
        'userId': (profile['userId'] ?? roomData['ownerUserId'] ?? partyNovaUid).toString(),
        'name': (profile['name'] ?? roomData['ownerName'] ?? user.displayName ?? 'PartyNova User').toString(),
        'photoBase64': (profile['photoBase64'] ?? '').toString(),
        'clubName': (roomData['clubName'] ?? '').toString(),
        'role': 'Leader',
        'isRoomLeader': true,
      };
      if (!memberSnapshot.exists) {
        leaderRecord['joinedAt'] = FieldValue.serverTimestamp();
      }
      await memberRef.set(leaderRecord, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Room owner/leader member backfill failed: $error');
      _leaderMemberBackfillStarted = false;
    }
  }

  @override
  void dispose() {
    _roomDetailsSubscription?.cancel();
    _memberSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentRoomName = widget.roomName;
    _currentRoomPhotoBase64 = widget.roomPhotoBase64;
    _currentRoomDescription = widget.roomDescription;
    _currentClubName = '';
    // Keep the Room Profile live for every viewer, not only the editor.
    _roomDetailsSubscription = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final data = snapshot.data() ?? <String, dynamic>{};
      setState(() {
        _currentRoomName = (data['roomName'] ?? _currentRoomName).toString();
        _currentRoomPhotoBase64 =
            (data['roomPhotoBase64'] ?? _currentRoomPhotoBase64).toString();
        _currentRoomDescription =
            (data['roomDescription'] ?? _currentRoomDescription).toString();
        _currentClubName = (data['clubName'] ?? _currentClubName).toString();
        _selectedLanguages
          ..clear()
          ..addAll(((data['roomLanguages'] as List?) ?? const [])
              .map((value) => value.toString()));
      });
    }, onError: (error) {
      debugPrint('Live room profile update failed: $error');
    });
    _loadRoomDetails();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureLeaderMemberRecord();
    });
  }

  Future<void> _loadRoomDetails() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomDocumentId)
          .get();
      if (!mounted || !doc.exists) return;
      final data = doc.data() ?? <String, dynamic>{};
      setState(() {
        _currentRoomName = (data['roomName'] ?? _currentRoomName).toString();
        _currentRoomPhotoBase64 =
            (data['roomPhotoBase64'] ?? _currentRoomPhotoBase64).toString();
        _currentRoomDescription =
            (data['roomDescription'] ?? _currentRoomDescription).toString();
        _currentClubName = (data['clubName'] ?? _currentClubName).toString();
        _selectedLanguages
          ..clear()
          ..addAll(((data['roomLanguages'] as List?) ?? const [])
              .map((e) => e.toString()));
      });
    } catch (e) {
      debugPrint('Load room details failed: $e');
    }
  }

  // Room management is restricted to the actual room owner/leader.
  // New rooms store both UIDs; the fallback supports older room documents.
  Future<bool> _isCurrentUserRoomLeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final room = await FirebaseFirestore.instance
          .collection('rooms').doc(widget.roomDocumentId).get();
      if (!room.exists) return false;
      final data = room.data() ?? <String, dynamic>{};
      final ownerUid = (data['ownerUid'] ?? '').toString();
      final leaderUid = (data['leaderUid'] ?? '').toString();
      final effectiveOwnerUid = ownerUid.isNotEmpty ? ownerUid : leaderUid;
      final effectiveLeaderUid = leaderUid.isNotEmpty ? leaderUid : ownerUid;
      return effectiveOwnerUid == user.uid && effectiveLeaderUid == user.uid;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _saveRoomFields(Map<String, dynamic> fields) async {
    if (_savingRoomDetails) return false;
    if (!await _isCurrentUserRoomLeader()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only this room Owner/Leader can edit room details.')),
      );
      return false;
    }
    setState(() => _savingRoomDetails = true);
    try {
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomDocumentId)
          .update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room details saved')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
      return false;
    } finally {
      if (mounted) setState(() => _savingRoomDetails = false);
    }
  }

  Future<void> _editRoomText({required bool editName}) async {
    if (!await _isCurrentUserRoomLeader()) return;
    final controller = TextEditingController(
      text: editName ? _currentRoomName : _currentRoomDescription,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        title: Text(
          editName ? 'Change Room Name' : 'Room Description',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: editName ? 74 : 300,
          child: TextField(
            controller: controller,
            maxLength: editName ? 30 : 200,
            maxLines: editName ? 1 : null,
            expands: !editName,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: gold,
            decoration: InputDecoration(
              hintText: editName ? 'Enter room name (max 30)' : 'Write room description (max 200 characters)',
              hintStyle: const TextStyle(color: Colors.white54),
              counterStyle: const TextStyle(color: Colors.white54),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: pink, width: 1.2),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: gold, width: 1.5),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: pink),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    final maxLength = editName ? 30 : 200;
    if (result.length > maxLength) return;
    final field = editName ? 'roomName' : 'roomDescription';
    final saved = await _saveRoomFields({field: result});
    if (!saved || !mounted) return;
    setState(() {
      if (editName) {
        _currentRoomName = result;
      } else {
        _currentRoomDescription = result;
      }
    });
  }

  Future<void> _pickRoomPhoto() async {
    if (_savingRoomDetails || _pickingRoomPhoto) return;
    if (!await _isCurrentUserRoomLeader()) return;
    setState(() => _pickingRoomPhoto = true);

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null || !mounted) return;

      // Use the same square crop and JPEG compression as the normal profile DP.
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust Room Photo',
            toolbarColor: const Color(0xFF7028A0),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFFFF1688),
            lockAspectRatio: true,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'Adjust Room Photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPresets: [CropAspectRatioPreset.square],
          ),
        ],
      );
      if (cropped == null || !mounted) return;

      final bytes = await cropped.readAsBytes();
      // Match profile DP's 450 KB raw-image limit. This keeps Base64 safely
      // below the Firestore document-size ceiling with room for other fields.
      if (bytes.length > 450 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo is too large. Please choose another photo.'),
          ),
        );
        return;
      }

      final encoded = base64Encode(bytes);
      final saved = await _saveRoomFields({'roomPhotoBase64': encoded});
      if (!saved || !mounted) return;
      setState(() => _currentRoomPhotoBase64 = encoded);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room photo updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _pickingRoomPhoto = false);
    }
  }

  Future<void> _copyRoomId() async {
    await Clipboard.setData(
      ClipboardData(text: widget.roomUid),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PartyNova ID copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openLanguagePopup() async {
    final Set<String> temporarySelection =
        Set<String>.from(_selectedLanguages);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'Select Room Languages',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 9,
                    runSpacing: 10,
                    children: _languages.map((language) {
                      final bool selected =
                          temporarySelection.contains(language);

                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            if (selected) {
                              temporarySelection.remove(language);
                            } else {
                              temporarySelection.add(language);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? pink : bg,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: selected
                                  ? pink
                                  : Colors.white24,
                            ),
                          ),
                          child: Text(
                            language,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final saved = await _saveRoomFields({
                      'roomLanguages': temporarySelection.toList(),
                    });
                    if (!saved || !mounted) return;
                    setState(() {
                      _selectedLanguages
                        ..clear()
                        ..addAll(temporarySelection);
                    });
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pink,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTopTab(String title, int index) {
    final bool selected = _selectedTab == index;
    final IconData tabIcon = index == 0
        ? Icons.person_rounded
        : index == 1
            ? Icons.groups_rounded
            : Icons.credit_card_rounded;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tabIcon,
                color: selected ? pink : Colors.white70,
                size: 27,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: selected ? 34 : 0,
                decoration: BoxDecoration(
                  color: pink,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: pink.withOpacity(0.45),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : const [],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoint(
    String title,
    String value,
    IconData icon,
  ) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: pink,
            size: 25,
          ),
          const SizedBox(height: 7),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomLevel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ROOM LEVEL',
          style: TextStyle(
            color: gold,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              color: gold,
              size: 28,
            ),
            const SizedBox(width: 9),
            const Text(
              'Level 1',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '0%',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: const LinearProgressIndicator(
            value: 0,
            minHeight: 7,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(pink),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSelector() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (await _isCurrentUserRoomLeader()) _openLanguagePopup();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pink.withOpacity(0.45), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language_rounded, color: pink, size: 21),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Room Languages',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: pink,
                  size: 25,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_selectedLanguages.isEmpty)
              const Text(
                'Select Room Languages',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              )
            else
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: _selectedLanguages.map((language) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: pink,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xFFFF9BC8),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: pink.withOpacity(0.20),
                          blurRadius: 7,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      language,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderEditIcon({required VoidCallback onPressed, String tooltip = 'Edit'}) {
    return FutureBuilder<bool>(
      future: _isCurrentUserRoomLeader(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.edit_rounded, color: gold, size: 19),
        );
      },
    );
  }

  Widget _buildDescription() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 15),
      decoration: BoxDecoration(
        color: panel.withOpacity(0.94),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: pink.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(color: pink.withOpacity(0.10), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded, color: gold, size: 19),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Description', style: TextStyle(
                  color: gold, fontSize: 16, fontWeight: FontWeight.w900,
                )),
              ),
              _buildLeaderEditIcon(onPressed: () => _editRoomText(editName: false), tooltip: 'Edit description'),
            ],
          ),
          Text(
            _currentRoomDescription.trim().isEmpty
                ? 'No room rules or description added yet.'
                : _currentRoomDescription,
            textAlign: TextAlign.left,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _editClubName() async {
    if (!await _isCurrentUserRoomLeader()) return;
    final roomRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomDocumentId);
    final roomSnapshot = await roomRef.get();
    final roomData = roomSnapshot.data() ?? <String, dynamic>{};
    final lastChanged = roomData['clubNameChangedAt'];
    if (lastChanged is Timestamp) {
      final nextAllowed = lastChanged.toDate().add(const Duration(days: 30));
      if (DateTime.now().isBefore(nextAllowed)) {
        final remaining = nextAllowed.difference(DateTime.now());
        final days = remaining.inDays + (remaining.inHours % 24 == 0 ? 0 : 1);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Club Name can be changed after $days more day(s).')),
        );
        return;
      }
    }

    final controller = TextEditingController(text: _currentClubName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Change Club Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Maximum 6 letters',
            hintStyle: TextStyle(color: Colors.white54),
            counterStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: pink),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || value.length > 6 || !mounted) return;
    final clubName = value.toUpperCase();

    // Recheck authority and cooldown immediately before saving.
    if (!await _isCurrentUserRoomLeader()) return;
    final freshRoom = await roomRef.get();
    final freshTimestamp = freshRoom.data()?['clubNameChangedAt'];
    if (freshTimestamp is Timestamp &&
        DateTime.now().isBefore(freshTimestamp.toDate().add(const Duration(days: 30)))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club Name can only be changed once every 30 days.')),
        );
      }
      return;
    }

    final ok = await _saveRoomFields({
      'clubName': clubName,
      'clubNameChangedAt': FieldValue.serverTimestamp(),
    });
    if (!ok || !mounted) return;
    setState(() => _currentClubName = clubName);
    // The room document is the single source of truth for Club Name.
    // New members copy it into their member record when they join.
  }

  Widget _buildPoints() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('rooms').doc(widget.roomDocumentId).snapshots(),
      builder: (context, roomSnapshot) {
        final roomData = roomSnapshot.data?.data() ?? <String, dynamic>{};
        final clubName = (roomData['clubName'] ?? _currentClubName).toString();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                children: [
                  const Text('Club Name', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF9A642D),
                              Color(0xFF603512),
                              Color(0xFF321A0D),
                              Color(0xFF8B5726),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFFFD58A), width: 1.2),
                          boxShadow: const [
                            BoxShadow(color: Color(0x99D99A45), blurRadius: 13, spreadRadius: 1),
                            BoxShadow(color: Color(0x667A3D12), blurRadius: 4, spreadRadius: 2),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_moon_rounded, color: Color(0xFFFFD58A), size: 17),
                            const SizedBox(width: 6),
                            Text(
                              clubName.isEmpty ? 'CLUB' : clubName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFFE6B8),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                                shadows: [
                                  Shadow(color: Color(0xFFFFD27A), blurRadius: 9),
                                  Shadow(color: Color(0xFFB66B2B), blurRadius: 15),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                  colors: [Color(0xFFFFB0B0), Color(0xFFFF2424), Color(0xFF8B0000)],
                                ),
                                border: Border.all(color: const Color(0xFFFFBABA), width: 0.8),
                                boxShadow: const [
                                  BoxShadow(color: Color(0xFFFF3030), blurRadius: 9, spreadRadius: 2),
                                  BoxShadow(color: Color(0x99FF0000), blurRadius: 15, spreadRadius: 1),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildLeaderEditIcon(onPressed: _editClubName, tooltip: 'Edit Club Name'),
                    ],
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 54, color: Colors.white24),
            _buildPoint('Club Point', widget.clubPoint, Icons.stars_rounded),
            Container(width: 1, height: 54, color: Colors.white24),
            _buildPoint('Member Point', widget.memberPoint, Icons.military_tech_rounded),
          ],
        );
      },
    );
  }

  Future<void> _joinRoomFromProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw StateError('Your PartyNova profile was not found.');
      final profile = userDoc.data() ?? <String, dynamic>{};
      await syncPartyNovaPublicProfile(user);
      final partyNovaUid = (profile['userId'] ?? '').toString();
      if (!RegExp(r'^(?:[0-9]{6}|[0-9]{8}|[0-9]{10})$').hasMatch(partyNovaUid)) {
        throw StateError('Your PartyNova UID is invalid.');
      }
      final roomRef = firestore.collection('rooms').doc(widget.roomDocumentId);
      final memberRef = roomRef.collection('members').doc(user.uid);
      await firestore.runTransaction((transaction) async {
        final roomSnapshot = await transaction.get(roomRef);
        final memberSnapshot = await transaction.get(memberRef);
        if (!roomSnapshot.exists) throw StateError('Room not found.');
        final roomData = roomSnapshot.data() ?? <String, dynamic>{};
        final leaderUid = (roomData['leaderUid'] ?? '').toString();
        final ownerUid = (roomData['ownerUid'] ?? '').toString();
        if ((leaderUid.isNotEmpty ? leaderUid : ownerUid) == user.uid || memberSnapshot.exists) return;
        final currentCount = (roomData['memberCount'] as num?)?.toInt() ?? 0;
        if (currentCount >= 1000) {
          throw StateError('This room has reached its 1000-member limit.');
        }
        transaction.set(memberRef, {
          'firebaseUid': user.uid,
          'userId': partyNovaUid,
          'name': (profile['name'] ?? 'PartyNova User').toString(),
          'photoBase64': (profile['photoBase64'] ?? '').toString(),
          'clubName': (roomData['clubName'] ?? '').toString(),
          'role': 'Member',
          'joinedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(roomRef, {
          'memberCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You joined the room as a Member.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join room: $error')),
      );
    }
  }

  Future<void> _unjoinRoomFromProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final roomRef = firestore.collection('rooms').doc(widget.roomDocumentId);
      final memberRef = roomRef.collection('members').doc(user.uid);
      await firestore.runTransaction((transaction) async {
        final roomSnapshot = await transaction.get(roomRef);
        final memberSnapshot = await transaction.get(memberRef);
        if (!roomSnapshot.exists || !memberSnapshot.exists) return;
        final roomData = roomSnapshot.data() ?? <String, dynamic>{};
        final memberData = memberSnapshot.data() ?? <String, dynamic>{};
        final leaderUid = (roomData['leaderUid'] ?? '').toString();
        final ownerUid = (roomData['ownerUid'] ?? '').toString();
        if (user.uid == leaderUid || user.uid == ownerUid ||
            (memberData['role'] ?? '').toString().toLowerCase() == 'leader' ||
            (memberData['role'] ?? '').toString().toLowerCase() == 'owner') {
          throw StateError('The room Owner/Leader cannot unjoin their own room.');
        }
        transaction.delete(memberRef);
        final currentCount = (roomData['memberCount'] as num?)?.toInt() ?? 0;
        transaction.update(roomRef, {
          if (currentCount > 0) 'memberCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the room.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not leave room: $error')),
      );
    }
  }

  Widget _buildProfileMembershipAction() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();
    final roomRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomDocumentId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, roomSnapshot) {
        final roomData = roomSnapshot.data?.data() ?? <String, dynamic>{};
        if (((roomData['leaderUid'] ?? '').toString().isNotEmpty
                ? (roomData['leaderUid'] ?? '').toString()
                : (roomData['ownerUid'] ?? '').toString()) == currentUser.uid) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: roomRef.collection('members').doc(currentUser.uid).snapshots(),
          builder: (context, memberSnapshot) {
            if (memberSnapshot.data?.exists != true) return const SizedBox.shrink();
            return SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _unjoinRoomFromProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1769AA),
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: const Color(0xFF42A5F5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: const BorderSide(color: Color(0xFF90CAF9), width: 1.2),
                  ),
                ),
                child: const Text('UNJOIN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _canAssignDeputyLeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Use the signed-in account first. Looking up the room owner's public
    // profile here incorrectly checked the room creator instead of the actor.
    final signedInRole = partyNovaRoleForEmail(user.email);
    if (signedInRole == 'owner' || signedInRole == 'admin') return true;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final storedRole = resolvePartyNovaRole(
        email: user.email,
        userId: (userData['userId'] ?? '').toString(),
        storedRole: userData['role']?.toString(),
      );
      if (storedRole == 'owner' || storedRole == 'admin') return true;

      final publicProfile = await FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(user.uid)
          .get();
      final publicData = publicProfile.data() ?? <String, dynamic>{};
      final publicRole = resolvePartyNovaRole(
        email: user.email,
        userId: (publicData['userId'] ?? '').toString(),
        storedRole: publicData['role']?.toString(),
      );
      return publicRole == 'owner' || publicRole == 'admin';
    } catch (error) {
      debugPrint('Check Deputy Leader permission failed: $error');
      return false;
    }
  }

  // Only the app Owner/Admin and this room's Owner/Leader can manage members.
  // Deputy Leader controls stay unavailable until the future room-upgrade feature.
  Future<bool> _canManageRoomMembers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final signedInRole = partyNovaRoleForEmail(user.email);
    if (signedInRole == 'owner' || signedInRole == 'admin') return true;

    try {
      final roomSnapshot = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomDocumentId)
          .get();
      if (!roomSnapshot.exists) return false;

      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      final ownerUid = (roomData['ownerUid'] ?? '').toString();
      final leaderUid = (roomData['leaderUid'] ?? '').toString();
      final effectiveOwnerUid = ownerUid.isNotEmpty ? ownerUid : leaderUid;
      final effectiveLeaderUid = leaderUid.isNotEmpty ? leaderUid : ownerUid;

      return user.uid == effectiveOwnerUid || user.uid == effectiveLeaderUid;
    } catch (error) {
      debugPrint('Check room member-management permission failed: $error');
      return false;
    }
  }

  Future<void> _showLeaderPermissionScreen() async {
    final roomRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId);
    try {
      final roomSnapshot = await roomRef.get();
      final savedPermissions =
          roomSnapshot.data()?['leaderPermissions'];
      _leaderPermissionUiState
        ..clear()
        ..addAll(savedPermissions is Map
            ? Map<String, bool>.fromEntries(
                savedPermissions.entries.map(
                  (entry) => MapEntry(
                    entry.key.toString(),
                    entry.value == true,
                  ),
                ),
              )
            : <String, bool>{});
    } catch (error) {
      debugPrint('Load room permissions failed: $error');
    }

    const permissionNames = <String>[
      'Activity Notice Management',
      'Tic Tac Toe Game Access',
      'Gift Scoring Management',
      'You Say, I Guess Game Access',
      "Who's the Spy Game Access",
      'Birthday Party Management',
      'Singing Queue Management',
      'Lucky Draw Management',
      'Clock Access',
      'Vote Management',
      'Fruit Fight Game Access',
      'Transfer Bomb Game Access',
      'Crocodile Dentist Game Access',
      'Fortune Chest Management',
      'Microphone Lock & Unlock',
      'Room Theme Management',
      'Room Theme Sharing',
    ];

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 18),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: gold, width: 1.3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'IN-CHARGE & DEPUTY PERMISSIONS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Green = ON     Red = OFF',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: permissionNames.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final label =
                          'Permission In-Charge & Deputy — ${permissionNames[index]}';
                      final enabled = _leaderPermissionUiState[label] ?? false;
                      return Container(
                        constraints: const BoxConstraints(minHeight: 66),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF211923),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: gold.withOpacity(0.75),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                final next = !enabled;
                                _leaderPermissionUiState[label] = next;
                                refreshDialog(() {});
                                try {
                                  await roomRef.set({
                                    'leaderPermissions':
                                        Map<String, bool>.from(_leaderPermissionUiState),
                                    'leaderPermissionsUpdatedAt':
                                        FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                } catch (error) {
                                  _leaderPermissionUiState[label] = !next;
                                  refreshDialog(() {});
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Could not save permission. Please try again.'),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 62,
                                height: 34,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: enabled
                                      ? const Color(0xFF168A43)
                                      : const Color(0xFFB32632),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: enabled
                                        ? const Color(0xFF5DFF9A)
                                        : const Color(0xFFFF858B),
                                    width: 1,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    Align(
                                      alignment: enabled
                                          ? Alignment.centerLeft
                                          : Alignment.centerRight,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 5),
                                        child: Text(
                                          enabled ? 'ON' : 'OFF',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                    AnimatedAlign(
                                      duration: const Duration(milliseconds: 180),
                                      curve: Curves.easeInOut,
                                      alignment: enabled
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Permission settings are saved automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  CollectionReference<Map<String, dynamic>> get _roomActionRecords =>
      FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomDocumentId)
          .collection('roomRecords');

  Future<void> _writeRoomActionRecord({
    required String action,
    required String targetUid,
    required String targetName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _roomActionRecords.add({
      'action': action,
      'targetUid': targetUid,
      'targetName': targetName,
      'actorUid': user.uid,
      'actorName': user.displayName ?? 'Room Staff',
      'createdAt': FieldValue.serverTimestamp(),
      if (action == 'Remove')
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
    });
  }

  Future<void> _showJoinFeeSettings() async {
    final roomRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId);
    final snapshot = await roomRef.get();
    final data = snapshot.data() ?? <String, dynamic>{};
    final feeController = TextEditingController(
      text: ((data['joinFeeDiamonds'] ?? 0).toString()),
    );
    if (!mounted) {
      feeController.dispose();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text(
          'ROOM JOIN FEE',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter 0 for free entry, or enter 10 to 2000 diamonds.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Diamonds (0 or 10–2000)',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.diamond, color: gold),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: gold.withOpacity(.7)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: gold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
            onPressed: () async {
              final fee = int.tryParse(feeController.text.trim());
              if (fee == null || (fee != 0 && (fee < 10 || fee > 2000))) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter 0 or a value from 10 to 2000 diamonds.')),
                );
                return;
              }
              await roomRef.set({
                'freeJoin': fee == 0,
                'joinFeeDiamonds': fee,
                'joinFeeUpdatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    feeController.dispose();
  }

  Future<void> _showRemoveMemberConfirmation({
    required String memberFirebaseUid,
    required String memberName,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('REMOVE MEMBER?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove $memberName from this room? The action will remain in Room Record for 7 days.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REMOVE', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final roomRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId);
    await _writeRoomActionRecord(
      action: 'Remove',
      targetUid: memberFirebaseUid,
      targetName: memberName,
    );
    final membersRef = roomRef.collection('members');
    final matchingMember = await membersRef
        .where('firebaseUid', isEqualTo: memberFirebaseUid)
        .limit(1)
        .get();
    if (matchingMember.docs.isNotEmpty) {
      await matchingMember.docs.first.reference.delete();
    } else {
      await membersRef.doc(memberFirebaseUid).delete();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$memberName removed. The record will remain for 7 days.')),
      );
    }
  }

  Future<void> _showBlockMemberScreen({
    required String memberFirebaseUid,
    required String memberName,
  }) async {
    final roomRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: panel,
        child: SizedBox(
          width: MediaQuery.of(dialogContext).size.width,
          height: MediaQuery.of(dialogContext).size.height,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('BLOCKED MEMBERS',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (memberFirebaseUid.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB32632),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;
                        await roomRef.collection('blockedMembers').doc(memberFirebaseUid).set({
                          'targetUid': memberFirebaseUid,
                          'targetName': memberName,
                          'actorUid': user.uid,
                          'actorName': user.displayName ?? 'Room Staff',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        await _writeRoomActionRecord(action: 'Ban', targetUid: memberFirebaseUid, targetName: memberName);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      icon: const Icon(Icons.block_rounded),
                      label: Text('BLOCK $memberName'),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _showRoomMemberPicker(forBlock: true);
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded, color: gold),
                      label: const Text('SELECT MEMBER TO BLOCK', style: TextStyle(color: gold)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: roomRef.collection('blockedMembers').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(child: Text('Unable to load the blocked members list.', style: TextStyle(color: Colors.white70)));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('No blocked members.', style: TextStyle(color: Colors.white60)));
                      }
                      return ListView.builder(
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          final doc = snapshot.data!.docs[index];
                          final item = doc.data();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.redAccent.withOpacity(.6)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((item['targetName'] ?? 'Member').toString(),
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text('Blocked by: ${(item['actorName'] ?? 'Room Staff')}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await _writeRoomActionRecord(
                                      action: 'Unban',
                                      targetUid: doc.id,
                                      targetName: (item['targetName'] ?? 'Member').toString(),
                                    );
                                    await doc.reference.delete();
                                  },
                                  child: const Text('UNBAN', style: TextStyle(color: Color(0xFF36D477))),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('CLOSE', style: TextStyle(color: gold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRoomRecordScreen() async {
    const tabs = ['Ban', 'Unban', 'Remove', 'Kick'];
    int selectedTab = 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: panel,
          child: SizedBox(
            width: MediaQuery.of(dialogContext).size.width,
            height: MediaQuery.of(dialogContext).size.height,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('ROOM RECORD',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(tabs.length, (index) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: InkWell(
                          onTap: () => refresh(() => selectedTab = index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                            decoration: BoxDecoration(
                              color: selectedTab == index ? gold : const Color(0xFF211923),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: gold.withOpacity(.7)),
                            ),
                            child: Text(tabs[index].toUpperCase(), textAlign: TextAlign.center,
                                style: TextStyle(color: selectedTab == index ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w900, fontSize: 10)),
                          ),
                        ),
                      ),
                    )),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _roomActionRecords.orderBy('createdAt', descending: true).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(child: Text('Unable to load room records.', style: TextStyle(color: Colors.white70)));
                        }
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final action = tabs[selectedTab];
                        final records = snapshot.data!.docs.where((doc) {
                          final item = doc.data();
                          if ((item['action'] ?? '').toString() != action) return false;
                          if (action == 'Remove') {
                            final expiry = item['expiresAt'];
                            if (expiry is Timestamp && expiry.toDate().isBefore(DateTime.now())) return false;
                          }
                          return true;
                        }).toList();
                        if (records.isEmpty) {
                          return Center(child: Text('No $action records.', style: const TextStyle(color: Colors.white60)));
                        }
                        return ListView.builder(
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final item = records[index].data();
                            final time = item['createdAt'];
                            final dateText = time is Timestamp ? time.toDate().toString().substring(0, 16) : 'Recent';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                border: Border.all(color: gold.withOpacity(.55)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${item['targetName'] ?? 'Member'}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                  Text('Action: $action  •  By: ${item['actorName'] ?? 'Room Staff'}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  Text(dateText, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('CLOSE', style: TextStyle(color: gold)),
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

  Future<void> _showRoomSettingsMenu() async {
    if (!await _canManageRoomMembers() || !mounted) return;

    const options = <String>[
      'Leader Permission',
      'Join Fee',
      'Remove Member',
      'Block Member',
      'Room Record',
    ];

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold, width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('ROOM SETTINGS',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ...options.map((option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      if (option == 'Leader Permission') {
                        _showLeaderPermissionScreen();
                      } else if (option == 'Join Fee') {
                        _showJoinFeeSettings();
                      } else if (option == 'Remove Member') {
                        _showRoomMemberPicker(forBlock: false);
                      } else if (option == 'Block Member') {
                        _showBlockMemberListAndPicker();
                      } else if (option == 'Room Record') {
                        _showRoomRecordScreen();
                      }
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 58),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF211923),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: gold.withOpacity(0.8), width: 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(option,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: gold, size: 25),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRoomMemberPicker({required bool forBlock}) async {
    final membersRef = FirebaseFirestore.instance
        .collection('rooms').doc(widget.roomDocumentId).collection('members');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: panel,
        child: SizedBox(
          width: MediaQuery.of(dialogContext).size.width,
          height: MediaQuery.of(dialogContext).size.height,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                children: [
                  Expanded(
                    child: Text(
                      forBlock ? 'SELECT MEMBER TO BLOCK' : 'REMOVE MEMBER',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: membersRef.snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      final docs = snapshot.data!.docs.where((doc) {
                        final d = doc.data();
                        final uid = (d['firebaseUid'] ?? doc.id).toString();
                        final role = (d['role'] ?? '').toString().toLowerCase();
                        return uid != currentUid && role != 'owner' && role != 'leader';
                      }).toList();
                      if (docs.isEmpty) return const Center(child: Text('No members available.', style: TextStyle(color: Colors.white70)));
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final uid = (data['firebaseUid'] ?? doc.id).toString();
                          final name = (data['name'] ?? 'PartyNova User').toString();
                          return ListTile(
                            title: Text(name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('UID: ${(data['userId'] ?? '').toString()}', style: const TextStyle(color: Colors.white60)),
                            trailing: const Icon(Icons.chevron_right, color: gold),
                            onTap: () {
                              Navigator.pop(dialogContext);
                              if (forBlock) {
                                _showBlockMemberScreen(memberFirebaseUid: uid, memberName: name);
                              } else {
                                _showRemoveMemberConfirmation(memberFirebaseUid: uid, memberName: name);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                Align(alignment: Alignment.centerRight, child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CLOSE', style: TextStyle(color: gold)),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showBlockMemberListAndPicker() async {
    // The block list is opened from Room Settings; its existing entries and
    // Unban actions remain available before choosing another member to block.
    await _showBlockMemberScreen(memberFirebaseUid: '', memberName: '');
  }

  Future<void> _changeRoomMemberRole({
    required String memberFirebaseUid,
    required String memberName,
    required String action,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final roomRef = FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomDocumentId);
      final membersRef = roomRef.collection('members');
      final roomSnapshot = await roomRef.get();
      if (!roomSnapshot.exists) {
        throw StateError('Room could not be found.');
      }
      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      final leaderUid =
          (roomData['leaderUid'] ?? roomData['ownerUid'] ?? '').toString();
      final ownerUid = (roomData['ownerUid'] ?? leaderUid).toString();

      if (!await _canManageRoomMembers()) {
        throw StateError('You do not have permission to manage room members.');
      }
      if (action.contains('Deputy Leader') &&
          !await _canAssignDeputyLeader()) {
        throw StateError(
          'Only the app Owner/Admin can change Deputy Leader.',
        );
      }
      if (memberFirebaseUid == leaderUid || memberFirebaseUid == ownerUid) {
        throw StateError(
          'The Room Leader/Owner cannot be changed from this menu.',
        );
      }

      final matching = await membersRef
          .where('firebaseUid', isEqualTo: memberFirebaseUid)
          .limit(1)
          .get();
      final memberRef = matching.docs.isNotEmpty
          ? matching.docs.first.reference
          : membersRef.doc(memberFirebaseUid);

      if (action == 'Remove Member') {
        await _showRemoveMemberConfirmation(
          memberFirebaseUid: memberFirebaseUid,
          memberName: memberName,
        );
        return;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final latestRoom = await transaction.get(roomRef);
        final latestMember = await transaction.get(memberRef);
        if (!latestRoom.exists || !latestMember.exists) {
          throw StateError('Member or room could not be found.');
        }

        final latestRoomData = latestRoom.data() ?? <String, dynamic>{};
        final deputies = <String>{
          ...((latestRoomData['deputyLeaderUids'] as List?) ?? const [])
              .map((value) => value.toString()),
        };
        final legacyDeputy =
            (latestRoomData['deputyLeaderUid'] ?? '').toString();
        if (legacyDeputy.isNotEmpty) deputies.add(legacyDeputy);

        String newRole;
        switch (action) {
          case 'Set Deputy Leader':
            deputies.add(memberFirebaseUid);
            newRole = 'Deputy Leader';
            break;
          case 'Remove Deputy Leader':
            deputies.remove(memberFirebaseUid);
            newRole = 'Member';
            break;
          case 'Set In-Charge':
            deputies.remove(memberFirebaseUid);
            newRole = 'Seat Incharge';
            break;
          case 'Remove In-Charge':
            newRole = 'Member';
            break;
          default:
            throw StateError('Unknown member action: $action');
        }

        transaction.set(memberRef, {
          'firebaseUid': memberFirebaseUid,
          'role': newRole,
          'roleUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(roomRef, {
          'deputyLeaderUids': deputies.toList(),
          'deputyLeaderUid': deputies.isEmpty
              ? FieldValue.delete()
              : deputies.first,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      try {
        await _writeRoomActionRecord(
          action: action,
          targetUid: memberFirebaseUid,
          targetName: memberName,
        );
      } catch (recordError) {
        debugPrint('Room action record write failed: $recordError');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$memberName: $action completed.')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Room member action "$action" failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        final message = error is FirebaseException
            ? '${error.code}: ${error.message ?? 'Firestore operation failed.'}'
            : error.toString().replaceFirst('Bad state: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$action failed: $message'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _showMemberThreeDotMenu({
    required String memberFirebaseUid,
    required String memberName,
    required bool isLeader,
    required bool isDeputy,
    required bool isIncharge,
  }) async {
    if (!await _canManageRoomMembers() || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You do not have permission to manage room members.')),
        );
      }
      return;
    }

    // Deputy Leader is reserved for app Owner/Admin until room upgrades
    // are implemented. Normal room Owners/Leaders only get In-Charge actions.
    final canManageDeputy = await _canAssignDeputyLeader();
    final actions = <String>[
      if (canManageDeputy && !isDeputy) 'Set Deputy Leader',
      if (canManageDeputy && isDeputy) 'Remove Deputy Leader',
      if (!isIncharge) 'Set In-Charge',
      if (isIncharge) 'Remove In-Charge',
      'Remove Member',
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: gold, width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                memberName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...actions.map((action) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: _memberActionButton(
                    label: action,
                    color: action == 'Remove Member'
                        ? Colors.redAccent
                        : action.startsWith('Remove')
                            ? const Color(0xFFFF8A80)
                            : gold,
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _changeRoomMemberRole(
                        memberFirebaseUid: memberFirebaseUid,
                        memberName: memberName,
                        action: action,
                      );
                    },
                  ),
                ),
              )),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: panel,
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color, width: 1),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  Widget _buildMemberTab() {
    if (!_leaderMemberBackfillStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureLeaderMemberRecord();
      });
    }
    final membersRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId)
        .collection('members');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomDocumentId)
          .snapshots(),
      builder: (context, roomSnapshot) {
        final roomData = roomSnapshot.data?.data() ?? <String, dynamic>{};
        final storedLeaderUid = (roomData['leaderUid'] ?? '').toString();
        final actualLeaderUid = storedLeaderUid.isNotEmpty
            ? storedLeaderUid
            : (roomData['ownerUid'] ?? '').toString();
        final actualOwnerUid = (roomData['ownerUid'] ?? '').toString();
        final actualDeputyUid = (roomData['deputyLeaderUid'] ?? '').toString();
        final actualDeputyUids = <String>{
          ...((roomData['deputyLeaderUids'] as List?) ?? const [])
              .map((value) => value.toString()),
          if (actualDeputyUid.isNotEmpty) actualDeputyUid,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: membersRef.snapshots(),
          builder: (context, snapshot) {
            final count = snapshot.data?.docs.length ?? 0;
            final displayCount = count > 1000 ? 1000 : count;
            return Row(
              children: [
                const Text('Member', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Text('$displayCount', style: const TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold)),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 1.5,
                  height: 20,
                  color: Colors.white70,
                ),
                const Text('1000', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: 'Room Settings',
                  onPressed: () async {
                    if (!await _canManageRoomMembers() || !mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You do not have permission to open Room Settings.')),
                      );
                      return;
                    }
                    _showRoomSettingsMenu();
                  },
                  icon: const Icon(Icons.settings_rounded, color: pink, size: 25),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _memberSearchController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          onChanged: (value) => setState(() => _memberSearchQuery = value.trim()),
          decoration: InputDecoration(
            hintText: 'Search member by PartyNova UID',
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, color: pink),
            filled: true,
            fillColor: panel,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: membersRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(padding: EdgeInsets.all(12), child: Text('Members could not be loaded.', style: TextStyle(color: Colors.white70)));
            }
            if (!snapshot.hasData) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: pink)));
            }
            final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';
            final query = _memberSearchQuery;
            final docs = snapshot.data!.docs.where((doc) {
              if (query.isEmpty) return true;
              final data = doc.data();
              return (data['userId'] ?? '').toString().contains(query);
            }).toList();
            // The room document is the single source of truth for role badges.
            // This prevents a stale member role field from making the Leader badge flicker.
            bool isLeaderDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
              final memberData = doc.data();
              final memberUid = (memberData['firebaseUid'] ?? doc.id).toString();
              final memberRole = (memberData['role'] ?? '').toString().toLowerCase();
              return (actualLeaderUid.isNotEmpty && memberUid == actualLeaderUid) ||
                  memberRole == 'leader' ||
                  memberData['isRoomLeader'] == true;
            }
            final originalOrder = <String, int>{for (var i = 0; i < docs.length; i++) docs[i].id: i};
            int memberPriority(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
              if (isLeaderDoc(doc)) return 0;
              final memberData = doc.data();
              final uid = (memberData['firebaseUid'] ?? doc.id).toString();
              final role = (memberData['role'] ?? '').toString().toLowerCase();
              if (actualDeputyUids.contains(uid) || role == 'deputy leader') return 1;
              if (role == 'seat incharge' || role == 'admin') return 2;
              return 3;
            }
            docs.sort((a, b) {
              final priority = memberPriority(a).compareTo(memberPriority(b));
              return priority != 0 ? priority : originalOrder[a.id]!.compareTo(originalOrder[b.id]!);
            });
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text(query.isEmpty ? 'No members yet.' : 'No member found with this PartyNova UID.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final name = (data['name'] ?? 'PartyNova User').toString();
                final userId = (data['userId'] ?? '').toString();
                final joinedAt = data['joinedAt'];
                final joinedDate = joinedAt is Timestamp ? joinedAt.toDate() : null;
                final joinedDays = joinedDate == null ? 0 : DateTime.now().difference(joinedDate).inDays;
                final role = (data['role'] ?? 'Member').toString();
                final memberFirebaseUid = (data['firebaseUid'] ?? docs[index].id).toString();
                final isLeader = (actualLeaderUid.isNotEmpty && memberFirebaseUid == actualLeaderUid) ||
                    role.toLowerCase() == 'leader' ||
                    data['isRoomLeader'] == true;
                final isOwner = actualOwnerUid.isNotEmpty && memberFirebaseUid == actualOwnerUid;
                final isDeputy = actualDeputyUids.contains(memberFirebaseUid) || role.toLowerCase() == 'deputy leader';
                final isIncharge = role.toLowerCase() == 'seat incharge' || role.toLowerCase() == 'admin';
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('publicProfiles').doc(memberFirebaseUid).snapshots(),
                  builder: (context, publicSnapshot) {
                    final publicData = publicSnapshot.data?.data() ?? <String, dynamic>{};
                    final displayName = (publicData['name'] ?? name).toString();
                    final displayUid = (publicData['userId'] ?? userId).toString();
                    final platformRole = resolvePartyNovaRole(userId: displayUid, storedRole: publicData['role']?.toString());
                    final isPlatformPrivileged = platformRole == 'owner' || platformRole == 'admin';
                    return InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text(displayName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                        content: Text('PartyNova UID: $displayUid', style: const TextStyle(color: Colors.black87)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('CANCEL', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              final firebaseUid = (data['firebaseUid'] ?? docs[index].id).toString();
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PartyNovaPublicProfilePage(
                                  firebaseUid: firebaseUid,
                                  hideBlockReport: true,
                                ),
                              ));
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD780), foregroundColor: const Color(0xFF3A210B)),
                            child: const Text('PROFILE', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: isLeader ? gold.withOpacity(0.75) : Colors.white12),
                    boxShadow: isLeader
                        ? [BoxShadow(color: gold.withOpacity(0.16), blurRadius: 12, spreadRadius: 1)]
                        : null,
                  ),
                  child: Row(
                    children: [
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('publicProfiles')
                            .doc(memberFirebaseUid)
                            .snapshots(),
                        builder: (context, profileSnapshot) {
                          final latestPhoto = (publicData['photoBase64'] ?? profileSnapshot.data?.data()?['photoBase64'] ??
                                  data['photoBase64'] ??
                                  '')
                              .toString();
                          return CircleAvatar(
                            radius: 23,
                            backgroundColor: bg,
                            backgroundImage: getCachedProfilePhotoImage(latestPhoto),
                          );
                        },
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!isLeader && !isDeputy && isOwner) ...[
                              const SizedBox(height: 3),
                              const Text(
                                'ROOM OWNER',
                                style: TextStyle(
                                  color: gold,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'UID: $displayUid',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: gold, fontSize: 12),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              joinedDate == null
                                  ? 'Joined recently'
                                  : 'Joined ${joinedDays == 0 ? 1 : joinedDays} day(s) ago',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLeader)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFF2A6),
                                    Color(0xFFFFD700),
                                    Color(0xFFB87900),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFFFF6C7),
                                  width: 0.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: gold.withOpacity(0.55),
                                    blurRadius: 9,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'LEADER',
                                style: TextStyle(
                                  color: Color(0xFF4A2B00),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            )
                          else if (isDeputy)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFB1B1),
                                    Color(0xFFFF3030),
                                    Color(0xFF970000),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFFFDADA),
                                  width: 0.8,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0xAAFF2020),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'DEPUTY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            )
                          else if (isIncharge)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFB8F0FF),
                                    Color(0xFF168BDB),
                                    Color(0xFF064477),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFD8F7FF),
                                  width: 0.8,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0xAA168BDB),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'INCHARGE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          if (isPlatformPrivileged) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFE8A6),
                                    Color(0xFFD9A43B),
                                    Color(0xFFB51F25),
                                    Color(0xFF650B16),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: const Color(0xFFFFE6B8),
                                  width: 0.8,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x99FFB45A),
                                    blurRadius: 9,
                                  ),
                                  BoxShadow(
                                    color: Color(0x88FF2424),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Text(
                                platformRole.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFFFFF4D6),
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                          IconButton(
                            tooltip: 'Member Options',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 36,
                            ),
                            onPressed: () => _showMemberThreeDotMenu(
                              memberFirebaseUid: memberFirebaseUid,
                              memberName: displayName,
                              isLeader: isLeader,
                              isDeputy: isDeputy,
                              isIncharge: isIncharge,
                            ),
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: gold,
                              size: 23,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                    );
                  },
                );
              },
            );
          },
        ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomImage = getCachedProfilePhotoImage(
      _currentRoomPhotoBase64,
    );

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Room profile navigation tabs (pink theme preserved).
              Row(
                children: [
                  _buildTopTab('Profile', 0),
                  _buildTopTab('Member', 1),
                  _buildTopTab('Card', 2),
                ],
              ),

              const SizedBox(height: 24),

              if (_selectedTab == 1)
                _buildMemberTab()
              else ...[
              // Room photo, PartyNova ID and room name.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () async { if (await _isCurrentUserRoomLeader()) _pickRoomPhoto(); },
                    child: Stack(
                      children: [
                  Container(
                    width: 116,
                    height: 116,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: pink, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: pink.withOpacity(0.20),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: roomImage == null
                          ? const ColoredBox(
                              color: panel,
                              child: Icon(
                                Icons.groups_rounded,
                                color: pink,
                                size: 65,
                              ),
                            )
                          : Image(
                              image: roomImage,
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: FutureBuilder<bool>(
                          future: _isCurrentUserRoomLeader(),
                          builder: (context, snapshot) => snapshot.data == true
                              ? Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(color: pink, shape: BoxShape.circle),
                                  child: const Icon(Icons.edit, color: Colors.white, size: 15),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'ID: ',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                widget.roomUid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: gold,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _copyRoomId,
                              icon: const Icon(
                                Icons.copy_rounded,
                                color: pink,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _editRoomText(editName: true),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _currentRoomName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _buildLeaderEditIcon(
                                onPressed: () => _editRoomText(editName: true),
                                tooltip: 'Edit room name',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Room level.
              _buildRoomLevel(),

              const SizedBox(height: 23),

              // Language selector.
              _buildLanguageSelector(),

              const SizedBox(height: 22),

              // Room description.
              _buildDescription(),

              const SizedBox(height: 26),

              // Club name, Club Point and Member Point (future level system).
              _buildPoints(),

              if (_selectedTab == 0) ...[
                const SizedBox(height: 25),
                _buildProfileMembershipAction(),
              ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
                                      
        





class _FourCornerFramePainter extends CustomPainter {
  final Color color;
  const _FourCornerFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.95)..strokeWidth = 2.2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const length = 9.0;
    const inset = 4.0;
    final paths = <Path>[
      Path()..moveTo(inset, inset + length)..lineTo(inset, inset)..lineTo(inset + length, inset),
      Path()..moveTo(size.width - inset - length, inset)..lineTo(size.width - inset, inset)..lineTo(size.width - inset, inset + length),
      Path()..moveTo(inset, size.height - inset - length)..lineTo(inset, size.height - inset)..lineTo(inset + length, size.height - inset),
      Path()..moveTo(size.width - inset - length, size.height - inset)..lineTo(size.width - inset, size.height - inset)..lineTo(size.width - inset, size.height - inset - length),
    ];
    for (final path in paths) { canvas.drawPath(path, paint); }
  }

  @override
  bool shouldRepaint(covariant _FourCornerFramePainter oldDelegate) => oldDelegate.color != color;
}

class PartyRoomScreen extends StatefulWidget {
  final String roomName;
  final String roomUid;
  final String roomPhotoBase64;
  final String roomDocumentId;

  const PartyRoomScreen({
    super.key,
    required this.roomName,
    required this.roomUid,
    this.roomPhotoBase64 = '',
    required this.roomDocumentId,
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
  bool _showLeaveOptions = false;
  Timer? _presenceHeartbeat;

  DocumentReference<Map<String, dynamic>>? get _myRoomPresenceRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId)
        .collection('presence')
        .doc(user.uid);
  }

  Future<void> _ensureCreatorLeaderMemberRecord() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final roomRef = firestore.collection('rooms').doc(widget.roomDocumentId);
      final roomSnapshot = await roomRef.get();
      if (!roomSnapshot.exists) return;
      final roomData = roomSnapshot.data() ?? <String, dynamic>{};
      final ownerUid = (roomData['ownerUid'] ?? '').toString();
      var leaderUid = (roomData['leaderUid'] ?? '').toString();
      if (leaderUid.isEmpty && ownerUid == user.uid) {
        await roomRef.update({'leaderUid': user.uid});
        leaderUid = user.uid;
      }
      // Only the actual Leader/creator can backfill their own Leader record.
      if (leaderUid != user.uid) return;

      final userRef = firestore.collection('users').doc(user.uid);
      final userSnapshot = await userRef.get();
      final profile = userSnapshot.data() ?? <String, dynamic>{};
      var partyNovaUid = (profile['userId'] ?? '').toString().trim();
      if (partyNovaUid.isEmpty) {
        partyNovaUid = await assignPartyNovaUserId(user);
      }
      final leaderMemberRef = roomRef.collection('members').doc(user.uid);
      final leaderMemberSnapshot = await leaderMemberRef.get();
      await leaderMemberRef.set({
        'firebaseUid': user.uid,
        'userId': partyNovaUid,
        'name': (profile['name'] ?? user.displayName ?? 'PartyNova User').toString(),
        'photoBase64': (profile['photoBase64'] ?? '').toString(),
        'clubName': (roomData['clubName'] ?? '').toString(),
        'role': 'Leader',
        'isRoomLeader': true,
        if (!leaderMemberSnapshot.exists) 'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Automatic Leader member setup failed: $error');
    }
  }

  Future<void> _startRoomPresence() async {
    final user = FirebaseAuth.instance.currentUser;
    final presenceRef = _myRoomPresenceRef;
    if (user == null || presenceRef == null) return;

    // Repair older rooms independently of the presence write result.
    unawaited(_ensureCreatorLeaderMemberRecord());

    try {
      // Publish presence first so the user appears even if profile loading is slow.
      await presenceRef.set({
        'firebaseUid': user.uid,
        'name': user.displayName ?? 'PartyNova User',
        'photoBase64': '',
        'role': resolvePartyNovaRole(email: user.email),
        'enteredAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Add the latest profile information after presence is already active.
      try {
        final userSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final profile = userSnapshot.data() ?? <String, dynamic>{};
        final profileName =
            (profile['name'] ?? user.displayName ?? 'PartyNova User').toString();
        final profilePhoto = (profile['photoBase64'] ?? '').toString();
        final profileUserId = (profile['userId'] ?? '').toString();
        final profileRole = resolvePartyNovaRole(
          email: user.email,
          userId: profileUserId,
          storedRole: profile['role']?.toString(),
        );

        await presenceRef.set({
          'firebaseUid': user.uid,
          'userId': profileUserId,
          'name': profileName,
          'photoBase64': profilePhoto,
          'role': profileRole,
          'lastSeenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (profileError) {
        debugPrint('Room presence profile enrichment failed: $profileError');
      }

      _presenceHeartbeat?.cancel();
      _presenceHeartbeat = Timer.periodic(const Duration(seconds: 45), (_) {
        presenceRef.set({
          'firebaseUid': user.uid,
          'lastSeenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((error) {
          debugPrint('Room presence heartbeat failed: $error');
        });
      });
    } catch (error) {
      debugPrint('Room presence start failed: $error');
    }
  }

  Future<void> _leaveRoomPresence() async {
    _presenceHeartbeat?.cancel();
    final presenceRef = _myRoomPresenceRef;
    if (presenceRef == null) return;
    try {
      await presenceRef.delete();
    } catch (error) {
      debugPrint('Room presence cleanup failed: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _startRoomPresence();
  }

  Future<void> _joinRoom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) throw StateError('Your PartyNova profile was not found.');
      final profile = userDoc.data() ?? <String, dynamic>{};
      await syncPartyNovaPublicProfile(user);
      final partyNovaUid = (profile['userId'] ?? '').toString();
      if (!RegExp(r'^(?:[0-9]{6}|[0-9]{8}|[0-9]{10})$').hasMatch(partyNovaUid)) {
        throw StateError('Your PartyNova UID is invalid.');
      }
      final roomRef = firestore.collection('rooms').doc(widget.roomDocumentId);
      final memberRef = roomRef.collection('members').doc(user.uid);
      await firestore.runTransaction((transaction) async {
        final roomSnapshot = await transaction.get(roomRef);
        final memberSnapshot = await transaction.get(memberRef);
        if (!roomSnapshot.exists) throw StateError('Room not found.');
        final roomData = roomSnapshot.data() ?? <String, dynamic>{};
        final leaderUid = (roomData['leaderUid'] ?? '').toString();
        final ownerUid = (roomData['ownerUid'] ?? '').toString();
        if ((leaderUid.isNotEmpty ? leaderUid : ownerUid) == user.uid) return;
        if (memberSnapshot.exists) return;
        final currentCount = (roomData['memberCount'] as num?)?.toInt() ?? 0;
        if (currentCount >= 1000) {
          throw StateError('This room has reached its 1000-member limit.');
        }
        transaction.set(memberRef, {
          'firebaseUid': user.uid,
          'userId': partyNovaUid,
          'name': (profile['name'] ?? 'PartyNova User').toString(),
          'photoBase64': (profile['photoBase64'] ?? '').toString(),
          'clubName': (roomData['clubName'] ?? '').toString(),
          'role': 'Member',
          'joinedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(roomRef, {
          'memberCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You joined the room as a Member.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join room: $error')),
      );
    }
  }

  Future<void> _unjoinRoom() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final roomRef = firestore.collection('rooms').doc(widget.roomDocumentId);
      final memberRef = roomRef.collection('members').doc(user.uid);
      await firestore.runTransaction((transaction) async {
        final roomSnapshot = await transaction.get(roomRef);
        final memberSnapshot = await transaction.get(memberRef);
        if (!roomSnapshot.exists || !memberSnapshot.exists) return;
        final roomData = roomSnapshot.data() ?? <String, dynamic>{};
        final memberData = memberSnapshot.data() ?? <String, dynamic>{};
        final leaderUid = (roomData['leaderUid'] ?? '').toString();
        final ownerUid = (roomData['ownerUid'] ?? '').toString();
        if (user.uid == leaderUid || user.uid == ownerUid ||
            (memberData['role'] ?? '').toString().toLowerCase() == 'leader' ||
            (memberData['role'] ?? '').toString().toLowerCase() == 'owner') {
          throw StateError('The room Owner/Leader cannot unjoin their own room.');
        }
        transaction.delete(memberRef);
        final currentCount = (roomData['memberCount'] as num?)?.toInt() ?? 0;
        transaction.update(roomRef, {
          if (currentCount > 0) 'memberCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the room.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not leave room: $error')),
      );
    }
  }

  Widget _buildMembershipFrame(String label, {required bool leader}) {
    final colors = leader
        ? const [Color(0xFFFFE7B0), Color(0xFFB87333), Color(0xFF5B2E0B), Color(0xFFD79A55)]
        : const [Color(0xFFFFE9A6), Color(0xFFD6A83C), Color(0xFF8A5A12), Color(0xFFFFD780)];
    return Container(
      width: 58,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE6B8), width: 1.3),
        boxShadow: [
          BoxShadow(color: leader ? const Color(0xFFFFB45A) : gold, blurRadius: 13, spreadRadius: 1),
          BoxShadow(color: Colors.white.withOpacity(0.22), blurRadius: 4, spreadRadius: 1),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _FourCornerFramePainter(color: const Color(0xFFFFF1D2)))),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (leader) const Icon(Icons.workspace_premium_rounded, color: Color(0xFF4A2508), size: 17),
            if (leader) const SizedBox(width: 3),
            Text(label, style: const TextStyle(color: Color(0xFF3A210B), fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8)),
          ]),
        ],
      ),
    );
  }

  Widget _buildLeaderStatueIcon() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE2A3), Color(0xFFB87333), Color(0xFF5B2E0B)],
        ),
        border: Border.all(color: const Color(0xFFFFE6B8), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0xFFFFB45A), blurRadius: 13, spreadRadius: 1),
          BoxShadow(color: Color(0x66FFFFFF), blurRadius: 4, spreadRadius: 1),
        ],
      ),
      child: const Icon(
        Icons.person_rounded,
        color: Color(0xFFFFF0D0),
        size: 24,
      ),
    );
  }

  Widget _buildRoomOwnerAdminBadge() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final roomRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomDocumentId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final ownerUid = (data['ownerUid'] ?? '').toString();
        final leaderUid = (data['leaderUid'] ?? '').toString();
        final isOwnRoom = user.uid == ownerUid ||
            (leaderUid.isNotEmpty && user.uid == leaderUid);
        if (!isOwnRoom) return const SizedBox.shrink();
        final role = partyNovaRoleForEmail(user.email);
        if (role != 'owner' && role != 'admin') return const SizedBox.shrink();
        final label = role == 'owner' ? 'OWNER' : 'ADMIN';
        return Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF7777), Color(0xFFE01832), Color(0xFF850014)],
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFFFC4C4), width: 0.9),
            boxShadow: const [
              BoxShadow(color: Color(0x99FF2020), blurRadius: 9, spreadRadius: 1),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderMembershipAction() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final roomRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomDocumentId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: roomRef.snapshots(),
      builder: (context, roomSnapshot) {
        final roomData = roomSnapshot.data?.data() ?? <String, dynamic>{};
        final leaderUid = (roomData['leaderUid'] ?? '').toString();
        final ownerUid = (roomData['ownerUid'] ?? '').toString();
        final actualLeaderUid = leaderUid.isNotEmpty ? leaderUid : ownerUid;
        if (user.uid == actualLeaderUid) {
          return _buildLeaderStatueIcon();
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: roomRef.collection('members').doc(user.uid).snapshots(),
          builder: (context, memberSnapshot) {
            if (memberSnapshot.data?.exists == true) {
              return _buildMembershipFrame('1', leader: false);
            }
            return SizedBox(
              width: 58,
              height: 42,
              child: ElevatedButton(
                onPressed: _joinRoom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: const Color(0xFF4A2B00),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFFFFF0A6), width: 1.4),
                  ),
                  elevation: 9,
                  shadowColor: const Color(0xFFFFD700),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(child: CustomPaint(painter: _FourCornerFramePainter(color: const Color(0xFFFFF7CF)))),
                  const Text('JOIN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8)),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _presenceHeartbeat?.cancel();
    unawaited(_leaveRoomPresence());
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
                  color: Colors.black,
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

  Widget _buildOnlineUsersStrip() {
    final presenceRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomDocumentId)
        .collection('presence');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: presenceRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(height: 42);
        }

        final now = DateTime.now();
        final onlineDocs = snapshot.data!.docs.where((doc) {
          final lastSeen = doc.data()['lastSeenAt'];
          if (lastSeen is! Timestamp) return false;
          return now.difference(lastSeen.toDate()) <= const Duration(minutes: 2);
        }).toList()
          ..sort((a, b) {
            final aEntered = a.data()['enteredAt'];
            final bEntered = b.data()['enteredAt'];
            if (aEntered is Timestamp && bEntered is Timestamp) {
              return aEntered.compareTo(bEntered);
            }
            return a.id.compareTo(b.id);
          });

        final visibleDocs = onlineDocs.take(5).toList();
        final hasMore = onlineDocs.length > 5;

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 9),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                for (final doc in visibleDocs)
                  GestureDetector(
                    onTap: () {
                      final uid = (doc.data()['firebaseUid'] ?? doc.id).toString();
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PartyNovaPublicProfilePage(firebaseUid: uid),
                      ));
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF1688), width: 1.5),
                      ),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: const Color(0xFF171017),
                        backgroundImage: getCachedProfilePhotoImage(
                          (doc.data()['photoBase64'] ?? '').toString(),
                        ),
                        child: getCachedProfilePhotoImage(
                          (doc.data()['photoBase64'] ?? '').toString(),
                        ) == null
                            ? const Icon(Icons.person_rounded, color: Colors.white70, size: 18)
                            : null,
                      ),
                    ),
                  ),
                if (hasMore)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PartyRoomOnlineUsersPage(
                          roomDocumentId: widget.roomDocumentId,
                        ),
                      ));
                    },
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFF1688), width: 1.5),
                      ),
                      child: const Text(
                        'USERS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
          children: [
            // Room header.
Padding(
  padding: const EdgeInsets.fromLTRB(0, 8, 6, 6),
  child: Row(
    children: [
      // Room DP - tap to open Room Details.
InkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: darkBlue,
          body: SafeArea(
            child: RoomDetailsOverview(
  roomName: widget.roomName,
  roomUid: widget.roomUid,
  roomPhotoBase64: widget.roomPhotoBase64,
  roomDocumentId: widget.roomDocumentId,
),
          ),
        ),
      ),
    );
  },
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 82,
      height: 82,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('rooms')
            .doc(widget.roomDocumentId)
            .snapshots(),
        builder: (context, snapshot) {
          final roomData = snapshot.data?.data() ?? <String, dynamic>{};
          final livePhoto = (roomData['roomPhotoBase64'] ??
                  widget.roomPhotoBase64)
              .toString();
          final liveImage = getCachedProfilePhotoImage(livePhoto);
          if (liveImage != null) {
            return Image(
              image: liveImage,
              width: 82,
              height: 82,
              fit: BoxFit.cover,
            );
          }
          final creatorUid = (roomData['leaderUid'] ?? roomData['ownerUid'] ?? '').toString();
          if (creatorUid.isEmpty) {
            return const Icon(Icons.groups_rounded, color: gold, size: 48);
          }
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('publicProfiles')
                .doc(creatorUid)
                .snapshots(),
            builder: (context, profileSnapshot) {
              final profilePhoto = (profileSnapshot.data?.data()?['photoBase64'] ?? '').toString();
              final fallbackImage = getCachedProfilePhotoImage(profilePhoto);
              return fallbackImage == null
                  ? const Icon(Icons.groups_rounded, color: gold, size: 48)
                  : Image(image: fallbackImage, width: 82, height: 82, fit: BoxFit.cover);
            },
          );
        },
      ),
    ),
  ),
),

      const SizedBox(width: 8),

      // Name background and JOIN area.
      Expanded(
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 54,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.white.withValues(alpha: 0.07),
                panelBlue,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.20),
                blurRadius: 15,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              // Scrolling room name and UID.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance
                                .collection('rooms')
                                .doc(widget.roomDocumentId)
                                .snapshots(),
                            builder: (context, snapshot) => ScrollingRoomName(
                              text: (snapshot.data?.data()?['roomName'] ??
                                      widget.roomName)
                                  .toString(),
                            ),
                          ),
                        ),
                        _buildRoomOwnerAdminBadge(),
                      ],
                    ),
                    const SizedBox(height: 5),
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

              const SizedBox(width: 6),
              _buildHeaderMembershipAction(),
            ],
          ),
        ),
      ),

      const SizedBox(width: 5),

      // Room options and leave buttons.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () {},
            tooltip: 'Room options',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 46,
            ),
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 35,
            ),
          ),
          const SizedBox(width: 7),
          IconButton(
            onPressed: () {
              setState(() => _showLeaveOptions = true);
            },
            tooltip: 'Room options',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 46,
            ),
            icon: const Icon(
              Icons.power_settings_new_rounded,
              color: gold,
              size: 32,
            ),
          ),
        ],
      ),
    ],
  ),
),
            
                                

            // Online users appear below the room header and above the mic seats.
            _buildOnlineUsersStrip(),

            // Fifteen seats: three rows of five.
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 64, 5, 0),
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

            // Permanent PartyNova welcome message in every room.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 7),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF17112E).withOpacity(0.94),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFF8D65D8).withOpacity(0.35)),
                ),
                child: const Text(
                  'Welcome to PartyNova. Please respect each other and keep the room friendly.',
                  style: TextStyle(
                    color: Color(0xFF62D6B4), fontSize: 14,
                    fontWeight: FontWeight.w800, height: 1.35,
                  ),
                ),
              ),
            ),

            // Saved room rules/description shown in a separate box for everyone.
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .doc(widget.roomDocumentId)
                  .snapshots(),
              builder: (context, snapshot) {
                final description = (snapshot.data?.data()?['roomDescription'] ?? '')
                    .toString().trim();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 7),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17112E).withOpacity(0.94),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFF8D65D8).withOpacity(0.30)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Description', style: TextStyle(
                          color: Color(0xFFFFD84D), fontSize: 15,
                          fontWeight: FontWeight.w900,
                        )),
                        const SizedBox(height: 7),
                        Text(
                          description.isEmpty ? 'Room rules will appear here.' : description,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 14,
                            fontWeight: FontWeight.w600, height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Remaining ro            _buildBottomBar(),
          ],
        ),
      ),
          if (_showLeaveOptions) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showLeaveOptions = false),
                child: const ColoredBox(color: Color(0xE6000000)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 34,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _showLeaveOptions = false),
                      borderRadius: BorderRadius.circular(60),
                      child: Column(
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFFF1688), width: 3),
                              boxShadow: const [
                                BoxShadow(color: Color(0x66FF1688), blurRadius: 13, spreadRadius: 1),
                              ],
                            ),
                            child: const Icon(Icons.file_upload_rounded, color: Colors.white, size: 43),
                          ),
                          const SizedBox(height: 7),
                          const Text('Keep', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    InkWell(
                      onTap: () async {
                        setState(() => _showLeaveOptions = false);
                        await _leaveRoomPresence();
                        if (mounted) Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(60),
                      child: Column(
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFFF1688), width: 3),
                              boxShadow: const [
                                BoxShadow(color: Color(0x66FF1688), blurRadius: 13, spreadRadius: 1),
                              ],
                            ),
                            child: const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 43),
                          ),
                          const SizedBox(height: 7),
                          const Text('Exit', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PartyRoomOnlineUsersPage extends StatelessWidget {
  final String roomDocumentId;

  const PartyRoomOnlineUsersPage({
    super.key,
    required this.roomDocumentId,
  });

  @override
  Widget build(BuildContext context) {
    final presenceRef = FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomDocumentId)
        .collection('presence');

    return Scaffold(
      backgroundColor: const Color(0xFF100810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF24101F),
        foregroundColor: const Color(0xFFFFD700),
        title: const Text(
          'Online Users',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: presenceRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Could not load online users.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFFD700),
              ),
            );
          }

          final now = DateTime.now();
          final onlineDocs = snapshot.data!.docs.where((doc) {
            final lastSeen = doc.data()['lastSeenAt'];
            if (lastSeen is! Timestamp) return false;
            return now.difference(lastSeen.toDate()) <=
                const Duration(minutes: 2);
          }).toList()
            ..sort((a, b) {
              final aEntered = a.data()['enteredAt'];
              final bEntered = b.data()['enteredAt'];
              if (aEntered is Timestamp && bEntered is Timestamp) {
                return aEntered.compareTo(bEntered);
              }
              return a.id.compareTo(b.id);
            });

          if (onlineDocs.length > 1000) onlineDocs.removeRange(1000, onlineDocs.length);

          if (onlineDocs.isEmpty) {
            return const Center(
              child: Text(
                'No users are online right now.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: onlineDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = onlineDocs[index];
              final data = doc.data();
              final firebaseUid =
                  (data['firebaseUid'] ?? doc.id).toString();
              final name = (data['name'] ?? 'PartyNova User').toString();
              final role = (data['role'] ?? 'user').toString();
              final photo = (data['photoBase64'] ?? '').toString();
              final photoImage = getCachedProfilePhotoImage(photo);

              return Material(
                color: const Color(0xFF24101F),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PartyNovaPublicProfilePage(
                          firebaseUid: firebaseUid,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFF1688), width: 1.5),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 9),
                        CircleAvatar(
                          radius: 23,
                          backgroundColor: const Color(0xFF100810),
                          backgroundImage: photoImage,
                          child: photoImage == null
                              ? const Icon(Icons.person_rounded, color: Colors.white70)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          role.toUpperCase() == 'USER'
                              ? 'ONLINE'
                              : role.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.circle,
                          color: Color(0xFF42D98A),
                          size: 9,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ScrollingRoomName extends StatefulWidget {
  final String text;

  const ScrollingRoomName({
    super.key,
    required this.text,
  });

  @override
  State<ScrollingRoomName> createState() =>
      _ScrollingRoomNameState();
}

class _ScrollingRoomNameState
    extends State<ScrollingRoomName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.text.length > 30
        ? widget.text.substring(0, 30)
        : widget.text;

    const textStyle = TextStyle(
      color: Color(0xFFFFD780),
      fontSize: 21,
      fontWeight: FontWeight.w900,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: displayName,
            style: textStyle,
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final textWidth = painter.width;

        if (textWidth <= constraints.maxWidth) {
          return SizedBox(
            height: 27,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayName,
                maxLines: 1,
                style: textStyle,
              ),
            ),
          );
        }

        const gap = 45.0;
        final distance = textWidth + gap;

        return SizedBox(
          height: 27,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset =
                    _controller.value * distance;

                return Transform.translate(
                  offset: Offset(-offset, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: textWidth,
                        child: Text(
                          displayName,
                          maxLines: 1,
                          softWrap: false,
                          style: textStyle,
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: textWidth,
                        child: Text(
                          displayName,
                          maxLines: 1,
                          softWrap: false,
                          style: textStyle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
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


Future<void> _sendFriendRequest({
  required String receiverFirebaseUid,
  required String receiverPartyNovaUid,
  required String receiverName,
  required String receiverPhotoBase64,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser == null) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please log in first.')),
    );
    return;
  }

  if (currentUser.uid == receiverFirebaseUid) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You cannot add yourself.')),
    );
    return;
  }

  try {
    final firestore = FirebaseFirestore.instance;

    final senderProfile = await firestore
        .collection('publicProfiles')
        .doc(currentUser.uid)
        .get();

    if (!senderProfile.exists) {
      throw Exception('Your public profile was not found.');
    }

    final senderData = senderProfile.data()!;
    final senderPartyNovaUid =
        (senderData['userId'] ?? '').toString();
    final senderName =
        (senderData['name'] ?? 'PartyNova User').toString();
    final senderPhotoBase64 =
        (senderData['photoBase64'] ?? '').toString();

    if (senderPartyNovaUid.isEmpty) {
      throw Exception('Your PartyNova ID was not found.');
    }

    final requestId = '${currentUser.uid}_$receiverFirebaseUid';
    final reverseRequestId = '${receiverFirebaseUid}_${currentUser.uid}';

    final requestRef =
        firestore.collection('friendRequests').doc(requestId);
    final reverseRequestRef =
        firestore.collection('friendRequests').doc(reverseRequestId);

    final existingRequest = await requestRef.get();

    if (existingRequest.exists) {
      final status = existingRequest.data()?['status'];

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'pending'
                ? 'Friend request already sent.'
                : status == 'accepted'
                    ? 'You are already friends.'
                    : 'A request already exists.',
          ),
        ),
      );
      return;
    }

    final reverseRequest = await reverseRequestRef.get();

    if (reverseRequest.exists &&
        reverseRequest.data()?['status'] == 'pending') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This user has already sent you a request.',
          ),
        ),
      );
      return;
    }

    await requestRef.set({
      'senderUid': currentUser.uid,
      'receiverUid': receiverFirebaseUid,
      'senderPartyNovaUid': senderPartyNovaUid,
      'receiverPartyNovaUid': receiverPartyNovaUid,
      'senderName': senderName,
      'senderPhotoBase64': senderPhotoBase64,
      'receiverName': receiverName,
      'receiverPhotoBase64': receiverPhotoBase64,
      'status': 'pending',
      'seenByReceiver': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend request sent successfully.')),
    );
  } catch (e) {
    debugPrint('Send friend request error: $e');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not send request. Please try again.',
        ),
      ),
    );
  }
}

Widget _buildSearchResult() {
  final query = _query.trim();
  final currentUser = FirebaseAuth.instance.currentUser;

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

  if (currentUser == null) {
    return const Center(
      child: Text(
        'Please log in first.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    key: ValueKey(query),
    future: FirebaseFirestore.instance
        .collection('publicProfiles')
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
            style: TextStyle(color: Colors.redAccent),
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

      final profileDoc = snapshot.data!.docs.first;
      final userData = profileDoc.data();
      final receiverFirebaseUid = profileDoc.id;

      if (receiverFirebaseUid == currentUser.uid) {
        return const Center(
          child: Text(
            'This is your profile.',
            style: TextStyle(color: Colors.white70),
          ),
        );
      }

      final partyNovaUid = (userData['userId'] ?? '').toString();
      final name = (userData['name'] ?? 'PartyNova User').toString();
      final photoBase64 = (userData['photoBase64'] ?? '').toString();
      final photoBytes = getCachedProfilePhoto(photoBase64);

      return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
        future: Future.wait([
          FirebaseFirestore.instance
              .collection('friendRequests')
              .where('senderUid', isEqualTo: currentUser.uid)
              .where('receiverUid', isEqualTo: receiverFirebaseUid)
              .get(),
          FirebaseFirestore.instance
              .collection('friendRequests')
              .where('senderUid', isEqualTo: receiverFirebaseUid)
              .where('receiverUid', isEqualTo: currentUser.uid)
              .get(),
        ]),
        builder: (context, requestSnapshot) {
          if (requestSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: gold),
            );
          }

          if (requestSnapshot.hasError) {
            return const Center(
              child: Text(
                'Could not check friend status. Please try again.',
                style: TextStyle(color: Colors.redAccent),
              ),
            );
          }

          final outgoingDocs = requestSnapshot.data![0].docs;
          final incomingDocs = requestSnapshot.data![1].docs;
          final allRequests = [...outgoingDocs, ...incomingDocs];

          final alreadyFriends = allRequests.any(
            (doc) => doc.data()['status'] == 'accepted',
          );

          final requestPending = allRequests.any(
            (doc) => doc.data()['status'] == 'pending',
          );

          // Open the searched user's public profile.
          void openUserProfile() {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyNovaPublicProfilePage(
                  firebaseUid: receiverFirebaseUid,
                ),
              ),
            );
          }

          return Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Tap the DP to open the user's profile.
                InkWell(
                  onTap: openUserProfile,
                  borderRadius: BorderRadius.circular(30),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage:
                        photoBytes != null ? MemoryImage(photoBytes) : null,
                    child: photoBytes == null
                        ? const Icon(
                            Icons.person_rounded,
                            color: Colors.grey,
                            size: 25,
                          )
                        : null,
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tap the name to open the same profile.
                      InkWell(
                        onTap: openUserProfile,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'ID: $partyNovaUid',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                if (alreadyFriends)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Friends',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (requestPending)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Request Pending',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _sendFriendRequest(
                          receiverFirebaseUid: receiverFirebaseUid,
                          receiverPartyNovaUid: partyNovaUid,
                          receiverName: name,
                          receiverPhotoBase64: photoBase64,
                        );
                      },
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 16,
                      ),
                      label: const Text(
                        'Send Request',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: darkBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
          _buildSearchResult(),
        ],
      ),
    );
  }
}

// Social and friend-request widgets (kept at top level to avoid nested-class syntax errors).
class _SocialBottomNavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _SocialBottomNavIcon({
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Icon(
        icon,
        color: selected
            ? const Color(0xFFFFD700)
            : Colors.white54,
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, conversationSnapshot) {
        final unreadMessageCount =
            (conversationSnapshot.data?.docs ?? const [])
                .fold<int>(0, (total, doc) {
          final counts = Map<String, dynamic>.from(
            doc.data()['unreadCounts'] ?? {},
          );

          return total +
              ((counts[uid] as num?)?.toInt() ?? 0);
        });

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('friendRequests')
              .where('receiverUid', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, requestSnapshot) {
            final requestCount = requestSnapshot.data?.docs
                    .where(
                      (doc) =>
                          doc.data()['seenByReceiver'] != true,
                    )
                    .length ??
                0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFFFFD700)
                      : Colors.white54,
                ),

                if (requestCount > 0)
                  Positioned(
                    right: -10,
                    top: -7,
                    child: _RequestCountBadge(
                      count: requestCount,
                    ),
                  ),

                if (unreadMessageCount > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SocialBottomNavLabel extends StatelessWidget {
  final bool selected;
  const _SocialBottomNavLabel({required this.selected});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Text('Social', style: TextStyle(fontSize: 10, color: selected ? const Color(0xFFFFD700) : Colors.white54));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, conversationSnapshot) {
        final hasUnreadMessages = conversationSnapshot.data?.docs.any((doc) {
          final counts = Map<String, dynamic>.from(doc.data()['unreadCounts'] ?? {});
          return ((counts[uid] as num?)?.toInt() ?? 0) > 0;
        }) ?? false;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('friendRequests')
              .where('receiverUid', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, requestSnapshot) {
            final count = requestSnapshot.data?.docs
                    .where((doc) => doc.data()['seenByReceiver'] != true)
                    .length ?? 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Social', maxLines: 1, style: TextStyle(fontSize: 10, color: selected ? const Color(0xFFFFD700) : Colors.white54)),
                if (count > 0 || hasUnreadMessages) ...[
                  const SizedBox(width: 3),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _RequestCountBadge extends StatelessWidget {
  final int count;
  const _RequestCountBadge({required this.count});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        child: Center(
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      );
}



class PartyNovaSocialTab extends StatefulWidget {
  const PartyNovaSocialTab({super.key});

  @override
  State<PartyNovaSocialTab> createState() => _PartyNovaSocialTabState();
}

class _PartyNovaSocialTabState extends State<PartyNovaSocialTab>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  bool _markingSeen = false;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
    _controller.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTabChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_controller.indexIsChanging && _controller.index == 2) {
      _markIncomingRequestsSeen();
    }
  }

  Future<void> _markIncomingRequestsSeen() async {
    if (_markingSeen) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _markingSeen = true;

    try {
      final requests = await FirebaseFirestore.instance
          .collection('friendRequests')
          .where('receiverUid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();

      final unseen = requests.docs
          .where((doc) => doc.data()['seenByReceiver'] != true)
          .toList();

      for (var i = 0; i < unseen.length; i += 400) {
        final batch = FirebaseFirestore.instance.batch();

        for (final doc in unseen.skip(i).take(400)) {
          batch.update(doc.reference, {
            'seenByReceiver': true,
            'seenAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
      }
    } catch (e) {
      debugPrint('Mark friend requests seen error: $e');
    } finally {
      _markingSeen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const black = Color(0xFF09070B);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _controller,
              indicatorColor: black,
              indicatorWeight: 3,
              labelColor: black,
              unselectedLabelColor: Colors.black54,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              tabs: [
                const Tab(text: 'Friend List'),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('conversations')
                      .where(
                        'participants',
                        arrayContains:
                            FirebaseAuth.instance.currentUser?.uid,
                      )
                      .snapshots(),
                  builder: (context, snapshot) {
                    final uid = FirebaseAuth.instance.currentUser?.uid;

                    final count = uid == null
                        ? 0
                        : (snapshot.data?.docs ?? []).fold<int>(
                            0,
                            (total, doc) {
                              final counts = Map<String, dynamic>.from(
                                doc.data()['unreadCounts'] ?? {},
                              );

                              return total +
                                  ((counts[uid] as num?)?.toInt() ?? 0);
                            },
                          );

                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Message List'),
                          if (count > 0) ...[
                            const SizedBox(width: 5),
                            _RequestCountBadge(count: count),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _incomingPendingStream(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs
                            .where(
                              (doc) =>
                                  doc.data()['seenByReceiver'] != true,
                            )
                            .length ??
                        0;

                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Friend Request'),
                          if (count > 0) ...[
                            const SizedBox(width: 5),
                            _RequestCountBadge(count: count),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: const [
                _FriendsListSection(),
                _MessagesListSection(),
                _IncomingRequestsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


        
                

Stream<QuerySnapshot<Map<String, dynamic>>> _incomingPendingStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return const Stream.empty();
  }
  return FirebaseFirestore.instance
      .collection('friendRequests')
      .where('receiverUid', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .snapshots();
}

class _SocialEmptySection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const _SocialEmptySection({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEAF8FF),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF09070B), fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFFFF1688), size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Text(subtitle, style: const TextStyle(color: Color(0xFF09070B), fontSize: 15))),
                ],
              ),
            ),
          ],
        ),
      );
}

class _IncomingRequestsSection extends StatefulWidget {
  const _IncomingRequestsSection();

  @override
  State<_IncomingRequestsSection> createState() => _IncomingRequestsSectionState();
}

class _IncomingRequestsSectionState extends State<_IncomingRequestsSection> {
  bool _working = false;

  Future<void> _respond(DocumentSnapshot<Map<String, dynamic>> doc, String status) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await doc.reference.update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'seenByReceiver': true,
        'seenAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 'accepted' ? 'Friend added successfully.' : 'Friend request rejected.')),
      );
    } catch (e) {
      debugPrint('Respond to friend request error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update request. Check Firestore rules.')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Please log in again.'));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _incomingPendingStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Could not load requests. Check Firestore rules.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF1688)));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const _SocialEmptySection(title: 'Friend Requests', subtitle: 'No pending friend requests.', icon: Icons.person_add_alt_1_rounded);
        }
        return Container(
          color: const Color(0xFFEAF8FF),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final senderUid = (data['senderUid'] ?? '').toString();
              final name = (data['senderName'] ?? 'PartyNova User').toString();
              final partyId = (data['senderPartyNovaUid'] ?? '').toString();
              final photo = (data['senderPhotoBase64'] ?? '').toString();
              final photoImage = getCachedProfilePhotoImage(photo);
              return Container(
                key: ValueKey<String>(doc.id),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFFF1688).withValues(alpha: 0.35))),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: senderUid.isEmpty ? null : () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PartyNovaPublicProfilePage(firebaseUid: senderUid)));
                      },
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFEDEDED),
                        backgroundImage: photoImage,
                        child: photoImage == null ? const Icon(Icons.person_rounded, color: Colors.black54) : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: senderUid.isEmpty ? null : () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PartyNovaPublicProfilePage(firebaseUid: senderUid)));
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text('ID: $partyId', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _BlackRequestAction(icon: Icons.check_rounded, onTap: _working ? null : () => _respond(doc, 'accepted')),
                    const SizedBox(width: 6),
                    _BlackRequestAction(icon: Icons.close_rounded, onTap: _working ? null : () => _respond(doc, 'rejected')),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _BlackRequestAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _BlackRequestAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: const Color(0xFF09070B), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}


class _FriendsListSection extends StatelessWidget {
  const _FriendsListSection();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(
        child: Text('Please log in again.'),
      );
    }

    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('friendRequests')
          .where('senderUid', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, outgoing) {
        if (outgoing.hasError) {
          return const Center(
            child: Text('Could not load friends.'),
          );
        }

        if (!outgoing.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFFF1688),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('friendRequests')
              .where('receiverUid', isEqualTo: uid)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
          builder: (context, incoming) {
            if (incoming.hasError) {
              return const Center(
                child: Text('Could not load friends.'),
              );
            }

            if (!incoming.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF1688),
                ),
              );
            }

            final docs =
                <DocumentSnapshot<Map<String, dynamic>>>[
              ...outgoing.data!.docs,
              ...incoming.data!.docs,
            ];

            final unique =
                <String, DocumentSnapshot<Map<String, dynamic>>>{};

            for (final doc in docs) {
              final data = doc.data()!;
              final friendUid = data['senderUid'] == uid
                  ? data['receiverUid']
                  : data['senderUid'];

              unique[friendUid.toString()] = doc;
            }

            final friends = unique.values.toList();

            if (friends.isEmpty) {
              return const _SocialEmptySection(
                title: 'Friends',
                subtitle: 'Accepted friends will appear here.',
                icon: Icons.people_rounded,
              );
            }

            return Container(
              color: const Color(0xFFEAF8FF),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final doc = friends[index];
                  final data = doc.data()!;
                  final isSender = data['senderUid'] == uid;

                  final friendUid = (isSender
                          ? data['receiverUid']
                          : data['senderUid'])
                      .toString();

                  final fallbackName = (isSender
                          ? data['receiverName']
                          : data['senderName'] ??
                              'PartyNova User')
                      .toString();

                  final partyId = (isSender
                          ? data['receiverPartyNovaUid']
                          : data['senderPartyNovaUid'] ??
                              '')
                      .toString();

                  final fallbackPhoto = (isSender
                          ? data['receiverPhotoBase64']
                          : data['senderPhotoBase64'] ??
                              '')
                      .toString();

                  return StreamBuilder<
                      DocumentSnapshot<Map<String, dynamic>>>(
                    stream: firestore
    .collection('publicProfiles')
    .doc(friendUid)
    .snapshots(),
                    builder: (context, profileSnapshot) {
                      final profile =
                          profileSnapshot.data?.data() ??
                              <String, dynamic>{};

                      final liveName =
                          (profile['name'] as String?)?.trim() ??
                              '';

                      final name = liveName.isNotEmpty
                          ? liveName
                          : fallbackName.trim().isNotEmpty
                              ? fallbackName.trim()
                              : 'PartyNova User';

                      final livePhoto =
                          (profile['photoBase64'] as String?) ??
                              '';

                      final photo = livePhoto.isNotEmpty
                          ? livePhoto
                          : fallbackPhoto;

                      final photoImage = getCachedProfilePhotoImage(photo);

                      return Card(
                        key: ValueKey<String>(friendUid),
                        color: Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: photoImage,
                            child: photoImage == null
                                ? const Icon(Icons.person_rounded)
                                : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'ID: $partyId',
                            style: const TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                          onTap: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (dialogContext) {
                                return AlertDialog(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    side: const BorderSide(
                                      color: Color(0xFFFF1688),
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.fromLTRB(
                                    20,
                                    20,
                                    20,
                                    12,
                                  ),
                                  content: SizedBox(
                                    width: 300,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 42,
                                          backgroundColor:
                                              const Color(0xFFFFE3F1),
                                          backgroundImage: photoImage,
                                          child: photoImage == null
                                              ? const Icon(
                                                  Icons.person_rounded,
                                                  size: 42,
                                                  color:
                                                      Color(0xFFFF1688),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          name,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          'PartyNova ID: $partyId',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 22),

                                        _friendPopupButton(
                                          text: 'Delete',
                                          background:
                                              const Color(0xFFFF1688),
                                          foreground: Colors.white,
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                              context: dialogContext,
                                              builder:
                                                  (confirmContext) =>
                                                      AlertDialog(
                                                backgroundColor:
                                                    Colors.white,
                                                title: const Text(
                                                  'Remove friend?',
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                content: const Text(
                                                  'This removes the friendship only. It will not delete either account.',
                                                  style: TextStyle(
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                      confirmContext,
                                                      false,
                                                    ),
                                                    child: const Text(
                                                      'Cancel',
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                      confirmContext,
                                                      true,
                                                    ),
                                                    child: const Text(
                                                      'Remove',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFF1688,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm != true) return;

                                            try {
                                              final currentUid =
                                                  FirebaseAuth.instance
                                                      .currentUser
                                                      ?.uid;

                                              if (currentUid == null) {
                                                throw StateError(
                                                  'Not signed in',
                                                );
                                              }

                                              final db =
                                                  FirebaseFirestore
                                                      .instance;
                                              final batch = db.batch();

                                              final pairs =
                                                  <QuerySnapshot<
                                                      Map<String,
                                                          dynamic>>>[];

                                              pairs.add(
                                                await db
                                                    .collection(
                                                      'friendRequests',
                                                    )
                                                    .where(
                                                      'senderUid',
                                                      isEqualTo:
                                                          currentUid,
                                                    )
                                                    .where(
                                                      'receiverUid',
                                                      isEqualTo:
                                                          friendUid,
                                                    )
                                                    .get(),
                                              );

                                              pairs.add(
                                                await db
                                                    .collection(
                                                      'friendRequests',
                                                    )
                                                    .where(
                                                      'senderUid',
                                                      isEqualTo:
                                                          friendUid,
                                                    )
                                                    .where(
                                                      'receiverUid',
                                                      isEqualTo:
                                                          currentUid,
                                                    )
                                                    .get(),
                                              );

                                              var removed = 0;

                                              for (final result
                                                  in pairs) {
                                                for (final friendshipDoc
                                                    in result.docs) {
                                                  if ((friendshipDoc
                                                              .data()[
                                                          'status'] ??
                                                      '')
                                                      .toString() ==
                                                      'accepted') {
                                                    batch.delete(
                                                      friendshipDoc
                                                          .reference,
                                                    );
                                                    removed++;
                                                  }
                                                }
                                              }

                                              if (removed == 0) {
                                                if (dialogContext
                                                    .mounted) {
                                                  Navigator.pop(
                                                    dialogContext,
                                                  );
                                                }

                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Friendship was not found.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }

                                              await batch.commit();

                                              if (dialogContext
                                                  .mounted) {
                                                Navigator.pop(
                                                  dialogContext,
                                                );
                                              }

                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Friend removed successfully.',
                                                  ),
                                                ),
                                              );
                                            } catch (e, stackTrace) {
                                              debugPrint(
                                                'Friend removal failed: $e',
                                              );
                                              debugPrint(
                                                'Friend removal stack trace: $stackTrace',
                                              );

                                              if (!context.mounted) {
                                                return;
                                              }

                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Could not remove friend: $e',
                                                  ),
                                                  duration:
                                                      const Duration(
                                                    seconds: 8,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),

                                        const SizedBox(height: 10),

                                        _friendPopupButton(
                                          text: 'Profile',
                                          background:
                                              const Color(0xFFFF1688),
                                          foreground: Colors.white,
                                          onPressed: () {
                                            Navigator.pop(
                                              dialogContext,
                                            );

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PartyNovaPublicProfilePage(
                                                  firebaseUid:
                                                      friendUid,
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        const SizedBox(height: 10),

                                        _friendPopupButton(
                                          text: 'Message',
                                          background:
                                              const Color(0xFFFF1688),
                                          foreground: Colors.white,
                                          onPressed: () {
                                            Navigator.pop(
                                              dialogContext,
                                            );

                                            context
                                                .findAncestorStateOfType<
                                                    _PartyNovaSocialTabState>()
                                                ?._controller
                                                .index = 1;

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PartyNovaChatPage(
                                                  friendUid: friendUid,
                                                  friendName: name,
                                                  friendPhotoBase64:
                                                      photo,
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        const SizedBox(height: 10),

                                        _friendPopupButton(
                                          text: 'Cancel',
                                          background:
                                              const Color(0xFFFF1688),
                                          foreground: Colors.white,
                                          onPressed: () =>
                                              Navigator.pop(
                                            dialogContext,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}







Widget _friendPopupButton({
  required String text,
  required Color background,
  required Color foreground,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    height: 46,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(
            color: Color(0xFFFF1688),
            width: 1,
          ),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    ),
  );
}








class PartyNovaPublicProfilePage extends StatelessWidget {
  final String firebaseUid;
  final bool hideBlockReport;

  const PartyNovaPublicProfilePage({
    super.key,
    required this.firebaseUid,
    this.hideBlockReport = false,
  });

  static const Color _background = Color(0xFF09070B);
  static const Color _gold = Color(0xFFFFD780);
  static const Color _pink = Color(0xFFFF1688);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _gold,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: FirebaseFirestore.instance
      .collection('publicProfiles')
      .doc(firebaseUid)
      .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Could not load profile. Please check your connection and profile access.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                color: _gold,
              ),
            );
          }

          if (!snapshot.data!.exists) {
            return const Center(
              child: Text(
                'Profile not found.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final data = snapshot.data!.data() ?? {};

          final name =
              (data['name'] ?? 'PartyNova User').toString();

          final userId =
              (data['userId'] ?? '').toString().trim();

          final bio =
              (data['bio'] ?? 'No bio added yet.').toString();

          final photoBase64 =
              (data['photoBase64'] ?? '').toString();

          final profileFrameAsset =
              (data['profileFrameAsset'] ?? '').toString();

          final role = resolvePartyNovaRole(
            userId: userId,
            storedRole: data['role']?.toString(),
          );

          final isOwnerOrAdmin =
              role == 'owner' || role == 'admin';

          final photoImage =
              getCachedProfilePhotoImage(photoBase64);

          return Container(
            color: _background,
            width: double.infinity,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.of(context).size.width < 360 ? 14 : 20,
                20,
                MediaQuery.of(context).size.width < 360 ? 14 : 20,
                30,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'ID: $userId',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isOwnerOrAdmin ? const Color(0xFFFFD58A) : Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      shadows: isOwnerOrAdmin ? const [Shadow(color: Color(0xFFFFB45A), blurRadius: 12), Shadow(color: Color(0xFFFF2424), blurRadius: 16)] : null,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Profile picture and frame
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
                        color: _gold,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _pink.withValues(alpha: 0.25),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 106,
                            height: 106,
                            child: photoImage == null
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 64,
                                    color: Colors.white,
                                  )
                                : Image(
                                    image: photoImage,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    errorBuilder:
                                        (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.person_rounded,
                                        size: 64,
                                        color: Colors.white,
                                      );
                                    },
                                  ),
                          ),
                        ),

                        if (profileFrameAsset.isNotEmpty)
                          Positioned.fill(
                            child: Image.asset(
                              profileFrameAsset,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) {
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

                  // Owner/Admin badge or PartyNova ID
                  if (isOwnerOrAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFE8A6), Color(0xFFD9A43B), Color(0xFFB51F25), Color(0xFF650B16), Color(0xFFFFD780)],
                        ),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFFFE6B8), width: 1.4),
                        boxShadow: const [
                          BoxShadow(color: Color(0xAAFFB45A), blurRadius: 16, spreadRadius: 1),
                          BoxShadow(color: Color(0x99FF2424), blurRadius: 18, spreadRadius: 1),
                        ],
                      ),
                      child: Stack(alignment: Alignment.center, children: [
                        Positioned.fill(child: CustomPaint(painter: _FourCornerFramePainter(color: const Color(0xFFFFF1D2)))),
                        Text(role.toUpperCase(), style: const TextStyle(color: Color(0xFFFFF4D6), fontWeight: FontWeight.w900, letterSpacing: 1.5, shadows: [Shadow(color: Color(0xFFFFD780), blurRadius: 9), Shadow(color: Color(0xFFFF2424), blurRadius: 12)])),
                      ]),
                    )
                  else
                    const SizedBox.shrink(),

                  const SizedBox(height: 18),

                  // Bio
                  if (bio.trim().isNotEmpty &&
                      bio != 'No bio added yet.')
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                      ),
                      child: Text(
                        bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Public-profile actions. Block and Report are UI-only for now.
                  if (!hideBlockReport && firebaseUid != FirebaseAuth.instance.currentUser?.uid) ...[
                    Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'More options',
                        color: const Color(0xFF171019),
                        icon: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF21102F),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _gold,
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            color: _gold,
                            size: 23,
                          ),
                        ),
                        onSelected: (value) {
                          final action = value == 'block' ? 'Block' : 'Report';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$action option is not active yet.',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'block',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.block_rounded,
                                  color: _gold,
                                  size: 19,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Block',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.flag_rounded,
                                  color: _pink,
                                  size: 19,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Report',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                    const SizedBox(height: 8),
                  ],

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
                          color: _gold,
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

                  // Keep the existing Owner/Admin ID card.
                  if (isOwnerOrAdmin) ...[
                    const SizedBox(height: 24),
                    PartyNovaGoldenIdCard(userId: userId),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}





String _partyNovaConversationId(String uidA, String uidB) {
  final ids = [uidA, uidB]..sort();
  return '${ids[0]}_${ids[1]}';
}

const Color _chatBackground = Colors.white;
const Color _chatPink = Colors.black; // Retained name for compatibility; chat accent is black, never pink.
const Color _chatGold = Color(0xFFB58A2A);

DateTime _chatExpiryCutoff() {
  return DateTime.now().subtract(const Duration(days: 7));
}

Uint8List? _chatPhotoBytes(String base64Photo) {
  return getCachedProfilePhoto(base64Photo);
}

String _chatTimeLabel(Timestamp? timestamp) {
  if (timestamp == null) return 'Sending...';

  final time = timestamp.toDate().toLocal();
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour >= 12 ? 'PM' : 'AM';

  return '$hour:$minute $period';
}







class PartyNovaChatPage extends StatefulWidget {
  final String friendUid;
  final String friendName;
  final String friendPhotoBase64;

  const PartyNovaChatPage({
    super.key,
    required this.friendUid,
    required this.friendName,
    required this.friendPhotoBase64,
  });

  @override
  State<PartyNovaChatPage> createState() => _PartyNovaChatPageState();
}

class _PartyNovaChatPageState extends State<PartyNovaChatPage> {
  final TextEditingController _messageController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final ValueNotifier<bool> _sending = ValueNotifier<bool>(false);

late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesSnapshots;
late final Stream<DocumentSnapshot<Map<String, dynamic>>> _friendProfileSnapshots;
late final Stream<DocumentSnapshot<Map<String, dynamic>>> _myProfileSnapshots;

StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _friendProfileSubscription;
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myProfileSubscription;
  String _latestFriendName = '';
  String _latestFriendPhotoBase64 = '';
  String _latestMyName = '';
  String _latestMyPhotoBase64 = '';

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

Stream<DocumentSnapshot<Map<String, dynamic>>> get _friendProfileStream =>
    FirebaseFirestore.instance
        .collection('publicProfiles')
        .doc(widget.friendUid)
        .snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> get _myProfileStream =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(_myUid)
        .snapshots();

  

  String get _conversationId =>
      _partyNovaConversationId(_myUid, widget.friendUid);

  

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationId)
          .collection('messages');


  

Future<void> _markMessagesRead() async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  final db = FirebaseFirestore.instance;
  final conversationRef =
      db.collection('conversations').doc(_conversationId);

  try {
    // Clear only this user's unread counter and remember whether work is needed.
    final hadUnreadMessages = await db.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(conversationRef);
      if (!snapshot.exists) return false;

      final data = snapshot.data() ?? <String, dynamic>{};
      final participants =
          List<String>.from(data['participants'] ?? const <String>[]);
      if (!participants.contains(currentUser.uid)) return false;

      final unreadCounts =
          Map<String, dynamic>.from(data['unreadCounts'] ?? {});
      final unread = (unreadCounts[currentUser.uid] as num?)?.toInt() ?? 0;

      if (unread > 0) {
        unreadCounts[currentUser.uid] = 0;
        transaction.set(
          conversationRef,
          {'unreadCounts': unreadCounts},
          SetOptions(merge: true),
        );
      }

      return unread > 0;
    });

    // Do not touch old message documents when there is nothing unread.
    if (!hadUnreadMessages) return;

    final received = await _messagesRef
        .where('receiverUid', isEqualTo: currentUser.uid)
        .get();

    final unseenDocs = received.docs.where((doc) {
      final seenBy = List<String>.from(doc.data()['seenBy'] ?? const []);
      return !seenBy.contains(currentUser.uid);
    }).toList();

    for (var i = 0; i < unseenDocs.length; i += 400) {
      final batch = db.batch();
      for (final doc in unseenDocs.skip(i).take(400)) {
        batch.set(
          doc.reference,
          {'seenBy': FieldValue.arrayUnion([currentUser.uid])},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  } catch (e) {
    debugPrint('Mark messages read failed: $e');
  }
}


@override
void initState() {
  super.initState();
    _friendProfileSnapshots = _friendProfileStream;
  _myProfileSnapshots = _myProfileStream;

  _messagesSnapshots = _messagesRef
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots();

  _friendProfileSubscription = _friendProfileSnapshots.listen((snapshot) {
    if (!mounted) return;

    final profile = snapshot.data() ?? <String, dynamic>{};

    // Keep send-message metadata current without rebuilding the whole chat.
    _latestFriendName =
        (profile['name'] as String?)?.trim().isNotEmpty == true
            ? (profile['name'] as String).trim()
            : widget.friendName;

    _latestFriendPhotoBase64 =
        (profile['photoBase64'] as String?) ??
            widget.friendPhotoBase64;
  });

  _myProfileSubscription = _myProfileSnapshots.listen((snapshot) {
    if (!mounted) return;

    final profile = snapshot.data() ?? <String, dynamic>{};

    // Profile StreamBuilders update only the widgets that display profile data.
    _latestMyName =
        (profile['name'] as String?)?.trim().isNotEmpty == true
            ? (profile['name'] as String).trim()
            : 'You';

    _latestMyPhotoBase64 =
        (profile['photoBase64'] as String?) ?? '';
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _markMessagesRead();
  });
}
  

@override
void dispose() {
  _friendProfileSubscription?.cancel();
  _myProfileSubscription?.cancel();
  _sending.dispose();
  _messageController.dispose();
  _scrollController.dispose();
  super.dispose();
}

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending.value) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (widget.friendUid.trim().isEmpty || widget.friendUid == currentUser?.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This conversation is not valid.')),
      );
      return;
    }
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    _sending.value = true;
    _messageController.clear();

    try {
      final db = FirebaseFirestore.instance;
      final conversationRef = db.collection('conversations').doc(_conversationId);
      final messageRef = _messagesRef.doc();
      final now = FieldValue.serverTimestamp();

      // A batch is queued locally by Firestore, so the message can appear
      // immediately without waiting for a transaction read round-trip.
      // A local timestamp also avoids the temporary repeated "Sending..." label.
      final batch = db.batch();
      batch.set(messageRef, {
        'senderUid': _myUid,
        'receiverUid': widget.friendUid,
        'senderName': ((currentUser.displayName ?? '').trim().isNotEmpty ? currentUser.displayName : (_latestMyName.trim().isNotEmpty ? _latestMyName : 'You')),
        'senderPhotoURL': currentUser.photoURL ?? '',
        'text': text,
        'seenBy': <String>[_myUid],
        'createdAt': now,
      });
      batch.set(
        conversationRef,
        {
          'participants': ([_myUid, widget.friendUid]..sort()),
          'lastMessage': text,
          'lastMessageAt': now,
          'lastSenderUid': _myUid,
          'unreadCounts': <String, dynamic>{
            widget.friendUid: FieldValue.increment(1),
          },
        },
        SetOptions(merge: true),
      );

      // Firestore renders the pending write locally immediately. Await the
      // server acknowledgement so rejected writes are reported instead of
      // silently disappearing from the chat.
      await batch.commit();
    } catch (e) {
      debugPrint('PARTYNOVA SEND ERROR: $e');
      if (mounted) {
        // Restore the text so the user does not lose a message rejected by
        // Firestore rules or a network failure.
        if (_messageController.text.trim().isEmpty) {
          _messageController.text = text;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Message not saved: ${e.toString()}'),
              duration: const Duration(seconds: 5),
            ),
          );
      }
    } finally {
      if (mounted) _sending.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFFB9E8FF),
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: const Color(0xFFB9E8FF),
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
 stream: _friendProfileSnapshots,
  builder: (context, profileSnapshot) {
    final profile = profileSnapshot.data?.data();

    final latestName =
        (profile?['name'] as String?)?.trim().isNotEmpty == true
            ? (profile!['name'] as String).trim()
            : widget.friendName;

    final latestPhoto =
        (profile?['photoBase64'] as String?) ??
        widget.friendPhotoBase64;

    final photoImage = getCachedProfilePhotoImage(latestPhoto);

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFF101B36),
          backgroundImage: photoImage,
          child: photoImage == null
              ? const Icon(
                  Icons.person,
                  color: Color(0xFFFFC857),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            latestName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  },
),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesSnapshots,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Could not load messages.',
                      style: TextStyle(color: Colors.black),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  // Keep chat opening calm: no flashing spinner while the
                  // first Firestore snapshot is arriving.
                  return const SizedBox.expand();
                }

                final cutoff = _chatExpiryCutoff();

final messages = snapshot.data!.docs.where((doc) {
  final data = doc.data();
  final createdAt = data['createdAt'];

  // Show newly sent messages while the server timestamp is pending.
  if (createdAt is! Timestamp) {
    return doc.metadata.hasPendingWrites;
  }

  return createdAt.toDate().isAfter(cutoff);
}).toList();
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Start your conversation 💬',
                      style: TextStyle(color: Colors.black54),
                    ),
                  );
                }

                return ListView.builder(
                    findChildIndexCallback: (Key key) {
    final messageId = (key as ValueKey<String>).value;
    final index = messages.indexWhere((doc) => doc.id == messageId);
    return index == -1 ? null : index;
  },
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final isMine = data['senderUid'] == _myUid;
                    final text = data['text'] as String? ?? '';
                    final timestamp = data['createdAt'] as Timestamp?;

                    final bubbleColor = isMine ? Colors.white : Colors.black;
                    final textColor = isMine ? Colors.black : Colors.white;
                    final senderName = isMine
    ? (_latestMyName.trim().isNotEmpty ? _latestMyName : 'You')
    : (_latestFriendName.trim().isNotEmpty
        ? _latestFriendName
        : widget.friendName);

final senderPhoto = isMine
    ? _latestMyPhotoBase64
    : (_latestFriendPhotoBase64.isNotEmpty
        ? _latestFriendPhotoBase64
        : widget.friendPhotoBase64);

final senderPhotoImage = getCachedProfilePhotoImage(senderPhoto);
                    final isLastMessage = index == 0;
                    final seenByOther = data['seenBy'] is List &&
                        (data['seenBy'] as List).contains(widget.friendUid);

                    return Align(
  key: ValueKey<String>(messages[index].id),
                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMine) ...[
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PartyNovaPublicProfilePage(firebaseUid: widget.friendUid),
                              )),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: const Color(0xFF101B36),
                                backgroundImage: senderPhotoImage,
                                child: senderPhotoImage == null ? const Icon(Icons.person, size: 18, color: Color(0xFFFFC857)) : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: isMine ? const Color(0xFFE0E0E0) : Colors.black, width: 0.8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(senderName, style: TextStyle(color: textColor.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 3),
                                  Text(text, style: TextStyle(color: textColor, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(_chatTimeLabel(timestamp), style: TextStyle(color: isMine ? Colors.black54 : Colors.white70, fontSize: 10)),
                                    if (isMine) ...[
                                      const SizedBox(width: 5),
                                      Text(seenByOther ? 'Seen' : (isLastMessage ? 'Sent' : ''), style: const TextStyle(color: Colors.black54, fontSize: 10)),
                                    ],
                                  ]),
                                ],
                              ),
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PartyNovaPublicProfilePage(firebaseUid: _myUid),
                              )),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: const Color(0xFF101B36),
backgroundImage: senderPhotoImage,
child: senderPhotoImage == null
    ? const Icon(
        Icons.person,
        size: 18,
        color: Color(0xFFFFC857),
      )
    : null,
),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE0E0E0), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle:
                            const TextStyle(color: Colors.black45),
                        filled: true,
                        fillColor: const Color(0xFFF4F4F4),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
  borderRadius: BorderRadius.circular(24),
  borderSide: BorderSide.none,
),
),
onSubmitted: (_) => _sendMessage(),
),
),
ValueListenableBuilder<bool>(
  valueListenable: _sending,
  builder: (context, sending, _) {
    return IconButton(
      onPressed: sending ? null : _sendMessage,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(Icons.send_rounded),
    );
  },
),
],
),
),
),
],
),
);
}
}



class _MessagesListSection extends StatelessWidget {
  const _MessagesListSection();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(
        child: Text(
          'Please sign in to view messages.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('friendRequests')
          .where('senderUid', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, outgoing) {
        if (outgoing.hasError) {
          return const Center(child: Text('Could not load messages.'));
        }

        if (!outgoing.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _chatGold),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('friendRequests')
              .where('receiverUid', isEqualTo: uid)
              .where('status', isEqualTo: 'accepted')
              .snapshots(),
          builder: (context, incoming) {
            if (incoming.hasError) {
              return const Center(
                child: Text('Could not load messages.'),
              );
            }

            if (!incoming.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _chatGold),
              );
            }

            final allDocs =
                <DocumentSnapshot<Map<String, dynamic>>>[
              ...outgoing.data!.docs,
              ...incoming.data!.docs,
            ];

            final unique =
                <String, DocumentSnapshot<Map<String, dynamic>>>{};

            for (final doc in allDocs) {
              final data = doc.data();
              if (data == null) continue;

              final otherUid = data['senderUid'] == uid
                  ? data['receiverUid']
                  : data['senderUid'];

              if (otherUid is String &&
                  otherUid.isNotEmpty &&
                  otherUid != uid) {
                unique[otherUid] = doc;
              }
            }

            final friends = unique.values.toList();

            if (friends.isEmpty) {
              return const _SocialEmptySection(
                title: 'Messages',
                subtitle: 'Your accepted friends will appear here.',
                icon: Icons.chat_bubble_rounded,
              );
            }

            return Container(
              color: const Color(0xFFEAF8FF),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                itemCount: friends.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final doc = friends[index];
                  final data = doc.data()!;

                  final isSender = data['senderUid'] == uid;

                  final friendUid = (isSender
                          ? data['receiverUid']
                          : data['senderUid'])
                      .toString();

                  final friendName = ((isSender
                              ? data['receiverName']
                              : data['senderName']) ??
                          'PartyNova User')
                      .toString()
                      .trim();

                  final friendPhoto = ((isSender
            ? data['receiverPhotoBase64']
            : data['senderPhotoBase64']) ??
        '')
    .toString();

final conversationId =
    _partyNovaConversationId(uid, friendUid);

                  return StreamBuilder<
                      DocumentSnapshot<Map<String, dynamic>>>(
                    stream: firestore
                        .collection('conversations')
                        .doc(conversationId)
                        .snapshots(),
                    builder: (context, conversationSnapshot) {
                      final counts = Map<String, dynamic>.from(
                        conversationSnapshot.data
                                ?.data()?['unreadCounts'] ??
                            {},
                      );

                      final unreadCount =
                          (counts[uid] as num?)?.toInt() ?? 0;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartyNovaChatPage(
                                  friendUid: friendUid,
                                  friendName: friendName.isEmpty
                                      ? 'PartyNova User'
                                      : friendName,
                                  friendPhotoBase64: friendPhoto,
                                ),
                              ),
                            );
                          },
                          child: Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 13,
    vertical: 12,
  ),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
  ),
  child: Row(
    children: [
      _StableChatAvatar(
  key: ValueKey<String>(friendUid),
  firebaseUid: friendUid,
  photoBase64: friendPhoto,
  radius: 26,
),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          friendName.isEmpty
              ? 'PartyNova User'
              : friendName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      if (unreadCount > 0)
        _RequestCountBadge(
          count: unreadCount,
        ),
    ],
  ),
),
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}



class _StableChatAvatar extends StatelessWidget {
  final String firebaseUid;
  final String photoBase64;
  final double radius;

  const _StableChatAvatar({
    super.key,
    required this.firebaseUid,
    required this.photoBase64,
    this.radius = 26,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(firebaseUid)
          .snapshots(),
      builder: (context, snapshot) {
        String latestPhoto = photoBase64;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          latestPhoto = (data?['photoBase64'] ?? '').toString();
        }

        final imageProvider = getCachedProfilePhotoImage(latestPhoto);

        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFEDEDED),
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? const Icon(
                  Icons.person_rounded,
                  color: Colors.black54,
                )
              : null,
        );
      },
    );
  }
}

