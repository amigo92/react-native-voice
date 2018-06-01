

#import <AVFoundation/AVFoundation.h>

#import "AudioController.h"

@interface AudioController () {
    AudioComponentInstance remoteIOUnit;
}
@property (nonatomic, nullable) AVAudioFormat *format;
@property (nonatomic) AudioStreamBasicDescription asbdSaved;


@end

@implementation AudioController
@synthesize audioBuffer, gain;

+ (instancetype) sharedInstance {
    static AudioController *instance = nil;
    instance.gain = 0;
    if (!instance) {
        instance = [[self alloc] init];
    }
    return instance;
}

- (void) dealloc {
    AudioComponentInstanceDispose(remoteIOUnit);
}

static OSStatus CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) {
        return error;
    }
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    return error;
}

static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    OSStatus status;
    
    AudioController *audioController = (__bridge AudioController *) inRefCon;
    
    int channelCount = 1;
    
    // build the AudioBufferList structure
    AudioBufferList *bufferList = (AudioBufferList *) malloc (sizeof (AudioBufferList));
    bufferList->mNumberBuffers = channelCount;
    bufferList->mBuffers[0].mNumberChannels = 1;
    bufferList->mBuffers[0].mDataByteSize = inNumberFrames * 2;
    bufferList->mBuffers[0].mData = NULL;
    
    // get the recorded samples
    status = AudioUnitRender(audioController->remoteIOUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             bufferList);
    if (status != noErr) {
        return status;
    }
    
    NSData *data = [[NSData alloc] initWithBytes:bufferList->mBuffers[0].mData
                                          length:bufferList->mBuffers[0].mDataByteSize];
    dispatch_async(dispatch_get_main_queue(), ^{
        //    [audioController.delegate processSampleData:self.updateWithAudioBuffer()];
        //        [audioController processBuffer:bufferList];
        
        [audioController updateWithAudioBuffer:bufferList capacity:(AVAudioFrameCount)inNumberFrames];
    });
    
    return noErr;
}
-(void)processBuffer: (AudioBufferList*) audioBufferList
{
    AudioBuffer sourceBuffer = audioBufferList->mBuffers[0];
    
    // we check here if the input data byte size has changed
    if (audioBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
        // clear old buffer
        free(audioBuffer.mData);
        // assing new byte size and allocate them on mData
        audioBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
        audioBuffer.mData = malloc(sourceBuffer.mDataByteSize);
    }
    
    /**
     Here we modify the raw data buffer now.
     In my example this is a simple input volume gain.
     iOS 5 has this on board now, but as example quite good.
     */
    SInt16 *editBuffer = audioBufferList->mBuffers[0].mData;
    
    // loop over every packet
    for (int nb = 0; nb < (audioBufferList->mBuffers[0].mDataByteSize / 2); nb++) {
        
        // we check if the gain has been modified to save resoures
        if (gain != 0) {
            // we need more accuracy in our calculation so we calculate with doubles
            double gainSample = ((double)editBuffer[nb]) / 32767.0;
            
            /*
             at this point we multiply with our gain factor
             we dont make a addition to prevent generation of sound where no sound is.
             
             no noise
             0*10=0
             
             noise if zero
             0+10=10
             */
            gainSample *= 2;
            
            /**
             our signal range cant be higher or lesser -1.0/1.0
             we prevent that the signal got outside our range
             */
            gainSample = (gainSample < -1.0) ? -1.0 : (gainSample > 1.0) ? 1.0 : gainSample;
            
            /*
             This thing here is a little helper to shape our incoming wave.
             The sound gets pretty warm and better and the noise is reduced a lot.
             Feel free to outcomment this line and here again.
             
             You can see here what happens here http://silentmatt.com/javascript-function-plotter/
             Copy this to the command line and hit enter: plot y=(1.5*x)-0.5*x*x*x
             */
            
            gainSample = (1.5 * gainSample) - 0.5 * gainSample * gainSample * gainSample;
            
            // multiply the new signal back to short
            gainSample = gainSample * 32767.0;
            
            // write calculate sample back to the buffer
            editBuffer[nb] = (SInt16)gainSample;
        }
    }
    
    // copy incoming audio data to the audio buffer
    memcpy(audioBuffer.mData, audioBufferList->mBuffers[0].mData, audioBufferList->mBuffers[0].mDataByteSize);
}

- (void)updateWithAudioBuffer:(AudioBufferList *)list capacity:(AVAudioFrameCount)capacity {
    
    AudioBuffer *pBuffer = &list->mBuffers[0];
    //    [self.format.streamDescription ];
    //    self.format.streamDescription.m
    //    self.asbdSaved.m
    //    self.format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt32 sampleRate:16000 channels:1 interleaved:NO];
    //    self.format
    AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat: self.format frameCapacity:capacity];
    outBuffer.frameLength = pBuffer->mDataByteSize/2;
    float *pData = (float *)pBuffer->mData;
    memcpy(outBuffer.int16ChannelData[0], pData, pBuffer->mDataByteSize);
    [self.delegate processSampleData:outBuffer];
    //    [self.delegate audioTabProcessor:self didReceiveBuffer:outBuffer];
}

static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberFrames,
                                 AudioBufferList *ioData) {
    OSStatus status = noErr;
    
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    AudioController *audioController = (__bridge AudioController *) inRefCon;
    
    UInt32 bus1 = 1;
    status = AudioUnitRender(audioController->remoteIOUnit,
                             ioActionFlags,
                             inTimeStamp,
                             bus1,
                             inNumberFrames,
                             ioData);
    CheckError(status, "Couldn't render from RemoteIO unit");
    return status;
}

- (OSStatus) prepareWithSampleRate:(double) specifiedSampleRate {
    OSStatus status = noErr;
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    NSError *error;
    BOOL ok = [session setCategory:AVAudioSessionCategoryRecord error:&error];
    NSLog(@"set category %d", ok);
    
    // This doesn't seem to really indicate a problem (iPhone 6s Plus)
#ifdef IGNORE
    NSInteger inputChannels = session.inputNumberOfChannels;
    if (!inputChannels) {
        NSLog(@"ERROR: NO AUDIO INPUT DEVICE");
        return -1;
    }
#endif
    
    [session setPreferredIOBufferDuration:10 error:&error];
    
    double sampleRate = session.sampleRate;
    NSLog (@"hardware sample rate = %f, using specified rate = %f", sampleRate, specifiedSampleRate);
    sampleRate = specifiedSampleRate;
    
    // Describe the RemoteIO unit
    AudioComponentDescription audioComponentDescription;
    audioComponentDescription.componentType = kAudioUnitType_Output;
    audioComponentDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    audioComponentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioComponentDescription.componentFlags = 0;
    audioComponentDescription.componentFlagsMask = 0;
    
    // Get the RemoteIO unit
    AudioComponent remoteIOComponent = AudioComponentFindNext(NULL,&audioComponentDescription);
    status = AudioComponentInstanceNew(remoteIOComponent,&(self->remoteIOUnit));
    if (CheckError(status, "Couldn't get RemoteIO unit instance")) {
        return status;
    }
    
    UInt32 oneFlag = 1;
    AudioUnitElement bus0 = 0;
    AudioUnitElement bus1 = 1;
    
    if ((NO)) {
        // Configure the RemoteIO unit for playback
        status = AudioUnitSetProperty (self->remoteIOUnit,
                                       kAudioOutputUnitProperty_EnableIO,
                                       kAudioUnitScope_Output,
                                       bus0,
                                       &oneFlag,
                                       sizeof(oneFlag));
        if (CheckError(status, "Couldn't enable RemoteIO output")) {
            return status;
        }
    }
    
    // Configure the RemoteIO unit for input
    status = AudioUnitSetProperty(self->remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  bus1,
                                  &oneFlag,
                                  sizeof(oneFlag));
    if (CheckError(status, "Couldn't enable RemoteIO input")) {
        return status;
    }
    
    AudioStreamBasicDescription asbd;
    memset(&asbd, 0, sizeof(asbd));
    asbd.mSampleRate = sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket = 2;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 2;
    asbd.mChannelsPerFrame = 1;
    asbd.mBitsPerChannel = 16;
    self.asbdSaved = (asbd);
    self.format = [[AVAudioFormat alloc] initWithStreamDescription:&asbd];
    // Set format for output (bus 0) on the RemoteIO's input scope
    status = AudioUnitSetProperty(self->remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  bus0,
                                  &asbd,
                                  sizeof(asbd));
    if (CheckError(status, "Couldn't set the ASBD for RemoteIO on input scope/bus 0")) {
        return status;
    }
    
    // Set format for mic input (bus 1) on RemoteIO's output scope
    status = AudioUnitSetProperty(self->remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  bus1,
                                  &asbd,
                                  sizeof(asbd));
    if (CheckError(status, "Couldn't set the ASBD for RemoteIO on output scope/bus 1")) {
        return status;
    }
    
    // Set the recording callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void *) self;
    status = AudioUnitSetProperty(self->remoteIOUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  bus1,
                                  &callbackStruct,
                                  sizeof (callbackStruct));
    if (CheckError(status, "Couldn't set RemoteIO's render callback on bus 0")) {
        return status;
    }
    
    if ((NO)) {
        // Set the playback callback
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = playbackCallback;
        callbackStruct.inputProcRefCon = (__bridge void *) self;
        status = AudioUnitSetProperty(self->remoteIOUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Global,
                                      bus0,
                                      &callbackStruct,
                                      sizeof (callbackStruct));
        if (CheckError(status, "Couldn't set RemoteIO's render callback on bus 0")) {
            return status;
        }
    }
    
    // Initialize the RemoteIO unit
    audioBuffer.mNumberChannels = 1;
    audioBuffer.mDataByteSize = 512 * 2;
    audioBuffer.mData = malloc( 512 * 2 );
    
    status = AudioUnitInitialize(self->remoteIOUnit);
    if (CheckError(status, "Couldn't initialize the RemoteIO unit")) {
        return status;
    }
    
    return status;
}

- (OSStatus) start {
    
    return AudioOutputUnitStart(self->remoteIOUnit);
}

- (OSStatus) stop {
    return AudioOutputUnitStop(self->remoteIOUnit);
}

@end



