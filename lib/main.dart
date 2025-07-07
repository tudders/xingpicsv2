// main.dart
import 'package:flutter/material.dart';
import 'details_page.dart'; // Import the new page

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _selectedIndex = 0; // To manage the current tab index

  // List of pages to display in the PageView, corresponding to the tabs
  static const List<Widget> _widgetOptions = <Widget>[
    DetailsPage(), // Your main form page
    Center(
      child: Text(
        'XingPics - v3 Page (Image Tab)',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XingPics',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: 'Inter', // Applying Inter font
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('XingPics'),
          backgroundColor: Colors.blue, // Use the primary color from the seed
        ),
        body: IndexedStack(
          // Use IndexedStack to preserve state of pages
          index: _selectedIndex,
          children: _widgetOptions,
        ),
      ),
    );
  }
}
