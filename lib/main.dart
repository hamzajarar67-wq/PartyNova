import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';


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
      home: const PartyNovaHome(),
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
        onTap: () {},
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

              // The full-height area keeps the icon and text vertically centered.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 0,
                  ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
