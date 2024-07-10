// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'pages/send_file.dart';
import 'pages/receive_file.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sharing App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainPage(), // Start with MainPage as the home page
    );
  }
}

class MainPage extends StatelessWidget {
  final List<String> menuItems = ['Receive File', 'Send File'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Sharing App'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 200, // Fixed width for the ListView
              child: ListView.builder(
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  return NavigationButton(
                    title: menuItems[index],
                    onPressed: () {
                      if (index == 0) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ReceiveFilePage()),
                        );
                      } else if (index == 1) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SendFilePage()),
                        );
                      }
                    },
                  );
                },
              ),
            ),
            SizedBox(width: 32), // Add some spacing between the ListView and the text
            Expanded(
              child: Center(
                child: Text(
                  'File Sharing App',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NavigationButton extends StatelessWidget {
  final String title;
  final VoidCallback onPressed;

  NavigationButton({
    required this.title,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(200, 50),
            textStyle: const TextStyle(fontSize: 18),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(
            title,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
