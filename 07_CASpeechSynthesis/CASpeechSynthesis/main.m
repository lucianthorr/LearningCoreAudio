//
//  main.m
//  CASpeechSynthesis
//
//  Created by Jason Aylward on 12/30/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <ApplicationServices/ApplicationServices.h>

#define PART_II

#pragma mark UserData struct
// 7.19 - UserData struct for speech synthesis AU
typedef struct MyAUGraphPlayer {
    AUGraph graph;
    AudioUnit speechAU;
} MyAUGraphPlayer;

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

void CreateMyAUGraph(MyAUGraphPlayer *player){
    // 7.21 - Setup AUGraph and AUNodes for Speech Synthesis
    //  Create a new AUGraph
    CheckError(NewAUGraph(&player->graph), "NewAUGraph failed");
    // Generate a description that matches our output device (speakers)
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Add a node with the above description to the graph
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph, &outputcd, &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
    
    // Generate a description that will match a generator AU of type: speech synthesizer
    AudioComponentDescription speechcd = {0};
    speechcd.componentType = kAudioUnitType_Generator;
    speechcd.componentSubType = kAudioUnitSubType_SpeechSynthesis;
    speechcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    // Add node with above description to the graph
    AUNode speechNode;
    CheckError(AUGraphAddNode(player->graph, &speechcd, &speechNode), "AUGraphAddNode[kAudioUnitSubType_SpeechSynthesis] failed");
    // Open the graph, opening all contained audio units but will not allocate any resources yet
    CheckError(AUGraphOpen(player->graph), "AUGraphOpen failed");
    // Get the reference to the audiounit object for the speech synthesis graph node
    CheckError(AUGraphNodeInfo(player->graph, speechNode, NULL, &player->speechAU), "AUGraphNodeInfo failed");
#ifdef PART_II
    // 7.24 - Create an AUMatrixReverb AUGraph Node
    // Generate a description that matches the reverb effect
    AudioComponentDescription reverbcd = {0};
    reverbcd.componentType = kAudioUnitType_Effect;
    reverbcd.componentSubType = kAudioUnitSubType_MatrixReverb;
    reverbcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    // Add a node with the above description
    AUNode reverbNode;
    CheckError(AUGraphAddNode(player->graph, &reverbcd, &reverbNode), "AUGraphNodeAdd[kAudioUnitSubType_MatrixReverb] failed");
    // 7.25 - Connect the AUNodes (in a different order than Part1) to send synthesized speech through the reverb node
    //Connect the output source of the speech synth AU to the input source of the reverb node
    CheckError(AUGraphConnectNodeInput(player->graph, speechNode, 0, reverbNode, 0), "AUGraphConnectNodeInput(speech to reverb) failed");
    //Connect the output source ofht ereverb AU to the input source of the output Node
    CheckError(AUGraphConnectNodeInput(player->graph, reverbNode, 0, outputNode, 0), "AUGraphConnectNodeInput(reverb to output) failed");
    // 7.26 - Configure the Matrix Reverb
    // Get the reference to the AudioUnit object for the reverb graph node
    AudioUnit reverbUnit;
    CheckError(AUGraphNodeInfo(player->graph, reverbNode, NULL, &reverbUnit), "AUGraphNodeInfo failed");
    // Now initialize the graph
    CheckError(AUGraphInitialize(player->graph), "AUGraphInitialize failed");
    // Set the reverb preset for room size
    UInt32 roomType = kReverbRoomType_LargeHall;
    CheckError(AudioUnitSetProperty(reverbUnit, kAudioUnitProperty_ReverbRoomType, kAudioUnitScope_Global, 0, &roomType, sizeof(roomType)), "AudioUnitSetProperty[kAudioUnitProperty_ReverbRoomType] failed");
#else
    // 7.22 - Part1: Connect Units in the speech synthesis graph
    // Connect the output source of the speech synthesis AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(player->graph, speechNode, 0, outputNode, 0), "AUGraphConnectNodeInput failed");
    // NOW initialize the graph (causing resources to be allocated)
    CheckError(AUGraphInitialize(player->graph), "AUGraphInitialize failed");
#endif
    CAShow(player->graph);
}

// 7.23 - Setup Speech Synthesis
void PrepareSpeechAU(MyAUGraphPlayer *player){
    SpeechChannel chan;
    UInt32 propSize = sizeof(SpeechChannel);
    CheckError(AudioUnitGetProperty(player->speechAU, kAudioUnitProperty_SpeechChannel, kAudioUnitScope_Global, 0, &chan, &propSize), "AudioUnitGetProperty[kAudioUnitProperty_SpeechChannel] failed");
    SpeakCFString(chan, CFSTR("hello world?"), NULL);
    
}

#pragma mark Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 7.20 -
        MyAUGraphPlayer player = {0};
        // Build a basic speech->speaker graph
        CreateMyAUGraph(&player);
        // Configure the speech synthesizer
        PrepareSpeechAU(&player);
        // Start playing
        CheckError(AUGraphStart(player.graph), "AUGraphStart failed");
        //Sleep while speech is playing
        usleep((int)(10 * 1000. * 1000.));
        // Cleanup
        AUGraphStop(player.graph);
        AUGraphUninitialize(player.graph);
        AUGraphClose(player.graph);
    }
    return 0;
}
