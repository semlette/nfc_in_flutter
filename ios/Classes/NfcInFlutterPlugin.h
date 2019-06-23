#import <Flutter/Flutter.h>
#import <CoreNFC/CoreNFC.h>

@protocol NFCWrapper <FlutterStreamHandler>
    -(void)startReading:(BOOL)once;
    -(BOOL)isEnabled;
    @end


@interface NfcInFlutterPlugin : NSObject<FlutterPlugin> {
    FlutterEventSink events;
    NSObject<NFCWrapper>* wrapper;
}
@end

API_AVAILABLE(ios(11))
@interface NFCWrapperImpl : NSObject <NFCWrapper, NFCNDEFReaderSessionDelegate> {
    FlutterEventSink events;
    FlutterMethodChannel* methodChannel;
    dispatch_queue_t dispatchQueue;
    NFCNDEFReaderSession* session;
}
    -(id)init:(FlutterMethodChannel*)methodChannel dispatchQueue:(dispatch_queue_t)dispatchQueue;
@end

@interface NFCUnsupportedWrapper : NSObject <NFCWrapper>
@end
