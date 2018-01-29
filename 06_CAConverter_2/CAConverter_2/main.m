//
//  main.m
//  CAConverter_2
//
//  Created by Jason Aylward on 12/29/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kInputFileLocation CFSTR("/Users/jasonaylward/Desktop/output2.caf")


#pragma mark UserData struct
// 6.23 - Struct for passing ASBD and Audio File references
typedef struct MyAudioConverterSettings {
    AudioStreamBasicDescription outputFormat;
    ExtAudioFileRef inputFile;
    AudioFileID outputFile;
} MyAudioConverterSettings;


#pragma mark Utility functions
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
// 6.28 - 6.34
// 6.28 = Determine the Size of the output buffer and packets/buffer count
void Convert(MyAudioConverterSettings *mySettings){
    UInt32 outputBufferSize = 32*1024;  // 32 KB to start
    UInt32 sizePerPacket = mySettings->outputFormat.mBytesPerPacket;
    UInt32 packetsPerBuffer = outputBufferSize / sizePerPacket;
    // 6.29 - Allocate a Buffer for Receiving Data from the Ext. Audio File
    UInt8 *outputBuffer = (UInt8*)malloc(sizeof(UInt8)*outputBufferSize);
    UInt32 outputFilePacketPosition = 0; //in bytes
    // 6.30 - Read-convert-write loop
    while(1){
        AudioBufferList convertedData;
        convertedData.mNumberBuffers = 1;
        convertedData.mBuffers[0].mNumberChannels = mySettings->outputFormat.mChannelsPerFrame;
        convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
        convertedData.mBuffers[0].mData = outputBuffer;
        // 6.31 - Read and Convert with ExtAudioFileRead()
        UInt32 frameCount = packetsPerBuffer;
        CheckError(ExtAudioFileRead(mySettings->inputFile, &frameCount, &convertedData), "Couldn't read from input file");
        // 6.32 - Terminate if no frames are read
        if(frameCount == 0){
            printf("Done reading from file\n");
            return;
        }
        // 6.33 - Write converted audio data to an output file
        CheckError(AudioFileWritePackets(mySettings->outputFile, FALSE, frameCount, NULL, outputFilePacketPosition / mySettings->outputFormat.mBytesPerPacket, &frameCount, convertedData.mBuffers[0].mData),"Couldn't write packets to file");
        // 6.34 - Advance output file write position
        outputFilePacketPosition += (frameCount * mySettings->outputFormat.mBytesPerPacket);
    }
    
}


#pragma mark Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 6.24 Open an Extended Audio File for Input
        MyAudioConverterSettings audioConverterSettings = {0};
        // Open the input with ExtAudioFile
        CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, kCFURLPOSIXPathStyle, false);
        CheckError(ExtAudioFileOpenURL(inputFileURL, &audioConverterSettings.inputFile), "ExtAudioFileOpenURL failed");
        // 6.25 Set the Output Audio Data format and create an audio file
        audioConverterSettings.outputFormat.mSampleRate = 44100.0;
        audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM;
        audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        audioConverterSettings.outputFormat.mBytesPerPacket = 4;
        audioConverterSettings.outputFormat.mFramesPerPacket = 1;
        audioConverterSettings.outputFormat.mBytesPerFrame = 4;
        audioConverterSettings.outputFormat.mChannelsPerFrame = 2;
        audioConverterSettings.outputFormat.mBitsPerChannel = 16;
        CFURLRef outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("output.aif"), kCFURLPOSIXPathStyle, false);
        CheckError(AudioFileCreateWithURL(outputFileURL, kAudioFileAIFFType, &audioConverterSettings.outputFormat, kAudioFileFlags_EraseFile, &audioConverterSettings.outputFile), "AudioFileCreateWithURL failed");
        CFRelease(outputFileURL);
        // 6.26 Call the Conversion Function and Close the Extended Audio File
        fprintf(stdout, "Converting...\n");
        Convert(&audioConverterSettings);
        // Cleanup
        ExtAudioFileDispose(audioConverterSettings.inputFile);
        AudioFileClose(audioConverterSettings.outputFile);
    }
    return 0;
}
