//
//  main.m
//  CAToneFileGenerator
//
//  Created by Jason Aylward on 12/23/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define SAMPLE_RATE 44100                               //1
#define DURATION 5.0                                    //2
#define FILENAME_FORMAT @"%0.3f-%@.aif"             //3

SInt16 square(int index, double wavelengthInSamples){
    if (index < wavelengthInSamples/2){                                     //12
        // CFSwapInt16hostToBig converts the Int16 to Big Endian format because that is the format in the AudioStreamBasicDescription
        return CFSwapInt16HostToBig(SHRT_MAX);                        //13
    }else {
        return CFSwapInt16HostToBig(SHRT_MIN);
    }
}

SInt16 saw(int index, double wavelengthInSamples){
    return CFSwapInt16HostToBig(((index/wavelengthInSamples)*SHRT_MAX*2)-SHRT_MAX);
}

SInt16 sine(int index, double wavelengthInSamples){
    return CFSwapInt16HostToBig((SInt16)SHRT_MAX * sin(2*M_PI * (index/wavelengthInSamples)));
}

// Main modified from the textbook example to accept "square", "saw", or "sine" as the second command line argument.
// Functions extracted from main to compute the three waveforms
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc <3) {
            printf("Usage: CAToneFileGenerator n\n(where n is tone in Hz)");
            return -1;
        }
        double hz = atof(argv[1]);                      //4
        NSString *waveform = [NSString stringWithUTF8String:argv[2]];
        assert (hz > 0);
        NSLog(@"generating %f hz tone", hz);
        
        NSString *fileName = [NSString stringWithFormat: FILENAME_FORMAT, hz, waveform];      //5
        NSString *filePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:fileName];
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        
        // Prepare the format
        AudioStreamBasicDescription asbd;                                           //6
        memset(&asbd, 0, sizeof(asbd));                                             //7
        asbd.mSampleRate = SAMPLE_RATE;                                             //8
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        asbd.mBitsPerChannel = 16;
        asbd.mChannelsPerFrame = 1;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerFrame = 2;
        asbd.mBytesPerPacket = 2;
        
        // Set up the file
        AudioFileID audioFile;
        OSStatus audioErr = noErr;
        audioErr = AudioFileCreateWithURL((__bridge CFURLRef)fileURL,               //9
                                          kAudioFileAIFFType, &asbd,
                                          kAudioFileFlags_EraseFile,
                                          &audioFile);
        assert (audioErr == noErr);
        
        // Start writing samples
        long maxSampleCount = SAMPLE_RATE * DURATION;                               //10
        long sampleCount = 0;
        UInt32 bytesToWrite = 2;
        // wavelength * freq = speed_of_sound(c)
        // wavelength = c/freq
        // as frequency increase, # of samples necessary for one wavelength decreases
        double wavelengthInSamples = SAMPLE_RATE / hz;                              //11
        
        
        while (sampleCount < maxSampleCount){
            for (int i = 0; i <wavelengthInSamples; i++){
                // Square wave
                SInt16 sample;
                if ([waveform isEqualToString:@"square"]) {
                    sample = square(i, wavelengthInSamples);
                }else if ([waveform isEqualToString:@"saw"]) {
                    sample = saw(i, wavelengthInSamples);
                }
                else if ([waveform isEqualToString:@"sine"]) {
                    sample = sine(i, wavelengthInSamples);
                }
                audioErr = AudioFileWriteBytes(audioFile,                           //14
                                               false,
                                               sampleCount*2,
                                               &bytesToWrite,
                                               &sample);
                assert (audioErr == noErr);
                sampleCount++;
            }
        }
        
        audioErr = AudioFileClose(audioFile);
        assert (audioErr == noErr);
        NSLog(@"write %d samples", (int)sampleCount);
    }
    return 0;
}


