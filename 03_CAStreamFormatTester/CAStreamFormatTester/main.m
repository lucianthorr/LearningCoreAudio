//
//  main.m
//  CAStreamFormatTester
//
//  Created by Jason Aylward on 12/23/17.
//  Copyright © 2017 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        AudioFileTypeAndFormatID fileTypeAndFormat;     //1
        fileTypeAndFormat.mFileType = kAudioFileMP3Type;
        fileTypeAndFormat.mFormatID = kAudioFormatMPEGLayer3;  // MP3 == "MPEG-1 Audio Layer 3"
        
        OSStatus audioErr = noErr;                      // 2
        UInt32 infoSize = 0;
        
        // AudioFileGetGlobalInfoSize
        audioErr =                                      // 3
            AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, sizeof(fileTypeAndFormat), &fileTypeAndFormat, &infoSize);
        if (audioErr != noErr){
            UInt32 err4cc = CFSwapInt32HostToBig(audioErr);
            NSLog(@"audioErr = %4.4s", (char*)&err4cc);
        }
//        assert(audioErr == noErr);
        
        // AudioFileGetGlobalInfo
        AudioStreamBasicDescription *asbds = malloc(infoSize);      // 4
        audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                          sizeof(fileTypeAndFormat), &fileTypeAndFormat, &infoSize, asbds);
        assert(audioErr == noErr);
        
        int asbdCount = infoSize / sizeof(AudioStreamBasicDescription);
        
        for(int i=0; i<asbdCount; i++){                                     // 6
            UInt32 format4cc = CFSwapInt32HostToBig(asbds[i].mFormatID);    // 7
            NSLog(@"%d: mFormatId: %4.4s, mFormatFlags: %d, mBitsPerChannel: %d",
            i, (char*)&format4cc, asbds[i].mFormatFlags, asbds[i].mBitsPerChannel);
        }
        free(asbds);
        
        
    }
    return 0;
}
