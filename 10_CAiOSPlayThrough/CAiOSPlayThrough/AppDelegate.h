//
//  AppDelegate.h
//  CAiOSPlayThrough
//
//  Created by Jason Aylward on 1/21/18.
//  Copyright © 2018 Jason Aylward. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

// 10.16 - Header File for iOS Audio Unit Pass-Through app
typedef struct {
    AudioUnit rioUnit;
    AudioStreamBasicDescription asbd;
    float sineFrequency;
    float sinePhase;
    
} EffectState;


@interface AppDelegate : UIResponder <UIApplicationDelegate>


@property (strong, nonatomic) UIWindow *window;
@property (assign, nonatomic)   EffectState effectState;

@end

