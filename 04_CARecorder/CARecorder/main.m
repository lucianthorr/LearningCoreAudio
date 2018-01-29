//
//  main.m
//  CARecorder
//
//  Created by Jason Aylward on 12/27/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kNumberRecordBuffers 3


#pragma mark - UserData
// 4.3 - struct for Recording Audio Queue Callbacks to access info
typedef struct MyRecorder {
    AudioFileID recordFile;
    SInt64      recordPacket;
    Boolean     running;
} MyRecorder;


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

// 4.19 - Getting Current Audio Input Device Info
OSStatus MyGetDefaultInputDeviceSampleRate(Float64 *outSampleRate) {
    OSStatus error;
    AudioDeviceID deviceID = 0;
    // 4.20 - Get Current Audio Input Device Info from Audio Hardware Services
    AudioObjectPropertyAddress propertyAddress;
    UInt32 propertySize;
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(AudioDeviceID);
    error = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &propertySize, &deviceID);
    if (error) return error;
    // 4.21 - Get Input Device's Sample Rate
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    propertySize = sizeof(Float64);
    error = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &propertySize, outSampleRate);
    return error;
}
// 4.22 - Copying Magic Cookie from AudioQueue to Audio File
static void MyCopyEncoderCookieToFile(AudioQueueRef queue, AudioFileID theFile) {
    OSStatus error;
    UInt32 propertySize;
    
    error = AudioQueueGetPropertySize(queue, kAudioConverterCompressionMagicCookie, &propertySize);
    if(error == noErr && propertySize > 0){
        Byte *magicCookie = (Byte*)malloc(propertySize);
        CheckError(AudioQueueGetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize), "Couldn't get audio queue's magic cookie");
        CheckError(AudioFileSetProperty(theFile, kAudioFilePropertyMagicCookieData, propertySize, magicCookie), "Couldn't set audio file's magic cookie");
        free(magicCookie);
    }
}
// 4.23 - Compute Recording Buffer Size
static int MyComputeRecordBufferSize(const AudioStreamBasicDescription *format,
                                     AudioQueueRef queue,
                                     float seconds){
    int packets, frames, bytes;
    frames = (int)ceil(seconds * format->mSampleRate);
    
    // Constant bite rate
    if(format->mBytesPerFrame > 0){                                     // 1  frame = sample/channel
        bytes = frames * format->mBytesPerFrame;
    }else {
        UInt32 maxPacketSize;
        if(format->mBytesPerPacket > 0){                                // 2
            // Constant packet size
            maxPacketSize = format->mBytesPerPacket;
        }else {
            // Get the largest single packet size possible
            UInt32 propertySize = sizeof(maxPacketSize);                // 3
            CheckError(AudioQueueGetProperty(queue, kAudioConverterPropertyMaximumOutputPacketSize, &maxPacketSize, &propertySize), "Couldn't get queue's maximum output packet size");
        }
        if(format->mFramesPerPacket > 0){
            packets = frames / format->mFramesPerPacket;                // 4
        }else {
            // Worst-case scenario: 1 frame/packet
            packets = frames;                                           // 5
        }
        
        // Sanity check
        if(packets == 0){
            packets = 1;
        }
        bytes = packets * maxPacketSize;                                // 6
    }
    return bytes;
}


#pragma mark - CallBack
// 4.24 Header for Audio Queue Callback
static void MyAQInputCallback(void *inUserData,
                              AudioQueueRef inQueue,
                              AudioQueueBufferRef inBuffer,
                              const AudioTimeStamp *inStartTime,
                              UInt32 inNumPackets,
                              const AudioStreamPacketDescription *inPacketDesc){
    // 4.24 - Casting inUserData pointer to MyRecorder
    MyRecorder *recorder = (MyRecorder *)inUserData;
    // 4.25 - Writing Captured Packets to Audio File
    if(inNumPackets>0){
        CheckError(AudioFileWritePackets(recorder->recordFile, FALSE, inBuffer->mAudioDataByteSize, inPacketDesc, recorder->recordPacket, &inNumPackets, inBuffer->mAudioData), "AudioFileWritePackets failed");
        recorder->recordPacket += inNumPackets;
    }
    // 4.26 - Re-enqueuing a Used Buffer
    if(recorder->running){
        CheckError(AudioQueueEnqueueBuffer(inQueue, inBuffer, 0, NULL), "AudioQueueEnqueueBuffer failed");
    }
    
}

# pragma mark - Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // setup format
        // 4.4 - Create MyRecorder struct and ASBD for Audio Queue
        MyRecorder recorder = {0};
        AudioStreamBasicDescription recordFormat;
        memset(&recordFormat, 0, sizeof(recordFormat));
        // 4.5 - Set format of ASBD for Audio Queue
        recordFormat.mFormatID = kAudioFormatMPEG4AAC;
        recordFormat.mChannelsPerFrame = 2;
        // 4.6 Get and Set the correct sample rate
        CheckError(MyGetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate), "Getting SampleRate failed");
        // 4.7 Filling in the remaining ASBD properties to recordFormat
        UInt32 propSize = sizeof(recordFormat);
        CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &propSize, &recordFormat), "AudioFormatGetProperty failed");
        
        // Setup queue
        // 4.8 - Create the AudioQueue using the ASBD recordFormat as input and setting the Callback function and callback UserData
        AudioQueueRef queue = {0};
        CheckError(AudioQueueNewInput(&recordFormat, MyAQInputCallback, &recorder, NULL, NULL, 0, &queue), "AudioQueueNewInput failed");
        // 4.9 - Retrieve the Filled-Out ASBD from Audio Queue
        UInt32 size = sizeof(recordFormat);
        CheckError(AudioQueueGetProperty(queue, kAudioConverterCurrentOutputStreamDescription, &recordFormat, &size), "Couldn't get the queue's format");
        
        // Setup file
        // 4.10 Create the Audio File for Output
        CFURLRef myFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("output.caf"), kCFURLPOSIXPathStyle, false);
        CheckError(AudioFileCreateWithURL(myFileURL, kAudioFileCAFType, &recordFormat, kAudioFileFlags_EraseFile, &recorder.recordFile), "AudioFileCreateWithURL failed");
        CFRelease(myFileURL);
        // 4.11 Handle the Magic Cookie
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        
        // Other setup
        // 4.12 - Compute Buffer Size
        int bufferByteSize = MyComputeRecordBufferSize(&recordFormat, queue, 0.5);
        // 4.13 - Allocating and Enqueuing Buffers
        int bufferIndex = 0;
        for(bufferIndex = 0; bufferIndex < kNumberRecordBuffers; ++bufferIndex){
            AudioQueueBufferRef buffer;
            CheckError(AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer), "AudioQueueAllocateBuffer failed");
            CheckError(AudioQueueEnqueueBuffer(queue, buffer, 0, NULL), "AudioQueueEnqueueBuffer failed");
        }
        
        // 4.14 - Start queue
        recorder.running = TRUE;
        CheckError(AudioQueueStart(queue, NULL), "AudioQueueStart failed");
        // 4.15 - Blocking on stdin to continue recording
        printf("Recording, press <return> to stop:\n");
        getchar();
        
        // 4.16 - Stop queue
        printf("* recording done*\n");
        recorder.running = FALSE;
        CheckError(AudioQueueStop(queue, TRUE), "AudioQueueStop failed");
        // 4.17 - Copy Magic Cooke to File
        MyCopyEncoderCookieToFile(queue, recorder.recordFile);
        // 4.18 - Clean up audio queue and audio file
        AudioQueueDispose(queue, TRUE);
        AudioFileClose(recorder.recordFile);
        return 0;
    }
    return 0;
}
