import 'package:flutter/material.dart';

void main() {
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
                color: const Color(0xFFFF1688).withValues(alpha: 0.08),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF1688)
                        .withValues(alpha: 0.12),
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
                color: const Color(0xFFB52B76).withValues(alpha: 0.08),
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
                color: pink,
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
          color: isProfile ? white : const Color(0xFF111111),
          border: Border(
            top: BorderSide(
              color: isProfile
                  ? const Color(0xFFFFD5E8)
                  : const Color(0xFF292929),
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
            selectedItemColor: pink,
            unselectedItemColor:
                isProfile ? const Color(0xFF777777) : Colors.white60,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            showUnselectedLabels: true,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.meeting_room_rounded),
                label: 'Rooms',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.sports_esports_rounded),
                label: 'Games',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Wallet',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_alt_rounded),
                label: 'Social',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090909),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xFFFF1688),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const SizedBox.expand(),
    );
  }
}
