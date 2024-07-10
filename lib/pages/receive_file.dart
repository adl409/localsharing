import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:local_file_sharing/network_helper.dart'; // Adjust the import according to your package name
import 'dart:io';

class ReceiveFilePage extends StatefulWidget {
  @override
  _ReceiveFilePageState createState() => _ReceiveFilePageState();
}

class _ReceiveFilePageState extends State<ReceiveFilePage> {
  NetworkHelper networkHelper = NetworkHelper(); // Instantiate network helper
  String? ipAddress;
  static const int port = 5555; // Same port as in NetworkHelper

  @override
  void initState() {
    super.initState();
    _startReceivingFiles();
    _getIpAddress();
  }

  @override
  void dispose() {
    networkHelper.stopReceiving();
    super.dispose();
  }

  Future<void> _startReceivingFiles() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String savePath = appDocDir.path;
    networkHelper.startReceiving(savePath);
    print('Started receiving files, saving to $savePath');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive File'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ipAddress != null
                ? Text(
                    'IP Address: $ipAddress\nPort: $port',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  )
                : const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Waiting for files...',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
