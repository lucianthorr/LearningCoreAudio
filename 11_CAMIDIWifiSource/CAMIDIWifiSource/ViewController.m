//
//  ViewController.m
//  CAMIDIWifiSource
//
//  Created by Jason Aylward on 1/28/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import "ViewController.h"

// 11.16 Define for MIDI Host Address
#define DESTINATION_ADDRESS @"192.168.1.65"

// 11.14 - Class Extension for ViewController Helper Methods and Properties
@interface ViewController ()
-(void)connectToHost;
-(void)sendStatus:(Byte)status data1:(Byte)data1 data2:(Byte)data2;
-(void)sendNoteOnEvent:(Byte)note velocity:(Byte)velocity;
-(void)sendNoteOffEvent:(Byte)key velocity:(Byte)velocity;

@property (assign) MIDINetworkSession *midiSession;
@property (assign) MIDIEndpointRef destinationEndpoint;
@property (assign) MIDIPortRef outputPort;
@end

@implementation ViewController

@synthesize midiSession, destinationEndpoint, outputPort;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self connectToHost];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// 11.17 - Create a MIDINetworkHost
-(void)connectToHost {
    MIDINetworkHost *host = [MIDINetworkHost hostWithName:@"MyMIDIWifi" address:DESTINATION_ADDRESS port: 5004];
    if(!host){
        return;
    }
    // 11.18 - Create a MIDINetworkConnection
    MIDINetworkConnection *connection = [MIDINetworkConnection connectionWithHost:host];
    if(!connection){
        return;
    }
    // 11.19 - Setup MIDINetworkSession to Send MIDI Data
    self.midiSession = [MIDINetworkSession defaultSession];
    if(self.midiSession){
        NSLog(@"Got MIDI Session");
        [self.midiSession addConnection:connection];
        self.midiSession.enabled = YES;
        self.destinationEndpoint = [self.midiSession destinationEndpoint];
        // 11.20 - Setup a MIDI Output Port
        MIDIClientRef client = NULL;
        MIDIPortRef output = NULL;
        CheckError(MIDIClientCreate(CFSTR("MyMIDIWifi Client"), NULL, NULL, &client), "Couldn't create MIDI client");
        CheckError(MIDIOutputPortCreate(client, CFSTR("MyMIDIWifi Output port"), &output), "Couldn't create output port");
        self.outputPort = output;
        NSLog(@"Got output port");
    }
}

-(void)sendStatus:(Byte)status data1:(Byte)data1 data2:(Byte)data2 {
    MIDIPacketList packetList;
    packetList.numPackets = 1;
    packetList.packet[0].length = 3;
    packetList.packet[0].data[0] = status;
    packetList.packet[0].data[1] = data1;
    packetList.packet[0].data[2] = data2;
    packetList.packet[0].timeStamp = 0;
    CheckError(MIDISend(self.outputPort, self.destinationEndpoint, &packetList), "Couldn't send MIDI packet list");
}
// 11.22 - Send NOTE ON and NOTE OFF Events
-(void)sendNoteOnEvent:(Byte)key velocity:(Byte)velocity {
    [self sendStatus:0x90 data1:key & 0x7F data2:velocity & 0x7F];
}
-(void)sendNoteOffEvent:(Byte)key velocity:(Byte)velocity {
    [self sendStatus:0x80 data1:key & 0x7F data2:velocity & 0x7F];
}

// 11.23 - Handle User Taps on Keys
- (IBAction)handleKeyUp:(id)sender{
    NSInteger note = [sender tag];
    [self sendNoteOffEvent:(Byte)note velocity:127];
}
- (IBAction)handleKeyDown:(id)sender {
    NSInteger note = [sender tag];
    [self sendNoteOnEvent:(Byte)note velocity:127];
}



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
@end
