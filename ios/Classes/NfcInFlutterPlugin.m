#import <CoreNFC/CoreNFC.h>
#import "NfcInFlutterPlugin.h"

@implementation NfcInFlutterPlugin {
    dispatch_queue_t dispatchQueue;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    dispatch_queue_t dispatchQueue = dispatch_queue_create("me.andisemler.nfc_in_flutter.dispatch_queue", NULL);
    
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"nfc_in_flutter"
                                     binaryMessenger:[registrar messenger]];
    
    FlutterEventChannel* tagChannel = [FlutterEventChannel
                                       eventChannelWithName:@"nfc_in_flutter/tags"
                                       binaryMessenger:[registrar messenger]];
    
    NfcInFlutterPlugin* instance = [[NfcInFlutterPlugin alloc]
                                    init:dispatchQueue
                                    channel:channel];
  
    [registrar addMethodCallDelegate:instance channel:channel];
    [tagChannel setStreamHandler:instance->wrapper];
}
    
- (id)init:(dispatch_queue_t)dispatchQueue channel:(FlutterMethodChannel*)channel {
    self->dispatchQueue = dispatchQueue;
    if (@available(iOS 11.0, *)) {
        wrapper = [[NFCWrapperImpl alloc] init:channel dispatchQueue:dispatchQueue];
    } else {
        wrapper = [[NFCUnsupportedWrapper alloc] init];
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    dispatch_async(dispatchQueue, ^{
        [self handleMethodCallAsync:call result:result];
    });
}
    
- (void)handleMethodCallAsync:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"readNDEFSupported" isEqualToString:call.method]) {
        result([NSNumber numberWithBool:[wrapper isEnabled]]);
    } else if ([@"startNDEFReading" isEqualToString:call.method]) {
        NSDictionary* args = call.arguments;
        [wrapper startReading:[args[@"scan_once"] boolValue]];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end


@implementation NFCWrapperBase

- (void)readerSession:(nonnull NFCNDEFReaderSession *)session didInvalidateWithError:(nonnull NSError *)error API_AVAILABLE(ios(11.0)) {
    // When a session has been invalidated it needs to be created again to work.
    // Since this function is called when it invalidates, the session can safely be removed.
    // A new session doesn't have to be created immediately as that will happen the next time
    // startReading() is called.
    session = nil;
    
    // If the event stream is closed we can't send the error
    if (events == nil) {
        return;
    }
    switch ([error code]) {
        case NFCReaderSessionInvalidationErrorFirstNDEFTagRead:
            // When this error is returned it doesn't need to be sent to the client
            // as it cancels the stream after 1 read anyways
            events(FlutterEndOfEventStream);
            return;
        case NFCReaderErrorUnsupportedFeature:
            events([FlutterError
                    errorWithCode:@"NDEFUnsupportedFeatureError"
                    message:error.localizedDescription
                    details:nil]);
            break;
        case NFCReaderSessionInvalidationErrorUserCanceled:
            events([FlutterError
                    errorWithCode:@"UserCanceledSessionError"
                    message:error.localizedDescription
                    details:nil]);
            break;
        case NFCReaderSessionInvalidationErrorSessionTimeout:
            events([FlutterError
                    errorWithCode:@"SessionTimeoutError"
                    message:error.localizedDescription
                    details:nil]);
            break;
        case NFCReaderSessionInvalidationErrorSessionTerminatedUnexpectedly:
            events([FlutterError
                    errorWithCode:@"SessionTerminatedUnexpectedlyError"
                    message:error.localizedDescription
                    details:nil]);
            break;
        case NFCReaderSessionInvalidationErrorSystemIsBusy:
            events([FlutterError
                    errorWithCode:@"SystemIsBusyError"
                    message:error.localizedDescription
                    details:nil]);
            break;
        default:
            events([FlutterError
                    errorWithCode:@"SessionError"
                    message:error.localizedDescription
                    details:nil]);
    }
    // Make sure to close the stream, otherwise bad things will happen.
    // (onCancelWithArguments will never be called so the stream will
    //  not be reset and will be stuck in a 'User Canceled' error loop)
    events(FlutterEndOfEventStream);
    return;
}

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events {
    self->events = events;
    return nil;
}

// onCancelWithArguments is called when the event stream is canceled,
// which most likely happens because of manuallyStopStream().
// However if it was not triggered by manuallyStopStream(), it should invalidate
// the reader session if activate
- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    if (session != nil) {
        [session invalidateSession];
        session = nil;
    }
    events = nil;
    return nil;
}

// formatMessageWithIdentifier turns a NFCNDEFMessage into a NSDictionary that
// is ready to be sent to Flutter
- (NSDictionary * _Nonnull)formatMessageWithIdentifier:(NSString* _Nonnull)identifier message:(NFCNDEFMessage* _Nonnull)message {
    NSLog(@"records: %lu", (unsigned long)message.records.count);
    NSMutableArray<NSDictionary*>* records = [[NSMutableArray alloc] initWithCapacity:message.records.count];
    for (NFCNDEFPayload* payload in message.records) {
        NSString* type;
        type = [[NSString alloc]
                initWithData:payload.type
                encoding:NSUTF8StringEncoding];
        NSString* payloadData;
        payloadData = [[NSString alloc]
                       initWithData:payload.payload
                       encoding:NSUTF8StringEncoding];
        NSString* identifier;
        identifier = [[NSString alloc]
                      initWithData:payload.identifier
                      encoding:NSUTF8StringEncoding];
        
        NSString* tnf;
        switch (payload.typeNameFormat) {
            case NFCTypeNameFormatEmpty:
                tnf = @"empty";
                break;
            case NFCTypeNameFormatNFCWellKnown:
                tnf = @"well_known";
                break;
            case NFCTypeNameFormatMedia:
                tnf = @"mime_media";
                break;
            case NFCTypeNameFormatAbsoluteURI:
                tnf = @"absolute_uri";
                break;
            case NFCTypeNameFormatNFCExternal:
                tnf = @"external";
                break;
            case NFCTypeNameFormatUnchanged:
                tnf = @"unchanged";
                break;
            default:
                tnf = @"unknown";
        }
        
        NSDictionary* record = @{
            @"type": type,
            @"payload": payloadData,
            @"data": payloadData,
            @"id": identifier,
            @"tnf": tnf,
        };
        [records addObject:record];
    }
    NSDictionary* result = @{
        @"id": identifier,
        @"message_type": @"ndef",
        @"records": records,
    };
    return result;
}

@end

@implementation NFCWrapperImpl

- (id)init:(FlutterMethodChannel*)methodChannel dispatchQueue:(dispatch_queue_t)dispatchQueue {
    self->methodChannel = methodChannel;
    self->dispatchQueue = dispatchQueue;
    return self;
}
    
- (void)startReading:(BOOL)once {
    if (session == nil) {
        session = [[NFCNDEFReaderSession alloc]initWithDelegate:self queue:dispatchQueue invalidateAfterFirstRead: once];
    }
    [self->session beginSession];
}
    
- (BOOL)isEnabled {
    return NFCNDEFReaderSession.readingAvailable;
}
    
- (void)readerSession:(nonnull NFCNDEFReaderSession *)session didDetectNDEFs:(nonnull NSArray<NFCNDEFMessage *> *)messages API_AVAILABLE(ios(11.0)) {
    // Iterate through the messages and send them to Flutter with the following structure:
    // { Map
    //   "message_type": "ndef",
    //   "records": [ List
    //     { Map
    //       "type": "The record's content type",
    //       "payload": "The record's payload",
    //       "id": "The record's identifier",
    //     }
    //   ]
    // }
    for (NFCNDEFMessage* message in messages) {
        NSDictionary* result = [self formatMessageWithIdentifier:@"" message:message];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->events != nil) {
               self->events(result);
            }
        });
    }
}

- (void)readerSession:(NFCNDEFReaderSession *)session
        didDetectTags:(NSArray<__kindof id<NFCNDEFTag>> *)tags API_AVAILABLE(ios(13.0)) {
    // Iterate through the tags and send them to Flutter with the following structure:
    // { Map
    //   "id": "", // empty
    //   "message_type": "ndef",
    //   "records": [ List
    //     { Map
    //       "type": "The record's content type",
    //       "payload": "The record's payload",
    //       "id": "The record's identifier",
    //     }
    //   ]
    // }
    
    // Set the last tags scanned
    lastTag = tags[[tags count] - 1];
    
    for (id<NFCNDEFTag> tag in tags) {
        [session connectToTag:tag completionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                NSLog(@"connect error: %@", error.localizedDescription);
                return;
            }
            [tag readNDEFWithCompletionHandler:^(NFCNDEFMessage * _Nullable message, NSError * _Nullable error) {
                
                if (error != nil) {
                    NSLog(@"ERROR: %@", error.localizedDescription);
                    return;
                }
                
                NSDictionary* result = [self formatMessageWithIdentifier:@"" message:message];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self->events != nil) {
                        self->events(result);
                    }
                });
            }];
        }];
    }
}

- (void)readerSessionDidBecomeActive:(NFCNDEFReaderSession *)session API_AVAILABLE(ios(13.0)) {
    NSLog(@"didBecomeActive");
}

- (void)writeToTag:(NSDictionary*)data {
    // recordList is a list of records sent by Flutter
    NSArray* recordList = [data valueForKey:@"records"];
    // records is a mutable array of records for the final NDEF message
    NSMutableArray<NSArray<NFCNDEFPayload*>*>* records = [[NSMutableArray alloc] initWithCapacity:[recordList count]];
    // TODO: continue
}

@end

@implementation NFCUnsupportedWrapper

- (BOOL)isEnabled {
    // https://knowyourmeme.com/photos/1483348-bugs-bunnys-no
    return NO;
}
- (void)startReading:(BOOL)once {
    return;
}

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events {
    return [FlutterError
            errorWithCode:@"NDEFUnsupportedFeatureError"
            message:nil
            details:nil];
}
    
- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    return nil;
}

- (void)writeToTag:(NSDictionary*)data {
    return;
}
    
@end
