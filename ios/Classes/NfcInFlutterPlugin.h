#import <Flutter/Flutter.h>
#import <CoreNFC/CoreNFC.h>

@interface NFCDelegate : NSObject<FlutterStreamHandler, NFCNDEFReaderSessionDelegate, NFCTagReaderSessionDelegate>

// MARK: Properties

@property (atomic, retain) FlutterMethodChannel * _Nonnull methodChannel;
@property (atomic, retain) dispatch_queue_t _Nonnull queue;
@property (atomic, retain) id<NFCNDEFTag> _Nullable lastNDEFTag API_AVAILABLE(ios(13.0));
@property (atomic, retain) id<NFCTag> _Nullable lastTag API_AVAILABLE(ios(13.0));
@property (atomic, copy) FlutterEventSink _Nullable events;
@property (atomic, retain) NFCNDEFReaderSession * _Nullable ndefSession API_AVAILABLE(ios(11.0));
@property (atomic, retain) NFCTagReaderSession * _Nullable tagSession API_AVAILABLE(ios(13.0));

- (instancetype _Nonnull)init:(FlutterMethodChannel * _Nonnull)methodChannel dispatchQueue:(dispatch_queue_t _Nonnull)dispatchQueue;

// MARK: NDEF operations

- (BOOL)isNDEFReadingAvailable;

- (void)beginReadingNDEF:(BOOL)once  alertMessage:(NSString * _Nonnull)alertMessage API_AVAILABLE(ios(11.0));

- (void)writeNDEFMessage:(NFCNDEFMessage * _Nonnull)message completionHandler:(void (^ _Nonnull) (FlutterError * _Nullable error))completionHandler API_AVAILABLE(ios(13.0));

- (NSDictionary * _Nonnull)formatMessageWithIdentifier:(NSString * _Nonnull)identifier message:(NFCNDEFMessage * _Nonnull)message API_AVAILABLE(ios(11.0));

- (NFCNDEFMessage * _Nonnull)formatNDEFMessageWithDictionary:(NSDictionary * _Nonnull)dictionary API_AVAILABLE(ios(13.0));

- (FlutterError * _Nonnull)mapError:(NSError * _Nonnull)error context:(NSDictionary * _Nullable)context;

// MARK: Tag operations

- (BOOL)isTagReadingAvailable;

- (void)beginReadingTags:(BOOL)once pollingOption:(NSInteger)pollingOption API_AVAILABLE(ios(13.0));

- (void)iso7816SendCommand:(NFCISO7816APDU * _Nonnull)command completionHandler:(void (^ _Nonnull) (NSData * _Nullable data, FlutterError * _Nullable error))completionHandler API_AVAILABLE(ios(13.0));

- (void)iso15693ReadBlockRange:(RequestFlag)flag range:(NSRange)range completionHandler:(void (^ _Nonnull) (NSArray<NSData *> * _Nullable dataBlocks, FlutterError * _Nullable error))completionHandler API_AVAILABLE(ios(13.0));

// TODO: Add ISO 15693 'Read Single Block', 'Write Single Block' and 'Write Multiple Blocks' methods

@end

@interface NfcInFlutterPlugin : NSObject<FlutterPlugin>

@property (atomic, retain) dispatch_queue_t _Nonnull queue;
@property (atomic, retain) NFCDelegate * _Nonnull delegate;

@end
