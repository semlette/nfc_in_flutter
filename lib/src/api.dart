import 'dart:async';
import 'dart:core';

import 'package:flutter/services.dart';

import './exceptions.dart';
import './messages.dart';

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
          records.add(NDEFRecord(
            record["id"],
            record["payload"],
            record["type"],
            record["tnf"] != null ? int.parse(record["tnf"]) : 0,
            data: record["data"],
          ));
        }

        return NDEFMessage(tag["type"], records, id: tag["id"] ?? "");
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
