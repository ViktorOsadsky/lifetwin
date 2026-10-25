import XCTest

final class Demo133UITests: XCTestCase {
  let app = XCUIApplication(bundleIdentifier: "com.danielqi.lifesim.demo133current")
  @MainActor func button(_ name:String) -> XCUIElement {
    let exact=app.buttons[name].firstMatch
    if exact.exists { return exact }
    return app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",name)).firstMatch
  }
  @MainActor func tapElement(_ b:XCUIElement, name:String, timeout:TimeInterval=15) {
    XCTAssertTrue(b.exists || b.waitForExistence(timeout:timeout),"Missing button \(name)\n\(app.debugDescription)")
    func visible() -> Bool {
      let f=b.frame, v=app.frame.intersection(f)
      return f.width>1 && f.height>1 && !v.isNull && v.width>1 && v.height>1 && app.frame.contains(CGPoint(x:f.midX,y:f.midY))
    }
    for _ in 0..<4 {
      if visible() { break }
      let scroll=app.scrollViews.firstMatch
      if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
    }
    XCTAssertTrue(visible(),"Button has no visible frame: \(name)\n\(app.debugDescription)")
    let f=b.frame
    app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:f.midX-app.frame.minX,dy:f.midY-app.frame.minY)).tap()
  }
  @MainActor func tap(_ name:String, timeout:TimeInterval=15) {
    tapElement(button(name),name:name,timeout:timeout)
  }
  @MainActor func type(_ text:String, confirm:Bool=true) {
    let field=app.textFields.firstMatch
    XCTAssertTrue(field.exists || field.waitForExistence(timeout:15),"No typing field for synthetic answer\n\(app.debugDescription)")
    field.tap();field.typeText(text);tap("Send")
    if confirm { tap("Yes") }
  }
  @MainActor func shot(_ name:String) {
    print("DEMO133_\(name)_TREE_BEGIN\n"+app.debugDescription+"\nDEMO133_\(name)_TREE_END")
    let screen=app.screenshot()
    let a=XCTAttachment(screenshot:screen);a.name=name;a.lifetime = .keepAlways;add(a)
    let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("demo133")
    try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    try? screen.pngRepresentation.write(to:dir.appendingPathComponent(name+".png"))
    try? app.debugDescription.write(to:dir.appendingPathComponent(name+".txt"),atomically:true,encoding:.utf8)
  }
  @MainActor func testInspectActualMain() throws {
    continueAfterFailure=false;app.launch()
    XCTAssertTrue(button("Experiment with your twin").waitForExistence(timeout:60));shot("initial-home")
  }
  @MainActor func testPrepareRealIntake() throws {
    continueAfterFailure=false;app.launch()
    XCTAssertTrue(button("Experiment with your twin").waitForExistence(timeout:60))
    tap("Add band");tap("Find my band");tap("Try a recorded demo",timeout:30)
    shot("prepared-band");tap("Back to room")
    tap("Talk");tap("No, I'll type");Thread.sleep(forTimeInterval:1);tap("Not now")
    shot("memory-choice");type("no",confirm:false)
    let cases=["64","female","never","162.6 cm","66.49 kg","6.9 hours","good","no","no","420 minutes a day","120 minutes a week"]
    for (i,text) in cases.enumerated() {
      type(text)
      if i==2 { type("no",confirm:false) }
      print("DEMO133_SETUP_FIELD_\(i)_DONE")
    }
    app.scrollViews.element(boundBy:0).swipeUp()
    shot("prepared-final-question")
    try runTimedRoute()
  }
  @MainActor func runTimedRoute() throws {
    let start=ProcessInfo.processInfo.systemUptime
    let utc=ISO8601DateFormatter().string(from:Date())
    var metrics=[[String:Any]]()
    var dwells=[[String:Any]]()
    func dwell(_ screen:String,_ seconds:TimeInterval) {
      let a=ProcessInfo.processInfo.systemUptime-start
      Thread.sleep(forTimeInterval:seconds)
      let b=ProcessInfo.processInfo.systemUptime-start
      dwells.append(["screen":screen,"start":a,"end":b,"elapsed":b-a])
      print("DEMO133_DWELL \(screen) \(a) \(b)")
    }
    func beat(_ name:String,_ target:TimeInterval,_ body:() -> Void) {
      let a=ProcessInfo.processInfo.systemUptime-start
      body()
      let actionEnd=ProcessInfo.processInfo.systemUptime-start
      let wait=start+target-ProcessInfo.processInfo.systemUptime
      if wait>0 { Thread.sleep(forTimeInterval:wait) }
      let end=ProcessInfo.processInfo.systemUptime-start
      metrics.append(["beat":name,"start":a,"actions_end":actionEnd,"end":end,"elapsed":end-a])
      print("DEMO133_BEAT \(name) \(a) \(actionEnd) \(end)")
    }
    beat("intake",25) {
      tap("Fill from Apple Health or a document");shot("01-import-choice")
      tap("Not now");type("none",confirm:false)
      XCTAssertTrue(button("Yes").waitForExistence(timeout:10));shot("02-intake-readback")
      Thread.sleep(forTimeInterval:2);tap("Yes")
      XCTAssertTrue(button("Continue").waitForExistence(timeout:10));shot("03-intake-ready")
      tap("Continue")
    }
    beat("reveal",55) {
      tap("Ask the ball");tap("About this estimate",timeout:15)
      shot("04-reveal-caveat");dwell("reveal-caveat",23);tap("Close")
      shot("05-reveal")
    }
    beat("home",72) {
      tap("Back")
      XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Health score plus 0.59")).firstMatch.waitForExistence(timeout:10))
      shot("06-home-score")
    }
    beat("daily-checkin",97) {
      tap("Check in.");type("7 hours",confirm:false);type("0 minutes hard and 20 minutes easy",confirm:false)
      type("420 minutes",confirm:false)
      XCTAssertTrue(button("Looks right").waitForExistence(timeout:10));shot("07-checkin-readback")
      dwell("daily-readback",8);tap("Looks right")
      XCTAssertTrue(button("Back to my room").waitForExistence(timeout:15));shot("08-checkin-saved")
      tap("Back to my room")
    }
    beat("experiment",122) {
      tap("Experiment with your twin");tap("Moderate exercise")
      tap("15 minutes more moderate exercise");shot("09-experiment-step")
      let use=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@ AND label CONTAINS %@","Use ","in my what-if"))
      XCTAssertEqual(use.count,1,"Expected one visible what-if confirmation")
      tapElement(use.firstMatch,name:"Use selected duration in my what-if")
      XCTAssertTrue(button("Ideas for you").waitForExistence(timeout:10));shot("10-experiment-result")
    }
    beat("ideas",148) {
      tap("Ideas for you")
      let idea=app.buttons.matching(NSPredicate(format:"label ENDSWITH %@",". Open details")).firstMatch
      XCTAssertTrue(idea.waitForExistence(timeout:15));shot("11-ideas");dwell("ideas-list",2)
      tapElement(idea,name:"Open first idea details");XCTAssertTrue(button("Back to ideas").waitForExistence(timeout:10));shot("12-idea-detail");dwell("idea-detail",14)
      tap("Back to ideas");tap("Back to Experiment");tap("Back to room")
    }
    beat("band-demo",168) {
      tap("Add band");tap("Week");shot("13-band-demo-week")
      tap("Mochi has a suggestion");shot("14-band-demo-offer")
      tap("Use this");XCTAssertTrue(button("Close").waitForExistence(timeout:10));shot("15-band-demo-readback")
    }
    beat("close",178) {
      tap("Close");tap("Back to room");XCTAssertTrue(button("Experiment with your twin").waitForExistence(timeout:10));shot("16-close-home")
    }
    let total=ProcessInfo.processInfo.systemUptime-start
    let data=try JSONSerialization.data(withJSONObject:["source":"1a648bd","utc_start":utc,"total_seconds":total,"mode":"readability-paced silent native UI rehearsal; template server; no live provider","beats":metrics,"visible_dwells":dwells],options:[.sortedKeys])
    let json=String(data:data,encoding:.utf8)!
    print("DEMO133_TIMING_JSON "+json)
    let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("demo133")
    try? data.write(to:dir.appendingPathComponent("timing.json"))
    let a=XCTAttachment(string:json);a.name="demo133-timing.json";a.lifetime = .keepAlways;add(a)
    XCTAssertLessThanOrEqual(total,180,"Actual continuous UI route exceeded three-minute budget")
  }

}
