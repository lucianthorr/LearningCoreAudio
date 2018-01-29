//
//  main.m
//  CASineWavePlayer
//
//  Created by Jason Aylward on 12/30/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define sineFrequency 880.0

#pragma mark UserData struct
// 7.28 - UserData struct for Sine Wave Player
typedef struct MySineWavePlayer {
    AudioUnit outputUnit;
    double startingFrameCount;
} MySineWavePlayer;


#pragma mark Callback
// 7.34
OSStatus SineWaveRenderProc(void *inRefCon,
                            AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp,
                            UInt32 inBusNumber,
                            UInt32 inNumberFrames,
                            AudioBufferList *ioData){
    MySineWavePlayer *player = (MySineWavePlayer*)inRefCon;
    
    double j = player->startingFrameCount;
    double cycleLength = 44100. / sineFrequency;
    int frame = 0;
    for(frame = 0; frame < inNumberFrames; ++frame){
        Float32 *data = (Float32*)ioData->mBuffers[0].mData;
        (data)[frame] = (Float32)sin(2 * M_PI *(j/cycleLength));
        // copy to right channel too
        data = (Float32*)ioData->mBuffers[1].mData;
        (data)[frame] = (Float32)sin(2 * M_PI * (j/cycleLength));
        
        j += 1.0;
        if(j>cycleLength){
            j-= cycleLength;
        }
    }
    player->startingFrameCount = j;
    return noErr;
}

#pragma mark Utility
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

// 7.30 Describe a default output audio unit
void CreateAndConnectOutputUnit(MySineWavePlayer *player){
    // Generate a description that matches the output device
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    // 7.31 - Getting an audiounit with AudioComponentFindNext
    AudioComponent comp = AudioComponentFindNext(NULL, &outputcd);
    if(comp == NULL){
        printf("can't get output unit");
        exit(-1);
    }
    CheckError(AudioComponentInstanceNew(comp, &player->outputUnit), "Couldn't open component for outputUnit");
    // 7.32 - Set the Render Callback on the Audio Unit
    // register the render callback
    AURenderCallbackStruct input;
    input.inputProc = SineWaveRenderProc;
    input.inputProcRefCon = player;     // text says to use &player but this throws an error during cleanup.  inputProcRefCon is a void* and player is MySineWavePlayer*.
    CheckError(AudioUnitSetProperty(player->outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &input, sizeof(input)), "AudioUnitSetProperty failed");
    // Initialize unit
    CheckError(AudioUnitInitialize(player->outputUnit), "Couldn't initialize output unit");
}

int main(int argc, const char * argv[]) {
    // 7.29 - Super simple main function
    @autoreleasepool {
        MySineWavePlayer player = {0};
        // Setup output unit and callback
        CreateAndConnectOutputUnit(&player);
        // Start playing
        CheckError(AudioOutputUnitStart(player.outputUnit), "Couldn't start output unit");
        // play for 5 seconds
        sleep(1);
        // Clean up

        CheckError(AudioOutputUnitStop(player.outputUnit), "AudioOutputUnitStop failed");
        CheckError(AudioUnitUninitialize(player.outputUnit), "AudioUnitUninitialize failed");
        CheckError(AudioComponentInstanceDispose(player.outputUnit), "AudioUnitDispose failed");
    }
    return 0;
}
