import Foundation
import UIKit
import os
import WebKit

public struct NeuroID {
    
    fileprivate static var sequenceId = 1
    fileprivate static var clientKey: String?
    fileprivate static let sessionId: String = ParamsCreator.getSessionID()
    fileprivate static let clientId: String = ParamsCreator.getClientId()
    fileprivate static var userId: String?
    private static let SEND_INTERVAL: Double = 5
    fileprivate static var trackers = [String: NeuroIDTracker]()
    fileprivate static var secrectViews = [UIView]()
    fileprivate static let showDebugLog = false
    
    // InputID, currentVal, newVal
    fileprivate static let localStorageNIDStopAll = "nid_stop_all"

    /// Turn on/off printing the SDK log to your console
    public static var logVisible = true
    

    // MARK: - Setup
    /// 1. Configure the SDK
    /// 2. Setup silent running loop
    /// 3. Send cached events from DB every `SEND_INTERVAL`
    public static func configure(clientKey: String) {
        if NeuroID.clientKey != nil {
            print("NeuroID Error: You already configured the SDK")
        }
        NeuroID.clientKey = clientKey
        
        let key = "nid_key";
        let defaults = UserDefaults.standard
        defaults.set(clientKey, forKey: key)
    }
    
    public static func stop(){
        UserDefaults.standard.set(true, forKey: localStorageNIDStopAll)
    }
    
    public static func setScreenName(screen: String) {
        UserDefaults.standard.set(nil, forKey: "nid_screen")
    }
    
    public static func getScreenName() -> String? {
        let savedScreenName = UserDefaults.standard.string(forKey: "nid_screen")
        return savedScreenName
    }
    
    public static func clearSession(){
        UserDefaults.standard.set(nil, forKey: "nid_sid")
    }
    
    public static func getSessionID() -> String? {
        return UserDefaults.standard.string(forKey: "nid_sid")
    }
    
    // When start is called, enable swizzling, as well as dispatch queue to send to API
    public static func start(){
        clearSession()
        UserDefaults.standard.set(false, forKey: localStorageNIDStopAll)
        swizzle()
        
        if ProcessInfo.processInfo.environment["debugJSON"] == "true" {
            let filemgr = FileManager.default
            let path = filemgr.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("nidJSONPOSTFormat.txt")
            print("DEBUG PATH \(path.absoluteString)");
        }
        
        #if DEBUG
        if NSClassFromString("XCTest") == nil {
            initTimer()
        }
        #else
        initTimer()
        #endif
    }
    
    public static func isStopped() -> Bool{
        let key = UserDefaults.standard.bool(forKey: localStorageNIDStopAll);
        if (key){
            return true
        }
        return false
    }
    
    /**
        Form Submit, Sccuess & Failure
     */
    public static func formSubmit() -> NIDEvent{
        let submitEvent = NIDEvent(type: NIDEventName.applicationSubmit)
        saveEventToLocalDataStore(submitEvent);
        return submitEvent;
    }
    
    public static func formSubmitFailure() -> NIDEvent{
        let submitEvent = NIDEvent(type: NIDEventName.applicationSubmitFailure)
        saveEventToLocalDataStore(submitEvent);
        return submitEvent
    }
    
    public static func formSubmitSuccess() -> NIDEvent{
        let submitEvent = NIDEvent(type: NIDEventName.applicationSubmitSuccess)
        saveEventToLocalDataStore(submitEvent);
        return submitEvent
    }
    
    /**
     Set a custom variable with a key and value.
        - Parameters:
            - key: The string value of the variable key
            - v: The string value of variable
        - Returns: An `NIDEvent` object of type `SET_VARIABLE`
     
     */
    public static func setCustomVariable(key: String, v: String) -> NIDEvent{
        var setCustomVariable = NIDEvent(type: NIDSessionEventName.setVariable, key: key, v: v )
        let myKeys: [String] = trackers.map{String($0.key) }
        // Set the screen to the last active view
        setCustomVariable.url = myKeys.last
        // If we don't have a valid URL, that means this was called before any views were tracked. Use "AppDelegate" as default
        if (setCustomVariable.url == nil || setCustomVariable.url!.isEmpty) {
            setCustomVariable.url = "AppDelegate"
        }
        saveEventToLocalDataStore(setCustomVariable);
        return setCustomVariable
    }
    
    public static func getBaseURL() -> String {
        return "https://api.neuro-id.com"
//      return "http://localhost:9090"
//      return "https://api.usw2-dev1.nidops.net";
    }
    
    static func getClientKeyFromLocalStorage() -> String {
        let keyName = "nid_key";
        let defaults = UserDefaults.standard
        let key = defaults.string(forKey: keyName);
        return key ?? ""
    }
    
    private static func swizzle() {
        UIViewController.startSwizzling()
        UINavigationController.swizzleNavigation()
    }
    private static func initTimer() {
        // Send up the first payload, and then setup a repeating timer
//        self.send()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + SEND_INTERVAL) {
            self.send()
            self.initTimer()
        }
    }
    /**
     Publically exposed just for testing. This should not be any reason to call this directly.
     */
    public static func send() {
        DispatchQueue.global(qos: .utility).async {
            if (!NeuroID.isStopped()) {
                groupAndPOST()
            }
        }
    }
    
    /**
     Publically exposed just for testing. This should not be any reason to call this directly.
     */
    public static func groupAndPOST() {
        if (NeuroID.isStopped()){
            return
        }
        let dataStoreEvents = DataStore.getAllEvents()
        let backupCopy = dataStoreEvents
        // Clean event queue immediately after fetching
        DataStore.removeSentEvents()
        if dataStoreEvents.isEmpty { return }
        // Group by screen, and send to API
//        let groupedEvents = Dictionary(grouping: dataStoreEvents, by: { (element: NIDEvent) in
//            return element.url
//        })
//
        /** Just send all the evnets*/
        let cleanEvents = dataStoreEvents.map { (nidevent) -> NIDEvent in
            var newEvent = nidevent
            newEvent.url = nil
            return newEvent
        }
        
        post(events: cleanEvents , screen: (self.getScreenName() ?? backupCopy[0].url) ?? "unnamed_screen", onSuccess: { _ in
            logInfo(category: "APICall", content: "Sending successfully")
                // send success -> delete
                
            }, onFailure: { error in
                logError(category: "APICall", content: String(describing: error))
//                DataStore.events = backupCopy
            })
        
//        for key in groupedEvents.keys {
//            var oldEvents = groupedEvents[key]
//
//            // Since we are seriazling this object, we need to remove any values we don't want to send in the event object to the API. This is sort of a not pretty hack
//            var newEvents = oldEvents.map { (value: [NIDEvent]) -> [NIDEvent] in
//                let result = value.map { NIDEvent -> NIDEvent in
//                    var newEvent = NIDEvent
//                    newEvent.url = nil
//                    return newEvent
//                }
//                return result
//            }
//            post(events: newEvents ?? [], screen: key ?? "", onSuccess: { _ in
//                logInfo(category: "APICall", content: "Sending successfully")
//                    // send success -> delete
//                }, onFailure: { error in
//                    logError(category: "APICall", content: String(describing: error))
//                })
//        }
        // TODO, add more sophisticated removal of events (in case of failure)
        
    }
    
    /// Direct send to API to create session
    /// Regularly send in loop
    fileprivate static func post(events: [NIDEvent],
                                 screen: String,
                                 onSuccess: @escaping(Any) -> Void,
                                 onFailure: @escaping(Error) -> Void) {
        guard let url = URL(string: NeuroID.getBaseURL() + "/v3/c") else {
            logError(content: "NeuroID base URL found")
            return
        }
        guard let clientKey = clientKey else {
            logError(content: "NeuroID client key not setup")
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(clientKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"
        
        let encoder = JSONEncoder()
        
        var jsonData:Data;
        do {
            jsonData = try encoder.encode(events)
        }catch{
            return
        }
        let jsonEvents:String = String(data: jsonData,
                                       encoding: .utf8) ?? ""
        
        let testEncoding = jsonData.base64EncodedString(options: [])
        let base64Events: String = Data(jsonEvents.utf8).base64EncodedString()
        
        var params = ParamsCreator.getDefaultSessionParams()
        var cleanedEventNoSpaces = base64Events.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        params["events"] = base64Events
        
        params["url"] = screen
        
        // Unwrap all optionals and convert to null if empty
        var unwrappedParams: [String: Any] = [:]
        for (key, value) in params {
           let newValue = value ?? "null"
            unwrappedParams[key] = newValue
        }
        
        let _dataString = unwrappedParams.toKeyValueString();
        let dataString = _dataString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)?.replacingOccurrences(of: "+", with: "%2B") ?? ""

        // If we are set to debugJSON, don't base64 encode the events so we can easily see what is in the payload
        if ProcessInfo.processInfo.environment["debugJSON"] == "true" {
            saveDebugJSON(events: "******************** New POST to NID Collector")
            saveDebugJSON(events: dataString)
            saveDebugJSON(events: jsonEvents)
            saveDebugJSON(events: "******************** END")
        }
        
        
        guard let data = dataString.data(using: .utf8) else { return }
        request.httpBody = data
        
        // Output post data to terminal if debug
        if ProcessInfo.processInfo.environment["debugJSON"] == "true" {
            print("*********** BEGIN **************")
            print(dataString.description)
            print(jsonEvents.description)
            print("*********** END ***************")
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let response = response as? HTTPURLResponse,
                  error == nil else {
                NIDPrintLog("error", error ?? "Unknown error")
//                onFailure(error ?? NSError(message: "Unknown"))
                return
            }

            let responseDict = try? JSONSerialization.jsonObject(with: data, options: .allowFragments)
            NIDPrintLog(responseDict as Any)

            guard (200 ... 299) ~= response.statusCode else {
                NIDPrintLog("statusCode: ", response.statusCode)
                onFailure(error ?? NSError(domain: "unknown", code: response.statusCode, userInfo: nil))
                return
            }

            if response.statusCode >= 200 && response.statusCode < 299 {
                onSuccess("success")
                return
            }

            guard let responseObject = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) else {
                NIDPrintLog("Can't decode")
                return
            }
            onSuccess(responseObject)
        }

        task.resume()
    }

    public static func setUserID(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: "nid_user_id")
        let setUserEvent = NIDEvent(session: NIDSessionEventName.setUserId, uid: userId);
        saveEventToLocalDataStore(setUserEvent)
    }
    public static func logInfo(category: String = "default", content: Any...) {
        osLog(category: category, content: content, type: .info)
    }

    public static func logError(category: String = "default", content: Any...) {
        osLog(category: category, content: content, type: .error)
    }

    public static func logFault(category: String = "default", content: Any...) {
        osLog(category: category, content: content, type: .fault)
    }

    public static func logDebug(category: String = "default", content: Any...) {
        osLog(category: category, content: content, type: .debug)
    }

    public static func logDefault(category: String = "default", content: Any...) {
        osLog(category: category, content: content, type: .default)
    }

    private static func osLog(category: String = "default", content: Any..., type: OSLogType) {
        Log.log(category: category, contents: content, type: .info)
    }

    static func saveEventToLocalDataStore(_ event: NIDEvent) {
            DataStore.insertEvent(screen: event.type, event: event)
    }
    
    /**
     Save the params being sent to POST to collector endpoint to a local file
     */
    private static func saveDebugJSON(events: String){
        let jsonStringNIDEvents = "\(events)".data(using: .utf8)!
        do {

            let filemgr = FileManager.default
            let path = filemgr.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("nidJSONPOSTFormat.txt")
            if !filemgr.fileExists(atPath: (path.path)) {
                filemgr.createFile(atPath: (path.path), contents: jsonStringNIDEvents, attributes: nil)
                
            } else {
                let file = FileHandle(forReadingAtPath: (path.path))
                if let fileUpdater = try? FileHandle(forUpdating: path) {
    
                    // Function which when called will cause all updates to start from end of the file
                    fileUpdater.seekToEndOfFile()

                    // Which lets the caller move editing to any position within the file by supplying an offset
                    fileUpdater.write(",\n".data(using: .utf8)!)
                    fileUpdater.write(jsonStringNIDEvents)
                }
                else {
                    print("Unable to append DEBUG JSON")
                }
            }
        } catch{
            print(String(describing: error))
        }
    }
}

extension NeuroID {
    static func cleanUpForTesting() {
        clientKey = nil
    }
}

// MARK: - NeuroIDTracker
public class NeuroIDTracker: NSObject {
    private var screen: String?
    private var className: String?
    private var createSessionEvent: NIDEvent?
    /// Capture letter count of textfield/textview to detect a paste action
    var textCapturing = [String: String]()
    public init(screen: String, controller: UIViewController?) {
        super.init()
        self.screen = screen
        if (!NeuroID.isStopped()){
            if(getCurrentSession() == nil){
                self.createSessionEvent = createSession(screen: screen)
            }
            subscribe(inScreen: controller)
        }
        className = controller?.className
    }

    public func captureEvent(event: NIDEvent) {
        if (NeuroID.isStopped()){
            return
        }
        NeuroID.logDebug(category: "saveEvent", content: event.toDict())
        let screenName = screen ?? UUID().uuidString
        var newEvent = event
        // Make sure we have a valid url set
        newEvent.url = screenName
        DataStore.insertEvent(screen: screenName, event: newEvent)
        NeuroID.logDebug(category: "saveEvent", content: "save event finish")
    }
    
    func getCurrentSession() -> String? {
        return UserDefaults.standard.string(forKey: "nid_sid")
    }
}

// MARK: - Custom events
public extension NeuroIDTracker {
    func captureEventCheckBoxChange(isChecked: Bool, checkBox: UIView) {
        let tg = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.checkboxChange, view: checkBox, type: "UIView")
        let event = NIDEvent(type: .checkboxChange, tg: tg, v: String(isChecked))
        captureEvent(event: event)
    }

    func captureEventRadioChange(isChecked: Bool, radioButton: UIView) {
        let tg = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.radioChange, view: radioButton, type: "UIView")
        captureEvent(event: NIDEvent(type: .radioChange, tg: tg, v: String(isChecked)))
    }

    func captureEventSubmission(_ params: [String: TargetValue]? = nil) {
        captureEvent(event: NIDEvent(type: .formSubmit, tg: params, view: nil))
        captureEvent(event: NIDEvent(type: .applicationSubmit, tg: params, view: nil))
        captureEvent(event: NIDEvent(type: .pageSubmit, tg: params, view: nil))
    }

    func captureEventSubmissionSuccess(_ params: [String: TargetValue]? = nil) {
        captureEvent(event: NIDEvent(type: .formSubmitSuccess, tg: params, view: nil))
        captureEvent(event: NIDEvent(type: .applicationSubmitSuccess, tg: params, view: nil))
    }

    func captureEventSubmissionFailure(error: Error, params: [String: TargetValue]? = nil) {
        var newParams = params ?? [:]
        newParams["error"] = TargetValue.string(error.localizedDescription)
        captureEvent(event: NIDEvent(type: .formSubmitFailure, tg: newParams, view: nil))
        captureEvent(event: NIDEvent(type: .applicationSubmitFailure, tg: newParams, view: nil))
    }

    func excludeViews(views: UIView...) {
        for v in views {
            NeuroID.secrectViews.append(v)
        }
    }
}

// MARK: - Private functions


extension Bundle {
    static func infoPlistValue(forKey key: String) -> Any? {

        guard let value = Bundle.main.object(forInfoDictionaryKey: key) else {
            os_log("NeuroID Failed to find Plist");
           return nil
        }
        os_log("NeuroID config found");
        return value
    }
}

private extension NeuroIDTracker {
    func subscribe(inScreen controller: UIViewController?) {
        // Early exit if we are stopped
        if (NeuroID.isStopped()){
            return;
        }
        if let views = controller?.view.subviews {
            observeViews(views)
        }
        observeTextInputEvents()
        observeAppEvents()
        observePasteboard()
        observeRotation()
    }

    func observeViews(_ views: [UIView]) {
        for v in views {
            if let sender = v as? UIControl {
                observeTouchEvents(sender)
                observeValueChanged(sender)
            }
            if v.subviews.isEmpty == false {
                observeViews(v.subviews)
                continue
            }
        }
    }

    func createSession(screen: String) -> NIDEvent {
        // Since we are creating a new session, clear any existing session ID
        NeuroID.clearSession()
        // TODO, return session if already exists
        let event = NIDEvent(session: .createSession, f: ParamsCreator.getClientKey(), siteId: nil, sid: ParamsCreator.getSessionID(), lsid: nil, cid: ParamsCreator.getClientId(), did: ParamsCreator.getDeviceId(), iid: ParamsCreator.getIntermediateId(), loc: ParamsCreator.getLocale(), ua: ParamsCreator.getUserAgent(), tzo: ParamsCreator.getTimezone(), lng: ParamsCreator.getLanguage(),p: ParamsCreator.getPlatform(), dnt: false, tch: ParamsCreator.getTouch(), url: screen, ns: ParamsCreator.getCommandQueueNamespace(), jsv: ParamsCreator.getSDKVersion())
        
        captureEvent(event: event)
        return event;
    }
}

// MARK: - Text control events
private extension NeuroIDTracker {


    func observeTextInputEvents() {
        // UITextField
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textBeginEditing),
                                               name: UITextField.textDidBeginEditingNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textChange),
                                               name: UITextField.textDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textEndEditing),
                                               name: UITextField.textDidEndEditingNotification,
                                               object: nil)

        // UITextView
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textBeginEditing),
                                               name: UITextView.textDidBeginEditingNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textChange),
                                               name: UITextView.textDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textEndEditing),
                                               name: UITextView.textDidEndEditingNotification,
                                               object: nil)

    }

    @objc func textBeginEditing(notification: Notification) {
        // Set the current value of the textDictionary
        DispatchQueue.global(qos:.utility).async {
            if let textControl = notification.object as? UITextField {
                UserDefaults.standard.setValue(textControl.text, forKey: textControl.id)
            } else if let textControl = notification.object as? UITextView {
                UserDefaults.standard.setValue(textControl.text, forKey: textControl.id)
            }
        }
        logTextEvent(from: notification, eventType: .focus)
    }

    @objc func textChange(notification: Notification) {
        
        DispatchQueue.global(qos:.utility).async {
            var similarity:Double = 0;
            var percentDiff:Double = 0;
            if let textControl = notification.object as? UITextField {
                let existingTextValue = UserDefaults.standard.value(forKey: textControl.id)
                UserDefaults.standard.setValue(textControl.text, forKey: textControl.id)
                 similarity = self.calcSimilarity(previousValue: existingTextValue as? String ?? "", currentValue: textControl.text ?? "")
                 percentDiff = self.percentageDifference(newNumOrig: textControl.text ?? "", originalNumOrig: existingTextValue as? String ?? "")
            } else if let textControl = notification.object as? UITextView {
                let existingTextValue = UserDefaults.standard.value(forKey: textControl.id)
                UserDefaults.standard.setValue(textControl.text, forKey: textControl.id)
                 similarity = self.calcSimilarity(previousValue: existingTextValue as? String ?? "", currentValue: textControl.text ?? "")
                 percentDiff = self.percentageDifference(newNumOrig: textControl.text ?? "", originalNumOrig: existingTextValue as? String ?? "")
            }
            self.logTextEvent(from: notification, eventType: .input, sm: similarity, pd: percentDiff)
        }
        // count the number of letters in 10ms (for instance) -> consider paste action
    }

    @objc func textEndEditing(notification: Notification) {
        /**
         We want to make sure to erase user defaults on blur for security
         */
        DispatchQueue.global(qos:.utility).async {
            if let textControl = notification.object as? UITextField {
                UserDefaults.standard.setValue("", forKey: textControl.id)
            } else if let textControl = notification.object as? UITextView {
                UserDefaults.standard.setValue("", forKey: textControl.id)
            }
        }
        logTextEvent(from: notification, eventType: .blur)
    }

    /**
     Target values:
        ETN - Input
        ET - human readable tag
     */
    func logTextEvent(from notification: Notification, eventType: NIDEventName, sm: Double = 0, pd: Double = 0) {
        
        if let textControl = notification.object as? UITextField {
            let inputType = "text"
            // isSecureText
            if textControl.textContentType == .password || textControl.isSecureTextEntry { return }
            if #available(iOS 12.0, *) {
                if textControl.textContentType == .newPassword { return }
            }
            
            let lengthValue = "S~C~~\(textControl.text?.count ?? 0)"
            if (eventType == NIDEventName.input) {
                
//                // Keydown
//                let keydownTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.keyDown, view: textControl, type: inputType)
//                var keyDownEvent = NIDEvent(type: NIDEventName.keyDown, tg: keydownTG)
//                keyDownEvent.v = lengthValue
//                captureEvent(event: keyDownEvent)
                
                // Input
                let inputTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.input, view: textControl, type: inputType)
                var inputEvent = NIDEvent(type: NIDEventName.input, tg: inputTG)
                inputEvent.v = lengthValue
                captureEvent(event: inputEvent)
            } else if (eventType == NIDEventName.focus || eventType == NIDEventName.blur) {
                // Focus / Blur
                let focusBlurEvent = NIDEvent(type: eventType, tg: [
                    "tgs": TargetValue.string(textControl.id),
                ])
                captureEvent(event: focusBlurEvent)
                
                // If this is a blur event, that means we have a text change event
                if (eventType == NIDEventName.blur) {
                    // Text Change
                    let textChangeTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.textChange, view: textControl, type: inputType)
                    var textChangeEvent = NIDEvent(type:NIDEventName.textChange, tg: textChangeTG, sm: sm, pd: pd)
                    textChangeEvent.v = lengthValue
                    captureEvent(event:  textChangeEvent)
                }
            }
            
            detectPasting(view: textControl, text: textControl.text ?? "")
        } else if let textControl = notification.object as? UITextView {
            let inputType = "text"
            // isSecureText
            if textControl.textContentType == .password || textControl.isSecureTextEntry { return }
            if #available(iOS 12.0, *) {
                if textControl.textContentType == .newPassword { return }
            }

            let lengthValue = "S~C~~\(textControl.text?.count ?? 0)"
            if (eventType == NIDEventName.input) {
                
                // Keydown
                let keydownTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.keyDown, view: textControl, type: inputType)
                var keyDownEvent = NIDEvent(type: NIDEventName.keyDown, tg: keydownTG)
                keyDownEvent.v = lengthValue
                captureEvent(event: keyDownEvent)
                
                // Text Change
                let textChangeTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.textChange, view: textControl, type: inputType)
                var textChangeEvent = NIDEvent(type:NIDEventName.textChange, tg: textChangeTG, sm: sm, pd: pd)
                textChangeEvent.v = lengthValue
                captureEvent(event:  textChangeEvent)
                
                // Input
                let inputTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.input, view: textControl, type: inputType)
                var inputEvent = NIDEvent(type: NIDEventName.input, tg: inputTG)
                inputEvent.v = lengthValue
                captureEvent(event: inputEvent)
            } else if (eventType == NIDEventName.focus || eventType == NIDEventName.blur) {
                // Focus / Blur
                let focusBlurEvent = NIDEvent(type: eventType, tg: [
                    "tgs": TargetValue.string(textControl.id),
                ])
                captureEvent(event: focusBlurEvent)
                
                // If this is a blur event, that means we have a text change event
                if (eventType == NIDEventName.blur) {
                    // Text Change
                    let textChangeTG = ParamsCreator.getTGParamsForInput(eventName: NIDEventName.textChange, view: textControl, type: inputType)
                    var textChangeEvent = NIDEvent(type:NIDEventName.textChange, tg: textChangeTG, sm: sm, pd: pd)
                    textChangeEvent.v = lengthValue
                    captureEvent(event:  textChangeEvent)
                }
            }
            
            detectPasting(view: textControl, text: textControl.text ?? "")
        } else if let textControl = notification.object as? UISearchBar {
            let tg = ParamsCreator.getTGParamsForInput(eventName: eventType, view: textControl, type: "UISearchBar")
            captureEvent(event: NIDEvent(type: eventType, tg: tg))
            detectPasting(view: textControl, text: textControl.text ?? "")
        }

    }

    func detectPasting(view: UIView, text: String) {
        var id = "\(Unmanaged.passUnretained(view).toOpaque())"
        guard var savedText = textCapturing[id] else {
           return
        }
        let savedCount = savedText.count
        let newCount = text.count
        if newCount > 0 && newCount - savedCount > 2 {
            let tg = ParamsCreator.getTextTgParams(
                view: view,
                extraParams: ["etn": TargetValue.string(NIDEventName.input.rawValue)])
            captureEvent(event: NIDEvent(type: .paste, tg: tg, view: view))
        }
        textCapturing[id] = text
    }
    
    public func calcSimilarity(previousValue: String, currentValue: String) -> Double {
      var longer = previousValue;
      var shorter = currentValue;

      if (previousValue.count < currentValue.count) {
        longer = currentValue;
        shorter = previousValue;
      }
      let longerLength = Double(longer.count);

      if (longerLength == 0) {
        return 1;
      }

        return round(((longerLength - Double(levDis(longer, shorter))) / longerLength) * 100) / 100.0;
    }
    
    func levDis(_ w1: String, _ w2: String) -> Int {
        let empty = [Int](repeating:0, count: w2.count)
        var last = [Int](0...w2.count)

        for (i, char1) in w1.enumerated() {
            var cur = [i + 1] + empty
            for (j, char2) in w2.enumerated() {
                cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }
        return last.last!
    }
    
    public func percentageDifference(newNumOrig: String, originalNumOrig: String) -> Double{
      let originalNum = originalNumOrig.replacingOccurrences(of: " ", with: "")
        let newNum = newNumOrig.replacingOccurrences(of: " ", with: "")
   
        guard var originalNumParsed = Double (originalNum) else {
            return -1
        }
        
        guard var newNumParsed = Double (newNum) else {
            return -1
        }

      if (originalNumParsed <= 0) {
          originalNumParsed = 1;
      }

      if (newNumParsed <= 0) {
          newNumParsed = 1;
      }

        return round(Double((newNumParsed - originalNumParsed) / originalNumParsed) * 100) / 100.0;
    }
    
}

// MARK: - Touch events
private extension NeuroIDTracker {
    func observeTouchEvents(_ sender: UIControl) {
        sender.addTarget(self, action: #selector(controlTouchStart), for: .touchDown)
        sender.addTarget(self, action: #selector(controlTouchEnd), for: .touchUpInside)
        sender.addTarget(self, action: #selector(controlTouchMove), for: .touchUpOutside)
    }

    @objc func controlTouchStart(sender: UIView) {
        touchEvent(sender: sender, eventName: .touchStart)
    }

    @objc func controlTouchEnd(sender: UIView) {
        touchEvent(sender: sender, eventName: .touchEnd)
    }

    @objc func controlTouchMove(sender: UIView) {
        touchEvent(sender: sender, eventName: .touchMove)
    }

    func touchEvent(sender: UIView, eventName: NIDEventName) {
        if NeuroID.secrectViews.contains(sender) { return }
        let tg = ParamsCreator.getTgParams(
            view: sender,
            extraParams: ["sender": TargetValue.string(sender.className)])

        captureEvent(event: NIDEvent(type: eventName, tg: tg, view: nil))
    }
}

// MARK: - value events
private extension NeuroIDTracker {
    func observeValueChanged(_ sender: UIControl) {
        sender.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
    }

    @objc func valueChanged(sender: UIView) {
        var eventName = NIDEventName.change
        let tg: [String: TargetValue] = ParamsCreator.getUiControlTgParams(sender: sender)

        if let _ = sender as? UISwitch {
            eventName = .selectChange
        } else if let _ = sender as? UISegmentedControl {
            eventName = .selectChange
        } else if let _ = sender as? UIStepper {
            eventName = .change
        } else if let _ = sender as? UISlider {
            eventName = .sliderChange
        } else if let _ = sender as? UIDatePicker {
            eventName = .inputChange
        }

        captureEvent(event: NIDEvent(type: eventName, tg: tg, view: nil))
    }
}

// MARK: - App events
private extension NeuroIDTracker {
    private func observeAppEvents() {
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIScene.willDeactivateNotification, object: nil)
            
            NotificationCenter.default.addObserver(self, selector: #selector(appMovedToForeground), name: UIScene.willEnterForegroundNotification, object: nil)
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
            
            NotificationCenter.default.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
    }

    @objc func appMovedToBackground() {
        captureEvent(event: NIDEvent(type: NIDEventName.windowBlur))
    }
   
    @objc func appMovedToForeground() {
        captureEvent(event: NIDEvent(type: NIDEventName.windowFocus))
    }
}

// MARK: - Pasteboard events
private extension NeuroIDTracker {
    func observePasteboard() {
        NotificationCenter.default.addObserver(self, selector: #selector(contentCopied), name: UIPasteboard.changedNotification, object: nil)
    }

    @objc func contentCopied() {
        captureEvent(event: NIDEvent(type: NIDEventName.copy, tg: ParamsCreator.getCopyTgParams(), view: nil))
    }
}

// MARK: - Device events
private extension NeuroIDTracker {
    func observeRotation() {
        NotificationCenter.default.addObserver(self, selector: #selector(deviceRotated), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    @objc func deviceRotated(notification: Notification) {
        let orientation: String
        if UIDevice.current.orientation.isLandscape {
            orientation = "Landscape"
        } else {
            orientation = "Portrait"
        }

        captureEvent(event: NIDEvent(type: NIDEventName.windowOrientationChange, tg: ["orientation": TargetValue.string(orientation)], view: nil))
        captureEvent(event: NIDEvent(type: NIDEventName.deviceOrientation, tg: ["orientation": TargetValue.string(orientation)], view: nil))
    }
}

// MARK: - Properties - temporary public for testing
struct ParamsCreator {
    static func getTgParams(view: UIView, extraParams: [String: TargetValue] = [:]) -> [String: TargetValue] {
        // TODO, figure out if we need to find super class of ETN
        var params: [String: TargetValue] = ["tgs": TargetValue.string(view.id), "etn": TargetValue.string(view.className)]
        for (key, value) in extraParams {
            params[key] = value
        }
        return params
    }
    
    static func getTimeStamp() -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return now
    }

    static func getTextTgParams(view: UIView, extraParams: [String: TargetValue] = [:]) -> [String: TargetValue] {
        var params: [String: TargetValue] = [
            "tgs": TargetValue.string(view.id),
            "etn": TargetValue.string(NIDEventName.textChange.rawValue),
            "kc": TargetValue.int(0)
        ]
        for (key, value) in extraParams {
            params[key] = value
        }
        return params
    }
    
    static func getTGParamsForInput(eventName: NIDEventName, view: UIView, type: String, extraParams: [String: TargetValue] = [:]) -> [String: TargetValue] {
        var params: [String: TargetValue] = [:];
        
        switch eventName {
        case  NIDEventName.input,NIDEventName.focus, NIDEventName.blur, NIDEventName.textChange, NIDEventName.radioChange, NIDEventName.checkboxChange:
            params = [
                "tgs": TargetValue.string(view.id),
                "etn": TargetValue.string(view.id),
                "et": TargetValue.string(type)
            ]
            // TODO
            // After a blur happens, save the state of this field, and on a subsequent blur compute the text change value
        case NIDEventName.keyDown:
            params = [
                "tgs": TargetValue.string(view.id),
            ]
        default:
            print("Invalid type")
        }
        for (key, value) in extraParams {
            params[key] = value
        }
        return params
    }
    static func getUiControlTgParams(sender: UIView) -> [String: TargetValue] {
        var tg: [String: TargetValue] = ["sender": TargetValue.string(sender.className), "tgs": TargetValue.string(sender.id)]

        if let control = sender as? UISwitch {
            tg["oldValue"] = TargetValue.bool(!control.isOn)
            tg["newValue"] = TargetValue.bool(control.isOn)
        } else if let control = sender as? UISegmentedControl {
            tg["value"] = TargetValue.string(control.titleForSegment(at: control.selectedSegmentIndex) ?? "")
            tg["selectedIndex"] = TargetValue.int(control.selectedSegmentIndex)
        } else if let control = sender as? UIStepper {
            tg["value"] = TargetValue.double(control.value)
        } else if let control = sender as? UISlider {
            tg["value"] = TargetValue.double(Double(control.value))
        } else if let control = sender as? UIDatePicker {
            tg["value"] = TargetValue.string("\(control.date)")
        }
        return tg
    }

    static func getCopyTgParams() -> [String: TargetValue] {
        let val = UIPasteboard.general.string ?? ""
        return ["content": TargetValue.string(UIPasteboard.general.string ?? "")]
    }

    static func getOrientationChangeTgParams() -> [String: Any?] {
        let orientation: String
        if UIDevice.current.orientation.isLandscape {
            orientation = "Landscape"
        } else {
            orientation = "Portrait"
        }

        return ["orientation": orientation]
    }

    static func getDefaultSessionParams() -> [String: Any?] {
        let params = [
            "key": NeuroID.clientKey,
            "id": ParamsCreator.createRequestId(),
            "siteId": nil,
            "sid": ParamsCreator.getSessionID(),
            "cid": ParamsCreator.getClientId(),
            "aid": nil,
            "did": ParamsCreator.getDeviceId(),
            "uid": ParamsCreator.getUserID() ?? nil,
            "pid": ParamsCreator.getPageId(),
            "iid": ParamsCreator.getIntermediateId(),
            "jsv": ParamsCreator.getSDKVersion()
        ] as [String: Any?]

        return params
    }

    static func getClientKey() -> String {
        guard let key = NeuroID.clientKey else {
            print("Error: clientKey is not set")
            return ""
        }
        return key
    }

    static func createRequestId() -> String {
        let epoch = 1488084578518
        let now = Date().timeIntervalSince1970 * 1000
        let rawId = (Int(now) - epoch) * 1024  + NeuroID.sequenceId
        NeuroID.sequenceId += 1
        return String(format: "%02X", rawId)
    }

    // Sessions are created under conditions:
    // Launch of application
    // If user idles for > 30 min
    static func getSessionID() -> String {
        let sidName =  "nid_sid"
        let sidExpires = "nid_sid_expires"
        let defaults = UserDefaults.standard
        let sid = defaults.string(forKey: sidName)
        
        // TODO Expire sesions
        if (sid != nil) {
            return sid ?? "";
        }

        var id = ""
        for _ in 0 ..< 16 {
            let digit = Int.random(in: 0..<10)
            id += "\(digit)"
            defaults.set(id, forKey: sidName)
        }
        print("Session ID:", id);
        return id
    }

    /**
     Sessions expire after 30 minutes
     */
    static func isSessionExpired() -> Bool {
        var expireTime = Int64(UserDefaults.standard.integer(forKey: "nid_sid_expires"));
        
        // If 0, that means we need to set expire time
        if (expireTime == 0) {
            expireTime = setSessionExpireTime();
        }
        if (ParamsCreator.getTimeStamp() >= expireTime){
            return true
        }
        return false
        
    }
    
    static func setSessionExpireTime() -> Int64 {
        let thrityMinutes: Int64 =  1800000
        let expiresTime = ParamsCreator.getTimeStamp() + thrityMinutes
        UserDefaults.standard.set(expiresTime, forKey: "nid_sid_expires")
        return expiresTime;
    }

    static func getClientId() -> String {
        let clientIdName = "nid_cid";
        var cid = UserDefaults.standard.string(forKey: clientIdName);
        
        if (cid != nil){
            return cid!;
        } else {
            cid = genId()
            UserDefaults.standard.set(cid, forKey: clientIdName)
            return cid!
        }
    }
    
    
    static func getUserID() -> String? {
        let nidUserID = "nid_user_id";
        return UserDefaults.standard.string(forKey: nidUserID);
    }
    
    static func getDeviceId() -> String {
        let deviceIdCacheKey = "nid_did";
        var did = UserDefaults.standard.string(forKey: deviceIdCacheKey);
        
        if (did != nil){
            return did!;
        } else {
            did = self.genId()
            UserDefaults.standard.set(did, forKey: deviceIdCacheKey)
            return did!
        }
    }
    
    static func getIntermediateId() -> String {
        let intermediateIdCacheKey = "nid_iid";
        var iid = UserDefaults.standard.string(forKey: intermediateIdCacheKey);
        
        if (iid != nil){
            return iid!;
        } else {
            iid = self.genId()
            UserDefaults.standard.set(iid, forKey: intermediateIdCacheKey)
            return iid!
        }
    }
    
    private static func genId() -> String {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int(Double.random(in: 0..<1) * Double(Int32.max))
        return "\(now).\(random)";
    }
    
    static func getDnt() -> Bool {
        let dntName = "nid_dnt";
        let defaults = UserDefaults.standard
        let dnt = defaults.string(forKey: dntName);
        // If there is ANYTHING set in nid_dnt, we return true (meaning don't track)
        if (dnt != nil)
        {
            return true
        } else {
            return false
        }
    }
    
    // Obviously, being a phone we always support touch
    static func getTouch() -> Bool {
        return true
    }
    
    static func getPlatform() -> String {
        return "Apple"
    }

    static func getLocale() -> String {
        return Locale.current.identifier
    }

    static func getUserAgent() -> String {
        return "iOS " + UIDevice.current.systemVersion
    }

    // Minutes from GMT
    static func getTimezone() -> Int {
        let timezone = TimeZone.current.secondsFromGMT() / 60
        return timezone
    }

    static func getLanguage() -> String {
        let locale = Locale.current.languageCode
        return locale ?? Locale.current.identifier
    }

    /** Start with primar JS version as TrackJS requires to force correct session structure*/
    static func getSDKVersion() -> String {
        return "4.-ios-1.0.0"
    }
    
    static func getCommandQueueNamespace() -> String {
        return "nid";
    }

    static func getPageId() -> String {
        let x = 1
        let now = Date().timeIntervalSince1970 * 1000
        let rawId = (Int(now) - 1488084578518) * 1024 + (x + 1)
        return String(format: "%02X", rawId)
    }
}

extension UIView {
    var className: String {
        return String(describing: type(of: self))
    }
}

extension UIViewController {
    var className: String {
        return String(describing: type(of: self))
    }
}

/***
    Anytime a view loads
    Check child subviews for eligible form events
    Form all eligible form events, check to see if they have a valid identifier and set one
    Register form events
*/

extension UIView {

    func subviewsRecursive() -> [Any] {
        return subviews + subviews.flatMap { $0.subviewsRecursive() }
    }

}

private func registerSingleView(v: Any, screenName: String){
    switch v {
    case is UITextField:
        let tfView = v as! UITextField
        NeuroID.saveEventToLocalDataStore(NIDEvent(eventName: NIDEventName.registerTarget, tgs: tfView.id, en: tfView.id, etn: "INPUT", et: tfView.className, v: "S~C~~\(tfView.placeholder?.count ?? 0)" , url: screenName))
    case is UITextView:
        let tv = v as! UITextView
        NeuroID.saveEventToLocalDataStore(NIDEvent(eventName: NIDEventName.registerTarget, tgs: tv.id, en: tv.id, etn: "INPUT", et: tv.className, v: "S~C~~\(tv.text?.count ?? 0)" , url: screenName))
    case is UIButton:
        let tb = v as! UIButton
        NeuroID.saveEventToLocalDataStore(NIDEvent(eventName: NIDEventName.registerTarget, tgs: tb.id, en: tb.id, etn: "BUTTON", et: tb.className, v: "S~C~~0" , url: screenName))
    case is UISlider:
        print("Slider")
    case is UISwitch:
        print("Switch")
    case is UITableViewCell:
        print("Table view cell")
        break
    case is UIPickerView:
        let pv = v as! UIPickerView
        print("Picker")
    case is UIDatePicker:
        print("Date picker")
    default:
        return
//        print("Unknown type", v)
    }
        // Text
        // Inputs
        // Checkbox/Radios inputs
}

private func registerSubViewsTargets(subViewControllers: [UIViewController]){
    for ctrls in subViewControllers {
        let screenName = ctrls.className
        print(ctrls.neuroScreenName)
        guard let view = ctrls.view else {
            return
        }
        registerSingleView(v: view, screenName: screenName)
        let childViews = ctrls.view.subviewsRecursive()
        for _view in childViews {
            registerSingleView(v: _view, screenName: screenName)
        }
    }
}

private func swizzling(viewController: UIViewController.Type,
                       originalSelector: Selector,
                       swizzledSelector: Selector) {

    let originalMethod = class_getInstanceMethod(viewController, originalSelector)
    let swizzledMethod = class_getInstanceMethod(viewController, swizzledSelector)

    if let originalMethod = originalMethod,
       let swizzledMethod = swizzledMethod {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

// MARK: - Swizzling
extension UIViewController {
    private var ignoreLists: [String] {
        return [
            "UICompatibilityInputViewController",
            "UISystemKeyboardDockController",
            "UIInputWindowController",
            "UIPredictionViewController",
            "UIEditingOverlayViewController",
            "UISystemInputAssistantViewController"
        ]
    }

    @objc var neuroScreenName: String {
        return className
    }
    public var tracker: NeuroIDTracker? {
        if ignoreLists.contains(className) { return nil }
        if self is UINavigationController && className == "UINavigationController" { return nil }
        let tracker = NeuroID.trackers[className] ?? NeuroIDTracker(screen: neuroScreenName, controller: self)
        NeuroID.trackers[className] = tracker
        return tracker
    }

    public func captureEvent(event: NIDEvent) {
        if ignoreLists.contains(className) { return }
        var tg: [String: TargetValue] = event.tg ?? [:]
        tg["className"] = TargetValue.string(className)
        tg["title"] = TargetValue.string(title ?? "")
        
        // TODO Implement UIAlertController
//        if let vc = self as? UIAlertController {
//            tg["message"] = TargetValue.string(vc.message ?? "")
//            tg["actions"] = TargetValue.string(vc.actions.compactMap { $0.title }
//        }
//
//        if let eventName = NIDEventName(rawValue: event.type) {
//            let newEvent = NIDEvent(type: eventName, tg: tg, x: event.x, y: event.y)
//            tracker?.captureEvent(event: newEvent)
//        } else {
//            let newEvent = NIDEvent(customEvent: event.type, tg: tg, x: event.x, y: event.y)
            tracker?.captureEvent(event: event)
//        }
    }

    public func captureEvent(eventName: NIDEventName, params: [String: TargetValue]? = nil) {
        let event:NIDEvent;
        if (params.isEmptyOrNil) {
            event = NIDEvent(type: eventName, screenName: neuroScreenName)
        } else {
            event = NIDEvent(type: eventName, tg: params, view: self.view)
        }
        captureEvent(event: event)
    }

//    public func captureEventLogViewWillAppear(params: [String: TargetValue]) {
//        captureEvent(eventName: .windowFocus, params: params)
//    }
//
//    public func captureEventLogViewDidLoad(params: [String: TargetValue]) {
//        captureEvent(eventName: .windowLoad, params: params)
//    }
//
//    public func captureEventLogViewWillDisappear(params: [String: TargetValue]) {
//        captureEvent(eventName: .windowBlur, params: params)
//    }
}

private extension UIViewController {
    @objc static func startSwizzling() {
        let screen = UIViewController.self
    
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.viewWillAppear),
                  swizzledSelector: #selector(screen.neuroIDViewWillAppear))
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.viewWillDisappear),
                  swizzledSelector: #selector(screen.neuroIDViewWillDisappear))
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.viewDidLoad),
                  swizzledSelector: #selector(screen.neuroIDViewDidLoad))
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.dismiss),
                  swizzledSelector: #selector(screen.neuroIDDismiss))
    }

    @objc func neuroIDViewWillAppear(animated: Bool) {
        self.neuroIDViewWillAppear(animated: animated)
        captureEvent(eventName: .windowFocus)
        
        if (NeuroID.isStopped() || UIApplication.shared.applicationState == .background ){
            return
        }
        self.neuroIDViewDidLoad()
        captureEvent(eventName: .windowLoad)
        var subViews = self.view.subviews
        var allViewControllers = self.children
        allViewControllers.append(self)
        registerSubViewsTargets(subViewControllers: allViewControllers)
        
    }

    @objc func neuroIDViewWillDisappear(animated: Bool) {
        self.neuroIDViewWillDisappear(animated: animated)
        captureEvent(eventName: .windowBlur)
    }

    /**
        When overriding viewDidLoad in  controllers make sure that super is the last thing called in the function (so that we can accurately detect all added views/subviews)
    
          Anytime a view loads
          Check child subviews for eligible form events
          Form all eligible form events, check to see if they have a valid identifier and set one
          Register form events
     */
    @objc func neuroIDViewDidLoad() {
        if (NeuroID.isStopped() || UIApplication.shared.applicationState == .background ){
            return
        }
        self.neuroIDViewDidLoad()
//        captureEvent(eventName: .windowLoad)
//        var subViews = self.view.subviews
//        var allViewControllers = self.children
//        allViewControllers.append(self)
//        registerSubViewsTargets(subViewControllers: allViewControllers)
    }

    @objc func neuroIDDismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        self.neuroIDDismiss(animated: flag, completion: completion)
        captureEvent(eventName: .windowUnload)
    }
}

extension UINavigationController {
    fileprivate static func swizzleNavigation() {
        let screen = UINavigationController.self
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.popViewController(animated:)),
                  swizzledSelector: #selector(screen.neuroIDPopViewController(animated:)))
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.popToViewController(_:animated:)),
                  swizzledSelector: #selector(screen.neuroIDPopToViewController(_:animated:)))
        swizzling(viewController: screen,
                  originalSelector: #selector(screen.popToRootViewController),
                  swizzledSelector: #selector(screen.neuroIDPopToRootViewController))
    }

    @objc fileprivate func neuroIDPopViewController(animated: Bool) -> UIViewController? {
        captureEvent(eventName: .windowUnload)
        return self.neuroIDPopViewController(animated: animated)
    }

    @objc fileprivate func neuroIDPopToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        captureEvent(eventName: .windowUnload)
        return self.neuroIDPopToViewController(viewController, animated: animated)
    }

    @objc fileprivate func neuroIDPopToRootViewController(animated: Bool) -> [UIViewController]? {
        captureEvent(eventName: .windowUnload)
        return self.neuroIDPopToRootViewController(animated: animated)
    }
}

//extension NSError {
//    convenience init(message: String) {
//        self.init(domain: message, code: 0, userInfo: nil)
//    }
//
//    fileprivate static func errorSwizzling(_ obj: NSError.Type,
//                                           originalSelector: Selector,
//                                           swizzledSelector: Selector) {
//        let originalMethod = class_getInstanceMethod(obj, originalSelector)
//        let swizzledMethod = class_getInstanceMethod(obj, swizzledSelector)
//
//        if let originalMethod = originalMethod,
//           let swizzledMethod = swizzledMethod {
//            method_exchangeImplementations(originalMethod, swizzledMethod)
//        }
//    }
//
//    fileprivate static func startSwizzling() {
//        let obj = NSError.self
//        errorSwizzling(obj,
//                       originalSelector: #selector(obj.init(domain:code:userInfo:)),
//                       swizzledSelector: #selector(obj.neuroIDInit(domain:code:userInfo:)))
//    }
//
//    @objc fileprivate func neuroIDInit(domain: String, code: Int, userInfo dict: [String: Any]? = nil) {
//        let tg: [String: Any?] = [
//            "domain": domain,
//            "code": code,
//            "userInfo": userInfo
//        ]
//        NeuroID.captureEvent(NIDEvent(type: .error, tg: tg, view: nil))
//        self.neuroIDInit(domain: domain, code: code, userInfo: userInfo)
//    }
//}

extension String {
    func decodeBase64() -> [String: Any]? {
        guard let decodedData = Data(base64Encoded: self) else { return nil }

        do {
            let dict = try JSONSerialization.jsonObject(with: decodedData, options: .allowFragments)
            return dict as? [String: Any]
        } catch {
            return nil
        }

    }
}

//extension Collection where Iterator.Element == [String: Any?] {
//    func toJSONString() -> String {
//    if let arr = self as? [[String: Any]],
//       let dat = try? JSONSerialization.data(withJSONObject: arr),
//       let str = String(data: dat, encoding: String.Encoding.utf8) {
//      return str
//    }
//    return "[]"
//  }
//}
/** Base 64 Encode/Decoding
 */
extension StringProtocol {
    var data: Data { Data(utf8) }
    var base64Encoded: Data { data.base64EncodedData() }
    var base64Decoded: Data? { Data(base64Encoded: string) }
}
extension LosslessStringConvertible {
    var string: String { .init(self) }
}
extension Sequence where Element == UInt8 {
    var data: Data { .init(self) }
    var base64Decoded: Data? { Data(base64Encoded: data) }
    var string: String? { String(bytes: self, encoding: .utf8) }
}
/** End base64 block*/

func NIDPrintLog(_ strings: Any...) {
    if NeuroID.logVisible {
        Swift.print(strings)
    }
}

private struct Log {
    @available(iOS 10.0, *)
    static func log(category: String, contents: Any..., type: OSLogType) {
        #if DEBUG
        if NeuroID.showDebugLog {
            let message = contents.map { "\($0)"}.joined(separator: " ")
            os_log("NeuroID: %@", message)
        }
        #endif
    }
}

extension Double {
    func truncate(places : Int)-> Double {
        return Double(floor(pow(10.0, Double(places)) * self)/pow(10.0, Double(places)))
    }
}

public extension UIView {
    var id: String {
        get {
            // TODO insert generated ID
            return (accessibilityIdentifier.isEmptyOrNil) ? ("todo-id") : (accessibilityIdentifier!)
        }
        set {
            accessibilityIdentifier = newValue
        }
    }
}


extension Dictionary {
  func toKeyValueString() -> String {
    return map { key, value in
      let escapedKey = "\(key)" ?? ""
      let escapedValue = "\(value)" ?? ""
      return escapedKey + "=" + escapedValue
    }
    .joined(separator: "&")
  }
}

extension CharacterSet {
  static let urlQueryValueAllowed: CharacterSet = {
    let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
    let subDelimitersToEncode = "!$&'()*+,;="

    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
    return allowed
  }()
}

extension Optional where Wrapped: Collection {
  var isEmptyOrNil: Bool {
    guard let value = self else { return true }
    return value.isEmpty
  }
}

