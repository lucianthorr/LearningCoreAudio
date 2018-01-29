//
//  main.m
//  CAFilePlayer
//
//  Created by Jason Aylward on 12/29/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kInputFileLocation CFSTR("/Users/jasonaylward/Desktop/sample.mp3")


#pragma mark UserData struct
// 7.2 - UserData Struct for an Audio Unit File Player
typedef struct MyAUGraphPlayer {
    AudioStreamBasicDescription inputFormat;
    AudioFileID inputFile;
    
    AUGraph graph;
    AudioUnit fileAU;
} MyAUGraphPlayer;


#pragma mark Utility funcs
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
// 7.7-7.17
void CreateMyAUGraph(MyAUGraphPlayer *player){
    // 7.7 Create an AUGraph
    CheckError(NewAUGraph(&player->graph), "NewAUGraph failed");
    // 7.8 - Create Default Output AUGraph Node
    // Generate description that matches output device (speakers)
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    // Add a node with above's description to graph
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph, &outputcd, &outputNode), "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
    // 7.9 - Create a FilePlayer AUGraph Node
    // Generate description that matches a generator AU of type: audio file player
    AudioComponentDescription fileplayercd = {0};
    fileplayercd.componentType = kAudioUnitType_Generator;
    fileplayercd.componentSubType = kAudioUnitSubType_AudioFilePlayer;
    fileplayercd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    //Add a node with above description to the graph
    AUNode fileNode;
    CheckError(AUGraphAddNode(player->graph, &fileplayercd, &fileNode), "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed");
    
    // 7.10 - Open the AUGraph
    // Opening a graph opens all the contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(player->graph), "AUGraphOpen failed");
    
    // 7.11 - Retrieve an AudioUnit from an AUNode
    // Get the reference to the AudioUnit object for the file player graph node  (aka the fileAU)
    CheckError(AUGraphNodeInfo(player->graph, fileNode, NULL, &player->fileAU), "AUGraphNodeInfo failed");
    
    // 7.12 - Connect Nodes in an AUGraph
    // Connect the output source of the fileplayer AU to the input source of the output node
    // AUGraphConnectNodeInput params: (inGraph, inSourceNode, inSourceOutputNumber, inDestNode, inDestInputNumber)
    CheckError(AUGraphConnectNodeInput(player->graph, fileNode, 0, outputNode, 0), "AUGraphConnectNodeInput");
    
    // 7.13 - Initialize the AUGraph
    // this causes resources to be allocated
    CheckError(AUGraphInitialize(player->graph), "AUGraphInitialize failed");
}

// 7.14 - Schedule an AudioFileID with the AUFilePlayer
Float64 PrepareFileAU(MyAUGraphPlayer *player) {
    // Tell the file player unit to load the file we want to play
    CheckError(AudioUnitSetProperty(player->fileAU, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &player->inputFile, sizeof(player->inputFile)), "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileIDs] failed");
    // 7.15 Set a scheduledAudioFileRegion for the AUFilePlayer
    UInt64 nPackets;
    UInt32 propsize = sizeof(nPackets);
    // get packet count
    CheckError(AudioFileGetProperty(player->inputFile, kAudioFilePropertyAudioDataPacketCount, &propsize, &nPackets), "AudioFileGetProperty[kAudioFilePropertyAudioDataPacketCount] failed");
    // tell the file playerAU to play the entire file
    ScheduledAudioFileRegion region;
    memset(&region.mTimeStamp, 0, sizeof(region.mTimeStamp));
    region.mTimeStamp.mFlags = kAudioTimeStampHostTimeValid;
    region.mTimeStamp.mSampleTime = 0;
    region.mCompletionProc = NULL;
    region.mCompletionProcUserData = NULL;
    region.mAudioFile = player->inputFile;
    region.mLoopCount = 1;
    region.mStartFrame = 0;
    // most importantly, how to compute the # of frames to play
    region.mFramesToPlay = (UInt32)(nPackets * player->inputFormat.mFramesPerPacket);
    
    CheckError(AudioUnitSetProperty(player->fileAU, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &region, sizeof(region)), "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileRegion] failed");
    // 7.16 - Set the Scheduled STart Time for the AUFilePlayer
    // Tell the file player AU when to start playing (-1 sample time means next render cycle)
    AudioTimeStamp startTime;
    memset(&startTime, 0, sizeof(startTime));
    startTime.mFlags = kAudioTimeStampSampleTimeValid;
    startTime.mSampleTime = -1;
    CheckError(AudioUnitSetProperty(player->fileAU, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, sizeof(startTime)), "AudioUnitSetProperty[kAudioUnitProperty_ScheduleStartTimeStamp]");
    // 7.17 - Calculate File Playback Time in Seconds so that main() knows how long to sleep
    return (nPackets * player->inputFormat.mFramesPerPacket) / player->inputFormat.mSampleRate;
    
}

#pragma  mark Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 7.3 - Open an Audio File and get data format
        CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, kCFURLPOSIXPathStyle, false);
        MyAUGraphPlayer player = {0};
        // open input audio file
        CheckError(AudioFileOpenURL(inputFileURL, kAudioFileReadPermission, 0, &player.inputFile), "AudioFileOpenURL failed");
        // Get data format from file
        UInt32 propSize = sizeof(player.inputFormat);
        CheckError(AudioFileGetProperty(player.inputFile, kAudioFilePropertyDataFormat, &propSize, &player.inputFormat), "Couldn't get file's data format");
        // 7.4 - Call functions to sestup AUGraph and prep a file player unit
        //Build a basic fileplayer->speakers graph
        CreateMyAUGraph(&player);
        //configure the file player
        Float64 fileDuration = PrepareFileAU(&player);
        // 7.5 - Start the AUGraph
        CheckError(AUGraphStart(player.graph), "AUGraphStart failed");
        // Wait til it's done
        usleep((int)(fileDuration * 1000.0 * 1000.0));
        // 7.6 Stop and Clean up AUGraph
        AUGraphStop(player.graph);
        AUGraphUninitialize(player.graph);
        AUGraphClose(player.graph);
        AudioFileClose(player.inputFile);
    }
    return 0;
}
