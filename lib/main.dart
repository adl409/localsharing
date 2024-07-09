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
        title: const Text('Main Page'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: SizedBox(
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
            foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20), backgroundColor: Colors.blue,
            textStyle: TextStyle(fontSize: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
