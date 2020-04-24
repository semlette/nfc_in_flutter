import 'package:flutter/material.dart';
import 'package:nfc_in_flutter/ios.dart';

class IOSScreen extends StatefulWidget {
  @override
  _IOSScreenState createState() => _IOSScreenState();
}

class _IOSScreenState extends State<IOSScreen> {
  bool _knowsTagReadingSupported = false;
  bool _tagReadingSupported = false;

  @override
  void initState() {
    super.initState();
    IOSNFC.isTagReadingSupported.then((value) {
      setState(() {
        _knowsTagReadingSupported = true;
        _tagReadingSupported = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Read NFC example"),
      ),
      body: Builder(builder: (context) {
        String tagReadingSupportedString = "figuring out";
        if (_knowsTagReadingSupported) {
          if (_tagReadingSupported) {
            tagReadingSupportedString = "yes";
          } else {
            tagReadingSupportedString = "no";
          }
        }
        return ListView(
          children: <Widget>[
            ListTile(
              title: const Text("Is tag reading supported?"),
              subtitle: Text(tagReadingSupportedString),
            ),
          ],
        );
      }),
    );
  }
}
