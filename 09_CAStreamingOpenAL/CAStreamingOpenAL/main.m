//
//  main.m
//  CAStreamingOpenAL
//
//  Created by Jason Aylward on 1/7/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <OpenAL/al.h>
#import <OpenAL/alc.h>

#define RUN_TIME 20.0
#define BUFFER_COUNT 3
#define ORBIT_SPEED 1
#define BUFFER_DURATION_SECONDS 2.0
#define STREAM_PATH CFSTR("/Users/jasonaylward/Desktop/output2.caf")


#pragma mark UserData struct
typedef struct MyStreamPlayer {
    // 9.23 - struct for passing program around state
    AudioStreamBasicDescription dataFormat;
    UInt32                      bufferSizeBytes;
    SInt64                      fileLengthFrames;
    SInt64                      totalFramesRead;
    ALuint                      sources[1];
    ExtAudioFileRef             extAudioFile;
} MyStreamPlayer;


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

void updateSourceLocation(MyStreamPlayer player){
    // 9.17 - update the AL_POSITION of a source as an "Orbit"
    double theta = fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED, M_PI * 2);
    ALfloat x = 3 * cos(theta);
    ALfloat y = 0.5 * sin(theta);
    ALfloat z = 1.0 * sin(theta);
    alSource3f(player.sources[0], AL_POSITION, x, y, z);
}

OSStatus setUpExtAudioFile(MyStreamPlayer *player){
    // 9.30 - Set up an ExtAudioFile for Reading into a Stream
    CFURLRef streamFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, STREAM_PATH, kCFURLPOSIXPathStyle, false);
    // Describe the client format - AL needs mono
    memset(&player->dataFormat, 0, sizeof(player->dataFormat));
    player->dataFormat.mFormatID = kAudioFormatLinearPCM;
    player->dataFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    player->dataFormat.mSampleRate = 44100.0;
    player->dataFormat.mChannelsPerFrame = 1;
    player->dataFormat.mFramesPerPacket = 1;
    player->dataFormat.mBitsPerChannel = 16;
    player->dataFormat.mBytesPerFrame = 2;
    player->dataFormat.mBytesPerPacket = 2;
    CheckError(ExtAudioFileOpenURL(streamFileURL, &player->extAudioFile), "Couldn't open ExtAudioFile for reading");
    
    // Tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(player->extAudioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(AudioStreamBasicDescription), &player->dataFormat), "Couldn't set client format on ExtAudioFile");
    
    // Figure out how big file is
    UInt32 propSize = sizeof(player->fileLengthFrames);
    ExtAudioFileGetProperty(player->extAudioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &player->fileLengthFrames);
    printf("fileLengthFrames = %11d frames\n", (int)player->fileLengthFrames);
    
    player->bufferSizeBytes = BUFFER_DURATION_SECONDS * player->dataFormat.mSampleRate * player->dataFormat.mBytesPerFrame;
    printf("bufferSizeBytes=%d\n", player->bufferSizeBytes);
    printf("bottom of setupExtAudioFile\n");
    return noErr;
}

void fillALBuffer(MyStreamPlayer *player, ALuint alBuffer){
    // 9.31 - Setup an AudioBufferList and its single audiobuffer for Reading from ExtAudioFile
    AudioBufferList *bufferList;
    UInt32 ablSize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer) * 1); // 1 channel
    bufferList = malloc(ablSize);
    
    // Allocate sample buffer
    UInt16 *sampleBuffer = malloc(sizeof(UInt16)*player->bufferSizeBytes);
    
    bufferList->mNumberBuffers = 1;
    bufferList->mBuffers[0].mNumberChannels = 1;
    bufferList->mBuffers[0].mDataByteSize = player->bufferSizeBytes;
    bufferList->mBuffers[0].mData = sampleBuffer;
    printf("allocated %d byte buffer form ABL\n", player->bufferSizeBytes);
    // 9.32 - Read from ExtAudioFile
    UInt32 framesReadIntoBuffer = 0;
    do {
        UInt32 framesRead = player->fileLengthFrames - framesReadIntoBuffer;
        bufferList->mBuffers[0].mData = sampleBuffer + (framesReadIntoBuffer*(sizeof(UInt16)));
        CheckError(ExtAudioFileRead(player->extAudioFile, &framesRead, bufferList), "ExtAudioFileRead failed");
        framesReadIntoBuffer += framesRead;
        player->totalFramesRead += framesRead;
        printf("read %d frames\n", framesRead);
    }while(framesReadIntoBuffer < (player->bufferSizeBytes/sizeof(UInt16)));
    // 9.33 - Copying Samples from Memory Buffer to OpenAL Buffer
    alBufferData(alBuffer, AL_FORMAT_MONO16, sampleBuffer, player->bufferSizeBytes, player->dataFormat.mSampleRate);
    free(bufferList);
    free(sampleBuffer);
}

void refillALBuffers(MyStreamPlayer *player){
    // 9.34 - Check an OpenAL Source for Exhausted Streaming Buffers
    ALint processed;
    alGetSourcei(player->sources[0], AL_BUFFERS_PROCESSED, &processed);
    CheckALError("couldn't get al_buffers_processed");
    // 9.35 - Unqueue and refill OpenAL Buffers
    while(processed>0){
        ALuint freeBuffer;
        alSourceUnqueueBuffers(player->sources[0], 1, &freeBuffer);
        CheckALError("Couldn't unqueue buffer");
        printf("Refilling buffer %d\n", freeBuffer);
        fillALBuffer(player, freeBuffer);
        alSourceQueueBuffers(player->sources[0], 1, &freeBuffer);
        CheckALError("Couldn't queue refilled buffer");
        printf("Re-queue buffer %d\n", freeBuffer);
        processed--;
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Prepare the ExtAudioFile for reading
        // Set up OpenAL buffers
        // 9.24 - Set up ExtAudioFile and Create an OpenAL Context for Streaming
        MyStreamPlayer player;
        CheckError(setUpExtAudioFile(&player), "Couldn't openExtAudioFile");
        ALCdevice *alDevice = alcOpenDevice(NULL);
        CheckALError("Couldn't openAL device");
        ALCcontext *alContext = alcCreateContext(alDevice, 0);
        CheckALError("Couldn't open AL context");
        alcMakeContextCurrent(alContext);
        CheckALError("Couldn't make AL context current");
        
        // 9.25 - Create and Fill OpenAL Buffers for streaming
        ALuint buffers[BUFFER_COUNT];
        alGenBuffers(BUFFER_COUNT, buffers);
        CheckALError("Couldn't generate buffers");
        for(int i=0; i<BUFFER_COUNT; i++){
            fillALBuffer(&player, buffers[i]);
        }
        
        // Set up streaming source
        // 9.26 Create an OpenAL Source for Streaming
        alGenSources(1, player.sources);
        CheckALError("Couldn't generate sources");
        alSourcef(player.sources[0], AL_GAIN, AL_MAX_GAIN);
        CheckALError("Couldn't set source gain");
        updateSourceLocation(player);
        CheckALError("Couldn't set initial source position");
        
        // Queue up the buffers on the source
        // 9.27 - Queue Buffers on an OpenAL Source
        alSourceQueueBuffers(player.sources[0], BUFFER_COUNT, buffers);
        CheckALError("Couldn't queue buffers on source");
        
        // Set up listener
        // 9.28 - Create a Listener and Start a Stream-orbiting source
        alListener3f(AL_POSITION, 0.0, 0.0, 0.0);
        CheckALError("Couldn't set listener position");
        // Start playing
        alSourcePlayv(1, player.sources);
        
        
        // Loop and wait
        // 9.29 - Infinite loop to update the openAL source position and refill exhausted buffers
        printf("Playing...");
        time_t startTime = time(NULL);
        do {
            // Get next theta
            updateSourceLocation(player);
            CheckALError("Couldn't set looping source position");
            // Refill buffers if needed
            refillALBuffers(&player);
            
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        }while(difftime(time(NULL), startTime) < RUN_TIME);
        
        // Clean up
        // 9.29
        alSourceStop(player.sources[0]);
        alDeleteSources(1, player.sources);
        alDeleteBuffers(BUFFER_COUNT, buffers);
        alcDestroyContext(alContext);
        alcCloseDevice(alDevice);
        printf("Bottom of main\n");
    }
    return 0;
}








