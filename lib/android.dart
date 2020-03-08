import 'dart:async';
import 'dart:typed_data';
import './src/core.dart';
import './src/api.dart';

class NFCA {
  final Uint8List atqa;
  final int maxTransceiveLength;
  final int sak;
  final int timeout;
  final bool isConnected;

  NFCA._internal(
    this.atqa,
    this.maxTransceiveLength,
    this.sak,
    this.timeout,
    this.isConnected,
  );

  Future<void> connect() {
    return Core.channel.invokeMethod("android.connectNFCA");
  }

  Future<void> close() {
    return Core.channel.invokeMethod("android.closeNFCA");
  }

  Future<Uint8List> transceive(Uint8List data) async {
    Uint8List response =
        await Core.channel.invokeMethod("android.transceiveNFCA", data);
    return Future.value(response);
  }

  Future<void> setTimeout(Duration timeout) {
    return Core.channel.invokeMethod("android.setNFCATimeout", {
      "timeout": timeout.inMilliseconds,
    });
  }
}

class IsoDep extends NFCA {
  final Uint8List hiLayerResponse;
  final Uint8List historicalBytes;
  final bool isExtendedLengthApduSupported;

  IsoDep._internal(
    this.hiLayerResponse,
    this.historicalBytes,
    this.isExtendedLengthApduSupported,
    Uint8List atqa,
    int maxTransceiveLength,
    int sak,
    int timeout,
    bool isConnected,
  ) : super._internal(atqa, maxTransceiveLength, sak, timeout, isConnected);

  Future<void> connect() {
    return Core.channel.invokeMethod("android.connectIsoDep");
  }

  Future<void> close() {
    return Core.channel.invokeMethod("android.closeIsoDep");
  }

  Future<Uint8List> transceive(Uint8List data) async {
    Uint8List response =
        await Core.channel.invokeMethod("android.transceiveIsoDep", data);
    return Future.value(response);
  }

  Future<void> setTimeout(Duration timeout) {
    return Core.channel.invokeMethod("android.setIsoDepTimeout", {
      "timeout": timeout.inMilliseconds,
    });
  }
}

class AndroidNFC {
  static Stream<IsoDep> _streamWithIsoDep(Stream stream) {
    return stream.where((tag) {
      assert(tag is Map);
      return tag["message_type"] == "isodep";
    }).map<IsoDep>((tag) {
      assert(tag is Map);
      return IsoDep._internal(
        tag["hi_layer_response"],
        tag["historical_bytes"],
        tag["is_extended_length_apdu_supported"],
        tag["atqa"],
        tag["max_transceive_length"],
        tag["sak"],
        tag["timeout"],
        tag["is_connected"],
      );
    });
  }

  static void _startReadingIsoDep(bool once, NFCReaderMode readerMode) {
    // Start reading
    Map arguments = {
      "reader_mode": readerMode.name,
    }..addAll(readerMode.options);
    Core.channel.invokeMethod("android.startIsoDepReading", arguments);
  }

  static Stream<IsoDep> readIsoDep({
    /// once will stop reading after the first tag has been read.
    bool once = false,

    /// readerMode specifies which mode the reader should use. By default it
    /// will use the normal mode, which scans for tags normally without
    /// support for peer-to-peer operations, such as emulated host cards.
    ///
    /// TODO: explain the exact reader mode (intents, reader mode)
    NFCReaderMode readerMode = const NFCNormalReaderMode(),
  }) {
    return Core.startReading(
      (stream) => AndroidNFC._streamWithIsoDep(stream),
      () => AndroidNFC._startReadingIsoDep(once, readerMode),
      once: once,
    );
  }

  static Stream<NFCA> _streamWithNFCA(Stream stream) {
    return stream.where((tag) {
      assert(tag is Map);
      return tag["message_type"] == "nfca";
    }).map<NFCA>((tag) {
      assert(tag is Map);

      return NFCA._internal(
        tag["atqa"],
        tag["max_transceive_length"],
        tag["sak"],
        tag["timeout"],
        tag["is_connected"],
      );
    });
  }

  static void _startReadingNFCA(bool once, NFCReaderMode readerMode) {
    // Start reading
    Map arguments = {
      "reader_mode": readerMode.name,
    }..addAll(readerMode.options);
    Core.channel.invokeMethod("android.startNFCAReading", arguments);
  }

  static Stream<NFCA> readNFCA({
    /// once will stop reading after the first tag has been read.
    bool once = false,

    /// readerMode specifies which mode the reader should use. By default it
    /// will use the normal mode, which scans for tags normally without
    /// support for peer-to-peer operations, such as emulated host cards.
    ///
    /// TODO: explain the exact reader mode (intents, reader mode)
    NFCReaderMode readerMode = const NFCNormalReaderMode(),
  }) {
    return Core.startReading(
      (stream) => AndroidNFC._streamWithNFCA(stream),
      () => AndroidNFC._startReadingNFCA(once, readerMode),
      once: once,
    );
  }
}
