/// NFCReaderMode is an interface for different reading modes
// The reading modes are implemented as classes instead of enums, so they could
// support options in the future without breaking changes.
abstract class NFCReaderMode {
  String get name;
}

/// NFCNormalReaderMode uses the platform's normal reading mode. This does not
/// allow reading from emulated host cards or other peer-to-peer operations.
class NFCNormalReaderMode implements NFCReaderMode {
  String get name => "normal";

  const NFCNormalReaderMode();
}

/// NFCDispatchReaderMode allows reading from emulated host cards and other
/// peer-to-peer operations by using different platform APIs.
class NFCDispatchReaderMode implements NFCReaderMode {
  String get name => "dispatch";
}
