import 'package:flutter/material.dart';
import 'package:local_file_sharing/network_helper.dart'; // Adjust the import according to your package name
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/scheduler.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get IP address: $e')),
      );
    }
  }

  Future<void> _pickSaveDirectory() async {
    String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath != null) {
      setState(() {
        saveDirectory = directoryPath;
      });
      networkHelper.startReceiving(); // Save path is picked within startReceiving()
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saving files to $saveDirectory')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No directory selected')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive File'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (ipAddress != null)
                Text(
                  'IP Address: $ipAddress\nPort: $port',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                )
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 20),
              if (saveDirectory != null)
                Text(
                  'Saving to: $saveDirectory',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                )
              else
                ElevatedButton(
                  onPressed: _pickSaveDirectory,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue,
                    minimumSize: const Size(double.infinity, 50),
                    textStyle: const TextStyle(fontSize: 18),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: const Text('Select Save Directory'),
                ),
              const SizedBox(height: 20),
              if (saveDirectory != null) ...[
                const Text(
                  'Waiting for files...',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
