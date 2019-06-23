import 'dart:io';

/// NDEFReadingUnsupportedException is thrown if reading NDEF tags are either
/// not supported or not enabled on the device.
class NDEFReadingUnsupportedException implements Exception {
  @override
  String toString() => "NDEF reading is not supported on this device";
}

/// NFCUserCanceledSessionException is thrown on iOS when the users cancels the
/// reading session (Clicks OK/done).
class NFCUserCanceledSessionException implements Exception {
  @override
  String toString() => "the user has cancelled the reading session";
}

/// NFCSessionTimeoutException is thrown on iOS when the session has been active
/// for 60 seconds.
class NFCSessionTimeoutException implements Exception {
  @override
  String toString() => "the reading session timed out";
}

/// NFCSessionTerminatedUnexpectedlyException is thrown on iOS when "The reader
/// session terminated unexpectedly".
class NFCSessionTerminatedUnexpectedlyException implements Exception {
  final String message;

  NFCSessionTerminatedUnexpectedlyException(this.message);

  @override
  String toString() => message;
}

/// NFCSystemIsBusyException is thrown on iOS when "the reader session
/// failed because the system is busy".
class NFCSystemIsBusyException implements Exception {
  final String message;

  NFCSystemIsBusyException(this.message);

  @override
  String toString() => message;
}

/// NFCIOException is an I/O exception. Will happen if a tag is lost while being
/// read or a tag could not be connected to. NFCIOException is only thrown on
/// Android.
class NFCIOException extends IOException {
  final String message;

  NFCIOException(this.message);

  @override
  String toString() => message;
}

/// NDEFBadFormatException is thrown when a tag is read as NDEF, but it is not
/// properly formatted.
class NDEFBadFormatException implements Exception {
  final String message;

  NDEFBadFormatException(this.message);

  @override
  String toString() => message;
}
