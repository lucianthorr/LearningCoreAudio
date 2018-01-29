//
//  main.m
//  CAPositionalSound
//
//  Created by Jason Aylward on 1/7/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <OpenAL/al.h>
#import <OpenAL/alc.h>


#define RUN_TIME 20.0
#define ORBIT_SPEED 1
#define LOOP_PATH CFSTR("/Users/jasonaylward/Desktop/output2.caf")

#pragma mark UserData struct
// 9.3 - MyLoopPlayer struct
typedef struct MyLoopPlayer {
    AudioStreamBasicDescription dataFormat;
    UInt16 *sampleBuffer;
    UInt32 bufferSizeBytes;
    ALuint sources[1];
} MyLoopPlayer;

#pragma mark utility
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
// 9.2 - OpenAL version of CheckError
static void CheckALError(const char *operation){
    ALenum alErr = alGetError();
    if(alErr == AL_NO_ERROR) return;
    char *errFormat = NULL;
    switch (alErr) {
        case AL_INVALID_NAME:
            errFormat = "OpenAL Error: %s(AL_INVALID_NAME)";
            break;
        case AL_INVALID_VALUE:
            errFormat = "OpenAL Error: %s(AL_INVALID_VALID)";
            break;
        case AL_INVALID_ENUM:
            errFormat = "OpenAL Error: %s(AL_INVALID_ENUM)";
            break;
        case AL_INVALID_OPERATION:
            errFormat = "OpenAL Error: %s(AL_INVALID_OPERATION)";
            break;
        case AL_OUT_OF_MEMORY:
            errFormat = "OpenAL Error: %s(AL_OUT_OF_MEMORY)";
            break;
    }
    fprintf(stderr, errFormat, operation);
    exit(1);
}

void updateSourceLocation(MyLoopPlayer player){
    // 9.17 - update the AL_POSITION of a source as an "Orbit"
    double theta = fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED, M_PI * 2);
    ALfloat x = 3 * cos(theta);
    ALfloat y = 0.5 * sin(theta);
    ALfloat z = 1.0 * sin(theta);
    alSource3f(player.sources[0], AL_POSITION, x, y, z);
}

OSStatus loadLoopIntoBuffer(MyLoopPlayer *player){
    // 9.18 - Create an ExtAudioFile for Reading into OpenAL
    CFURLRef loopFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, LOOP_PATH, kCFURLPOSIXPathStyle, false);
    ExtAudioFileRef extAudioFile;
    CheckError(ExtAudioFileOpenURL(loopFileURL, &extAudioFile), "Couldn't open extAudioFile for reading");
    // 9.19 - Describe the AL_FORMAT_MONO16 format as an audiostreambasicdescription and use it with an ExtAudioFile
    memset(&player->dataFormat, 0, sizeof(player->dataFormat));
    player->dataFormat.mFormatID = kAudioFormatLinearPCM;
    player->dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    player->dataFormat.mSampleRate = 44100.0;
    player->dataFormat.mChannelsPerFrame = 1;
    player->dataFormat.mFramesPerPacket = 1;
    player->dataFormat.mBitsPerChannel = 16;
    player->dataFormat.mBytesPerFrame = 2;
    player->dataFormat.mBytesPerPacket = 2;
    // Tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(extAudioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &player->dataFormat), "Couldn't set client format on ExtAudioFile");
    // 9.20 -  Allocate a Read Buffer for the ExtAudioFile-to-OpenAL transfer
    SInt64 fileLengthFrames;
    UInt32 propSize = sizeof(fileLengthFrames);
    ExtAudioFileGetProperty(extAudioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &fileLengthFrames);
    player->bufferSizeBytes = fileLengthFrames*player->dataFormat.mBytesPerFrame;
    
    AudioBufferList *buffers;
    UInt32 ablSize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer)*1);
    buffers = malloc(ablSize);
    
    player->sampleBuffer = malloc(sizeof(UInt16)*player->bufferSizeBytes);
    buffers->mNumberBuffers = 1;
    buffers->mBuffers[0].mNumberChannels = 1;
    buffers->mBuffers[0].mDataByteSize = player->bufferSizeBytes;
    buffers->mBuffers[0].mData = player->sampleBuffer;
    
    // 9.21 Read Data with an ExtAudioFile for Use in openal Buffer
    // Loop reading into the ABL until buffer is full
    UInt32 totalFramesRead = 0;
    do{
        UInt32 framesRead = fileLengthFrames - totalFramesRead;
        // While doing successive reads
        buffers->mBuffers[0].mData = player->sampleBuffer + (totalFramesRead * sizeof(UInt16));
        CheckError(ExtAudioFileRead(extAudioFile, &framesRead, buffers), "ExtAudioFileRead failed");
        totalFramesRead += framesRead;
        printf("read %d frames\n", framesRead);
    }while(totalFramesRead < fileLengthFrames);
    free(buffers);
    return noErr;
}

#pragma Main
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Convert to an OpenAL-friendly format and read into memory
        // 9.4 - setup for OpenAL Looping
        MyLoopPlayer player;
        // Convert to an OpenAL-friendly format and read into memory
        CheckError(loadLoopIntoBuffer(&player), "Couldn't load loop into buffer");
        // 9.5 - Open a default OpenAL device and create a context
        ALCdevice *alDevice = alcOpenDevice(NULL);
        CheckALError("Couldn't open AL device.");
        ALCcontext *alContext = alcCreateContext(alDevice, 0);
        CheckALError("Couldn't open AL context.");
        alcMakeContextCurrent(alContext);
        CheckALError("Couldn't make AL context current.");
        
        //SetupOpenAL buffer
        // 9.6 - Create OpenAL buffers
        ALuint buffers[1];
        alGenBuffers(1, buffers);
        CheckALError("Couldn't generate buffers");
        // 9.7 - Attach a buffer of AudioSamples to an OpenAL buffer
        alBufferData(*buffers, AL_FORMAT_MONO16, player.sampleBuffer, player.bufferSizeBytes, player.dataFormat.mSampleRate);
        CheckALError("Couldn't buffer data");
        // 9.8 - Free a sample buffer after its contents have been copied to OpenAL
        free(player.sampleBuffer);
        // 9.9 Create an OpenAL Source
        alGenSources(1, player.sources);
        CheckALError("Couldn't generate sources");
        // 9.10 - Set AL_LOOPING and AL_GAIN properties on an OpenAL source
        alSourcei(player.sources[0], AL_LOOPING, AL_TRUE);
        CheckALError("Couldn't set source looping property");
        alSourcef(player.sources[0], AL_GAIN, AL_MAX_GAIN);
        CheckALError("Couldn't set source gain");
        // 9.11 - Set initial source position
        updateSourceLocation(player);
        CheckALError("Couldn't set initial source position");
        //Connect buffer to source
        // 9.12 - Attach OpenAL buffer to a source
        alSourcei(player.sources[0], AL_BUFFER, buffers[0]);
        CheckALError("Couldn't connect buffer to source");
        
        // Set up listener
        // 9.13 - set the initial position of the OpenAL listener
        alListener3f(AL_POSITION, 0.0, 0.0, 0.0);
        CheckALError("Couldn't set listener position");
        
        // Start playing
        // 9.14 - player an openal source
        alSourcePlay(player.sources[0]);
        CheckALError("Couldn't play");
        
        // 9.15 - Loop to Animate the Source Position
        // And wait
        printf("Playing...\n");
        time_t startTime = time(NULL);
        do {
            // Get next thetac
            updateSourceLocation(player);
            CheckALError("Couldn't set looping source position");
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        }while(difftime(time(NULL), startTime) < RUN_TIME);
        
        // Clean up
        // 9.16 - Clean up OpenAL Resources
        alSourceStop(player.sources[0]);
        alDeleteSources(1, player.sources);
        alDeleteBuffers(1, buffers);
        alcDestroyContext(alContext);
        alcCloseDevice(alDevice);
        printf("Bottom of main\n");
    }
    return 0;
}
