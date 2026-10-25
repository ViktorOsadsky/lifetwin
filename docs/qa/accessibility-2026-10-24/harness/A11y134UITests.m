#import <XCTest/XCTest.h>
#import <XCUIAutomation/XCUIAutomation.h>
@interface A11y134UITests : XCTestCase
@end
@implementation A11y134UITests
- (void)text:(NSString *)text name:(NSString *)name {
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/qa134-shots"];
 [[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 [text writeToFile:[dir stringByAppendingPathComponent:[[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingString:@".txt"]] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 XCTAttachment *a=[XCTAttachment attachmentWithString:text];a.name=name;a.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:a];
 NSLog(@"QA134 %@ %@",name,text);
}
- (void)shot:(XCUIApplication *)app name:(NSString *)name {
 [NSThread sleepForTimeInterval:1.2];
 XCUIScreenshot *screenshot=app.screenshot;
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/qa134-shots"];
 [[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 [screenshot.PNGRepresentation writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
 XCTAttachment *a=[XCTAttachment attachmentWithScreenshot:screenshot];a.name=name;a.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:a];
 [self text:app.debugDescription name:[name stringByAppendingString:@"-tree"]];
}
- (void)testVoiceOverCapabilityBase {
 XCUIApplication *app=[[XCUIApplication alloc]initWithBundleIdentifier:@"com.danielqi.lifesim.a11y134"];
 [app launch];
 XCTAssertTrue([app.buttons[@"Settings"] waitForExistenceWithTimeout:45]);
 [self shot:app name:@"base-home"];
 XCUIVoiceOverService *vo=XCUIDevice.sharedDevice.voiceOverService;
 BOOL initial=vo.isEnabled;NSError *error=nil;
 [self text:[NSString stringWithFormat:@"initialEnabled=%d",initial] name:@"voiceover-state"];
 @try {
  if(!initial) XCTAssertTrue([vo enableAndReturnError:&error],@"VO start: %@",error);
  XCTAssertTrue(vo.isEnabled);
  [self text:vo.debugDescription name:@"voiceover-service"];
  XCUIVoiceOverOutput *out=[vo currentSpeechAndReturnError:&error];
  [self text:out ? out.utterance : (error.description ?: @"NO_CURRENT_SPEECH") name:@"voiceover-current"];
  for(int i=0;i<8;i++) {
   error=nil;out=[vo moveForwardAndReturnError:&error];
   XCTAssertNotNil(out,@"VO speech failed: %@",error);
   if(!out)break;
   [self text:out.utterance name:[NSString stringWithFormat:@"voiceover-forward-%d",i]];
  }
  [self shot:app name:@"base-home-voiceover-focus"];
 } @finally {
  error=nil;if(!initial)XCTAssertTrue([vo disableAndReturnError:&error],@"restore: %@",error);
  XCTAssertEqual(vo.isEnabled,initial);
  [self text:[NSString stringWithFormat:@"finalEnabled=%d",vo.isEnabled] name:@"voiceover-restored"];
 }
}

- (NSString *)variant { return @"ax5"; }
- (XCUIApplication *)home {
 NSError *restoreError=nil;
 if(XCUIDevice.sharedDevice.voiceOverService.isEnabled)XCTAssertTrue([XCUIDevice.sharedDevice.voiceOverService disableAndReturnError:&restoreError],@"Restore recorded initial VO=false: %@",restoreError);
 XCUIApplication *app=[[XCUIApplication alloc]initWithBundleIdentifier:@"com.danielqi.lifesim.a11y134"];
 [app launch];XCTAssertTrue([app.buttons[@"Settings"] waitForExistenceWithTimeout:35]);return app;
}
- (BOOL)visible:(XCUIElement *)e app:(XCUIApplication *)app {
 return e.exists && e.hittable && !CGRectIsEmpty(e.frame) && e.frame.size.width>10 && e.frame.size.height>10 && CGRectContainsRect(app.frame,e.frame);
}
- (BOOL)tap:(NSString *)prefix app:(XCUIApplication *)app {
 for(int i=0;i<9;i++) {
  XCUIElementQuery *matches=[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@",prefix]];
  XCUIElement *e=matches.firstMatch;
  for(XCUIElement *candidate in matches.allElementsBoundByIndex)if([self visible:candidate app:app]){e=candidate;break;}
  if([self visible:e app:app]){[[e coordinateWithNormalizedOffset:CGVectorMake(0.5,0.5)] tap];[NSThread sleepForTimeInterval:1.2];return YES;}
  if(i==0&&[e waitForExistenceWithTimeout:3]&&[self visible:e app:app]){[[e coordinateWithNormalizedOffset:CGVectorMake(0.5,0.5)] tap];[NSThread sleepForTimeInterval:1.2];return YES;}
  [app swipeUp];[NSThread sleepForTimeInterval:1.0];
 }
 [self shot:app name:[[self variant] stringByAppendingFormat:@"-missing-action-%@",prefix]];
 XCTFail(@"Could not reach native button %@",prefix);return NO;
}
- (BOOL)tapContains:(NSString *)part app:(XCUIApplication *)app {
 for(int i=0;i<8;i++) {
  XCUIElementQuery *matches=[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@",part]];
  XCUIElement *e=matches.firstMatch;
  for(XCUIElement *candidate in matches.allElementsBoundByIndex)if([self visible:candidate app:app]){e=candidate;break;}
  if([self visible:e app:app]){[[e coordinateWithNormalizedOffset:CGVectorMake(0.5,0.5)] tap];[NSThread sleepForTimeInterval:1.2];return YES;}[app swipeUp];[NSThread sleepForTimeInterval:1.0];
 }
 [self shot:app name:[[self variant] stringByAppendingFormat:@"-missing-contains-%@",part]];
 XCTFail(@"Could not reach native button containing %@",part);return NO;
}
- (void)capture:(NSString *)screen app:(XCUIApplication *)app steps:(int)steps {
 NSString *name=[[self variant] stringByAppendingFormat:@"-%@",screen];
 [self shot:app name:name];
 if(![[self variant] isEqualToString:@"base"])steps=0;
 if(steps) {
  XCUIVoiceOverService *vo=XCUIDevice.sharedDevice.voiceOverService;
  BOOL initial=vo.isEnabled;NSError *error=nil;
  @try {
   if(!initial&&! [vo enableAndReturnError:&error]){XCTFail(@"VO start: %@",error);return;}
   [self text:[NSString stringWithFormat:@"enabled=%d",vo.isEnabled] name:[name stringByAppendingString:@"-vo-state"]];
   XCUIVoiceOverOutput *out=[vo currentSpeechAndReturnError:&error];
   [self text:out ? out.utterance : (error.description ?: @"NO_CURRENT_SPEECH") name:[name stringByAppendingString:@"-vo-current"]];
   for(int n=0;n<steps;n++) {
    error=nil;out=[vo moveForwardAndReturnError:&error];if(!out){XCTFail(@"VO: %@",error);break;}
    [self text:out.utterance name:[name stringByAppendingFormat:@"-vo-forward-%d",n]];
   }
   for(int n=0;n<6;n++) {
    error=nil;out=[vo moveBackwardAndReturnError:&error];if(!out)break;
    [self text:out.utterance name:[name stringByAppendingFormat:@"-vo-backward-%d",n]];
   }
  } @finally {
   error=nil;if(!initial)XCTAssertTrue([vo disableAndReturnError:&error],@"VO restore: %@",error);
   XCTAssertEqual(vo.isEnabled,initial);
  }
 }
 NSError *error=nil;
 BOOL ran=[app performAccessibilityAuditWithAuditTypes:(XCUIAccessibilityAuditTypeContrast|XCUIAccessibilityAuditTypeHitRegion|XCUIAccessibilityAuditTypeTextClipped|XCUIAccessibilityAuditTypeSufficientElementDescription)
 issueHandler:^BOOL(XCUIAccessibilityAuditIssue *issue){
  [self text:[NSString stringWithFormat:@"%@ Element: %@",issue.detailedDescription,issue.element.debugDescription] name:[name stringByAppendingString:@"-AUDIT-REVIEW"]];return YES;
 } error:&error];
 [self text:[NSString stringWithFormat:@"ran=%d error=%@; findings are recorded for manual triage, not ignored passes",ran,error] name:[name stringByAppendingString:@"-audit-status"]];
}
- (void)scrollShots:(NSString *)screen app:(XCUIApplication *)app count:(int)count {
 for(int n=1;n<=count;n++){[app swipeUp];[NSThread sleepForTimeInterval:1.0];[self shot:app name:[[self variant] stringByAppendingFormat:@"-%@-scroll%d",screen,n]];}
}
- (void)test01Home { XCUIApplication *app=[self home];[self capture:@"home" app:app steps:28];[self scrollShots:@"home" app:app count:4]; }
- (void)test02ScoreSheet {
 XCUIApplication *app=[self home];if(![self tap:@"About the health score" app:app])return;
 [self capture:@"score-info" app:app steps:22];[self scrollShots:@"score-info" app:app count:2];
 [self tap:@"Got it" app:app];[self shot:app name:[[self variant] stringByAppendingString:@"-score-dismissed"]];
}
- (void)test03Settings {
 XCUIApplication *app=[self home];if(![self tap:@"Settings" app:app])return;
 [self capture:@"settings" app:app steps:28];[self scrollShots:@"settings" app:app count:3];
}
- (void)test04History {
 XCUIApplication *app=[self home];if(![self tap:@"My history" app:app])return;
 [self capture:@"history" app:app steps:28];
 if(![self tap:@"See this day" app:app])return;
 [self shot:app name:[[self variant] stringByAppendingString:@"-history-after-tap-diagnostic"]];
 XCUIElement *caveat=[[app staticTexts] matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@",@"Past entries stay read-only"]].firstMatch;
 XCTAssertTrue([caveat waitForExistenceWithTimeout:3],@"History sheet caveat must actually exist");
 [self capture:@"history-detail" app:app steps:24];[self scrollShots:@"history-detail" app:app count:3];
}
- (void)test05Experiment {
 XCUIApplication *app=[self home];if(![self tap:@"Experiment with your twin" app:app])return;
 [self capture:@"experiment-hub" app:app steps:30];
 // Reopen so VoiceOver's auto-scrolling does not choose the starting viewport.
 [app terminate];app=[self home];if(![self tap:@"Experiment with your twin" app:app])return;
 if(![self tap:@"Sleep" app:app])return;
 XCTAssertTrue([app.buttons[@"Half an hour more sleep"] waitForExistenceWithTimeout:5],@"Actual sleep lever must open");
 [self capture:@"experiment-lever" app:app steps:26];
 if(![self tap:@"Half an hour more sleep" app:app])return;
 [self capture:@"experiment-result" app:app steps:24];
 [self scrollShots:@"experiment-result" app:app count:3];
 [self tap:@"Use in my what-if" app:app];
 [self shot:app name:[[self variant] stringByAppendingString:@"-experiment-applied"]];
}
- (void)test06Ideas {
 XCUIApplication *app=[self home];if(![self tap:@"Experiment with your twin" app:app])return;
 if(![self tap:@"Ideas for you" app:app])return;
 [self capture:@"ideas-list" app:app steps:32];
 // Return to the top of this real route after spoken traversal.
 for(int i=0;i<5;i++)[app swipeDown];[NSThread sleepForTimeInterval:1.0];
 if(![self tapContains:@"Open details" app:app])return;
 [self capture:@"ideas-detail" app:app steps:30];[self scrollShots:@"ideas-detail" app:app count:3];
 [self text:[NSString stringWithFormat:@"What does this mean? native button exists=%d",app.buttons[@"What does this mean?"].exists] name:@"ideas-detail-effect-control-check"];
 // Reopen the actual list to reach its distinct effect-cue button.
 [app terminate];app=[self home];if(![self tap:@"Experiment with your twin" app:app])return;
 if(![self tap:@"Ideas for you" app:app])return;
 if(![self tap:@"Modeled effect:" app:app])return;
 [self capture:@"ideas-effect" app:app steps:24];[self scrollShots:@"ideas-effect" app:app count:3];
}
- (void)test07Band {
 XCUIApplication *app=[self home];if(![self tap:@"Add band" app:app])return;
 [self shot:app name:[[self variant] stringByAppendingString:@"-band-pair"]];
 XCUIElement *panel=app.staticTexts[@"Your band"];
 if(!panel.exists){if(![self tap:@"Find my band" app:app])return;if(![self tap:@"Try a recorded demo" app:app])return;}
 [self capture:@"band-panel" app:app steps:28];[self scrollShots:@"band-panel" app:app count:3];
}
- (void)test08DailyCheckIn {
 XCUIApplication *app=[self home];if(![self tap:@"Check in." app:app])return;
 [self capture:@"daily-checkin" app:app steps:28];[self scrollShots:@"daily-checkin" app:app count:2];
 [[app coordinateWithNormalizedOffset:CGVectorMake(0.1,0.25)] tap];[self shot:app name:[[self variant] stringByAppendingString:@"-daily-checkin-after-background-tap"]];
}
- (void)test09Onboarding {
 XCUIApplication *app=[self home];if(![self tap:@"Talk" app:app])return;
 [self capture:@"onboarding-consent" app:app steps:24];
 if(![self tap:@"No, I'll type" app:app])return;
 [self capture:@"onboarding-conversation" app:app steps:26];[self scrollShots:@"onboarding-conversation" app:app count:2];
}

- (void)test00SecondaryVoiceOverDiagnostic {
 XCUIApplication *app=[self home];XCUIVoiceOverService *vo=XCUIDevice.sharedDevice.voiceOverService;
 BOOL initial=vo.isEnabled;NSError *error=nil;
 @try {
  if(!initial)XCTAssertTrue([vo enableAndReturnError:&error]);
  [self text:vo.debugDescription name:@"diagnostic-enabled-before-navigation"];
  [app.buttons[@"Settings"] tap];
  XCUIElement *title=app.staticTexts[@"Settings"];
  if(![title waitForExistenceWithTimeout:3]){[app doubleTap];[title waitForExistenceWithTimeout:3];}
  [self shot:app name:@"diagnostic-settings-enabled-before-navigation"];
  error=nil;XCUIVoiceOverOutput *out=[vo moveForwardAndReturnError:&error];
  [self text:out ? out.utterance : (error.description ?: @"nil") name:@"diagnostic-forward"];
  error=nil;out=[vo moveInAndReturnError:&error];
  [self text:out ? out.utterance : (error.description ?: @"nil") name:@"diagnostic-moveIn"];
  error=nil;out=[vo moveOutAndReturnError:&error];
  [self text:out ? out.utterance : (error.description ?: @"nil") name:@"diagnostic-moveOut"];
  for(int i=0;i<8;i++){
   [app swipeRight];error=nil;out=[vo currentSpeechAndReturnError:&error];
   [self text:out ? out.utterance : (error.description ?: @"nil") name:[NSString stringWithFormat:@"diagnostic-gesture-right-%d",i]];
  }
  [self shot:app name:@"diagnostic-settings-after-right-gestures"];
 } @finally { error=nil;if(!initial)XCTAssertTrue([vo disableAndReturnError:&error]);XCTAssertEqual(vo.isEnabled,initial); }
}

- (BOOL)waitWords:(NSString *)words app:(XCUIApplication *)app {
 XCUIElement *e=[[app descendantsMatchingType:XCUIElementTypeAny] matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS[c] %@",words]].firstMatch;
 BOOL ok=[e waitForExistenceWithTimeout:12];
 if(!ok){[self shot:app name:[[self variant] stringByAppendingFormat:@"-missing-question-%@",words]];XCTFail(@"Question %@ not shown",words);}return ok;
}
- (BOOL)answer:(NSString *)answer confirm:(BOOL)confirm app:(XCUIApplication *)app {
 XCUIElement *field=app.textFields.firstMatch;
 if(![field waitForExistenceWithTimeout:5]){XCTFail(@"No actual answer text field");return NO;}
 [field tap];[field typeText:answer];if(![self tap:@"Send" app:app])return NO;
 if(confirm)return [self tap:@"Yes" app:app];return YES;
}
- (void)test10OnboardingReadbackReveal {
 XCUIApplication *app=[self home];if(![self tap:@"Talk" app:app])return;
 if(![self tap:@"No, I'll type" app:app])return;
 if(![self tap:@"Not now" app:app])return;
 if(![self waitWords:@"Can I remember" app:app])return;
 if(![self answer:@"No thanks" confirm:NO app:app])return;
 if(![self waitWords:@"how old are you" app:app])return;
 if(![self answer:@"71" confirm:NO app:app])return;
 [self capture:@"onboarding-readback" app:app steps:20];
 if(![self tap:@"Yes" app:app])return;
 NSArray *steps=@[
 @[@"female or male",@"female",@YES],@[@"do you smoke now",@"never",@YES],
 @[@"Shall I fill",@"No thanks",@NO],@[@"how tall",@"164 cm",@YES],
 @[@"how much do you weigh",@"65 kg",@YES],@[@"hours do you sleep",@"7 hours",@YES],
 @[@"excellent, very good",@"good",@YES],@[@"high blood pressure",@"no",@YES],
 @[@"diabetes",@"no",@YES],@[@"how many hours",@"6 hours",@YES],
 @[@"lighter activity",@"150 minutes",@YES],@[@"harder exercise",@"none",@YES]];
 for(NSArray *step in steps){if(![self waitWords:step[0] app:app])return;if(![self answer:step[1] confirm:[step[2] boolValue] app:app])return;}
 if(![self tap:@"Continue" app:app])return;
 if(![self tap:@"Ask the ball" app:app])return;
 if(![self waitWords:@"Around" app:app])return;
 [self capture:@"onboarding-reveal" app:app steps:24];[self scrollShots:@"onboarding-reveal" app:app count:4];
}
@end
