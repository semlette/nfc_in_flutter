import 'dart:async';
import 'dart:core';

import 'package:flutter/services.dart';

import './exceptions.dart';

class NFC {
  static MethodChannel _channel = MethodChannel("nfc_in_flutter");
  static const EventChannel _eventChannel =
      const EventChannel("nfc_in_flutter/tags");

  static Stream<dynamic> _tagStream;

  /// readNDEF starts listening for NDEF formatted tags. Any non-NDEF formatted
  /// tags will be filtered out.
  static Stream<NDEFMessage> readNDEF(
      {

      /// once will stop reading after the first tag has been read.
      bool once = false,

      /// throwOnUserCancel decides if a [NFCUserCanceledSessionException] error
      /// should be thrown on iOS when the user clicks Cancel/Done.
      bool throwOnUserCancel = true,

      /// readerMode specifies which mode the reader should use. By default it
      /// will use the normal mode, which scans for tags normally without
      /// support for peer-to-peer operations, such as emulated host cards.
      ///
      /// This is ignored on iOS as it only has one reading mode.
      NFCReaderMode readerMode = const NFCNormalReaderMode()}) {
    if (_tagStream == null) {
      _tagStream = _eventChannel.receiveBroadcastStream().where((tag) {
        // In the future when more tag types are supported, this must be changed.
        assert(tag is Map);
        return tag["message_type"] == "ndef";
      }).map<NFCMessage>((tag) {
        assert(tag is Map);

        List<NDEFRecord> records = [];
        for (var record in tag["records"]) {
          NFCTypeNameFormat tnf;
          switch (record["tnf"]) {
            case "empty":
              tnf = NFCTypeNameFormat.empty;
              break;
            case "well_known":
              tnf = NFCTypeNameFormat.well_known;
              break;
            case "mime_media":
              tnf = NFCTypeNameFormat.mime_media;
              break;
            case "absolute_uri":
              tnf = NFCTypeNameFormat.absolute_uri;
              break;
            case "external_type":
              tnf = NFCTypeNameFormat.external_type;
              break;
            case "unchanged":
              tnf = NFCTypeNameFormat.unchanged;
              break;
            default:
              tnf = NFCTypeNameFormat.unknown;
          }

          records.add(NDEFRecord._internal(
            record["id"],
            record["payload"],
            record["type"],
            tnf,
            record["data"],
            record["languageCode"],
          ));
        }

        return NDEFMessage._internal(tag["id"], tag["type"], records);
      });
    }
    // Create a StreamController to wrap the tag stream. Any errors will be
    // converted to their matching exception classes. The controller stream will
    // be closed if the errors are fatal.
    StreamController<NDEFMessage> controller = StreamController();
    final stream = once ? _tagStream.take(1) : _tagStream;
    // Listen for tag reads.
    final subscription = stream.listen((message) {
      controller.add(message);
    }, onError: (error) {
      if (error is PlatformException) {
        switch (error.code) {
          case "NDEFUnsupportedFeatureError":
            controller.addError(NDEFReadingUnsupportedException());
            controller.close();
            return;
          case "UserCanceledSessionError":
            if (throwOnUserCancel)
              controller.addError(NFCUserCanceledSessionException());
            controller.close();
            return;
          case "SessionTimeoutError":
            controller.addError(NFCSessionTimeoutException());
            controller.close();
            return;
          case "SessionTerminatedUnexpectedlyErorr":
            controller.addError(
                NFCSessionTerminatedUnexpectedlyException(error.message));
            controller.close();
            return;
          case "SystemIsBusyError":
            controller.addError(NFCSystemIsBusyException(error.message));
            controller.close();
            return;
          case "IOError":
            controller.addError(NFCIOException(error.message));
            if (error.details != null) {
              assert(error.details is Map);
              if (error.details["fatal"] == true) controller.close();
            }
            return;
          case "NDEFBadFormatError":
            controller.addError(NDEFBadFormatException(error.message));
            return;
        }
      }
      controller.addError(error);
    }, onDone: () {
      _tagStream = null;
      return controller.close();
    });
    controller.onCancel = () {
      subscription.cancel();
    };

    // Start reading
    Map arguments = {
      "scan_once": once,
      "reader_mode": readerMode.name,
    }..addAll(readerMode._options);
    try {
      _channel.invokeMethod("startNDEFReading", arguments);
    } on PlatformException catch (err) {
      controller.close();
      if (err.code == "NFCMultipleReaderModes") {
        throw NFCMultipleReaderModesException();
      }
      throw err;
    }

    return controller.stream;
  }

  /// isNDEFSupported checks if the device supports reading NDEF tags
  static Future<bool> get isNDEFSupported async {
    final supported = await _channel.invokeMethod("readNDEFSupported");
    assert(supported is bool);
    return supported as bool;
  }
}

/// NFCReaderMode is an interface for different reading modes
// The reading modes are implemented as classes instead of enums, so they could
// support options in the future without breaking changes.
abstract class NFCReaderMode {
  String get name;

  Map get _options;
}

/// NFCNormalReaderMode uses the platform's normal reading mode. This does not
/// allow reading from emulated host cards or other peer-to-peer operations.
class NFCNormalReaderMode implements NFCReaderMode {
  String get name => "normal";

  /// noSounds tells the platform not to play any sounds when a tag has been
  /// read.
  /// Android only
  final bool noSounds;

  const NFCNormalReaderMode({
    this.noSounds = false,
  });

  @override
  Map get _options {
    return {
      "no_platform_sounds": noSounds,
    };
  }
}

/// NFCDispatchReaderMode allows reading from emulated host cards and other
/// peer-to-peer operations by using different platform APIs.
class NFCDispatchReaderMode implements NFCReaderMode {
  String get name => "dispatch";

  @override
  Map get _options {
    return {};
  }
}

enum MessageType {
  NDEF,
}

abstract class NFCMessage {
  MessageType get messageType;
  String get id;

  NFCTag get tag;
}

abstract class NFCTag {
  String get id;
  bool get writable;
  Future connect();
  Future close();
}

class NDEFMessage implements NFCMessage {
  final String id;
  String type;
  final List<NDEFRecord> records;

  NDEFMessage.withRecords(this.records, {this.id});

  NDEFMessage(this.type, this.records) : id = null;

  NDEFMessage._internal(this.id, this.type, this.records);

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

  @override
  NDEFTag get tag {
    return NDEFTag._internal(id, true);
  }

  Map<String, dynamic> _toMap() {
    return {
      "id": id,
      "type": type,
      "records": records.map((record) => record._toMap()).toList(),
    };
  }
}

enum NFCTypeNameFormat {
  empty,
  well_known,
  mime_media,
  absolute_uri,
  external_type,
  unknown,
  unchanged,
}

class NDEFRecord {
  final String id;
  final String payload;
  final String type;
  final String data;
  final NFCTypeNameFormat tnf;

  /// languageCode will be the language code of a well known text record. If the
  /// record is not created with the well known TNF and Text RTD, this will be
  /// null.
  final String languageCode;

  NDEFRecord.empty()
      : id = null,
        type = "",
        payload = "",
        data = "",
        tnf = NFCTypeNameFormat.empty,
        languageCode = null;

  NDEFRecord.plain(String data)
      : id = null,
        type = "text/plain",
        payload = data,
        this.data = data,
        tnf = NFCTypeNameFormat.unknown,
        languageCode = null; // TODO

  NDEFRecord.type(this.type, String payload)
      : id = null,
        data = payload,
        this.payload = payload,
        tnf = NFCTypeNameFormat.mime_media,
        languageCode = null;

  NDEFRecord.text(String message, {languageCode = "en"})
      : id = null,
        data = message,
        payload = languageCode + message,
        type = "T",
        tnf = NFCTypeNameFormat.well_known,
        this.languageCode = languageCode;

  NDEFRecord._internal(
      this.id, this.payload, this.type, this.tnf, this.data, this.languageCode);

  Map<String, dynamic> _toMap() {
    return {
      "id": id,
      "payload": payload,
      "type": type,
    };
  }
}

class NDEFTag implements NFCTag {
  String id;
  bool writable;

  NDEFTag._internal(this.id, this.writable);

  NDEFTag._fromMap(Map<String, dynamic> map) {
    assert(map["id"] is String);
    id = map["id"];
    assert(map["writable"] is bool);
    writable = map["writable"];
  }

  @override
  Future connect() async {}

  @override
  Future close() async {}

  Future write(NDEFMessage message) async {
    if (!writable) {
      throw NFCTagUnwritableException();
    }
    try {
      NFC._channel.invokeMethod("writeNDEF", {
        "id": id,
        "message": message._toMap(),
      });
    } on PlatformException catch (e) {
      switch (e.code) {
        case "IOError":
          throw NFCIOException(e.message);
        case "NFCTagUnavailable":
          throw NFCTagUnavailableException();
        case "NDEFUnsupported":
          throw NDEFUnsupportedException();
        case "NDEFBadFormatError":
          throw NDEFBadFormatException(e.message);
        default:
          throw e;
      }
    }
  }
}
