//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//
//

import Foundation
import AudioToolbox
import WebKit
import UserNotifications

let TAG = "GeofencePlugin"
let iOS8 = floor(NSFoundationVersionNumber) > floor(NSFoundationVersionNumber_iOS_7_1)

func log(_ message: String){
    NSLog("%@ - %@", TAG, message)
}

func log(_ messages: [String]) {
    for message in messages {
        log(message);
    }
}

@available(iOS 8.0, *)
@objc(HWPGeofencePlugin) class GeofencePlugin : CDVPlugin {
    lazy var geoNotificationManager = GeoNotificationManager()
    let priority = DispatchQoS.QoSClass.default
    
    override func pluginInitialize () {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveLocalNotification(_:)),
            name: NSNotification.Name(rawValue: "CDVLocalNotification"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveTransition(_:)),
            name: NSNotification.Name(rawValue: "handleTransition"),
            object: nil
        )
        geoNotificationManager = GeoNotificationManager()
    }
    
    @objc func initialize(_ command: CDVInvokedUrlCommand) {
        log("Plugin initialization")
        // let faker = GeofenceFaker(manager: geoNotificationManager)
        // faker.start()
        
        if iOS8 {
            promptForNotificationPermission()
            geoNotificationManager.registerPermissions()
        }
        geoNotificationManager.isActive = true
        geoNotificationManager.startUpdatingLocation()

        let (ok, warnings, errors) = geoNotificationManager.checkRequirements()
        
        log(warnings)
        log(errors)
        
        let result: CDVPluginResult
        
        if ok {
            result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: warnings.joined(separator: "\n"))
        } else {
            result = CDVPluginResult(
                status: CDVCommandStatus_ILLEGAL_ACCESS_EXCEPTION,
                messageAs: (errors + warnings).joined(separator: "\n")
            )
        }
        
        commandDelegate!.send(result, callbackId: command.callbackId)
    }
    
    @objc func deviceReady(_ command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc func ping(_ command: CDVInvokedUrlCommand) {
        log("Ping")
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc func promptForNotificationPermission() {
        UIApplication.shared.registerUserNotificationSettings(UIUserNotificationSettings(
            types: [UIUserNotificationType.sound, UIUserNotificationType.alert, UIUserNotificationType.badge],
            categories: nil
            )
        )
    }
    
    @objc func addOrUpdate(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: priority).async {
            for geo in command.arguments {
                self.geoNotificationManager.addOrUpdateGeoNotification(JSON(geo))
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func getWatched(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: priority).async {
            let watched = self.geoNotificationManager.getWatchedGeoNotifications()!
            let watchedJsonString = watched.description
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: watchedJsonString)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func remove(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: priority).async {
            for id in command.arguments {
                self.geoNotificationManager.removeGeoNotification(id as! String)
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func removeAll(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: priority).async {
            self.geoNotificationManager.removeAllGeoNotifications()
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func snooze(_ command: CDVInvokedUrlCommand) {
        log("snooze")
        DispatchQueue.global(qos: priority).async {
            if let id = command.arguments[0] as? Int,
                let duration = command.arguments[1] as? Int {
                self.geoNotificationManager.snoozeFence(String(id), duration: Double(duration))
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func dismissNotifications(_ command: CDVInvokedUrlCommand) {
        log("dismissNotifications")
        DispatchQueue.global(qos: priority).async {
            if let ids = command.arguments as? [Int] {
                self.geoNotificationManager.dismissNotifications(ids.map { String($0) })
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func didReceiveTransition (_ notification: Notification) {
        log("didReceiveTransition")
        if let geoNotificationString = notification.object as? String {
            let js = "setTimeout('geofence.onTransitionReceived([" + geoNotificationString.replacingOccurrences(of: "'", with: "\\'") + "])',0)"
            
            evaluateJs(js)
        }
    }
    
    @objc func didReceiveLocalNotification (_ notification: Notification) {
        log("didReceiveLocalNotification")
        var data = "undefined"
        if let uiNotification = notification.object as? UILocalNotification,
            let notificationData = uiNotification.userInfo?["geofence.notification.data"] as? String {
            data = notificationData
        } else if let geoNotificationString = notification.object as? String {
            data = geoNotificationString
        }
        
        let js = "setTimeout('geofence.onNotificationClicked(" + data.replacingOccurrences(of: "'", with: "\\'") + ")',0)"
        
        evaluateJs(js)
    }
    
    func evaluateJs (_ script: String) {
        if let webView = webView {
            //if let uiWebView = webView as? UIWebView {
            //    uiWebView.stringByEvaluatingJavaScript(from: script)
            //} else if let wkWebView = webView as? WKWebView {
			if let wkWebView = webView as? WKWebView {
                wkWebView.evaluateJavaScript(script, completionHandler: nil)
            }
        } else {
            log("webView is nil")
        }
    }
    
    override func onAppTerminate() {
        log("onAppTerminate")
        geoNotificationManager.isActive = false
        super.onAppTerminate()
    }
}

// class for faking crossing geofences
@available(iOS 8.0, *)
class GeofenceFaker {
    let priority = DispatchQoS.QoSClass.default
    let geoNotificationManager: GeoNotificationManager
    
    init(manager: GeoNotificationManager) {
        geoNotificationManager = manager
    }
    
    func start() {
        DispatchQueue.global(qos: priority).async {
            while (true) {
                log("FAKER")
                let notify = arc4random_uniform(4)
                if notify == 0 {
                    log("FAKER notify chosen, need to pick up some region")
                    var geos = self.geoNotificationManager.getWatchedGeoNotifications()!
                    if geos.count > 0 {
                        //WTF Swift??
                        let index = arc4random_uniform(UInt32(geos.count))
                        let geo = geos[Int(index)]
                        let id = geo["id"].stringValue
                        DispatchQueue.main.async {
                            if let region = self.geoNotificationManager.getMonitoredRegion(id) {
                                log("FAKER Trigger didEnterRegion")
                                self.geoNotificationManager.locationManager(
                                    self.geoNotificationManager.locationManager,
                                    didEnterRegion: region
                                )
                            }
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 3)
            }
        }
    }
    
    func stop() {
        
    }
}

@available(iOS 8.0, *)
class GeoNotificationManager : NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    let locationManager = CLLocationManager()
    let store = GeoNotificationStore()
    var snoozedFences = [String : Double]()
    var isActive = false
    
    override init() {
        log("GeoNotificationManager init")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        
        if iOS8 {
            locationManager.requestAlwaysAuthorization()
        }
        
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }
    }
    
    func registerPermissions() {
        locationManager.requestAlwaysAuthorization()
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func addOrUpdateGeoNotification(_ geoNotification: JSON) {
        var geoNotification = geoNotification
        log("GeoNotificationManager addOrUpdate")
        
        let (_, warnings, errors) = checkRequirements()
        
        log(warnings)
        log(errors)
        
        let location = CLLocationCoordinate2DMake(
            geoNotification["latitude"].doubleValue,
            geoNotification["longitude"].doubleValue
        )
        log("AddOrUpdate geo: \(geoNotification)")
        let radius = geoNotification["radius"].doubleValue as CLLocationDistance
        let id = geoNotification["id"].stringValue
        
        let region = CLCircularRegion(center: location, radius: radius, identifier: id)
        
        var transitionType = 0
        if let i = geoNotification["transitionType"].int {
            transitionType = i
        }
        region.notifyOnEntry = 0 != transitionType & 1
        region.notifyOnExit = 0 != transitionType & 2

        geoNotification["isInside"] = false
        //store
        store.addOrUpdate(geoNotification)
        locationManager.startMonitoring(for: region)
    }
    
    func checkRequirements() -> (Bool, [String], [String]) {
        var errors = [String]()
        var warnings = [String]()
        
        if (!CLLocationManager.isMonitoringAvailable(for: CLRegion.self)) {
            errors.append("Geofencing not available")
        }
        
        if (!CLLocationManager.locationServicesEnabled()) {
            errors.append("Error: Locationservices not enabled")
        }
        
        let authStatus = CLLocationManager.authorizationStatus()

        if authStatus != .authorizedAlways {
            if authStatus != .authorizedWhenInUse {
                errors.append("Error: Location when in use permissions not granted")
            } else {
                warnings.append("Warning: Location always permissions not granted")
            }
        }
        
        if iOS8 {
            if let notificationSettings = UIApplication.shared.currentUserNotificationSettings {
                if notificationSettings.types == UIUserNotificationType() {
                    errors.append("Error: notification permission missing")
                } else {
                    if !notificationSettings.types.contains(.sound) {
                        warnings.append("Warning: notification settings - sound permission missing")
                    }
                    if !notificationSettings.types.contains(.alert) {
                        warnings.append("Warning: notification settings - alert permission missing")
                    }
                    if !notificationSettings.types.contains(.badge) {
                        warnings.append("Warning: notification settings - badge permission missing")
                    }
                }
            } else {
                errors.append("Error: notification permission missing")
            }
        }
        let ok = (errors.count == 0)
        return (ok, warnings, errors)
    }
    
    func getWatchedGeoNotifications() -> [JSON]? {
        return store.getAll()
    }
    
    func getMonitoredRegion(_ id: String) -> CLRegion? {
        for object in locationManager.monitoredRegions {
            let region = object
            
            if (region.identifier == id) {
                return region
            }
        }
        return nil
    }
    
    func removeGeoNotification(_ id: String) {
        store.remove(id)
        let region = getMonitoredRegion(id)
        if (region != nil) {
            log("Stoping monitoring region \(id)")
            locationManager.stopMonitoring(for: region!)
        }
        //resetting snoozed fence
        snoozeFence(id, duration: 0)
    }
    
    func removeAllGeoNotifications() {
        store.clear()
        for object in locationManager.monitoredRegions {
            let region = object
            log("Stoping monitoring region \(region.identifier)")
            locationManager.stopMonitoring(for: region)
        }
    }
    
    func handleTransition(_ id: String, transitionType: Int) {
        if var geoNotification = store.findById(id),
            !isSnoozed(id),
            isWithinTimeRange(geoNotification) {
            geoNotification["transitionType"].int = transitionType
            
            if geoNotification["notification"].isExists() && canBeTriggered(geoNotification) {
                notifyAbout(geoNotification)
            }
            
            if geoNotification["url"].isExists() {
                log("Should post to " + geoNotification["url"].stringValue)
                let url = URL(string: geoNotification["url"].stringValue)!
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                //formatter.locale = Locale(identifier: "en_US")
                
                let jsonDict = ["geofenceId": geoNotification["id"].stringValue, "transition": geoNotification["transitionType"].intValue == 1 ? "ENTER" : "EXIT", "date": dateFormatter.string(from: Date())]
                let jsonData = try! JSONSerialization.data(withJSONObject: jsonDict, options: [])
                
                var request = URLRequest(url: url)
                request.httpMethod = "post"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(geoNotification["authorization"].stringValue, forHTTPHeaderField: "Authorization")
                request.httpBody = jsonData
                
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
                        print("error:", error)
                        return
                    }
                    
                    do {
                        guard let data = data else { return }
                        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else { return }
                        print("json:", json)
                    } catch {
                        print("error:", error)
                    }
                }
                
                task.resume()
            }
            
            NotificationCenter.default.post(name: Notification.Name(rawValue: "handleTransition"), object: geoNotification.rawString(String.Encoding.utf8.rawValue, options: []))
        }
    }
    
    func canBeTriggered(_ geo: JSON) -> Bool {
        let store = GeoNotificationStore()
        if(geo["notification"]["lastTriggered"].isExists() && geo["notification"]["frequency"].isExists()) {
            if(Int(NSDate().timeIntervalSince1970) < geo["notification"]["lastTriggered"].int! + geo["notification"]["frequency"].int!) {
                log("Frequency control. Skip notification")
                return false
            }
        }
        store.updateLastTriggeredByNotificationId(geo["notification"]["id"].stringValue)
        return true
    }
    
    func isWithinTimeRange(_ geoNotification: JSON) -> Bool {
        let now = Date()
        var greaterThanOrEqualToStartTime: Bool = true
        var lessThanEndTime: Bool = true
        if geoNotification["startTime"].isExists() {
            if let startTime = parseDate(dateStr: geoNotification["startTime"].stringValue) {
                greaterThanOrEqualToStartTime = (now.compare(startTime) == ComparisonResult.orderedDescending || now.compare(startTime) == ComparisonResult.orderedSame)
            }
        }
        if geoNotification["endTime"].isExists() {
            if let endTime = parseDate(dateStr: geoNotification["endTime"].stringValue) {
                lessThanEndTime = now.compare(endTime) == ComparisonResult.orderedAscending
            }
        }
        return greaterThanOrEqualToStartTime && lessThanEndTime
    }
    
    func parseDate(dateStr: String?) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter.date(from: dateStr!)
    }
    
    func notifyAbout(_ geo: JSON) {
        if #available(iOS 10.0, *) {
            log("Creating notification iOS > 10")
            let content = UNMutableNotificationContent()
            if let title = geo["notification"]["title"] as JSON? {
                content.title = title.stringValue
            }
            if let text = geo["notification"]["text"] as JSON? {
                content.body = text.stringValue
            }
            content.sound = UNNotificationSound.default()
            if let json = geo["notification"]["data"] as JSON? {
                content.userInfo = ["geofence.notification.data": json.rawString(String.Encoding.utf8.rawValue, options: [])!]
            }
            let identifier = geo["notification"]["id"].stringValue
            let request = UNNotificationRequest(identifier: identifier,
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: { (error) in
                if error != nil {
                    log("Couldn't create notification")
                }
            })
        } else {
            log("Creating notification iOS < 10")
            let notification = UILocalNotification()
            notification.timeZone = TimeZone.current
            let dateTime = Date()
            notification.fireDate = dateTime
            notification.soundName = UILocalNotificationDefaultSoundName
            if let title = geo["notification"]["title"] as JSON? {
                notification.alertTitle = title.stringValue
            }
            if let text = geo["notification"]["text"] as JSON? {
                notification.alertBody = text.stringValue
            }
            if let json = geo["notification"]["data"] as JSON? {
                notification.userInfo = ["geofence.notification.data": json.rawString(String.Encoding.utf8.rawValue, options: [])!]
            }
            UIApplication.shared.scheduleLocalNotification(notification)
            if let vibrate = geo["notification"]["vibrate"].array {
                if (!vibrate.isEmpty && vibrate[0].intValue > 0) {
                    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                }
            }
        }
    }
    
    func dismissNotifications(_ ids: [String]) {
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
    
    func snoozeFence(_ id: String, duration: Double) {
        snoozedFences[id] = NSTimeIntervalSince1970 + duration
    }
    
    func isSnoozed(_ id: String?) -> Bool {
        guard let id = id, let fenceTime = snoozedFences[id] else {
            return false
        }
        return fenceTime > NSTimeIntervalSince1970
    }
    
    func checkTransition(_ location: CLLocation) {
        if let allStored = store.getAll() {
            for var json in allStored {
                let radius = json["radius"].doubleValue as CLLocationDistance
                let coord = CLLocation(latitude: json["latitude"].doubleValue, longitude: json["longitude"].doubleValue)
                
                if location.distance(from: coord) <= radius {
                    if !json["isInside"].boolValue {
                        if json["transitionType"].intValue == 1 {
                            handleTransition(json["id"].stringValue, transitionType: 1)
                        }
                        json["isInside"] = true
                        store.addOrUpdate(json)
                    }
                } else {
                    if json["isInside"].boolValue {
                        if json["transitionType"].intValue == 2 {
                            handleTransition(json["id"].stringValue, transitionType: 2)
                        }
                        json["isInside"] = false
                        store.addOrUpdate(json)
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        log("update location \(locations[0])")
        if isActive {
            checkTransition(locations[0])
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("fail with error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        log("deferred fail error: \(String(describing: error))")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log("Entering region \(region.identifier)")
        if !isActive {
            handleTransition(region.identifier, transitionType: 1)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log("Exiting region \(region.identifier)")
        if !isActive {
            handleTransition(region.identifier, transitionType: 2)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        if region is CLCircularRegion {
            let lat = (region as! CLCircularRegion).center.latitude
            let lng = (region as! CLCircularRegion).center.longitude
            let radius = (region as! CLCircularRegion).radius
            
            log("Starting monitoring for region \(region) lat \(lat) lng \(lng) of radius \(radius)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        log("State for region " + region.identifier)
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        log("Monitoring region " + region!.identifier + " failed \(error)" )
    }
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.userInfo["geofence.notification.data"] != nil {
            // Play sound and show alert to the user if it is a geofence notification
            completionHandler([.alert,.sound])
        } else if (notification.request.content.userInfo["foreground"] != nil) {
            // Play sound and show alert to the user if the notification has foreground property
            completionHandler([.alert,.sound])
        } else {
            completionHandler([])
        }
    }
    
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Determine the user action
        log(response.actionIdentifier)
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            log("Dismiss Action")
        case UNNotificationDefaultActionIdentifier:
            if let data = response.notification.request.content.userInfo["geofence.notification.data"] {
                log("userNotificationCenter didReceive: \(data)")
                NotificationCenter.default.post(name: Notification.Name(rawValue: "CDVLocalNotification"), object: data)
            }
        case "Snooze":
            snoozeFence(response.notification.request.identifier, duration: 86400)
        case "Delete":
            snoozeFence(response.notification.request.identifier, duration: 300)
        default:
            log("Unknown action")
        }
        completionHandler()
    }
}

class GeoNotificationStore {
    init() {
        createDBStructure()
    }
    
    func createDBStructure() {
        let (tables, err) = SD.existingTables()
        
        if (err != nil) {
            log("Cannot fetch sqlite tables: \(String(describing: err))")
            return
        }
        
        if (tables.filter { $0 == "GeoNotifications" }.count == 0) {
            if let err = SD.executeChange("CREATE TABLE GeoNotifications (ID TEXT PRIMARY KEY, Data TEXT)") {
                //there was an error during this function, handle it here
                log("Error while creating GeoNotifications table: \(err)")
            } else {
                //no error, the table was created successfully
                log("GeoNotifications table was created successfully")
            }
        }
    }
    
    func addOrUpdate(_ geoNotification: JSON) {
        NSLog("geoNotification.description: %@", geoNotification.description)
        if (findById(geoNotification["id"].stringValue) != nil) {
            update(geoNotification)
        }
        else {
            add(geoNotification)
        }
    }
    
    func add(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        var notificationCopy = geoNotification
        notificationCopy["lastTriggered"] = 0
        let err = SD.executeChange("INSERT INTO GeoNotifications (Id, Data) VALUES(?, ?)",
                                   withArgs: [id as AnyObject, notificationCopy.description as AnyObject])
        
        if err != nil {
            log("Error while adding \(id) GeoNotification: \(String(describing: err))")
        }
    }
    
    func update(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        let err = SD.executeChange("UPDATE GeoNotifications SET Data = ? WHERE Id = ?",
                                   withArgs: [geoNotification.description as AnyObject, id as AnyObject])
        
        if err != nil {
            log("Error while adding \(id) GeoNotification: \(String(describing: err))")
        }
    }
    
    func updateLastTriggeredByNotificationId(_ id: String) {
        if let allStored = getAll() {
            for var json in allStored {
                if json["notification"]["id"].stringValue == id {
                    json["notification"]["lastTriggered"] = JSON(NSDate().timeIntervalSince1970)
                    update(json)
                }
            }
        }
    }

    func findById(_ id: String) -> JSON? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])
        
        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching \(id) GeoNotification table: \(String(describing: err))")
            return nil
        } else {
            if (resultSet.count > 0) {
                let jsonString = resultSet[0]["Data"]!.asString()!
                return JSON(data: jsonString.data(using: String.Encoding.utf8)!)
            }
            else {
                return nil
            }
        }
    }
    
    func getAll() -> [JSON]? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications")
        
        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching from GeoNotifications table: \(String(describing: err))")
            return nil
        } else {
            var results = [JSON]()
            for row in resultSet {
                if let data = row["Data"]?.asString() {
                    results.append(JSON(data: data.data(using: String.Encoding.utf8)!))
                }
            }
            return results
        }
    }
    
    func remove(_ id: String) {
        let err = SD.executeChange("DELETE FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])
        
        if err != nil {
            log("Error while removing \(id) GeoNotification: \(String(describing: err))")
        }
    }
    
    func clear() {
        let err = SD.executeChange("DELETE FROM GeoNotifications")
        
        if err != nil {
            log("Error while deleting all from GeoNotifications: \(String(describing: err))")
        }
    }
}
