//
//  AppDelegate.m
//  CAiOSPlayThrough
//
//  Created by Jason Aylward on 1/21/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import "AppDelegate.h"



@implementation AppDelegate
#pragma mark @synthesizes
// 10.18 - Synthesize properties
@synthesize window = _window;
@synthesize effectState = _effectState;


#pragma mark Helpers
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
// 10.28 - Initial Setup of Render Callback from RemoteIO
static OSStatus InputModulatingRenderCallback (void * inRefCon, AudioUnitRenderActionFlags * ioActionFlags, const AudioTimeStamp * inTimeStamp,
                                               UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList * ioData){
    EffectState *effectState = (EffectState*)inRefCon;
    // 10.29 - Copy Captured Sample to Play-Out Buffer in RemoteIO Render Callback
    // Just copy samples
    UInt32 bus1 = 1;
    CheckError(AudioUnitRender(effectState->rioUnit, ioActionFlags, inTimeStamp, bus1, inNumberFrames, ioData), "Couldn't render from RemoteIO unit");
    // 10.30 - Perform ring modulation effect on a buffer of samples
    // Walk the samples
    AudioSampleType sample = 0;
    UInt32 bytesPerChannel = effectState->asbd.mBytesPerFrame / effectState->asbd.mChannelsPerFrame;
    for (int bufCount=0; bufCount<ioData->mNumberBuffers; bufCount++){
        AudioBuffer buf = ioData->mBuffers[bufCount];
        int currentFrame = 0;
        while(currentFrame < inNumberFrames){
            // Copy samples to buffer, across all channels
            for (int currentChannel=0; currentChannel<buf.mNumberChannels; currentChannel++){
                memcpy(&sample, buf.mData+(currentFrame * effectState->asbd.mBytesPerFrame) + (currentChannel * bytesPerChannel), sizeof(AudioSampleType));
                float theta = effectState->sinePhase *M_PI * 2;
                sample = (sin(theta) * sample);
                memcpy(buf.mData + (currentFrame * effectState->asbd.mBytesPerFrame) + (currentChannel*bytesPerChannel), &sample, sizeof(AudioSampleType));
                effectState->sinePhase += 1.0/ (effectState->asbd.mSampleRate / effectState-> sineFrequency);
                if(effectState->sinePhase > 1.0){
                    effectState->sinePhase-=1.0;
                }
            }
            currentFrame++;
        }
    }
    return noErr;
}



#pragma mark Callbacks
// 10.27 Handle RIO Unit Interruptions on iOS
static void MyInterruptionListener(void *inUserData, UInt32 inInterruptionState){
    printf("Interrupted! inInterruptionState=%d\n", inInterruptionState);
    AppDelegate *appDelegate = (__bridge AppDelegate*)inUserData;
    switch(inInterruptionState) {
        case kAudioSessionBeginInterruption:
            break;
        case kAudioSessionEndInterruption:
            CheckError(AudioSessionSetActive(true), "Couldn't set audio session active");
            CheckError(AudioUnitInitialize(appDelegate.effectState.rioUnit), "Couldn't initialize RIO unit");
            CheckError(AudioOutputUnitStart(appDelegate.effectState.rioUnit), "Couldn't start RIO unit");
            break;
        default:
            break;
    };
}


#pragma mark App lifecycle

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 10.19 - Set up Audio Session for iOS play-through
    CheckError(AudioSessionInitialize(NULL, kCFRunLoopDefaultMode, MyInterruptionListener, (__bridge_retained void*)self), "Couldn't initialize the audio session");
    UInt32 category = kAudioSessionCategory_PlayAndRecord;
    CheckError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category), "Couldn't set the category on the audio session");
    
    // 10.20 - Check for Audio Input Availability on iOS
    UInt32 ui32PropertySize = sizeof(UInt32);
    UInt32 inputAvailable;
    CheckError(AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &ui32PropertySize, &inputAvailable), "Couldn't get current audio input available prop");
    if(!inputAvailable){
        UIAlertView *noInputAlert = [[UIAlertView alloc] initWithTitle: @"No audio input" message:@"No audio input device is currectly attached" delegate: nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
        [noInputAlert show];
        return YES;
    }
    
    // 10.21 - Get Hardware sample rate
    Float64 hardwareSampleRate;
    UInt32 propSize = sizeof(hardwareSampleRate);
    CheckError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &propSize, &hardwareSampleRate), "Couldn't get hardwareSampleRate");
    NSLog(@"hardwareSampleRate = %f", hardwareSampleRate);
    
    // 10.22 - Get RemoteIO Unit from audio component manager
    // Describe the unit
    AudioComponentDescription audioCompDesc;
    audioCompDesc.componentType = kAudioUnitType_Output;
    audioCompDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    audioCompDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioCompDesc.componentFlags = 0;
    audioCompDesc.componentFlagsMask = 0;
    // Get the RIO unit from the audio component manager
    AudioComponent rioComponent = AudioComponentFindNext(NULL, &audioCompDesc);
    CheckError(AudioComponentInstanceNew(rioComponent, &_effectState.rioUnit), "Couldn't get RIO unit instance");
    
    // Configure Rio unit
    // 10.23 - Enable IO on RemoteIO Audio Unit
    // Setup the RIO unit for playback
    UInt32 oneFlag = 1;
    AudioUnitElement bus0 = 0;
    CheckError(AudioUnitSetProperty(_effectState.rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, bus0, &oneFlag, sizeof(oneFlag)), "Couldn't enable RIO output");
    // Enable RIO input
    AudioUnitElement bus1=1;
    CheckError(AudioUnitSetProperty(_effectState.rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, bus1, &oneFlag, sizeof(oneFlag)), "Couldn't enable RIO input");
    
    // 10.24 - Set Stream Format on RIO audio unit
    // Setup an ASBD in the iphone canonical format
    AudioStreamBasicDescription myASBD;
    memset(&myASBD, 0, sizeof(myASBD));
    myASBD.mSampleRate = hardwareSampleRate;
    myASBD.mFormatID = kAudioFormatLinearPCM;
    myASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    myASBD.mBytesPerPacket = 4;
    myASBD.mFramesPerPacket = 1;
    myASBD.mBytesPerFrame = 4;
    myASBD.mChannelsPerFrame = 2;
    myASBD.mBitsPerChannel = 16;
    
    // Set format for output (bus 0) on the RIO's input scope
    CheckError(AudioUnitSetProperty(_effectState.rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus0, &myASBD, sizeof(myASBD)), "Couldn't set the ASBD for RIO on the input scope/bus0");
    // Set ASBD for mic input  (bus1) on RIO's output scope
    CheckError(AudioUnitSetProperty(_effectState.rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus1, &myASBD, sizeof(myASBD)), "Couldn't set the ASBD for RIO on the output scope/bus1");
    
    // 10.25 - Setup the render callback for RIO audio unit
    _effectState.asbd = myASBD;
    _effectState.sineFrequency = 30;
    _effectState.sinePhase = 0;
    // Set the callback method
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = InputModulatingRenderCallback;
    callbackStruct.inputProcRefCon = &_effectState;
    CheckError(AudioUnitSetProperty(_effectState.rioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, bus0, &callbackStruct, sizeof(callbackStruct)), "Couldn't set RIO's render callback on bus 0");
    // Start Rio AudioUnit
    // 10.26 - Start the RemoteIO Unit
    // Initialize and start the RIO unit
    CheckError(AudioUnitInitialize(_effectState.rioUnit), "Couldn't initialize the RIO unit");
    CheckError(AudioOutputUnitStart(_effectState.rioUnit), "Couldn't start the RIO unit");
    printf("RIO started!\n");
    
    [self.window makeKeyAndVisible];
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


@end
