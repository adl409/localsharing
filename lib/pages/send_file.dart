import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:typed_data';
import 'package:local_file_sharing/network_helper.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class SendFilePage extends StatefulWidget {
  const SendFilePage({super.key});

  @override
  _SendFilePageState createState() => _SendFilePageState();
}

class _SendFilePageState extends State<SendFilePage> {
  String? fileName;
  File? selectedFile;
  String? selectedDevice;
  bool isEncrypted = true;

  NetworkHelper networkHelper = NetworkHelper();

  final encrypt.Key _key = encrypt.Key.fromUtf8('32-character-long-key-for-aes256');
  final encrypt.IV _iv = encrypt.IV.fromLength(16);

  @override
  void initState() {
    super.initState();
    networkHelper.startMulticasting();
  }

  @override
  void dispose() {
    networkHelper.stopMulticasting();
    super.dispose();
  }

  void selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
        fileName = path.basename(result.files.single.path!);
      });
    } else {
      print('No file selected');
    }
  }

  Future<void> sendFile() async {
    if (selectedFile != null && selectedDevice != null) {
      try {
        if (isEncrypted) {
          final fileBytes = await selectedFile!.readAsBytes();
          final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
          final encryptedBytes = encrypter.encryptBytes(fileBytes, iv: _iv).bytes;
          final combinedBytes = Uint8List.fromList(_iv.bytes + encryptedBytes);
          final tempFile = File('${selectedFile!.path}.enc');
          await tempFile.writeAsBytes(combinedBytes);

          await networkHelper.sendFile(tempFile, selectedDevice!);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Encrypted file sent: $fileName to $selectedDevice')),
          );
        } else {
          await networkHelper.sendFile(selectedFile!, selectedDevice!);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File sent: $fileName to $selectedDevice')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File or device not selected')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send File'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('Select File'),
              onPressed: selectFile,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.blue,
                backgroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 18),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (fileName != null)
              Text(
                'Selected file: $fileName',
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Encrypt file'),
                Switch(
                  value: isEncrypted,
                  onChanged: (value) {
                    setState(() {
                      isEncrypted = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send File'),
              onPressed: sendFile,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.blue,
                backgroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 18),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Available Devices',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: StreamBuilder<List<String>>(
                          stream: networkHelper.devicesStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              List<String> discoveredDevices = snapshot.data!;
                              return ListView.builder(
                                itemCount: discoveredDevices.length,
                                itemBuilder: (context, index) {
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListTile(
                                      leading: const Icon(Icons.devices),
                                      title: Text(discoveredDevices[index]),
                                      onTap: () {
                                        setState(() {
                                          selectedDevice = discoveredDevices[index];
                                        });
                                        print('Device selected: ${discoveredDevices[index]}');
                                      },
                                    ),
                                  );
                                },
                              );
                            } else {
                              return const Center(child: CircularProgressIndicator());
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
