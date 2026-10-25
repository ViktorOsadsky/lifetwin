#import <XCTest/XCTest.h>
#import <XCUIAutomation/XCUIAutomation.h>
@interface A11y134UITests : XCTestCase
@end
@implementation A11y134UITests
- (NSString *)variant { return @"ax5"; }
- (void)setUp { [super setUp]; self.continueAfterFailure=NO; }
- (void)text:(NSString *)text name:(NSString *)name {
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/fixes134-shots"];
 [[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *filename=[NSString stringWithFormat:@"%@-%@.txt",[self variant],name];
 [text writeToFile:[dir stringByAppendingPathComponent:filename] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 XCTAttachment *a=[XCTAttachment attachmentWithString:text];a.name=filename;a.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:a];
 NSLog(@"FIX134 %@ %@",filename,text);
}
- (void)shot:(XCUIApplication *)app name:(NSString *)name {
 [NSThread sleepForTimeInterval:1.2];
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/fixes134-shots"];
 [[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 NSString *filename=[NSString stringWithFormat:@"%@-%@.png",[self variant],name];
 XCUIScreenshot *s=app.screenshot;
 [s.PNGRepresentation writeToFile:[dir stringByAppendingPathComponent:filename] atomically:YES];
 XCTAttachment *a=[XCTAttachment attachmentWithScreenshot:s];a.name=filename;a.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:a];
 [self text:app.debugDescription name:[name stringByAppendingString:@"-tree"]];
}
- (XCUIApplication *)home {
 XCUIApplication *app=[[XCUIApplication alloc]initWithBundleIdentifier:@"com.danielqi.lifesim.fixes134"];
 [app terminate];[app launch];
 XCTAssertTrue([app.buttons[@"Settings"] waitForExistenceWithTimeout:40]);
 [NSThread sleepForTimeInterval:1.2];return app;
}
- (BOOL)visible:(XCUIElement *)e app:(XCUIApplication *)app {
 return e.exists && e.hittable && !CGRectIsEmpty(e.frame) && e.frame.size.width>10 && e.frame.size.height>10 && CGRectContainsRect(app.frame,e.frame);
}
- (void)tap:(NSString *)prefix app:(XCUIApplication *)app {
 for(int n=0;n<10;n++) {
  XCUIElementQuery *q=[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@",prefix]];
  for(XCUIElement *e in q.allElementsBoundByIndex)if([self visible:e app:app]) {
   [[e coordinateWithNormalizedOffset:CGVectorMake(.5,.5)]tap];[NSThread sleepForTimeInterval:1.2];return;
  }
  [app swipeUp];[NSThread sleepForTimeInterval:1];
 }
 [self shot:app name:@"wrong-route-missing-button"];
 XCTFail(@"Could not reach visible button %@",prefix);
}
- (void)dragBody:(XCUIApplication *)app {
 [[app coordinateWithNormalizedOffset:CGVectorMake(.5,.40)]pressForDuration:.1 thenDragToCoordinate:[app coordinateWithNormalizedOffset:CGVectorMake(.5,.18)]];
 [NSThread sleepForTimeInterval:1];
}
- (void)dragDock:(XCUIApplication *)app {
 [[app coordinateWithNormalizedOffset:CGVectorMake(.18,.84)]pressForDuration:.1 thenDragToCoordinate:[app coordinateWithNormalizedOffset:CGVectorMake(.18,.62)]];
 [NSThread sleepForTimeInterval:1];
}
- (void)test01Home {
 XCUIApplication *app=[self home];
 [self shot:app name:@"home"];
 [self tap:@"About the health score" app:app];
 XCTAssertTrue([app.buttons[@"Got it"] waitForExistenceWithTimeout:5]);
 [self shot:app name:@"score-info"];
 for(int n=1;n<=3;n++){[app swipeUp];[self shot:app name:[NSString stringWithFormat:@"score-info-scroll%d",n]];}
 [self tap:@"Got it" app:app];
 app=[self home];
 for(int n=1;n<=5;n++) {
  [app swipeUp];[NSThread sleepForTimeInterval:1];
  [self shot:app name:[NSString stringWithFormat:@"home-scroll%d",n]];
 }
}
- (void)test02ExperimentModes {
 XCUIApplication *app=[self home];[self tap:@"Experiment with your twin" app:app];
 XCTAssertTrue([app.staticTexts[@"Experiment"]waitForExistenceWithTimeout:5]);
 [self shot:app name:@"experiment-hub"];
 for(int n=1;n<=3;n++){[self dragBody:app];[self shot:app name:[NSString stringWithFormat:@"experiment-body%d",n]];}
 [self dragDock:app];[self shot:app name:@"experiment-dock-scrolled"];
}
- (void)test03KeyboardCheckIn {
 XCUIApplication *app=[self home];[self tap:@"Check in." app:app];
 XCUIElement *prompt=app.staticTexts[@"How did you sleep?"];
 XCTAssertTrue([prompt waitForExistenceWithTimeout:8],@"Actual initial sleep question");
 XCTAssertTrue(app.keyboards.firstMatch.exists,@"Keyboard must be open");
 [self shot:app name:@"checkin-keyboard"];
 XCUIElement *field=app.textFields[@"Type your answer"];
 XCTAssertTrue(field.exists);[app typeText:@"7"];
 [self dragBody:app];
 // Scroll only inside the visible dock, never the keyboard below it.
 XCUIElement *skip=app.buttons[@"Skip"];
 CGFloat top=CGRectGetMinY(skip.frame)+6;
 CGFloat bottom=CGRectGetMinY(app.keyboards.firstMatch.frame)-8;
 CGFloat x=CGRectGetMaxX(app.frame)-8;
 if(bottom-top>40) {
  XCUICoordinate *start=[[app coordinateWithNormalizedOffset:CGVectorMake(0,0)]coordinateWithOffset:CGVectorMake(x,bottom)];
  XCUICoordinate *end=[[app coordinateWithNormalizedOffset:CGVectorMake(0,0)]coordinateWithOffset:CGVectorMake(x,top)];
  [start pressForDuration:.1 thenDragToCoordinate:end];[NSThread sleepForTimeInterval:1];
 }
 XCTAssertEqualObjects([app.textFields.firstMatch.value description],@"7",@"Scrolling retains the exact typed draft");
 XCTAssertTrue(app.keyboards.firstMatch.exists,@"Scrolling retains answer keyboard");
 [self shot:app name:@"checkin-draft-after-scroll"];

}
- (void)test04QuietAmbientVoiceOver {
 XCUIApplication *app=[self home];
 XCUIVoiceOverService *vo=XCUIDevice.sharedDevice.voiceOverService;
 BOOL initial=vo.isEnabled;NSError *error=nil;
 NSMutableArray *trace=[NSMutableArray array];
 NSMutableSet *activities=[NSMutableSet set];
 BOOL focused=NO, blocked=NO;int sampleErrors=0;
 @try {
  if(!initial && ![vo enableAndReturnError:&error]){[self text:[NSString stringWithFormat:@"BLOCKED enable: %@",error] name:@"voiceover-result"];return;}
  [NSThread sleepForTimeInterval:2];
  error=nil;XCUIVoiceOverOutput *initialSpeech=[vo currentSpeechAndReturnError:&error];
  [trace addObject:[NSString stringWithFormat:@"initialSpeech=%@ error=%@",initialSpeech.utterance,error]];
  for(int i=0;i<18;i++) {
   error=nil;XCUIVoiceOverOutput *out=[vo moveForwardAndReturnError:&error];
   if(!out){[trace addObject:[NSString stringWithFormat:@"BLOCKED traversal: %@",error]];blocked=YES;break;}
   [trace addObject:out.utterance ?: @""];
   if([out.utterance containsString:@"Settings"]){focused=YES;break;}
  }
  if(focused) {
   [self shot:app name:@"voiceover-settings-focus"];
   for(int i=0;i<12;i++) {
    XCUIElement *activity=[[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@",@"Change what"]]firstMatch];
    if(activity.exists)[activities addObject:activity.label];
    [NSThread sleepForTimeInterval:1];
    error=nil;XCUIVoiceOverOutput *out=[vo currentSpeechAndReturnError:&error];
    if(!out && error)sampleErrors++;
    [trace addObject:[NSString stringWithFormat:@"sample%d speech=%@ error=%@ activity=%@",i,out.utterance,error,activity.label]];
    if(out && ([out.utterance containsString:@"Change what"] || [out.utterance rangeOfString:@"is walking|is relaxing|is eating|is sleeping|is exercising" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound)) {
     XCTFail(@"Ambient activity interrupted Settings: %@",out.utterance);
    }
   }
   [self shot:app name:@"voiceover-after-ambient-window"];
  }
  NSString *result=blocked || !focused || activities.count<2 ? @"BLOCKED insufficient actual traversal or activity transition evidence" : (sampleErrors ? @"PARTIAL Settings spoken and activities changed, but speech sampling returned errors; no certified quiet-speech pass" : @"OBSERVED Settings focus followed by quiet ambient activity transitions; see speech samples");
  [self text:[NSString stringWithFormat:@"%@; focused=%d distinctActivities=%lu sampleErrors=%d",result,focused,(unsigned long)activities.count,sampleErrors] name:@"voiceover-result"];
 } @finally {
  [self text:[trace componentsJoinedByString:@"\n"] name:@"voiceover-actual-trace"];
  error=nil;if(!initial)XCTAssertTrue([vo disableAndReturnError:&error],@"Restore original VO: %@",error);
  XCTAssertEqual(vo.isEnabled,initial);
  [self text:[NSString stringWithFormat:@"initial=%d final=%d",initial,vo.isEnabled] name:@"voiceover-restoration"];
 }
}
@end
