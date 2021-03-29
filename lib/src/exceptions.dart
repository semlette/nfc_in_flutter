import 'dart:io';

/// NDEFReadingUnsupportedException is thrown if reading NDEF tags are either
/// not supported or not enabled on the device.
class NDEFReadingUnsupportedException implements Exception {
  @override
  String toString() => "NDEF reading is not supported on this device";
}

/// NFCMultipleReaderModesException is thrown when multiple reading streams
/// are open, but they use different reading modes. Only 1 reading mode can
/// be used at the same time.
class NFCMultipleReaderModesException implements Exception {
  @override
  String toString() =>
      "started reading with a different reader mode than the one already in use";
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
  final String? message;

  NFCSessionTerminatedUnexpectedlyException(this.message);

  @override
  String toString() => message ?? 'NFCSessionTerminatedUnexpectedlyException';
}

/// NFCSystemIsBusyException is thrown on iOS when "the reader session
/// failed because the system is busy".
class NFCSystemIsBusyException implements Exception {
  final String? message;

  NFCSystemIsBusyException(this.message);

  @override
  String toString() => message ?? 'NFCSystemIsBusyException';
}

/// NFCIOException is an I/O exception. Will happen if a tag is lost while being
/// read or a tag could not be connected to. NFCIOException is only thrown on
/// Android.
class NFCIOException extends IOException {
  final String? message;

  NFCIOException(this.message);

  @override
  String toString() => message ?? 'NFCIOException';
}

/// NDEFBadFormatException is thrown when a tag is read as NDEF, but it is not
/// properly formatted.
class NDEFBadFormatException implements Exception {
  final String? message;

  NDEFBadFormatException(this.message);

  @override
  String toString() => message ?? 'NDEFBadFormatException';
}

/// NFCTagNotWritableException is thrown when an unwritable tag is 'written to'.
/// This could be because the reader does not support writing to NFC tags or
/// simply the tag is read-only.
class NFCTagUnwritableException implements Exception {
  final message = "tag is not writable";

  @override
  String toString() => message;
}

/// NFCTagUnavailableException is thrown when the NFC tag being written to
/// is no longer in reach.
class NFCTagUnavailableException implements Exception {
  final message = "tag is no longer available";

  @override
  String toString() => message;
}

/// NDEFUnsupportedException is thrown when a tag does not support NDEF,
/// but is being written an NDEFMessage.
class NDEFUnsupportedException implements Exception {
  final message = "tag does not support NDEF formatting";

  @override
  String toString() => message;
}

/// NFCTagNotWritableException is thrown when a non-writable tag is being
/// written to.
class NFCTagNotWritableException implements Exception {
  static const message = "the tag does not support writing";

  @override
  String toString() => message;
}

/// NFCTagSizeTooSmallException is thrown when a NDEF message larger than
/// the tag's maximum size is being written to tag.
class NFCTagSizeTooSmallException implements Exception {
  final int maxSize;

  const NFCTagSizeTooSmallException(this.maxSize);

  @override
  String toString() =>
      "the new payload exceeds the tag's maximum payload size (maximum $maxSize bytes)";
}

/// NFCUpdateTagException is thrown when the reader failed to update the tag.
///
/// NFCUpdateTagException is only thrown on iOS and is mapped to the [NFCNdefReaderSessionErrorTagUpdateFailure](https://developer.apple.com/documentation/corenfc/nfcreadererror/nfcndefreadersessionerrortagupdatefailure?language=objc) error.
class NFCUpdateTagException implements Exception {
  static const message = "failed to update the tag";

  @override
  String toString() => message;
}
