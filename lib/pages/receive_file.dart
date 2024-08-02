import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:local_file_sharing/network_helper.dart'; // Adjust the import according to your package name

class ReceiveFilePage extends StatefulWidget {
  const ReceiveFilePage({super.key});

  @override
  _ReceiveFilePageState createState() => _ReceiveFilePageState();
}

class _ReceiveFilePageState extends State<ReceiveFilePage> {
  late NetworkHelper networkHelper;
  String? ipAddress;
  String? saveDirectory;
  static const int port = 5555; // Same port as in NetworkHelper
  final encrypt.Key _key = encrypt.Key.fromUtf8('32-character-long-key-for-aes256'); // Ensure this key matches the one used for encryption

  @override
  void initState() {
    super.initState();
    networkHelper = NetworkHelper();
    _getIpAddress();
    networkHelper.startDiscovery(); // Start multicasting when page initializes
  }

  @override
  void dispose() {
    networkHelper.stopReceiving();
    networkHelper.stopDiscovery(); // Stop multicasting when page is disposed
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
        const SnackBar(content: Text('No directory selected')),
      );
    }
  }

Future<void> _decryptFile() async {
  // Open file picker to select an encrypted file
  FilePickerResult? result = await FilePicker.platform.pickFiles();
  if (result != null) {
    File file = File(result.files.single.path!);
    final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));

    try {
      // Read the encrypted file
      Uint8List encryptedBytes = await file.readAsBytes();

      // Extract the IV from the first 16 bytes
      final iv = encrypt.IV(encryptedBytes.sublist(0, 16));
      final encryptedData = encryptedBytes.sublist(16);

      // Decrypt the file
      List<int> decryptedBytes = encrypter.decryptBytes(encrypt.Encrypted(encryptedData), iv: iv);

      // Save the decrypted file
      String originalFileName = path.basenameWithoutExtension(file.path);
      String originalExtension = path.extension(file.path);
      String newPath = '${saveDirectory ?? ""}/$originalFileName$originalExtension';
      File decryptedFile = File(newPath);
      await decryptedFile.writeAsBytes(decryptedBytes);

      // Notify user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File decrypted and saved to: $newPath')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error decrypting file: $e')),
      );
    }
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No file selected.')),
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
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _decryptFile,
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
                child: const Text('Decrypt File'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
