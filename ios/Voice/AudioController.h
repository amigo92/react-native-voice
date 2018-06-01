
#import <Foundation/Foundation.h>

@protocol AudioControllerDelegate <NSObject>

- (void) processSampleData:(AVAudioPCMBuffer *) data;

@end

@interface AudioController : NSObject

+ (instancetype) sharedInstance;

@property (nonatomic, weak) id<AudioControllerDelegate> delegate;
@property (readonly) AudioBuffer audioBuffer;
@property (nonatomic) float gain;

- (OSStatus) prepareWithSampleRate:(double) sampleRate;
- (OSStatus) start;
- (OSStatus) stop;

@end



