//
//  main.m
//  Playback
//
//  Created by Jason Aylward on 12/27/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kPlaybackFileLocation CFSTR("/Users/jasonaylward/Desktop/output.caf")
#define kNumberPlayerBuffers 3

# pragma mark UserData struct
// 5.2 - UserData struct for Playback Audio Queue Callbacks
typedef struct MyPlayer {
    AudioFileID                     playbackFile;
    SInt64                          packetPosition;
    UInt32                          numPacketsToRead;
    AudioStreamPacketDescription    *packetDescs;
    Boolean                         isDone;
} MyPlayer;


#pragma mark  - Utility
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

//5.14 - Handle the Magic Cookie from AudioFile to AudioQueue
static void MyCopyEncoderCookieToQueue(AudioFileID theFile, AudioQueueRef queue) {
    UInt32 propertySize;
    OSStatus result = AudioFileGetPropertyInfo(theFile, kAudioFilePropertyMagicCookieData, &propertySize, NULL);
    if(result == noErr && propertySize > 0){
        Byte* magicCookie = (UInt8*)malloc(sizeof(UInt8)*propertySize);
        CheckError(AudioFileGetProperty(theFile, kAudioFilePropertyMagicCookieData, &propertySize, magicCookie), "Get cookie from file failed");
        CheckError(AudioQueueSetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, propertySize), "Set cookie to queue failed.");
        free(magicCookie);
    }
}
//5.15 - Calculate Buffer Size and Max Number of Packets that can be read into the buffer
void CalculateBytesForTime(AudioFileID inAudioFile,
                           AudioStreamBasicDescription inDesc,
                           Float64 inSeconds,
                           UInt32 *outBufferSize,
                           UInt32 *outNumPackets){
    UInt32 maxPacketSize;                               // 1 - maxPacketSize for file encoding type
    UInt32 propSize = sizeof(maxPacketSize);
    CheckError(AudioFileGetProperty(inAudioFile, kAudioFilePropertyPacketSizeUpperBound, &propSize, &maxPacketSize), "Couldn't get max packet size");
    
    static const int maxBufferSize = 0x10000;           // 2    64KB max
    static const int minBufferSize = 0x4000;            // 2    16KB min
    
    if(inDesc.mFramesPerPacket){                        // 3    if mFramesPerPacket is defined, calculate the numberofpackets for the time given and multiple by maxPacketSize
        Float64 numPacketsForTime = inDesc.mSampleRate / inDesc.mFramesPerPacket * inSeconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    }else {                                             // 4    else just pick the biggest value possible
        *outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize: maxPacketSize;
    }
    
    if(*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize){
        *outBufferSize = maxBufferSize;                 // 5   if the buffer size is computed to be larger than the max's, decrease it == maxBufferSize
    }else{
        if(*outBufferSize < minBufferSize){
            *outBufferSize = minBufferSize;
        }
    }
    *outNumPackets = *outBufferSize / maxPacketSize;    // 6 finally compute the number of packets you can fit in the bufferSize
}

#pragma mark Playback Callback function
static void MyAQOutputCallback(void *inUserData,
                               AudioQueueRef inAQ,
                               AudioQueueBufferRef inCompleteAQBuffer){
    //5.16 - Cast UserData pointer back to Playback struct
    MyPlayer *player = (MyPlayer*)inUserData;   // text uses variable name aqp for (AudioQueue Player) but that's confusing to me and inconsistent with previous chapter
    if(player->isDone) return;
    //5.17 - Read Packets from Audio File
    UInt32 numBytes;
    UInt32 nPackets = player->numPacketsToRead;
    CheckError(AudioFileReadPackets(player->playbackFile, false, &numBytes, player->packetDescs, player->packetPosition, &nPackets, inCompleteAQBuffer->mAudioData), "AudioFileReadPackets failed");
    //5.18 - Enqueue Packets for Playback
    if(nPackets > 0){
        inCompleteAQBuffer->mAudioDataByteSize = numBytes;
        AudioQueueEnqueueBuffer(inAQ, inCompleteAQBuffer, (player->packetDescs ? nPackets:0), player->packetDescs);
        player->packetPosition += nPackets;
    } else {
    //5.19 - Sop Audio Queue Upon Reaching End of File
        CheckError(AudioQueueStop(inAQ, false), "AudioQueueStop failed");
        player->isDone = true;
    }
}

#pragma mark Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        //5.3 Allocation of MyPlayer struct
        MyPlayer player = {0};
        //5.4 Open an Audio File for Input
        CFURLRef myFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kPlaybackFileLocation, kCFURLPOSIXPathStyle, false);
        CheckError(AudioFileOpenURL(myFileURL, kAudioFileReadPermission, 0, &player.playbackFile), "AudioFileOpenURL failed");
        //5.5 Get the ASBD from an Audio File
        AudioStreamBasicDescription dataFormat;
        UInt32 propSize = sizeof(dataFormat);
        CheckError(AudioFileGetProperty(player.playbackFile, kAudioFilePropertyDataFormat, &propSize, &dataFormat), "Couldn't get file's data format");
        //5.6 - Create a New Audio Queue for Output
        AudioQueueRef queue;
        CheckError(AudioQueueNewOutput(&dataFormat, MyAQOutputCallback, &player, NULL, NULL, 0, &queue), "AudioQueueNewOutput failed");
        //5.7 - Calculate Playback Buffer Size and Number of Packets to Read
        UInt32 bufferByteSize;
        CalculateBytesForTime(player.playbackFile, dataFormat, 0.5, &bufferByteSize, &player.numPacketsToRead);
        //5.8 - Allocate Memory for Array of Packet Descriptions
        bool isFormatVBR = (dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0);
        if (isFormatVBR){   // if format is variable bit rate
            player.packetDescs = (AudioStreamPacketDescription*)malloc(sizeof(AudioStreamPacketDescription)*player.numPacketsToRead);
        }else {
            player.packetDescs = NULL;
        }
        
        //5.9 - Handle the Magic Cookie
        MyCopyEncoderCookieToQueue(player.playbackFile, queue);
        //5.10 - Allocate and Enqueue Playback Buffers
        AudioQueueBufferRef buffers[kNumberPlayerBuffers];
        player.isDone = false;
        player.packetPosition = 0;
        int i;
        for(i = 0; i<kNumberPlayerBuffers; ++i){
            CheckError(AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[i]), "AudioQueueAllocateBuffer failed");
            
            MyAQOutputCallback(&player, queue, buffers[i]); // manually invoke the callback to fill the buffers with data
            
            if(player.isDone){
                break;
            }
        }
        //5.11 Start the Playback Audio Queue
        CheckError(AudioQueueStart(queue, NULL), "AudioQueueStart failed");
        printf("Playing...\n");
        do {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
        }while(!player.isDone);
        //5.12 Delay to Ensure Queue Plays Out Buffered Audio
        // running for 2 more seconds assures that the 3 buffers of 0.5 seconds all finish playing through
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false);
        //5.13 - Clean up the Audio Queue and Audio File
        player.isDone = true;
        CheckError(AudioQueueStop(queue, TRUE), "AudioQueueStop failed");
        AudioQueueDispose(queue, TRUE);
        AudioFileClose(player.playbackFile);
    }
    return 0;
}
