//
//  AppDelegate.h
//  CAiOSBackgroundTone
//
//  Created by Jason Aylward on 1/15/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>



@interface AppDelegate : UIResponder <UIApplicationDelegate>  // UIResponder is NSObject in text

@property (strong, nonatomic) UIWindow *window;         // UIWindow -> IBOutlet

// 10.1 (Outline of header)
@property (nonatomic, assign) AudioQueueRef audioQueue;
@property (nonatomic, assign) AudioStreamBasicDescription streamFormat;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, assign) double currentFrequency;
@property (nonatomic, assign) double startingFrameCount;

-(OSStatus) fillBuffer: (AudioQueueBufferRef) buffer;

@end

