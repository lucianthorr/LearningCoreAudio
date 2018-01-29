//
//  AppDelegate.m
//  CAiOSBackgroundTone
//
//  Created by Jason Aylward on 1/15/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import "AppDelegate.h"


/*AVAudioSession *session = [AVAudioSession sharedInstance];
 NSError *setCategoryError = nil;
 if (![session setCategory:AVAudioSessionCategoryPlayback
 withOptions:AVAudioSessionCategoryOptionMixWithOthers
 error:&setCategoryError]) {
 // handle error
 }*/



#pragma mark - #defines
// 10.4 - Define Frequencies and Audio Queue Constants for the iOS Tone Generator
#define FOREGROUND_FREQUENCY 880.0
#define BACKGROUND_FREQUENCY 523.25
#define BUFFER_COUNT 3
#define BUFFER_DURATION 0.5


@interface AppDelegate ()

@end

@implementation AppDelegate

#pragma mark - @synthesizes


// 10.3 - Synthesize the properties
@synthesize window = _window;
@synthesize streamFormat = _streamFormat;
@synthesize audioQueue;
@synthesize bufferSize;
@synthesize  currentFrequency;
@synthesize startingFrameCount;



#pragma mark - Utilities
// 4.2 -- Error handling, use as a wrapper around functions that return OSStatus
static void CheckError(OSStatus error, const char *operation){
    if(error == noErr) return;
    
    char errorString[20];
    // See if it appears to be a 4-char-code
    // Writes the value of error (in Int32 format) to the address of errorString + 1
    *(UInt32 *)(errorString +1) = CFSwapInt32HostToBig(error);
    if(isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])){
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
        fprintf(stderr, "Error: %s(%s)\n", operation, errorString);
        exit(1);
    }
}

#pragma mark Callbacks
// 10.11 - Refill Buffers with Sine Wave Samples
-(OSStatus) fillBuffer: (AudioQueueBufferRef)buffer {
    double j = self.startingFrameCount;
    double cycleLength = 44100. / self.currentFrequency;
    int frame = 0;
    double frameCount = bufferSize/self.streamFormat.mBytesPerFrame;
    for(frame = 0; frame<frameCount; ++frame){
        SInt16 *data = (SInt16*)buffer->mAudioData;
        (data)[frame] = (SInt16)(sin(2*M_PI*(j/cycleLength))*SHRT_MAX);
        j += 1.0;
        if(j > cycleLength){
            j -= cycleLength;
        }
    }
    self.startingFrameCount = j;
    buffer->mAudioDataByteSize = bufferSize;
    return noErr;
}
// 10.12 - Callback to refill an AudioQueueBufferRef
static void MyAQOutputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inCompleteAQBuffer){
    AppDelegate *appDelegate = (__bridge AppDelegate*)inUserData;
    CheckError([appDelegate fillBuffer: inCompleteAQBuffer], "can't refill buffer");
    CheckError(AudioQueueEnqueueBuffer(inAQ, inCompleteAQBuffer, 0, NULL), "Couldn't enqueue the buffer, (aka refill)");
}
// 10.13 - Handle Audio Interruptions
void MyInterruptionListener(void *inUserData, UInt32 inInterruptionState) {
    printf("Interrupted! inInterruptionState = %1d\n", inInterruptionState);
    AppDelegate *appDelegate = (__bridge_transfer AppDelegate*)inUserData;
    switch(inInterruptionState){
        case kAudioSessionBeginInterruption:
            break;
        case kAudioSessionEndInterruption:
            CheckError(AudioQueueStart(appDelegate.audioQueue, 0), "Couldn't restart the audio queue");
            break;
        default:
            break;
    };
}


#pragma mark App Lifecycle

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Set up the audio session
    // 10.5 - Establish an Audio Session with AudioSessionInitialize()
    CheckError(AudioSessionInitialize(NULL, kCFRunLoopDefaultMode, MyInterruptionListener, (__bridge void*)self), "Couldn't initialize the audio session");
    // 10.6 - Set the Audio Category for the app
    UInt32 category = kAudioSessionCategory_MediaPlayback;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category), "Couldn't set category on audio session");
    
    // Set the stream format
    // 10.7 - Create AudioStreamBasicDescription for a Programmatically Generated Sine Wave
    self.currentFrequency = FOREGROUND_FREQUENCY;
    _streamFormat.mSampleRate = 44100.0;
    _streamFormat.mFormatID = kAudioFormatLinearPCM;
    _streamFormat.mFormatFlags = kAudioFormatFlagsCanonical;
    _streamFormat.mChannelsPerFrame = 1;
    _streamFormat.mFramesPerPacket = 1;
    _streamFormat.mBitsPerChannel = 16;
    _streamFormat.mBytesPerFrame = 2;
    _streamFormat.mBytesPerPacket = 2;
    
    // Set up the audio queue
    // 10.8 - Create an Audio Queue on iOS
    CheckError(AudioQueueNewOutput(&_streamFormat, MyAQOutputCallback, (__bridge_retained void*)self, NULL, kCFRunLoopCommonModes, 0, &audioQueue), "Couldn't create the output AudioQueue");
    // 10.9 - Prime the Audio Queue on iOS
    // Create and enqueue buffers
    AudioQueueBufferRef buffers[BUFFER_COUNT];
    bufferSize = BUFFER_DURATION * self.streamFormat.mSampleRate * self.streamFormat.mBytesPerFrame;
    NSLog(@"bufferSize is %1d", bufferSize);
    for(int i=0; i<BUFFER_COUNT; i++){
        CheckError(AudioQueueAllocateBuffer(audioQueue, bufferSize, &buffers[i]), "Couldn't allocate the Audio Queue buffer");
        CheckError([self fillBuffer: buffers[i]], "Couldn't fill buffer (priming)");
        CheckError(AudioQueueEnqueueBuffer(audioQueue, buffers[i], 0, NULL), "Couldn't enqueue buffer (priming)");
    }
    
    // 10.10 - Start the audio queue
    CheckError(AudioQueueStart(audioQueue, NULL), "Couldn't start the AudioQueue");
    
    // Override point for customization after the application launches
    [self.window makeKeyAndVisible];
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

// 10.14 - Handle Backgrounding App
- (void)applicationDidEnterBackground:(UIApplication *)application {
    NSLog(@"Entering Background");
    self.currentFrequency = BACKGROUND_FREQUENCY;
}

// 10.15 - Handle foregrounding
- (void)applicationWillEnterForeground:(UIApplication *)application {
    NSLog(@"Entering Foreground");
    CheckError(AudioSessionSetActive(true), "Couldn't re-set audio session active");
    CheckError(AudioQueueStart(self.audioQueue, 0), "Couldn't restart audio queue");
    self.currentFrequency = FOREGROUND_FREQUENCY;
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


@end
