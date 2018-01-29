//
//  main.m
//  CAMIDIToAUGraph
//
//  Created by Jason Aylward on 1/28/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <AudioToolbox/AudioToolbox.h>

#pragma mark - State Struct
// 11.2 - State Struct for Core MIDI Synthesizer Program
typedef struct MyMIDIPlayer {
    AUGraph graph;
    AudioUnit instrumentUnit;
} MyMIDIPlayer;


#pragma mark - Utility
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

#pragma mark - Callbacks
// 11.8 - Simple Implementation of MIDINotifyProc Callback
void MyMIDINotifyProc(const MIDINotification *message, void *refCon){
    printf("MIDI Notify, messageID=%d", message->messageID);
}
// 11.9 - Get a Context Object in MIDIReadProc
static void MyMIDIReadProc(const MIDIPacketList *pktlist, void *refCon, void *connRefCon){
    MyMIDIPlayer *player = (MyMIDIPlayer*)refCon;
    // 11.10 - Iterate over a MIDIPacketList
    MIDIPacket *packet = (MIDIPacket*)pktlist->packet;
    for(int i=0; i<pktlist->numPackets; i++){
        Byte midiStatus = packet->data[0];
        Byte midiCommand = midiStatus >> 4;
        // 11.11 - Parse NOTE ON and NOTE OFF events
        if((midiCommand == 0x08) || (midiCommand == 0x09)) {
            Byte note = packet->data[1] & 0x07F;
            Byte velocity = packet->data[2] & 0x07F;
            CheckError(MusicDeviceMIDIEvent(player->instrumentUnit, midiStatus, note, velocity, 0), "Couldn't send MIDI event");
        }
        packet = MIDIPacketNext(packet);
    }
}

#pragma mark - AUGraph
// 11.4 - Setup an AUGraph with a MIDI-Controllable Instrument Unit
void setupAUGraph(MyMIDIPlayer *player){
    CheckError(NewAUGraph(&player->graph), "Couldn't open AU Graph");
    // Generate description that will match our output device (speakers)
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    // Adds a node with above description to the graph
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph, &outputcd, &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
    
    // Generate description that will match the midi instrument?
    AudioComponentDescription instrumentcd = {0};
    instrumentcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    instrumentcd.componentType = kAudioUnitType_MusicDevice;
    instrumentcd.componentSubType = kAudioUnitSubType_DLSSynth;
    AUNode instrumentNode;
    CheckError(AUGraphAddNode(player->graph, &instrumentcd, &instrumentNode), "AUGraphAddNode[kAudioUnitSubType_DLSSynth] failed");
    
    // Opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(player->graph), "AUGraphOpen failed");
    
    // Get the reference to the AudioUnit object for the instrument graph node (and sets it to player->instrumentUnit, I think)
    CheckError(AUGraphNodeInfo(player->graph, instrumentNode, NULL, &player->instrumentUnit), "AUGraphNodeInfo failed");
    
    // Connect the output source of the speech synthesis AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(player->graph, instrumentNode, 0, outputNode, 0), "AUGraphConnectNodeInput failed");
    // Now initialzie the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player->graph), "AUGraphInitialize failed");
    
}

#pragma mark - MIDI
// 11.5 - Create a MIDIClientRef
void setupMIDI(MyMIDIPlayer *player) {
    MIDIClientRef client;
    CheckError(MIDIClientCreate(CFSTR("Core MIDI to System Sounds Demo"), MyMIDINotifyProc, player, &client), "Couldn't create MIDI client");
    // 11.6 - Create a MIDIPortRef
    MIDIPortRef inPort;
    CheckError(MIDIInputPortCreate(client, CFSTR("Input port"), MyMIDIReadProc, player, &inPort), "Couldn't create MIDI input port");
    // 11.7 - Connect a MIDI Port to Available Sources
    unsigned long sourceCount = MIDIGetNumberOfSources();
    printf("%ld sources\n", sourceCount);
    for(int i = 0; i < sourceCount; ++i){
        MIDIEndpointRef src = MIDIGetSource(i);
        CFStringRef endpointName = NULL;
        CheckError(MIDIObjectGetStringProperty(src, kMIDIPropertyName, &endpointName), "Couldn't get endpoint name");
        char endpointNameC[255];
        CFStringGetCString(endpointName, endpointNameC, 255, kCFStringEncodingUTF8);
        printf(" source %d: %s\n", i, endpointNameC);
        CheckError(MIDIPortConnectSource(inPort, src, NULL), "Couldn't connect MIDI port");
    }
}





int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 11.3 - main function for Core MIDI Synthesizer Program
        MyMIDIPlayer player;
        setupAUGraph(&player);
        setupMIDI(&player);
        
        CheckError(AUGraphStart(player.graph), "Couldn't start graph");
        CFRunLoopRun();
        // Run until aborted with Control-C
    }
    return 0;
}




