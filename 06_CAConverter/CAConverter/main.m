//
//  main.m
//  CAConverter
//
//  Created by Jason Aylward on 12/28/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kInputFileLocation CFSTR("/Users/jasonaylward/Desktop/output2.caf")

#pragma mark UserData struct
// 6.2
typedef struct MyAudioConverterSettings {
    AudioStreamBasicDescription inputFormat;
    AudioStreamBasicDescription outputFormat;
    
    AudioFileID inputFile;
    AudioFileID outputFile;
    
    UInt64 inputFilePacketIndex;
    UInt64 inputFilePacketCount;
    UInt32 inputFilePacketMaxSize;
    AudioStreamPacketDescription *inputFilePacketDescriptions;
    
    void *sourceBuffer;
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


#pragma mark Converter Callback
// 6.17 - Converter Callback, UserData casting, zero out audio buffers
OSStatus MyAudioConverterCallback(AudioConverterRef inAudioConverter,
                                  UInt32 *ioDataPacketCount,
                                  AudioBufferList *ioData,
                                  AudioStreamPacketDescription **outDataPacketDescription,
                                  void *inUserData){
    MyAudioConverterSettings *audioConverterSettings = (MyAudioConverterSettings *)inUserData;
    ioData->mBuffers[0].mData = NULL;
    ioData->mBuffers[0].mDataByteSize = 0;
    // 6.18 Determine how many packets can be read from the input file
    // If there are not enough packets to satisfy request, then read what's left.
    if(audioConverterSettings->inputFilePacketIndex + *ioDataPacketCount > audioConverterSettings->inputFilePacketCount){
        *ioDataPacketCount = audioConverterSettings->inputFilePacketCount - audioConverterSettings->inputFilePacketIndex;
    }
    if(*ioDataPacketCount == 0){
        return noErr;
    }
    // 6.19 Allocate a Buffer to Fill and Convert
    if(audioConverterSettings->sourceBuffer != NULL){
        free(audioConverterSettings->sourceBuffer);
        audioConverterSettings->sourceBuffer = NULL;
    }
    audioConverterSettings->sourceBuffer = (void*)calloc(1, *ioDataPacketCount * audioConverterSettings->inputFilePacketMaxSize);
    // 6.20 Read Packets into Conversion Buffer
    UInt32 outByteCount = 0;
    // AudioFileReadPackets is depreciated but AudioFileReadPacketData does not work (in a simple function swap)
    OSStatus result = AudioFileReadPackets(audioConverterSettings->inputFile, true, &outByteCount, audioConverterSettings->inputFilePacketDescriptions, audioConverterSettings->inputFilePacketIndex, ioDataPacketCount, audioConverterSettings->sourceBuffer);
#ifdef MAC_OS_X_VERSION_10_7
    if(result == kAudioFileEndOfFileError && *ioDataPacketCount) result = noErr;
#else
    if(result == eofErr && *ioDataPacketCount) result = noErr;
#endif
    else if(result != noErr) return result;
    // 6.21 Update the Source File Position and AudioBuffer Members with the results of read
    audioConverterSettings->inputFilePacketIndex += *ioDataPacketCount;
    ioData->mBuffers[0].mData = audioConverterSettings->sourceBuffer;
    ioData->mBuffers[0].mDataByteSize = outByteCount;
    if(outDataPacketDescription){
        *outDataPacketDescription = audioConverterSettings->inputFilePacketDescriptions;
    }
    return result;
}

// 6.7 Convert() convenience function
void Convert(MyAudioConverterSettings *mySettings) {
    // 6.8 - Create an Audio Converter
    AudioConverterRef audioConverter;
    CheckError(AudioConverterNew(&mySettings->inputFormat, &mySettings->outputFormat, &audioConverter), "AudioConverterNew failed");
// 6.9 - Determine Size of Packet Buffers Array and Packets/Buffer Count if format is Variable Bit Rate
    UInt32 packetsPerBuffer = 0;
    UInt32 outputBufferSize = 32 * 1024; // 32 KB as a starting point
    UInt32 sizePerPacket = mySettings->inputFormat.mBytesPerPacket;
    if(sizePerPacket == 0) {
        UInt32 size = sizeof(sizePerPacket);
        CheckError(AudioConverterGetProperty(audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &sizePerPacket), "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize");
        if(sizePerPacket > outputBufferSize){
            outputBufferSize = sizePerPacket;
        }
        packetsPerBuffer = outputBufferSize / sizePerPacket;
        mySettings->inputFilePacketDescriptions = (AudioStreamPacketDescription*)malloc(sizeof(AudioStreamPacketDescription)*packetsPerBuffer);
    }else {
        // 6.10 - else Handle constant bit rate format
        packetsPerBuffer = outputBufferSize / sizePerPacket;
    }
    // 6.11 - Allocate Memory for the Audio Conversion Buffer
    UInt8 *outputBuffer = (UInt8*)malloc(sizeof(UInt8)* outputBufferSize);
    // 6.12 - Track position in output file and loop to convert and write data
    UInt32 outputFilePacketPosition = 0;
    while(1){
        // 6.13 Prepare an AudioBufferList to receive converted data
        AudioBufferList convertedData;
        convertedData.mNumberBuffers = 1;
        convertedData.mBuffers[0].mNumberChannels = mySettings->inputFormat.mChannelsPerFrame;
        convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
        convertedData.mBuffers[0].mData = outputBuffer;
        // 6.14 - Call AudioConverterFillComplexBuffer
        UInt32 ioOutputDataPackets = packetsPerBuffer;
        OSStatus error = AudioConverterFillComplexBuffer(audioConverter, MyAudioConverterCallback, mySettings, &ioOutputDataPackets, &convertedData, (mySettings->inputFilePacketDescriptions ? mySettings->inputFilePacketDescriptions:nil));
        if(error || !ioOutputDataPackets){
            break;
        }
        // 6.15 - Write Converted Data to an Audio File
        CheckError(AudioFileWritePackets(mySettings->outputFile, FALSE, ioOutputDataPackets, NULL, outputFilePacketPosition/mySettings->outputFormat.mBytesPerPacket, &ioOutputDataPackets, convertedData.mBuffers[0].mData), "couldn't write packets to file");
        outputFilePacketPosition += (ioOutputDataPackets * mySettings->outputFormat.mBytesPerPacket);
    }
    //6.16 - Cleanup Audio Converter
    AudioConverterDispose(audioConverter);
}



#pragma mark Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // 6.3 - Create a MyAudioConverterSettings struct and open a source audio file for conversion
        MyAudioConverterSettings audioConverterSettings = {0};
        CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                              kInputFileLocation,
                                                              kCFURLPOSIXPathStyle,
                                                              false);
        CheckError(AudioFileOpenURL(inputFileURL, kAudioFileReadPermission, 0, &audioConverterSettings.inputFile), "AudioFileOpenURL failed");
        // 6.4 - Get the ASBD (AudioStreamBasicDescription) from an Input Audio File
        UInt32 propSize = sizeof(audioConverterSettings.inputFormat);
        CheckError(AudioFileGetProperty(audioConverterSettings.inputFile, kAudioFilePropertyDataFormat, &propSize, &audioConverterSettings.inputFormat), "Couldn't get file's data format");
        // 6.5 - Get packet count and maximum packet size properties from input audio file
        propSize = sizeof(audioConverterSettings.inputFilePacketCount);
        CheckError(AudioFileGetProperty(audioConverterSettings.inputFile,
                                        kAudioFileStreamProperty_AudioDataPacketCount,
                                        &propSize,
                                        &audioConverterSettings.inputFilePacketCount),
                   "Couldn't get file's packet count");
        // get size of the largest possible packet
        propSize = sizeof(audioConverterSettings.inputFilePacketMaxSize);
        CheckError(AudioFileGetProperty(audioConverterSettings.inputFile, kAudioFilePropertyMaximumPacketSize, &propSize, &audioConverterSettings.inputFilePacketMaxSize),
                   "Couldn't get file's max packet size");
        // 6.6 - Define Ouutput ASBD and Create an Output Audio File
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
        // 6.7 - Call Convert() function and close file
        fprintf(stdout, "Converting...\n");
        Convert(&audioConverterSettings);
        AudioFileClose(audioConverterSettings.inputFile);
        AudioFileClose(audioConverterSettings.outputFile);
    }
    return 0;
}






