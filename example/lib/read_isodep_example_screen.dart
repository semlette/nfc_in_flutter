import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_in_flutter/nfc_in_flutter.dart';

class ReadISODepExample extends StatefulWidget {
  @override
  _ReadISODepExampleState createState() => _ReadISODepExampleState();
}

class _ReadISODepExampleState extends State<ReadISODepExample> {
  StreamSubscription<IsoDepTag> _stream;

  void _beginReading() {
    _stream = NFC.readIsoDep().listen((IsoDepTag tag) {
      print("read IsoDep tag");
    });
  }

  void _stopReading() {
    _stream?.cancel();
    _stream = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Read IsoDep example"),
      ),
      body: Center(
        child: RaisedButton(
          child: const Text("Toggle reading"),
          onPressed: () {
            if (_stream == null) {
              _beginReading();
            } else {
              _stopReading();
            }
          },
        ),
      ),
    );
  }
}
