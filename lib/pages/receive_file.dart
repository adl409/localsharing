import 'package:flutter/material.dart';

class ReceiveFilePage extends StatefulWidget {
  @override
  _ReceiveFilePageState createState() => _ReceiveFilePageState();
}

class _ReceiveFilePageState extends State<ReceiveFilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Receive File'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              child: Text('Start Receiving'),
              onPressed: () {
                // TODO: Implement start receiving
              },
            ),
            ElevatedButton(
              child: Text('Stop Receiving'),
              onPressed: () {
                // TODO: Implement stop receiving
              },
            ),
          ],
        ),
      ),
    );
  }
}
