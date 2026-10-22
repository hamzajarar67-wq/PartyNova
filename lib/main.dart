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
        scaffoldBackgroundColor: const Color(0xFF090909),
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
  static const Color black = Color(0xFF090909);
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
    return const SizedBox.expand();
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
