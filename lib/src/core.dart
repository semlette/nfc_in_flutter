import 'dart:async';
import 'package:flutter/services.dart';
import './exceptions.dart';

class Core {
  static MethodChannel channel = MethodChannel("nfc_in_flutter");
  static const EventChannel eventChannel =
      const EventChannel("nfc_in_flutter/tags");

  static Stream<dynamic> tagStream;

  static void createTagStream() {
    tagStream = eventChannel.receiveBroadcastStream();
  }

  static Stream<T> startReading<T>(
      Stream<T> Function(Stream stream) transformer,
      void Function() startCallback,
      {bool once,
      bool throwOnUserCancel}) {
    if (Core.tagStream == null) {
      Core.createTagStream();
    }
    Stream<T> stream = transformer(Core.tagStream);
    // Create a StreamController to wrap the tag stream. Any errors will be
    // converted to their matching exception classes. The controller stream will
    // be closed if the errors are fatal.
    StreamController<T> controller = StreamController();

    if (once != null && once) {
      stream = stream.take(1);
    }

    // Listen for tag reads.
    final subscription = stream.listen((T tag) {
      controller.add(tag);
    }, onDone: () {
      Core.tagStream = null;
      controller.close();
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
    });
    controller.onCancel = () {
      subscription.cancel();
    };

    try {
      startCallback();
    } on PlatformException catch (err) {
      if (err.code == "NFCMultipleReaderModes") {
        throw NFCMultipleReaderModesException();
      }
      throw err;
    }

    return controller.stream;
  }
}
