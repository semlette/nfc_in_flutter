#import <CoreNFC/CoreNFC.h>
#import "NfcInFlutterPlugin.h"

@implementation NfcInFlutterPlugin
    
@synthesize delegate;
@synthesize queue;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    dispatch_queue_t dispatchQueue = dispatch_queue_create("me.andisemler.nfc_in_flutter.dispatch_queue", NULL);
    
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:@"nfc_in_flutter"
                                     binaryMessenger:[registrar messenger]];
    
    FlutterEventChannel *tagChannel = [FlutterEventChannel
                                       eventChannelWithName:@"nfc_in_flutter/tags"
                                       binaryMessenger:[registrar messenger]];
    
    NfcInFlutterPlugin *instance = [[NfcInFlutterPlugin alloc]
                                    init:dispatchQueue
                                    channel:channel];
  
    [registrar addMethodCallDelegate:instance channel:channel];
    [tagChannel setStreamHandler:instance->delegate];
}
    
- (instancetype)init:(dispatch_queue_t)dispatchQueue channel:(FlutterMethodChannel * _Nonnull)channel {
    queue = dispatchQueue;
    delegate = [[NFCDelegate alloc] init:channel dispatchQueue:dispatchQueue];
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall * _Nonnull)call result:(FlutterResult)result {
    dispatch_async(queue, ^{
        [self handleMethodCallAsync:call result:result];
    });
}
    
- (void)handleMethodCallAsync:(FlutterMethodCall * _Nonnull)call result:(FlutterResult)result {
    if ([@"readNDEFSupported" isEqualToString:call.method]) {
        result([NSNumber numberWithBool:[delegate isNDEFReadingAvailable]]);
    } else if ([@"startNDEFReading" isEqualToString:call.method]) {
        NSDictionary *args = call.arguments;
        if (@available(iOS 11.0, *)) {
            [delegate beginReadingNDEF:[args[@"scan_once"] boolValue] alertMessage:args[@"alert_message"]];
            result(nil);
        } else {
            result([FlutterError errorWithCode:@"NDEFUnsupportedFeatureError" message:@"Writing NDEF messages is not supported" details:nil]);
        }
    } else if ([@"writeNDEF" isEqualToString:call.method]) {
        if (@available(iOS 13.0, *)) {
            NSDictionary *args = call.arguments;
            NFCNDEFMessage *message = [delegate formatNDEFMessageWithDictionary:args];
            [delegate writeNDEFMessage:message completionHandler:^(FlutterError * _Nullable error) {
                result(error);
            }];
        } else {
            result([FlutterError errorWithCode:@"NDEFUnsupportedFeatureError" message:@"Writing NDEF messages is not supported" details:nil]);
        }
    } /*
       TODO: Add methods for interacting with other cards
   */ else {
        result(FlutterMethodNotImplemented);
    }
}

@end

@implementation NFCDelegate

@synthesize lastNDEFTag;
@synthesize lastTag;
@synthesize events;
@synthesize ndefSession;
@synthesize tagSession;

- (instancetype _Nonnull)init:(FlutterMethodChannel * _Nonnull)methodChannel dispatchQueue:(dispatch_queue_t _Nonnull)dispatchQueue {
    _methodChannel = methodChannel;
    _queue = dispatchQueue;
    return self;
}

// MARK: NDEF operations

- (BOOL)isNDEFReadingAvailable API_AVAILABLE(ios(11.0)) {
    if (@available(iOS 11.0, *)) {
        return NFCNDEFReaderSession.readingAvailable;
    }
    return NO;
}

- (void)beginReadingNDEF:(BOOL)once alertMessage:(NSString * _Nonnull)alertMessage API_AVAILABLE(ios(11.0)) {
    if (ndefSession == nil) {
        ndefSession = [[NFCNDEFReaderSession alloc]initWithDelegate:self queue:_queue invalidateAfterFirstRead: once];
        ndefSession.alertMessage = alertMessage;
    }
    [ndefSession beginSession];
}

- (void)writeNDEFMessage:(NFCNDEFMessage * _Nonnull)message completionHandler:(void (^ _Nonnull) (FlutterError * _Nullable error))completionHandler API_AVAILABLE(ios(13.0)) {
    if (lastNDEFTag != nil) {
        if (!lastTag.available) {
            completionHandler([FlutterError errorWithCode:@"NFCTagUnavailable" message:@"the tag is unavailable for writing" details:nil]);
            return;
        }
        
        // Connect to the tag.
        // The tag might already be connected to, but it doesn't hurt to do it again.
        [ndefSession connectToTag:lastNDEFTag completionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                completionHandler([FlutterError errorWithCode:@"IOError" message:[NSString stringWithFormat:@"could not connect to tag: %@", error.localizedDescription] details:nil]);
                return;
            }
            // Get the tag's read/write status
            [self->lastNDEFTag queryNDEFStatusWithCompletionHandler:^(NFCNDEFStatus status, NSUInteger capacity, NSError * _Nullable error) {
                if (error != nil) {
                    completionHandler([FlutterError errorWithCode:@"NFCUnexpectedError" message:error.localizedDescription details:nil]);
                    return;
                }
                
                // Write to the tag if possible
                if (status == NFCNDEFStatusReadWrite) {
                    [self->lastNDEFTag writeNDEF:message completionHandler:^(NSError * _Nullable error) {
                        if (error != nil) {
                            FlutterError *flutterError;
                            switch (error.code) {
                                case NFCNdefReaderSessionErrorTagNotWritable:
                                    flutterError = [FlutterError errorWithCode:@"NFCTagNotWritableError" message:@"the tag is not writable" details:nil];
                                    break;
                                case NFCNdefReaderSessionErrorTagSizeTooSmall: {
                                    NSDictionary *details = @{
                                        @"maxSize": [NSNumber numberWithInt:capacity],
                                    };
                                    flutterError = [FlutterError errorWithCode:@"NFCTagSizeTooSmallError" message:@"the tag's memory size is too small" details:details];
                                    break;
                                }
                                case NFCNdefReaderSessionErrorTagUpdateFailure:
                                    flutterError = [FlutterError errorWithCode:@"NFCUpdateTagError" message:@"the reader failed to update the tag" details:nil];
                                    break;
                                default:
                                    flutterError = [FlutterError errorWithCode:@"NFCUnexpectedError" message:error.localizedDescription details:nil];
                            }
                            completionHandler(flutterError);
                        } else {
                            // Successfully wrote data to the tag
                            completionHandler(nil);
                        }
                    }];
                } else {
                    // Writing is not supported on this tag
                    completionHandler([FlutterError errorWithCode:@"NFCTagNotWritableError" message:@"the tag is not writable" details:nil]);
                }
            }];
        }];
    } else {
        completionHandler([FlutterError errorWithCode:@"NFCTagUnavailable" message:@"no tag to write to" details:nil]);
    }
}

- (void)readerSessionDidBecomeActive:(NFCNDEFReaderSession * _Nonnull)session API_AVAILABLE(ios(13.0)) {
    return;
}

- (void)readerSession:(NFCNDEFReaderSession * _Nonnull)session didDetectNDEFs:(NSArray<NFCNDEFMessage *> * _Nonnull)messages API_AVAILABLE(ios(11.0)) {
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
        NSDictionary *result = [self formatMessageWithIdentifier:@"" message:message];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->events != nil) {
               self->events(result);
            }
        });
    }
}

- (void)readerSession:(NFCNDEFReaderSession * _Nonnull)session didDetectTags:(NSArray<id<NFCNDEFTag>> * _Nonnull)tags API_AVAILABLE(ios(13.0)) {
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
                
                NSDictionary *result = [self formatMessageWithIdentifier:@"" message:message];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self->events != nil) {
                        self->events(result);
                    }
                });
            }];
        }];
    }
}

- (void)readerSession:(NFCNDEFReaderSession * _Nonnull)session didInvalidateWithError:(NSError * _Nonnull)error API_AVAILABLE(ios(11.0)) {
    // When a session has been invalidated it needs to be created again to work.
    // Since this function is called when it invalidates, the session can safely be removed.
    // A new session doesn't have to be created immediately as that will happen the next time
    // startReading() is called.
    ndefSession = nil;
    
    // If the event stream is closed we can't send the error
    if (events == nil) {
        return;
    }
    switch (error.code) {
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
}

// formatMessageWithIdentifier turns a NFCNDEFMessage into a NSDictionary that
// is ready to be sent to Flutter
- (NSDictionary * _Nonnull)formatMessageWithIdentifier:(NSString * _Nonnull)identifier message:(NFCNDEFMessage * _Nonnull)message {
    NSMutableArray<NSDictionary *> *records = [[NSMutableArray alloc] initWithCapacity:message.records.count];
    for (NFCNDEFPayload *payload in message.records) {
        NSString *type;
        type = [[NSString alloc]
                initWithData:payload.type
                encoding:NSUTF8StringEncoding];
        
        NSString *payloadData;
        NSString *data;
        NSString *languageCode;
        if ([@"T" isEqualToString:type]) {
            // Remove the first byte from the payload
            payloadData = [[NSString alloc]
                    initWithData:[payload.payload
                                  subdataWithRange:NSMakeRange(1, payload.payload.length-1)]
                    encoding:NSUTF8StringEncoding];
            
            const unsigned char *bytes = [payload.payload bytes];
            int languageCodeLength = bytes[0] & 0x3f;
            languageCode = [[NSString alloc]
                            initWithData:[payload.payload
                                          subdataWithRange:NSMakeRange(1, languageCodeLength)]
                            encoding:NSUTF8StringEncoding];
            // Exclude the language code from the data
            data = [[NSString alloc]
                   initWithData:[payload.payload
                                 subdataWithRange:NSMakeRange(languageCodeLength+1, payload.payload.length-languageCodeLength-1)]
                   encoding:NSUTF8StringEncoding];
        } else if ([@"U" isEqualToString:type]) {
            NSString *url;
            const unsigned char *bytes = [payload.payload bytes];
            int prefixByte = bytes[0];
            switch (prefixByte) {
                case 0x01:
                    url = @"http://www.";
                    break;
                case 0x02:
                    url = @"https://www.";
                    break;
                case 0x03:
                    url = @"http://";
                    break;
                case 0x04:
                    url = @"https://";
                    break;
                case 0x05:
                    url = @"tel:";
                    break;
                case 0x06:
                    url = @"mailto:";
                    break;
                case 0x07:
                    url = @"ftp://anonymous:anonymous@";
                    break;
                case 0x08:
                    url = @"ftp://ftp.";
                    break;
                case 0x09:
                    url = @"ftps://";
                    break;
                case 0x0A:
                    url = @"sftp://";
                    break;
                case 0x0B:
                    url = @"smb://";
                    break;
                case 0x0C:
                    url = @"nfs://";
                    break;
                case 0x0D:
                    url = @"ftp://";
                    break;
                case 0x0E:
                    url = @"dav://";
                    break;
                case 0x0F:
                    url = @"news:";
                    break;
                case 0x10:
                    url = @"telnet://";
                    break;
                case 0x11:
                    url = @"imap:";
                    break;
                case 0x12:
                    url = @"rtsp://";
                    break;
                case 0x13:
                    url = @"urn:";
                    break;
                case 0x14:
                    url = @"pop:";
                    break;
                case 0x15:
                    url = @"sip:";
                    break;
                case 0x16:
                    url = @"sips";
                    break;
                case 0x17:
                    url = @"tftp:";
                    break;
                case 0x18:
                    url = @"btspp://";
                    break;
                case 0x19:
                    url = @"btl2cap://";
                    break;
                case 0x1A:
                    url = @"btgoep://";
                    break;
                case 0x1B:
                    url = @"btgoep://";
                    break;
                case 0x1C:
                    url = @"irdaobex://";
                    break;
                case 0x1D:
                    url = @"file://";
                    break;
                case 0x1E:
                    url = @"urn:epc:id:";
                    break;
                case 0x1F:
                    url = @"urn:epc:tag:";
                    break;
                case 0x20:
                    url = @"urn:epc:pat:";
                    break;
                case 0x21:
                    url = @"urn:epc:raw:";
                    break;
                case 0x22:
                    url = @"urn:epc:";
                    break;
                case 0x23:
                    url = @"urn:nfc:";
                    break;
                default:
                    url = @"";
            }
            // Remove the first byte from and add the URL prefix to the payload
            NSString *trimmedPayload = [[NSString alloc] initWithData:
                                        [payload.payload subdataWithRange:NSMakeRange(1, payload.payload.length-1)] encoding:NSUTF8StringEncoding];
            NSMutableString *payloadString = [[NSMutableString alloc]
                                              initWithString:trimmedPayload];
            [payloadString insertString:url atIndex:0];
            payloadData = payloadString;
            // Remove the prefix from the payload
            data = [[NSString alloc]
                    initWithData:[payload.payload
                                  subdataWithRange:NSMakeRange(1, payload.payload.length-1)]
                    encoding:NSUTF8StringEncoding];
        } else {
            payloadData = [[NSString alloc]
                           initWithData:payload.payload
                           encoding:NSUTF8StringEncoding];
            data = payloadData;
        }
        
        NSString *identifier;
        identifier = [[NSString alloc]
                      initWithData:payload.identifier
                      encoding:NSUTF8StringEncoding];
        
        NSString *tnf;
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
                tnf = @"external_type";
                break;
            case NFCTypeNameFormatUnchanged:
                tnf = @"unchanged";
                break;
            default:
                tnf = @"unknown";
        }
        
        NSMutableDictionary *record = [[NSMutableDictionary alloc]
                                       initWithObjectsAndKeys:type, @"type",
                                       payloadData, @"payload",
                                       data, @"data",
                                       identifier, @"id",
                                       tnf, @"tnf", nil];
        if (languageCode != nil) {
            [record setObject:languageCode forKey:@"languageCode"];
        }
        [records addObject:record];
    }
    NSDictionary *result = @{
        @"id": identifier,
        @"message_type": @"ndef",
        @"records": records,
    };
    return result;
}

- (NFCNDEFMessage * _Nonnull)formatNDEFMessageWithDictionary:(NSDictionary * _Nonnull)dictionary API_AVAILABLE(ios(13.0)) {
    NSMutableArray<NFCNDEFPayload *> *ndefRecords = [[NSMutableArray alloc] init];
    
    NSDictionary *message = [dictionary valueForKey:@"message"];
    NSArray<NSDictionary *> *records = [message valueForKey:@"records"];
    for (NSDictionary *record in records) {
        NSString *recordID = [record valueForKey:@"id"];
        NSString *recordType = [record valueForKey:@"type"];
        NSString *recordPayload = [record valueForKey:@"payload"];
        NSString *recordTNF = [record valueForKey:@"tnf"];
        NSString *recordLanguageCode = [record valueForKey:@"languageCode"];
        
        NSData *idData;
        if (recordID) {
            idData = [recordID dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            idData = [NSData data];
        }
        NSData *payloadData;
        if (recordPayload) {
            payloadData = [recordPayload dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            payloadData = [NSData data];
        }
        NSData *typeData;
        if (recordType) {
            typeData = [recordType dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            typeData = [NSData data];
        }
        NFCTypeNameFormat tnfValue;
        
        if ([@"empty" isEqualToString:recordTNF]) {
            // Empty records are not allowed to have a ID, type or payload.
            NFCNDEFPayload *ndefRecord = [[NFCNDEFPayload alloc] initWithFormat:NFCTypeNameFormatEmpty type:[NSData data] identifier:[NSData data] payload:[NSData data]];
            [ndefRecords addObject:ndefRecord];
            continue;
        } else if ([@"well_known" isEqualToString:recordTNF]) {
            if ([@"T" isEqualToString:recordType]) {
                NSLocale* locale = [NSLocale localeWithLocaleIdentifier:recordLanguageCode];
                NFCNDEFPayload *ndefRecord = [NFCNDEFPayload wellKnownTypeTextPayloadWithString:recordPayload locale:locale];
                [ndefRecords addObject:ndefRecord];
                continue;
            } else if ([@"U" isEqualToString:recordType]) {
                NFCNDEFPayload *ndefRecord = [NFCNDEFPayload wellKnownTypeURIPayloadWithString:recordPayload];
                [ndefRecords addObject:ndefRecord];
                continue;
            } else {
                tnfValue = NFCTypeNameFormatNFCWellKnown;
            }
        } else if ([@"mime_media" isEqualToString:recordTNF]) {
            tnfValue = NFCTypeNameFormatMedia;
        } else if ([@"absolute_uri" isEqualToString:recordTNF]) {
            tnfValue = NFCTypeNameFormatAbsoluteURI;
        } else if ([@"external_type" isEqualToString:recordTNF]) {
            tnfValue = NFCTypeNameFormatNFCExternal;
        } else if ([@"unchanged" isEqualToString:recordTNF]) {
            // TODO: Return error, not supposed to change the TNF value
            tnfValue = NFCTypeNameFormatUnchanged;
            continue;
        } else {
            tnfValue = NFCTypeNameFormatUnknown;
            // Unknown records are not allowed to have a type
            typeData = [NSData data];
        }
        
        NFCNDEFPayload* ndefRecord = [[NFCNDEFPayload alloc] initWithFormat:tnfValue type:typeData identifier:idData payload:payloadData];
        [ndefRecords addObject:ndefRecord];
    }
    
    return [[NFCNDEFMessage alloc] initWithNDEFRecords:ndefRecords];
}

// MARK: Tag operations

- (BOOL)isTagReadingAvailable {
    if (@available(iOS 13.0, *)) {
        return NFCTagReaderSession.readingAvailable;
    }
    return NO;
}

- (void)beginReadingTags:(BOOL)once API_AVAILABLE(ios(13.0)) {
    return;
}

- (void)tagReaderSessionDidBecomeActive:(NFCTagReaderSession * _Nonnull)session API_AVAILABLE(ios(13.0)) {
    return;
}

- (void)tagReaderSession:(NFCTagReaderSession * _Nonnull)session didDetectTags:(NSArray<id<NFCTag>> * _Nonnull)tags API_AVAILABLE(ios(13.0)) {
    return;
}

- (void)tagReaderSession:(NFCTagReaderSession * _Nonnull)session didInvalidateWithError:(NSError * _Nonnull)error API_AVAILABLE(ios(13.0)) {
    return;
}

- (void)iso7816SendCommand:(NFCISO7816APDU * _Nonnull)command completionHandler:(void (^ _Nonnull)(NSData * _Nullable, FlutterError * _Nullable))completionHandler API_AVAILABLE(ios(13.0)) {
    return;
}

- (void)iso15693ReadBlockRange:(RequestFlag)flag range:(NSRange)range completionHandler:(void (^)(NSArray<NSData *> * _Nullable, FlutterError * _Nullable))completionHandler API_AVAILABLE(ios(13.0)) {
    return;
}

// MARK: Flutter stream methods

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events {
    self->events = events;
    return nil;
}

// onCancelWithArguments is called when the event stream is canceled,
// which most likely happens because of manuallyStopStream().
// However if it was not triggered by manuallyStopStream(), it should invalidate
// the reader session if activate
- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    if (tagSession != nil) {
        [tagSession invalidateSession];
        tagSession = nil;
    }
    if (ndefSession != nil) {
        [ndefSession invalidateSession];
        ndefSession = nil;
    }
    events = nil;
    return nil;
}

@end
