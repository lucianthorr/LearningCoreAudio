//
//  main.m
//  CAPlayThrough
//
//  Created by Jason Aylward on 1/1/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <ApplicationServices/ApplicationServices.h>
#import "CARingBuffer.h"

#define PART_2

#pragma mark UserData struct
// 8.3 - UserData struct for PlayThrough (with ring buffer)
typedef struct MyAUGraphPlayer{
    AudioStreamBasicDescription streamFormat;
    AUGraph graph;
    AudioUnit inputUnit;
    AudioUnit outputUnit;
#ifdef PART_2
    // 8.23 - Add a Speech Synthesis Audio Unit to the struct
    AudioUnit speechUnit;
    AudioUnit mixerUnit;
#else
#endif
    AudioBufferList *inputBuffer;
    CARingBuffer *ringBuffer;
    
    Float64 firstInputSampleTime;
    Float64 firstOutputSampleTime;
    Float64 inToOutSampleTimeOffset;
} MyAUGraphPlayer;


#pragma mark Render
// 8.15 - Create the Input Callback
OSStatus InputRenderProc(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData){
    MyAUGraphPlayer *player = (MyAUGraphPlayer*) inRefCon;
    // 8.16 - Log timestamps from input AUHAL and calculate timestamp offset (from output)
    if(player->firstInputSampleTime < 0.0){
        player->firstInputSampleTime = inTimeStamp->mSampleTime;
        if((player->firstOutputSampleTime > 0.0) && (player->inToOutSampleTimeOffset < 0.0)) {
            player->inToOutSampleTimeOffset = player->firstInputSampleTime - player->firstOutputSampleTime;
        }
    }
    // 8.17 - Retrieve Captured Samples from Input AUHAL
    OSStatus inputProcErr = noErr;
    inputProcErr = AudioUnitRender(player->inputUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, player->inputBuffer);
    // 8.18 - Store Captured Samples to a CARingBuffer
    if(!inputProcErr){
        inputProcErr = player->ringBuffer->Store(player->inputBuffer, inNumberFrames, inTimeStamp->mSampleTime);
    }
    return inputProcErr;
}
// 8.21 - Create the Output Callback
OSStatus GraphRenderProc(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData){
    MyAUGraphPlayer *player = (MyAUGraphPlayer*) inRefCon;
    // adjust timestamp offset
    if(player->firstOutputSampleTime < 0.0){
        player->firstOutputSampleTime = inTimeStamp->mSampleTime;
        if((player->firstInputSampleTime > 0.0) && (player->inToOutSampleTimeOffset < 0.0)){
            player->inToOutSampleTimeOffset = player->firstInputSampleTime - player->firstOutputSampleTime;
        }
    }
    // 8.22 - Fetch Samples from CARingBuffer
    OSStatus outputProcErr = noErr;
    outputProcErr = player->ringBuffer->Fetch(ioData, inNumberFrames, inTimeStamp->mSampleTime + player->inToOutSampleTimeOffset);
    return outputProcErr;
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
// 8.4 - Create an AudioUnit for Input (AUHAL)
void CreateInputUnit(MyAUGraphPlayer *player){
    // Generate a description that matches audio HAL
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    inputcd.componentSubType = kAudioUnitSubType_HALOutput;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent comp = AudioComponentFindNext(NULL, &inputcd);
    if(comp == NULL){
        printf("Can't get output unit");
        exit(-1);
    }
    CheckError(AudioComponentInstanceNew(comp, &player->inputUnit), "Couldn't open component for inputUnit");
    // 8.5 - Enable I/O on Input AUHAL
    UInt32 disableFlag = 0;
    UInt32 enableFlag = 1;
    AudioUnitScope outputBus = 0;
    AudioUnitScope inputBus = 1;
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, inputBus, &enableFlag, sizeof(enableFlag)), "Couldn't enable input on I/O unit");
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, outputBus, &disableFlag, sizeof(disableFlag)), "Couldn't disable output on I/O unit");
    // 8.6 - Get the default audio input device
    AudioDeviceID defaultDevice = kAudioObjectUnknown;
    UInt32 propertySize = sizeof(defaultDevice);
    AudioObjectPropertyAddress defaultDeviceProperty;
    defaultDeviceProperty.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    defaultDeviceProperty.mScope = kAudioObjectPropertyScopeGlobal;
    defaultDeviceProperty.mElement = kAudioObjectPropertyElementMaster;
    
    CheckError(AudioObjectGetPropertyData(kAudioObjectSystemObject, &defaultDeviceProperty, 0, NULL, &propertySize, &defaultDevice), "Couldn't get default input device");
    // 8.7 Set the Current Device Property of the AUHAL
                                        /* !!! text says to use outputBus but that doesn't make sense       */
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, inputBus, &defaultDevice, sizeof(defaultDevice)), "Couldn't set default device on I/O unit");
    // 8.8 Get the AudioStreamBasicDescription from Input AUHAL
    propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitGetProperty(player->inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &player->streamFormat, &propertySize), "Couldn't get ASBD from input unit");
    // 8.9 Adopt Hardware Input Sample Rate  (get scope_input sampleRate and set it for scope_output)
    AudioStreamBasicDescription deviceFormat;
    CheckError(AudioUnitGetProperty(player->inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, inputBus, &deviceFormat, &propertySize), "Couldn't get ASBD from input unit");
    player->streamFormat.mSampleRate = deviceFormat.mSampleRate;
    propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &player->streamFormat, propertySize), "Couldn't set ASBD on input unit");
    // 8.10 Calculate Capture Buffer Size for an I/O Unit
    UInt32 bufferSizeFrames = 0;
    propertySize = sizeof(bufferSizeFrames);
    CheckError(AudioUnitGetProperty(player->inputUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bufferSizeFrames, &propertySize), "Couldn't get buffer frame size from input unit");
    UInt32 bufferSizeBytes = bufferSizeFrames * sizeof(Float32);
    // 8.11 Create an AudioBufferList to Receive Capture Data
    // Allocate an AudioBufferList plus enough space for array of AudioBuffers
    UInt32 propsize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer) * player->streamFormat.mChannelsPerFrame);
    // malloc buffer lists
    player->inputBuffer = (AudioBufferList *)malloc(propsize);
    player->inputBuffer->mNumberBuffers = player->streamFormat.mChannelsPerFrame;
    
    //Pre-malloc buffers for AudioBufferLists
    for(UInt32 i=0; i<player->inputBuffer->mNumberBuffers; i++){
        player->inputBuffer->mBuffers[i].mNumberChannels = 1;
        player->inputBuffer->mBuffers[i].mDataByteSize = bufferSizeBytes;
        player->inputBuffer->mBuffers[i].mData = malloc(bufferSizeBytes);
    }
    // 8.12 - Create a CARingBuffer
    // Alloc ring buffer that will hold data between the two audio devices
    player->ringBuffer = new CARingBuffer();
    player->ringBuffer->Allocate(player->streamFormat.mChannelsPerFrame, player->streamFormat.mBytesPerFrame, bufferSizeFrames * 3);
    // 8.13 Setup an Input Callback on the AUHAL
    // Set render proc to supply samples from input unit
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = InputRenderProc;
    callbackStruct.inputProcRefCon = player;
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioOutputUnitProperty_SetInputCallback,kAudioUnitScope_Global, 0, &callbackStruct, sizeof(callbackStruct)), "Couldn't set input callback");
    // 8.14 - Initialize Input AUHAL and offset time counters
    CheckError(AudioUnitInitialize(player->inputUnit), "Couldn't initialize input unit");
    player->firstInputSampleTime = -1;
    player->inToOutSampleTimeOffset = -1;
    printf("Bottom of CreateInputUnit()\n");
    
}

// 8.19 - Create an AUGraph for Audio Play-Through
void CreateMyAUGraph(MyAUGraphPlayer *player){
    CheckError(NewAUGraph(&player->graph), "NewAUGraph failed");
    // Generate a description that matches default output
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent comp = AudioComponentFindNext(NULL, &outputcd);
    if(comp == NULL) {
        printf("Can't get output unit");
        exit(-1);
    }
    // Add a node with above description to the graph
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph, &outputcd, &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
#ifdef PART_2
    // 8.24 - Create a Stereo Mixer Unit in an AUGraph
    // Add a mixer to the graph
    AudioComponentDescription mixercd = {0};
    mixercd.componentType = kAudioUnitType_Mixer;
    mixercd.componentSubType = kAudioUnitSubType_StereoMixer;
    mixercd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AUNode mixerNode;
    CheckError(AUGraphAddNode(player->graph, &mixercd, &mixerNode), "AUGraphAddNode[kAudioUnitSubTy[e+StereoMixer] failed");
    // Add the speech synthesizer to the graph
    AudioComponentDescription speechcd = {0};
    speechcd.componentType = kAudioUnitType_Generator;
    speechcd.componentSubType = kAudioUnitSubType_SpeechSynthesis;
    speechcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AUNode speechNode;
    CheckError(AUGraphAddNode(player->graph, &speechcd, &speechNode), "AUGraphAddNode[kAudioUnitSubType_AudioSpeechSynthesizer] failed");
    // 8.25 - Get default output, speech syntheses and mix audio units from enclosing AUNodes
    // Opening the graph opens all contained audio units (but doesn't allocate resources)
    CheckError(AUGraphOpen(player->graph), "AUGraphOpen failed");
    // Get the reference to the audio unit object for the various nodes
    CheckError(AUGraphNodeInfo(player->graph, outputNode, NULL, &player->outputUnit), "AUGraphNodeInfo failed");
    CheckError(AUGraphNodeInfo(player->graph, speechNode, NULL, &player->speechUnit), "AUGraphNodeInfo failed");
    CheckError(AUGraphNodeInfo(player->graph, mixerNode, NULL, &player->mixerUnit), "AUGraphNodeInfo failed");
    // 8.26 - Set streamFormat of OutputUnit and Mixer Unit
    // Set ASBDs here
    UInt32 propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitSetProperty(player->outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &player->streamFormat, propertySize), "Couldn't set stream format on output unit");
    CheckError(AudioUnitSetProperty(player->mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &player->streamFormat, propertySize), "Couldn't set stream format on mixer unit, bus 0");
    CheckError(AudioUnitSetProperty(player->mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &player->streamFormat, propertySize), "Couldn't set stream format on mixer unit, bus 1");
    // 8.27 - Connect Speech Synthesis, Stereo Mixer and Default Output Units
    // Connections
    // Mixer output scope /bus 0 to outputUnit input scope/ bus 0
    // Mixer input scope / bus 0 to render callback (from ringbuffer, which in turn is from inputUnit)
    // Mixer input scope / bus 1 to speech unit output scope /bus 0
    CheckError(AUGraphConnectNodeInput(player->graph, mixerNode, 0, outputNode, 0), "Couldn't connect mixer output(0) to outputNode(0)");
    CheckError(AUGraphConnectNodeInput(player->graph, speechNode, 0, mixerNode, 1), "Couldn't connect speech synth unit output(0) to mixer input(1)");
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = GraphRenderProc;
    callbackStruct.inputProcRefCon = player;
    CheckError(AudioUnitSetProperty(player->mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callbackStruct, sizeof(callbackStruct)), "Couldn't set render callback o mixer unit");
#else

    // Opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(player->graph), "Couldn't open graph");
    // Get the reference to the audiounit object for the output graph node
    CheckError(AUGraphNodeInfo(player->graph, outputNode, NULL, &player->outputUnit), "AUGRaphNodeInfo failed");
    // Set the stream format on the output unit's input scope
    UInt32 propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitSetProperty(player->outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &player->streamFormat, propertySize), "Couldn't set stream format on output unit");
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = GraphRenderProc;
    callbackStruct.inputProcRefCon = player;
    
    CheckError(AudioUnitSetProperty(player->outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callbackStruct, sizeof(callbackStruct)), "Couldn't set render callback on output unit");
#endif
    // Initialze the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player->graph), "AUGraphInitialize failed");
    player->firstOutputSampleTime = -1;
}

// 8.29 - Set Speech Units Speech Channel and Speak a string
void PrepareSpeechAU(MyAUGraphPlayer *player) {
    SpeechChannel chan;
    UInt32 propsize = sizeof(SpeechChannel);
    CheckError(AudioUnitGetProperty(player->speechUnit, kAudioUnitProperty_SpeechChannel, kAudioUnitScope_Global, 0, &chan, &propsize), "AudioFileGetProperty[kAudioUnitProperty_SpeechChannel] failed");
    SpeakCFString(chan,  CFSTR("PLEASE PURCHASE AS MANY COPIES OF OUR BOOK AS YOU CAN. PLEASE PLEASE."), NULL);
}

// 8.2 - Main function
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MyAUGraphPlayer player = {0};
        // Create the input unit
        CreateInputUnit(&player);
        // Build a graph with the output unit
        CreateMyAUGraph(&player);
        
#ifdef PART_2
        // 8.28 Start the speech synthesis unit
        PrepareSpeechAU(&player);
#else
#endif
        // Start playing
        CheckError(AudioOutputUnitStart(player.inputUnit), "AudioOutputUnitStart failed");
        CheckError(AUGraphStart(player.graph), "AUGraphStart failed");
        // and wait
        printf("capturing, press <return> to stop:\n");
        getchar();
        // cleanup
    cleanup:
        AUGraphStop(player.graph);
        AUGraphUninitialize(player.graph);
        AUGraphClose(player.graph);
    }
    return 0;
}








