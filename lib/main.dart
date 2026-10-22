import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

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
        scaffoldBackgroundColor: const Color(0xFF09070B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF1688),
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// Controls whether the user sees Welcome or the existing app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF09070B),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF1688),
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

const Color partyPink = Color(0xFFFF1688);
const Color partyBlack = Color(0xFF09070B);
const Color partyGold = Color(0xFFFFD780);
const Color partyWhite = Color(0xFFFFFFFF);

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

// Splash navigation
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

// Splash screen
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
                        Color(0xFFFF1688),
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

// Shared button style
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
                    Color(0xFFFF1688),
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

// Reusable text field with an optional password eye icon.
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

// Login screen
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

      if (!mounted) return;

      // AuthGate opens the existing app after successful login.
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
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

// Create account screen
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

      await credential.user?.updateDisplayName(
        _nameController.text.trim(),
      );

      await credential.user?.reload();

if (!mounted) return;

Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute<void>(
    builder: (_) => const PartyNovaHome(),
  ),
  (route) => false,
);

      // AuthGate opens the existing app after account creation.
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
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

// Existing PartyNova main app.
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
        builder: (context) => const SettingsPage(),
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
    return const ColoredBox(
      color: white,
      child: SizedBox.expand(),
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const Color white = Color(0xFFFFFFFF);

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF21101F),
        title: const Text(
          'Log Out',
          style: TextStyle(color: partyWhite),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: partyWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: partyGold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: partyPink),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not log out. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = <_SettingsOption>[
      _SettingsOption(
        title: 'Privacy',
        icon: Icons.shield_rounded,
        onTap: () {},
      ),
      _SettingsOption(
        title: 'Account',
        icon: Icons.person_rounded,
        onTap: () {},
      ),
      _SettingsOption(
        title: 'Help Center',
        icon: Icons.support_agent_rounded,
        onTap: () {},
      ),
      _SettingsOption(
        title: 'Log Out',
        icon: Icons.logout_rounded,
        onTap: () => _logout(context),
      ),
      _SettingsOption(
        title: 'Delete Account',
        icon: Icons.delete_forever_rounded,
        onTap: () {},
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF09070B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09070B),
        foregroundColor: white,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: white,
            fontSize: 23,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.3,
            colors: [
              Color(0xFF42152F),
              Color(0xFF21101F),
              Color(0xFF09070B),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 30),
            itemCount: options.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: 20),
            itemBuilder: (context, index) {
              final option = options[index];

              return _GlossySettingsBox(
                title: option.title,
                icon: option.icon,
                onTap: option.onTap,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsOption {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsOption({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}

class _GlossySettingsBox extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _GlossySettingsBox({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF9BC8),
                Color(0xFFFF1688),
                Color(0xFF9B1558),
              ],
              stops: [0.0, 0.42, 1.0],
            ),
            border: Border.all(
              color: const Color(0xFFFFC7E2),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF1688)
                    .withValues(alpha: 0.24),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 5,
                left: 8,
                right: 8,
                child: IgnorePointer(
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: 0.75),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFE9A8),
                            Color(0xFFFFC94F),
                            Color(0xFFB87919),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(0xFFFFF0BD),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD780)
                                .withValues(alpha: 0.28),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFF5C2C15),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
