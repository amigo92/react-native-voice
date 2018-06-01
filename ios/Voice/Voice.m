#import "Voice.h"
#import <React/RCTLog.h>
#import <UIKit/UIKit.h>
#import <React/RCTUtils.h>
#import <React/RCTEventEmitter.h>
#import <Speech/Speech.h>
#import "AudioController.h"


#define SAMPLE_RATE 16000.0f

@interface Voice () <SFSpeechRecognizerDelegate,AudioControllerDelegate>

@property (nonatomic) SFSpeechRecognizer* speechRecognizer;
@property (nonatomic) SFSpeechAudioBufferRecognitionRequest* recognitionRequest;
@property (nonatomic) AVAudioEngine* audioEngine;
@property (nonatomic) SFSpeechRecognitionTask* recognitionTask;
@property (nonatomic) AVAudioSession* audioSession;
@property (nonatomic) NSString *sessionId;
@property (nonatomic) AVCaptureSession* capture;


@property (nonatomic, strong) AVAudioRecorder *monitor;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) NSURL *monitorURL;


@property (nonatomic) NSString* startTime;
@property (nonatomic) NSString* startTimeToSend;
@property (nonatomic) NSString* endTime;
@property (nonatomic) NSString* endTimeToSend;
@property (nonatomic) NSString* meetingID;
@property (nonatomic) NSString* recordingID;
@property (nonatomic) NSNumber* confidence;
@property (nonatomic) NSString* userId;
@property (nonatomic) NSString* urlToConnect;
@property (nonatomic) NSString* finalTranscript;
@property (nonatomic) NSString* finalTranscriptToSend;
@property (nonatomic) BOOL isFinal;

@property (nonatomic) AVAudioRecorder* recorder;
@property (nonatomic) BOOL shouldAppendBuffers;



@end

@implementation Voice
{
}

- (void) setupAndStartRecognizing:(NSString*)localeStr {
    [self teardown];
    self.sessionId = [[NSUUID UUID] UUIDString];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    
    NSDate *now = [NSDate date];
    NSString *iso8601String = [dateFormatter stringFromDate:now];
    
   
    NSLocale* locale = nil;
    if ([localeStr length] > 0) {
        locale = [NSLocale localeWithLocaleIdentifier:localeStr];
    }

    if (locale) {
        self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    } else {
        self.speechRecognizer = [[SFSpeechRecognizer alloc] init];
    }

    self.speechRecognizer.delegate = self;

    NSError* audioSessionError = nil;
    self.audioSession = [AVAudioSession sharedInstance];

    if (audioSessionError != nil) {
        [self sendResult:RCTMakeError([audioSessionError localizedDescription], nil, nil) :nil :nil :nil];
        return;
    }

    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    
    if (self.recognitionRequest == nil){
        [self sendResult:RCTMakeError(@"Unable to created a SFSpeechAudioBufferRecognitionRequest object", nil, nil) :nil :nil :nil];
        return;
    }

    if (self.audioEngine == nil) {
        self.audioEngine = [[AVAudioEngine alloc] init];
    }


//    AVAudioInputNode* inputNode = self.audioEngine.inputNode;
//    if (inputNode == nil) {
//        [self sendResult:RCTMakeError(@"Audio engine has no input node", nil, nil) :nil :nil :nil];
//        return;
//    }

    // Configure request so that results are returned before audio recording is finished
    self.recognitionRequest.shouldReportPartialResults = YES;
//    NSError* audioSessionError = nil;
//    self.audioSession = [AVAudioSession sharedInstance];
//    CGFloat gain = 1;
//    NSError* error;
//    if (self.audioSession.isInputGainSettable) {
//        BOOL success = [self.audioSession setInputGain:gain
//                                                 error:&error];
//        if (!success){} //error handling
//    } else {
//        NSLog(@"ios6 - cannot set input gain");
//    }
//
//    [self sendEventWithName:@"onSpeechStart" body:@true];

    // A recognition task represents a speech recognition session.
    // We keep a reference to the task so that it can be cancelled.
    NSString *taskSessionId = self.sessionId;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
//        if (![taskSessionId isEqualToString:self.sessionId]) {
//            // session ID has changed, so ignore any capture results and error
//            return;
//        }
        if (error != nil && self.shouldAppendBuffers) {
            NSString *errorMessage = [NSString stringWithFormat:@"%ld/%@", error.code, [error localizedDescription]];
//            [self sendResult:RCTMakeError(errorMessage, nil, nil) :nil :nil :nil];
//            [self teardown];
//            [self setupAndStartRecognizing:nil];
            return;
        }

        BOOL isFinal = result.isFinal;
        self.isFinal = isFinal;
//        NSLog(@"%@",result.bestTranscription.formattedString);
        if (result != nil) {
            NSMutableArray* transcriptionDics = [NSMutableArray new];
            for (SFTranscription* transcription in result.transcriptions) {
                [transcriptionDics addObject:transcription.formattedString];
            }
            self.finalTranscript = result.bestTranscription.formattedString;
            [self sendResult:nil:result.bestTranscription.formattedString :transcriptionDics :@(isFinal)];
        }

        if (self.startTime == nil) {
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            
            [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
            
            NSDate *now = [NSDate date];
            NSString *iso8601String = [dateFormatter stringFromDate:now];
            self.startTime = iso8601String;
//            NSLog(@"startTime is : %@",self.startTime);

        }
        
        if (isFinal == YES) {
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            
            [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
            
            NSDate *now = [NSDate date];
            NSString *iso8601String = [dateFormatter stringFromDate:now];
            self.endTime = iso8601String;
            [self sendData:result.bestTranscription.formattedString];
            self.startTime = nil;
//            NSLog(@"startTime is nil");
            if (self.recognitionTask.isCancelled || self.recognitionTask.isFinishing){
                [self sendEventWithName:@"onSpeechEnd" body:@{@"error": @false}];
            }
//            [self teardown];
        }
    }];
//    AVAudioFormat* recordingFormat = [inputNode outputFormatForBus:0];
//    AVAudioMixerNode *mixer = [[AVAudioMixerNode alloc] init];
//    [self.audioEngine attachNode:mixer];
//    [mixer installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
//        if (self.recognitionRequest != nil) {
//            [self.recognitionRequest appendAudioPCMBuffer:buffer];
//        }
//    }];
//    [self.audioEngine connect:inputNode to:mixer format:[inputNode inputFormatForBus:0]];
//    [self.audioEngine prepare];
//    [self.audioEngine startAndReturnError:&audioSessionError];
    if (audioSessionError != nil) {
        [self sendResult:RCTMakeError([audioSessionError localizedDescription], nil, nil) :nil :nil :nil];
        return;
    }
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[
        @"onSpeechResults",
        @"onSpeechStart",
        @"onSpeechPartialResults",
        @"onSpeechError",
        @"onSpeechEnd",
        @"onSpeechRecognized",
        @"onSpeechVolumeChanged"
    ];
}

- (void) sendResult:(NSDictionary*)error :(NSString*)bestTranscription :(NSArray*)transcriptions :(NSNumber*)isFinal {
//    NSLog(@"%@", bestTranscription);
    if (error != nil) {
//        [self sendEventWithName:@"onSpeechError" body:@{@"error": error}];
    }
    if (bestTranscription != nil) {
//        NSLog(@"%@",bestTranscription);
        //        [self sendEventWithName:@"onSpeechResults" body:@{@"value":@[bestTranscription]} ];
    }
    if (transcriptions != nil) {
//        [self sendEventWithName:@"onSpeechPartialResults" body:@{@"value":transcriptions} ];
    }
    if (isFinal != nil) {
//        [self sendEventWithName:@"onSpeechRecognized" body: @{@"isFinal": isFinal}];
    }
}

-(void)sendData:(NSString *)transcript {
    
    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.urlToConnect]];
    
    [urlRequest setHTTPMethod:@"POST"];
    [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *userDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:self.meetingID, @"meetingId",self.startTime,@"startTime",@0.9,@"confidence",self.recordingID,@"recordingId" ,self.endTime,@"endTime",self.userId,@"SpokenBy",transcript,@"text", nil];
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:userDictionary options:NSJSONWritingPrettyPrinted error: nil];
    [urlRequest setValue:[NSString stringWithFormat:@"%lu",(unsigned long)[jsonData length]] forHTTPHeaderField:@"Content-length"];
    [urlRequest setHTTPBody:jsonData];//set data

    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if(httpResponse.statusCode == 200)
        {
            NSError *parseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            NSLog(@"The response is - %@",responseDictionary);
        }
        else
        {
//            NSLog(@"Error");
        }
    }];
    [dataTask resume];
}

- (void) teardown {
    [self.recognitionTask cancel];
    self.recognitionTask = nil;
    self.audioSession = nil;
    self.sessionId = nil;
//    if (self.audioEngine.isRunning) {
//        [self.audioEngine stop];
        [self.recognitionRequest endAudio];
//        [self.audioEngine.inputNode removeTapOnBus:0];
//    }

    self.recognitionRequest = nil;
}

// Called when the availability of the given recognizer changes
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    if (available == false) {
        [self sendResult:RCTMakeError(@"Speech recognition is not available now", nil, nil) :nil :nil :nil];
    }
}

RCT_EXPORT_METHOD(stopSpeech:(RCTResponseSenderBlock)callback)
{
    [self.recognitionTask finish];
    self.shouldAppendBuffers = NO;
    callback(@[@false]);
}


RCT_EXPORT_METHOD(toggleAppend:(RCTResponseSenderBlock)callback)
{
//    self.shouldAppendBuffers = !self.shouldAppendBuffers;
    self.shouldAppendBuffers = YES;
//    [self teardown];
//    [self setupAndStartRecognizing:nil];
    callback(@[@false]);
}

RCT_EXPORT_METHOD(cancelSpeech:(RCTResponseSenderBlock)callback) {
    [self.recognitionTask cancel];
    callback(@[@false]);
}

RCT_EXPORT_METHOD(destroySpeech:(RCTResponseSenderBlock)callback) {
    [self teardown];
    [[AudioController sharedInstance] stop];
    callback(@[@false]);
    [self.timer invalidate];
    if (!self.isFinal) {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    
    NSDate *now = [NSDate date];
    NSString *iso8601String = [dateFormatter stringFromDate:now];
    self.endTime = iso8601String;
//        NSLog(@"end time is : %@",self.endTime);
    [self sendData:self.finalTranscript];
    }
}

RCT_EXPORT_METHOD(isSpeechAvailable:(RCTResponseSenderBlock)callback) {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                callback(@[@true]);
                break;
            default:
                callback(@[@false]);
        }
    }];
}
RCT_EXPORT_METHOD(isRecognizing:(RCTResponseSenderBlock)callback) {
    if (self.recognitionTask != nil){
        switch (self.recognitionTask.state) {
            case SFSpeechRecognitionTaskStateRunning:
                callback(@[@true]);
                break;
            default:
                callback(@[@false]);
        }
    }
    else {
        callback(@[@false]);
    }
}

- (void) processSampleData:(AVAudioPCMBuffer *)data
{
    //  [self.audioData appendData:data];
    //  NSInteger frameCount = [data length] / 2;
    //  int16_t *samples = (int16_t *) [data bytes];
    //  int64_t sum = 0;
    //  for (int i = 0; i < frameCount; i++) {
    //    sum += abs(samples[i]);
    //  }
    //  NSLog(@"audio %d %d", (int) frameCount, (int) (sum * 1.0 / frameCount));
    
    // We recommend sending samples in 100ms chunks
    if (self.recognitionTask != nil){
        switch (self.recognitionTask.state) {
            case SFSpeechRecognitionTaskStateRunning:
                break;
            case SFSpeechRecognitionTaskStateStarting:
                break;
            default:
                //                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (self.shouldAppendBuffers && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
                [self teardown];
                [self setupAndStartRecognizing:nil];
                }
                //                });
        }
    }
    else {
        //        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.shouldAppendBuffers && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        [self teardown];
        [self setupAndStartRecognizing:nil];
        }
        //        });
    }
    if (self.shouldAppendBuffers ) {
        [self.recognitionRequest appendAudioPCMBuffer:data];
    }
}

RCT_EXPORT_METHOD(startSpeech:(NSString*)localeStr meetingID:(NSString*)meetingID recordingID:(NSString*)recordingID userID:(NSString*)userID url:(NSString*)url callback:(RCTResponseSenderBlock)callback) {
    self.meetingID = meetingID;
    self.recordingID = recordingID;
    self.userId = userID;
    self.urlToConnect = url;
    [AudioController sharedInstance].delegate = self;
    [[AudioController sharedInstance] prepareWithSampleRate:SAMPLE_RATE];
    [self.audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [[AudioController sharedInstance] start];
    self.shouldAppendBuffers = YES;
//    [self setupRecorder];
//    [self setupTimer];
    if (self.recognitionTask != nil) {
        [self sendResult:RCTMakeError(@"Speech recognition already started!", nil, nil) :nil :nil :nil];
        return;
    }

    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                [self sendResult:RCTMakeError(@"Speech recognition not yet authorized", nil, nil) :nil :nil :nil];
                break;
            case SFSpeechRecognizerAuthorizationStatusDenied:
                [self sendResult:RCTMakeError(@"User denied access to speech recognition", nil, nil) :nil :nil :nil];
                break;
            case SFSpeechRecognizerAuthorizationStatusRestricted:
                [self sendResult:RCTMakeError(@"Speech recognition restricted on this device", nil, nil) :nil :nil :nil];
                break;
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                [self setupAndStartRecognizing:localeStr];
                break;
        }
    }];
    callback(@[@false]);
}
- (void)setupRecorder {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:NULL];
    
    NSDictionary *recordSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                    [NSNumber numberWithFloat: 14400.0], AVSampleRateKey,
                                    [NSNumber numberWithInt: kAudioFormatAppleIMA4], AVFormatIDKey,
                                    [NSNumber numberWithInt: 2], AVNumberOfChannelsKey,
                                    [NSNumber numberWithInt: AVAudioQualityMax], AVEncoderAudioQualityKey,
                                    nil];
    NSString *monitorPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"monitor.caf"];
    _monitorURL = [NSURL fileURLWithPath:monitorPath];
    _monitor = [[AVAudioRecorder alloc] initWithURL:_monitorURL settings:recordSettings error:NULL];
    _monitor.meteringEnabled = YES;
}
- (void)setupTimer {
    [self.monitor record];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
}

- (void)updateTimer {
    
    // 不更新就没法用了
    [self.monitor updateMeters];
    
    // 获得0声道的音量，完全没有声音-160.0，0是最大音量
    float power = [self.monitor peakPowerForChannel:0];
    
    NSLog(@"%f", power);
    if (power > -20) {
//        if (!self.recorder.isRecording) {
        if (self.recognitionTask.state != SFSpeechRecognitionTaskStateRunning ) {
        [self teardown];
            [self setupAndStartRecognizing:nil];
        }
       
//        }
    } else {
//        if (self.recorder.isRecording) {
        if (self.recognitionTask.state == SFSpeechRecognitionTaskStateRunning ) {
            [self.recognitionTask finish];
        }
//        }
    }
}



- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()



@end
