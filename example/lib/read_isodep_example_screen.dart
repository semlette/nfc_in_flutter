import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nfc_in_flutter/android.dart';

class ReadIsoDepExampleScreen extends StatefulWidget {
  @override
  _ReadIsoDepExampleScreenState createState() =>
      _ReadIsoDepExampleScreenState();
}

class _ReadIsoDepExampleScreenState extends State<ReadIsoDepExampleScreen> {
  StreamSubscription<IsoDep> _stream;
  IsoDep _lastTag;

  void _startScanning() {
    setState(() {
      _stream = AndroidNFC.readIsoDep().listen((tag) {
        print("read IsoDep tag");
        print("  hi_layer_response: ${tag.hiLayerResponse}");
        print("  historical_bytes: ${tag.historicalBytes}");
        print(
            "  is_extended_length_apdu_supported: ${tag.isExtendedLengthApduSupported}");
        print("  max_transceive_length: ${tag.maxTransceiveLength}");
        print("  atqa: ${tag.atqa}");
        print("  sak: ${tag.sak}");
        print("  timeout: ${tag.timeout}");
        setState(() {
          _lastTag = tag;
        });
      }, onDone: () {
        print("closing stream");
      }, onError: (error) {
        print("tag error: $error");
      });
    });
  }

  void _stopScanning() {
    _stream?.cancel();
    if (mounted) {
      setState(() {
        _stream = null;
      });
    }
  }

  void _toggleScan() {
    if (_stream == null) {
      _startScanning();
    } else {
      _stopScanning();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _stopScanning();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Read NFC example"),
      ),
      body: Column(
        children: <Widget>[
          Center(
              child: RaisedButton(
            child: const Text("Toggle scan"),
            onPressed: _toggleScan,
          )),
          if (_lastTag != null)
            Column(
              children: <Widget>[
                const Text("whatever"),
              ],
            ),
        ],
      ),
    );
  }
}
