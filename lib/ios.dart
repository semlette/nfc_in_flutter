import './src/core.dart';

class IOSNFC {
  static Future<bool> get isTagReadingSupported async {
    final supported = await Core.channel.invokeMethod("tagReadingSupported");
    assert(supported is bool);
    return supported;
  }
}
