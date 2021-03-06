//
//  Zephyr.swift
//  Zephyr
//
//  Created by Arthur Ariel Sabintsev on 11/2/15.
//  Copyright © 2015 Arthur Ariel Sabintsev. All rights reserved.
//

import Foundation

/// Enumerates the Local (NSUserDefaults) and Remote (NSUNSUbiquitousKeyValueStore) data stores
fileprivate enum ZephyrDataStore {
    case local  // NSUserDefaults
    case remote // NSUbiquitousKeyValueStore
}

public class Zephyr: NSObject {

    /// A debug flag.
    ///
    /// If **true**, then this will enable console log statements.
    ///
    /// By default, this flag is set to **false**.
    public static var debugEnabled = false

    /// If **true**, then NSUbiquitousKeyValueStore.synchronize() will be called immediately after any change is made.
    public static var syncUbiquitousKeyValueStoreOnChange = true

    /// The singleton for Zephyr.
    fileprivate static let sharedInstance = Zephyr()

    /// A shared key that stores the last synchronization date between NSUserDefaults and NSUbiquitousKeyValueStore.
    fileprivate let ZephyrSyncKey = "ZephyrSyncKey"

    /// An array of keys that should be actively monitored for changes.
    fileprivate var monitoredKeys = [String]()

    /// An array of keys that are currently registered for observation.
    fileprivate var registeredObservationKeys = [String]()

    /// A queue used to serialize synchronization on monitored keys.
    fileprivate let zephyrQueue = DispatchQueue(label: "com.zephyr.queue");

    /// A session-persisted variable to directly access all of the NSUserDefaults elements.
    fileprivate var zephyrLocalStoreDictionary: [String: Any] {
        get {
            return UserDefaults.standard.dictionaryRepresentation()
        }
    }

    /// A session-persisted variable to directly access all of the NSUbiquitousKeyValueStore elements.
    fileprivate var zephyrRemoteStoreDictionary: [String: Any]  {
        get {
            return NSUbiquitousKeyValueStore.default().dictionaryRepresentation
        }
    }

    /// Zephyr's initialization method.
    ///
    /// Do not call this method directly.
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(keysDidChangeOnCloud(notification:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(notification:)),
                                               name: NSNotification.Name.UIApplicationWillEnterForeground,
                                               object: nil)
        NSUbiquitousKeyValueStore.default().synchronize()
    }


    /// Zephyr's de-initialization method.
    deinit {
        zephyrQueue.sync {
            for key in registeredObservationKeys {
                UserDefaults.standard.removeObserver(self, forKeyPath: key)
            }
        }
    }

    /// Zephyr's synchronization method.
    ///
    /// Zephyr will synchronize all NSUserDefaults with NSUbiquitousKeyValueStore.
    ///
    /// If one or more keys are passed, only those keys will be synchronized.
    ///
    /// - Parameters:
    ///     - keys: If you pass a one or more keys, only those key will be synchronized. If no keys are passed, than all NSUserDefaults will be synchronized with NSUbiquitousKeyValueStore.
    public static func sync(keys: String...) {
        if keys.count > 0 {
            sync(keys: keys)
            return
        }

        switch sharedInstance.dataStoreWithLatestData() {
        case .local:
            printGeneralSyncStatus(finished: false, destination: .remote)
            sharedInstance.zephyrQueue.sync {
                sharedInstance.syncToCloud()
            }
            printGeneralSyncStatus(finished: true, destination: .remote)
        case .remote:
            printGeneralSyncStatus(finished: false, destination: .local)
            sharedInstance.zephyrQueue.sync {
                sharedInstance.syncFromCloud()
            }
            printGeneralSyncStatus(finished: true, destination: .local)
        }
    }

    /// Overloaded version of Zephyr's synchronization method, **sync(keys:)**.
    ///
    /// This method will synchronize an array of keys between NSUserDefaults and NSUbiquitousKeyValueStore.
    ///
    /// - Parameters: 
    ///     - keys: An array of keys that should be synchronized between NSUserDefaults and NSUbiquitousKeyValueStore.
    public static func sync(keys: [String]) {
        switch sharedInstance.dataStoreWithLatestData() {
        case .local:
            printGeneralSyncStatus(finished: false, destination: .remote)
            sharedInstance.zephyrQueue.sync {
                sharedInstance.syncSpecificKeys(keys: keys, dataStore: .local)
            }
            printGeneralSyncStatus(finished: true, destination: .remote)
        case .remote:
            printGeneralSyncStatus(finished: false, destination: .local)
            sharedInstance.zephyrQueue.sync {
                sharedInstance.syncSpecificKeys(keys: keys, dataStore: .remote)
            }
            printGeneralSyncStatus(finished: true, destination: .local)
        }
    }

    /// Add specific keys to be monitored in the background. Monitored keys will automatically
    /// be synchronized between both data stores whenever a change is detected
    ///
    /// - Parameters:
    ///     - keys: Pass one or more keys that you would like to begin monitoring.
    public static func addKeysToBeMonitored(keys: [String]) {
        for key in keys {
            if sharedInstance.monitoredKeys.contains(key) == false {
                sharedInstance.monitoredKeys.append(key)

                sharedInstance.zephyrQueue.sync {
                    sharedInstance.registerObserver(key: key)
                }
            }
        }
    }

    /// Overloaded version of the **addKeysToBeMonitored(keys:)** method.
    ///
    /// Add specific keys to be monitored in the background. Monitored keys will automatically
    /// be synchronized between both data stores whenever a change is detected
    ///
    /// - Parameters:
    ///     - keys: Pass one or more keys that you would like to begin monitoring.
    public static func addKeysToBeMonitored(keys: String...) {
        addKeysToBeMonitored(keys: keys)
    }

    /// Remove specific keys from being monitored in the background.
    ///
    /// - Parameters:
    ///    - keys: Pass one or more keys that you would like to stop monitoring.
    public static func removeKeysFromBeingMonitored(keys: [String]) {
        for key in keys {
            if sharedInstance.monitoredKeys.contains(key) == true {
                sharedInstance.monitoredKeys = sharedInstance.monitoredKeys.filter {$0 != key }

                sharedInstance.zephyrQueue.sync {
                    sharedInstance.unregisterObserver(key: key)
                }
            }
        }
    }

    /// Overloaded version of the **removeKeysFromBeingMonitored(keys:)** method.
    ///
    /// Remove specific keys from being monitored in the background.
    ///
    /// - Parameters: 
    ///     - keys: Pass one or more keys that you would like to stop monitoring.
    public static func removeKeysFromBeingMonitored(keys: String...) {
        removeKeysFromBeingMonitored(keys: keys)
    }

}

// MARK: Helpers

fileprivate extension Zephyr {

    /// Compares the last sync date between NSUbiquitousKeyValueStore and NSUserDefaults.
    ///
    /// If no data exists in NSUbiquitousKeyValueStore, then NSUbiquitousKeyValueStore will synchronize with data from NSUserDefaults.
    /// If no data exists in NSUserDefaults, then NSUserDefaults will synchronize with data from NSUbiquitousKeyValueStore.
    ///
    /// - Returns: The persistent data store that has the newest data.
    func dataStoreWithLatestData() -> ZephyrDataStore {

        if let remoteDate = zephyrRemoteStoreDictionary[ZephyrSyncKey] as? Date,
            let localDate = zephyrLocalStoreDictionary[ZephyrSyncKey] as? Date {

            // If both localDate and remoteDate exist, compare the two, and then synchronize the data stores.
            return localDate.timeIntervalSince1970 > remoteDate.timeIntervalSince1970 ? .local : .remote

        } else {

            // If remoteDate doesn't exist, then assume local data is newer.
            guard let _ = zephyrRemoteStoreDictionary[ZephyrSyncKey] as? Date else {
                return .local
            }

            // If localDate doesn't exist, then assume that remote data is newer.
            guard let _ = zephyrLocalStoreDictionary[ZephyrSyncKey] as? Date else {
                return .remote
            }

            // If neither exist, synchronize local data store to iCloud.
            return .local
        }

    }

}

// MARK: Synchronizers

fileprivate extension Zephyr {

    /// Synchronizes specific keys to/from NSUbiquitousKeyValueStore and NSUserDefaults.
    /// 
    /// - Parameters: 
    ///     - keys: Array of keys to synchronize.
    ///     - dataStore: Signifies if keys should be synchronized to/from iCloud.
    func syncSpecificKeys(keys: [String], dataStore: ZephyrDataStore) {
        for key in keys {
            switch dataStore {
            case .local:
                let value = zephyrLocalStoreDictionary[key]
                syncToCloud(key: key, value: value)
            case .remote:
                let value = zephyrRemoteStoreDictionary[key]
                syncFromCloud(key: key, value: value)
            }
        }
    }

    /// Synchronizes all NSUserDefaults to NSUbiquitousKeyValueStore.
    ///
    /// If a key is passed, only that key will be synchronized.
    /// 
    /// - Parameters: 
    ///     - key: If you pass a key, only that key will be updated in NSUbiquitousKeyValueStore.
    ///     - value: The value that will be synchronized. Must be passed with a key, otherwise, nothing will happen.
    func syncToCloud(key: String? = nil, value: Any? = nil) {

        let ubiquitousStore = NSUbiquitousKeyValueStore.default()
        ubiquitousStore.set(Date(), forKey: ZephyrSyncKey)

        // Sync all defaults to iCloud if key is nil, otherwise sync only the specific key/value pair.
        guard let key = key else {
            for (key, value) in zephyrLocalStoreDictionary {
                unregisterObserver(key: key)
                ubiquitousStore.set(value, forKey: key)
                Zephyr.printKeySyncStatus(key: key, value: value, destination: .remote)
                if Zephyr.syncUbiquitousKeyValueStoreOnChange {
                    ubiquitousStore.synchronize()
                }
                registerObserver(key: key)
            }

            return
        }

        unregisterObserver(key: key)

        if let value = value {
            ubiquitousStore.set(value, forKey: key)
            Zephyr.printKeySyncStatus(key: key, value: value, destination: .remote)
        } else {
            NSUbiquitousKeyValueStore.default().removeObject(forKey: key)
            Zephyr.printKeySyncStatus(key: key, value: value, destination: .remote)
        }

        if Zephyr.syncUbiquitousKeyValueStoreOnChange {
            ubiquitousStore.synchronize()
        }

        registerObserver(key: key)
    }

    /// Synchronizes all NSUbiquitousKeyValueStore to NSUserDefaults.
    ///
    /// If a key is passed, only that key will be synchronized.
    ///
    /// - Parameters:
    ///     - key: If you pass a key, only that key will updated in NSUserDefaults.
    ///     - value: The value that will be synchronized. Must be passed with a key, otherwise, nothing will happen.
    func syncFromCloud(key: String? = nil, value: Any? = nil) {

        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: ZephyrSyncKey)

        // Sync all defaults from iCloud if key is nil, otherwise sync only the specific key/value pair.
        guard let key = key else {
            for (key, value) in zephyrRemoteStoreDictionary {
                unregisterObserver(key: key)
                defaults.set(value, forKey: key)
                Zephyr.printKeySyncStatus(key: key, value: value, destination: .local)
                registerObserver(key: key)
            }

            return
        }

        unregisterObserver(key: key)

        if let value = value {
            defaults.set(value, forKey: key)
            Zephyr.printKeySyncStatus(key: key, value: value, destination: .local)
        } else {
            defaults.set(nil, forKey: key)
            Zephyr.printKeySyncStatus(key: key, value: nil, destination: .local)
        }

        registerObserver(key: key)
    }

}

// MARK: Observers

extension Zephyr {

    /// Adds key-value observation after synchronization of a specific key.
    ///
    /// - Parameters: 
    ///     - key: The key that should be added and monitored.
    fileprivate func registerObserver(key: String) {
        if key == ZephyrSyncKey {
            return
        }

        if !self.registeredObservationKeys.contains(key) {

            UserDefaults.standard.addObserver(self, forKeyPath: key, options: .new, context: nil)
            self.registeredObservationKeys.append(key)

        }

        Zephyr.printObservationStatus(key: key, subscribed: true)
    }

    /// Removes key-value observation before synchronization of a specific key.
    ///
    /// - Parameters:
    ///     - key: The key that should be removed from being monitored.
    fileprivate func unregisterObserver(key: String) {

        if key == ZephyrSyncKey {
            return
        }

        if let index = self.registeredObservationKeys.index(of: key) {

            UserDefaults.standard.removeObserver(self, forKeyPath: key, context: nil)
            self.registeredObservationKeys.remove(at: index)

        }

        Zephyr.printObservationStatus(key: key, subscribed: false)
    }

    /// Observation method for UIApplicationWillEnterForegroundNotification
    func willEnterForeground(notification: Notification) {
        NSUbiquitousKeyValueStore.default().synchronize()
    }

    ///  Observation method for NSUbiquitousKeyValueStoreDidChangeExternallyNotification
    func keysDidChangeOnCloud(notification: Notification) {
        if notification.name == NSUbiquitousKeyValueStore.didChangeExternallyNotification {

            guard let userInfo = (notification as NSNotification).userInfo,
                let cloudKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                let localStoredDate = zephyrLocalStoreDictionary[ZephyrSyncKey] as? Date,
                let remoteStoredDate = zephyrRemoteStoreDictionary[ZephyrSyncKey] as? Date , remoteStoredDate.timeIntervalSince1970 > localStoredDate.timeIntervalSince1970 else {
                    return
            }

            for key in monitoredKeys where cloudKeys.contains(key) {
                self.syncSpecificKeys(keys: [key], dataStore: .remote)
            }
        }
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath, let object = object else {
            return
        }

        // Synchronize changes if key is monitored and if key is currently registered to respond to changes
        if monitoredKeys.contains(keyPath) {

            zephyrQueue.async {
                if self.registeredObservationKeys.contains(keyPath) {
                    if object is UserDefaults {
                        UserDefaults.standard.set(Date(), forKey: self.ZephyrSyncKey)
                    }

                    self.syncSpecificKeys(keys: [keyPath], dataStore: .local)
                }
            }
        }
    }
}

// MARK: Loggers

fileprivate extension Zephyr {

    /// Prints Zephyr's current sync status if
    ///
    /// - Parameters:
    ///     - debugEnabled == true
    ///     - finished: The current status of syncing
    static func printGeneralSyncStatus(finished: Bool, destination dataStore: ZephyrDataStore) {

        if debugEnabled == true {
            let destination = dataStore == .local ? "FROM iCloud" : "TO iCloud."

            var message = "Started synchronization \(destination)"
            if finished == true {
                message = "Finished synchronization \(destination)"
            }

            printStatus(status: message)
        }
    }

    /// Prints the key, value, and destination of the synchronized information if debugEnabled == true
    ///
    /// - Parameters:
    ///     - key: The key being synchronized.
    ///     - value: The value being synchronized.
    ///     - destination: The data store that is receiving the updated key-value pair.
    static func printKeySyncStatus(key: String, value: Any?, destination dataStore: ZephyrDataStore) {

        if debugEnabled == true {
            let destination = dataStore == .local ? "FROM iCloud" : "TO iCloud."

            guard let value = value else {
                let message = "Synchronized key '\(key)' with value 'nil' \(destination)"
                printStatus(status: message)
                return
            }
            
            let message = "Synchronized key '\(key)' with value '\(value)' \(destination)"
            printStatus(status: message)
        }
    }
    
    /// Prints the subscription state for a specific key if debugEnabled == true
    ///
    /// - Parameters: 
    ///     - key: The key being synchronized.
    ///     - subscribed: The subscription status of the key.
    static func printObservationStatus(key: String, subscribed: Bool) {
        
        if debugEnabled {
            let subscriptionState = subscribed == true ? "Subscribed" : "Unsubscribed"
            let preposition = subscribed == true ? "for" : "from"
            
            let message = "\(subscriptionState) '\(key)' \(preposition) observation."
            printStatus(status: message)
        }
    }
    
    /// Prints a status to the console if
    ///
    /// - Parameters: 
    ///     - debugEnabled == true
    ///     - status: The string that should be printed to the console.
    static func printStatus(status: String) {
        if debugEnabled == true {
            print("[Zephyr] \(status)")
        }
    }
    
}
