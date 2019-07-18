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
@interface NFCWrapperBase : NSObject <FlutterStreamHandler> {
    FlutterEventSink events;
    NFCNDEFReaderSession* session;
}
- (void)readerSession:(nonnull NFCNDEFReaderSession *)session didInvalidateWithError:(nonnull NSError *)error;

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events;

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments;

- (NSDictionary * _Nonnull)formatMessageWithIdentifier:(NSString* _Nonnull)identifier message:(NFCNDEFMessage* _Nonnull)message;
@end

API_AVAILABLE(ios(11))
@interface NFCWrapperImpl11 : NFCWrapperBase <NFCWrapper, NFCNDEFReaderSessionDelegate> {
    FlutterMethodChannel* methodChannel;
    dispatch_queue_t dispatchQueue;
}
-(id _Nullable )init:(FlutterMethodChannel*_Nonnull)methodChannel dispatchQueue:(dispatch_queue_t _Nonnull )dispatchQueue;
@end

API_AVAILABLE(ios(13))
@interface NFCWrapperImpl13 : NFCWrapperBase <NFCWrapper, NFCNDEFReaderSessionDelegate> {
    FlutterMethodChannel* methodChannel;
    dispatch_queue_t dispatchQueue;
}
-(id _Nullable )init:(FlutterMethodChannel*_Nonnull)methodChannel dispatchQueue:(dispatch_queue_t _Nonnull )dispatchQueue;

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events;

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments;
@end

@interface NFCUnsupportedWrapper : NSObject <NFCWrapper>
@end
