enum MessageType {
  NDEF,
}

abstract class NFCMessage {
  MessageType get messageType;
}

class NDEFMessage implements NFCMessage {
  final String type;
  final List<NDEFRecord> records;

  NDEFMessage(this.type, this.records);

  // payload returns the contents of the first non-empty record. If all records
  // are empty it will return null.
  String get payload {
    for (var record in records) {
      if (record.payload != "") {
        return record.payload;
      }
    }
    return null;
  }

  @override
  MessageType get messageType => MessageType.NDEF;
}

class NDEFRecord {
  final String id;
  final String payload;
  final String type;

  /// tnf is only available on Android
  final int tnf;

  NDEFRecord(this.id, this.payload, this.type, this.tnf);
}
