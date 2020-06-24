#import <Flutter/Flutter.h>
#import <CoreNFC/CoreNFC.h>

@protocol NFCWrapper <FlutterStreamHandler>
- (void)startReading:(BOOL)once alertMessage:(NSString* _Nonnull)alertMessage;
- (BOOL)isEnabled;
- (void)writeToTag:(NSDictionary* _Nonnull)data completionHandler:(void (^_Nonnull) (FlutterError * _Nullable error))completionHandler;
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

- (NFCNDEFMessage * _Nonnull)formatNDEFMessageWithDictionary:(NSDictionary* _Nonnull)dictionary;
@end

API_AVAILABLE(ios(11))
@interface NFCWrapperImpl : NFCWrapperBase <NFCWrapper, NFCNDEFReaderSessionDelegate> {
    FlutterMethodChannel* methodChannel;
    dispatch_queue_t dispatchQueue;
}
-(id _Nullable )init:(FlutterMethodChannel*_Nonnull)methodChannel dispatchQueue:(dispatch_queue_t _Nonnull )dispatchQueue;
@end

API_AVAILABLE(ios(13))
@interface NFCWritableWrapperImpl : NFCWrapperImpl

@property (atomic, retain) __kindof id<NFCNDEFTag> _Nullable lastTag;

@end

@interface NFCUnsupportedWrapper : NSObject <NFCWrapper>
@end
