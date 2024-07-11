import 'package:flutter/material.dart';
import 'package:local_file_sharing/network_helper.dart'; // Adjust the import according to your package name
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class ReceiveFilePage extends StatefulWidget {
  @override
  _ReceiveFilePageState createState() => _ReceiveFilePageState();
}

class _ReceiveFilePageState extends State<ReceiveFilePage> {
  NetworkHelper networkHelper = NetworkHelper(); // Instantiate network helper
  String? ipAddress;
  String? saveDirectory;
  static const int port = 5555; // Same port as in NetworkHelper

  @override
  void initState() {
    super.initState();
    _getIpAddress();
    networkHelper.startMulticasting(); // Start multicasting when page initializes
  }

  @override
  void dispose() {
    networkHelper.stopReceiving();
    networkHelper.stopMulticasting(); // Stop multicasting when page is disposed
    super.dispose();
  }

  Future<void> _getIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            setState(() {
              ipAddress = addr.address;
            });
            return;
          }
        }
      }
    } catch (e) {
      print('Failed to get IP address: $e');
    }
  }

  Future<void> _pickSaveDirectory() async {
    String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath != null) {
      setState(() {
        saveDirectory = directoryPath;
      });
      networkHelper.startReceiving(saveDirectory!);
      print('Started receiving files, saving to $saveDirectory');
    } else {
      print('No directory selected');
    }
  }

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
            ipAddress != null
                ? Text(
                    'IP Address: $ipAddress\nPort: $port',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  )
                : CircularProgressIndicator(),
            SizedBox(height: 20),
            saveDirectory != null
                ? Text(
                    'Saving to: $saveDirectory',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  )
                : ElevatedButton(
                    onPressed: _pickSaveDirectory,
                    child: Text('Select Save Directory'),
                  ),
            SizedBox(height: 20),
            saveDirectory != null
                ? Text(
                    'Waiting for files...',
                    style: TextStyle(fontSize: 18),
                  )
                : Container(),
            saveDirectory != null
                ? CircularProgressIndicator()
                : Container(),
          ],
        ),
      ),
    );
  }
}
