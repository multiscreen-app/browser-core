// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Shared
import Storage
import AVFoundation
import XCGLogger
import MessageUI
import SDWebImage
import SwiftKeychainWrapper
import LocalAuthentication
import CoreSpotlight
import UserNotifications
import BraveShared
import Data
import StoreKit
import BraveCore
import Combine

private let log = Logger.browserLogger

open class EmbeddedClient {
    
    var browserInstances: [BrowserInstance] = []
    var imageStore: DiskImageStore?
    weak var profile: Profile?
    var playlistRestorationController: UIViewController? // When Picture-In-Picture is enabled, we need to store a reference to the controller to keep it alive, otherwise if it deallocates, the system automatically kills Picture-In-Picture.
    var restoredTabs = false
    
    var braveCore: BraveCoreMain? {
        get {
            return BraveCoreShared.shared.braveCore
        }
        set {
            BraveCoreShared.shared.braveCore = newValue
        }
    }
    
    var shutdownWebServer: Timer?
    
    public init() {
    }
    
    public func initialize() {
        // Brave Core Initialization
        BraveCoreMain.setLogHandler { severity, file, line, messageStartIndex, message in
            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let level: XCGLogger.Level = {
                    switch -severity {
                    case 0: return .error
                    case 1: return .info
                    case 2..<7: return .debug
                    default: return .verbose
                    }
                }()
                Logger.braveCoreLogger.logln(
                    level,
                    fileName: file,
                    lineNumber: Int(line),
                    // Only print the actual message content, and drop the final character which is
                    // a new line as it will be handled by logln
                    closure: { message.dropFirst(messageStartIndex).dropLast() }
                )
            }
            return true
        }
        
        self.braveCore = BraveCoreMain()
        self.braveCore?.setUserAgent(UserAgent.mobile)
        
        AdBlockStats.shared.startLoading()
        HttpsEverywhereStats.shared.startLoading()
                
        // Must happen before passcode check, otherwise may unnecessarily reset keychain
        Migration.moveDatabaseToApplicationDirectory()
        
        // Passcode checking, must happen on immediate launch
        if !DataController.shared.storeExists() {
            // Since passcode is stored in keychain it persists between installations.
            //  If there is no database (either fresh install, or deleted in file system), there is no real reason
            //  to passcode the browser (no data to protect).
            // Main concern is user installs Brave after a long period of time, cannot recall passcode, and can
            //  literally never use Brave. This bypasses this situation, while not using a modifiable pref.
//            KeychainWrapper.sharedAppContainerKeychain.setAuthenticationInfo(nil)
        }
        
        // We have to wait until pre1.12 migration is done until we proceed with database
        // initialization. This is because Database container may change. See bugs #3416, #3377.
        DataController.shared.initialize()
    }
    
    public func start() {
        // Set the Safari UA for browsing.
        setUserAgent()

        // Start the keyboard helper to monitor and cache keyboard state.
        KeyboardHelper.defaultHelper.startObserving()
        DynamicFontHelper.defaultHelper.startObserving()

        MenuHelper.defaultHelper.setItems()
        
        SDImageCodersManager.shared.addCoder(PrivateCDNImageCoder())

        let logDate = Date()
        // Create a new sync log file on cold app launch. Note that this doesn't roll old logs.
        Logger.syncLogger.newLogWithDate(logDate)
        Logger.browserLogger.newLogWithDate(logDate)

        let profile = getProfile()
        // MS we don't need this as we don't have anything to migrate from
//        let profilePrefix = profile.prefs.getBranchPrefix()
//        Migration.launchMigrations(keyPrefix: profilePrefix)
        
        setUpWebServer(profile)
        
        do {
            imageStore = try DiskImageStore(files: profile.files, namespace: "TabManagerScreenshots", quality: UIConstants.screenshotQuality)
        } catch {
            log.error("Failed to create an image store for files: \(profile.files) and namespace: \"TabManagerScreenshots\": \(error.localizedDescription)")
            assertionFailure()
        }
        
        // Temporary fix for Bug 1390871 - NSInvalidArgumentException: -[WKContentView menuHelperFindInPage]: unrecognized selector
        if let clazz = NSClassFromString("WKCont" + "ent" + "View"), let swizzledMethod = class_getInstanceMethod(TabWebViewMenuHelper.self, #selector(TabWebViewMenuHelper.swizzledMenuHelperFindInPage)) {
            class_addMethod(clazz, MenuHelper.selectorFindInPage, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        }

        SystemUtils.onFirstRun()
        
        // Schedule Brave Core Priority Tasks
        self.braveCore?.scheduleLowPriorityStartupTasks()
        
        applyAppearanceDefaults()
    }
    
    public func createBrowserInstance(_ delegate: BrowserInstanceDelegate, launchOptions: LaunchOptions) -> BrowserInstance {
        return BrowserInstance(self, delegate: delegate, profile: getProfile(), store: self.imageStore!, launchOptions: launchOptions)
        // Add restoration class, the factory that will return the ViewController we will restore with.
//        browserViewController.restorationIdentifier = NSStringFromClass(BrowserViewController.self)
//        browserViewController.restorationClass = AppDelegate.self
    }
    
    public func willEnterForeground(application: UIApplication) {
        AdblockResourceDownloader.shared.startLoading()
    }
    
    public func didBecomeActive(application: UIApplication) {
        guard let profile = profile else {
            return
        }
        shutdownWebServer?.invalidate()
        shutdownWebServer = nil
        
        Preferences.AppState.backgroundedCleanly.value = false
        
        profile.reopen()
        setUpWebServer(profile)
    }
    
    public func willResignActive(application: UIApplication) {
        Preferences.AppState.backgroundedCleanly.value = true
    }
    
    public func didEnterBackground(application: UIApplication) {
        var taskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier(rawValue: 0)
        taskId = application.beginBackgroundTask {
            print("Running out of background time, but we have a profile shutdown pending.")
            self.shutdownProfileWhenNotActive(application)
            application.endBackgroundTask(taskId)
        }

        profile?.shutdown()
        
        application.endBackgroundTask(taskId)
        
        shutdownWebServer?.invalidate()
        shutdownWebServer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            WebServer.sharedInstance.server.stop()
            self?.shutdownWebServer = nil
        }
    }
    
    fileprivate func shutdownProfileWhenNotActive(_ application: UIApplication) {
        // Only shutdown the profile if we are not in the foreground
        guard application.applicationState != .active else {
            return
        }

        profile?.shutdown()
    }
    
    func terminate() {
        // We have only five seconds here, so let's hope this doesn't take too long.
        self.profile?.shutdown()

        // Allow deinitializers to close our database connections.
        self.profile = nil
        browserInstances = []
        
        // Clean up BraveCore
        BraveSyncAPI.removeAllObservers()
        self.braveCore = nil
    }
    
    func getProfile() -> Profile {
        if let profile = self.profile {
            return profile
        }
        let p = BrowserProfile(localName: "profile")
        self.profile = p
        return p
    }

    public func didFinishLaunchingWithOptions(application: UIApplication) {
        AdblockRustEngine.setDomainResolver { urlCString, start, end in
            guard let urlCString = urlCString else { return }
            let urlString = String(cString: urlCString)
            let parsableURLString: String = {
                // Apple's URL implementation requires a URL be prefixed with a scheme to be
                // parsed properly (otherwise URL(string: X) will resolve to placing the entire
                // contents of X into the `path` property
                if urlString.asURL?.scheme == nil {
                    return "http://\(urlString)"
                }
                return urlString
            }()
            guard let url = URL(string: parsableURLString),
                  let baseDomain = url.baseDomain,
                  let range = urlString.range(of: baseDomain) else {
                log.error("Failed to resolve domain ")
                return
            }
            let startIndex: Int = urlString.distance(from: urlString.startIndex, to: range.lowerBound)
            let endIndex: Int = urlString.distance(from: urlString.startIndex, to: range.upperBound)
            start?.pointee = UInt32(startIndex)
            end?.pointee = UInt32(endIndex)
        }
        
        UIScrollView.doBadSwizzleStuff()
        
        // Now roll logs.
        DispatchQueue.global(qos: DispatchQoS.background.qosClass).async {
            Logger.syncLogger.deleteOldLogsDownToSizeLimit()
            Logger.browserLogger.deleteOldLogsDownToSizeLimit()
        }

        // Force the ToolbarTextField in LTR mode - without this change the UITextField's clear
        // button will be in the incorrect position and overlap with the input text. Not clear if
        // that is an iOS bug or not.
        AutocompleteTextField.appearance().semanticContentAttribute = .forceLeftToRight
        
        let isFirstLaunch = Preferences.General.isFirstLaunch.value
        if Preferences.General.basicOnboardingCompleted.value == OnboardingState.undetermined.rawValue {
            Preferences.General.basicOnboardingCompleted.value =
                isFirstLaunch ? OnboardingState.unseen.rawValue : OnboardingState.completed.rawValue
        }
        Preferences.General.isFirstLaunch.value = false
        Preferences.Review.launchCount.value += 1
            
        // Search engine setup must be checked outside of 'firstLaunch' loop because of #2770.
        // There was a bug that when you skipped onboarding, default search engine preference
        // was not set.
        if Preferences.Search.defaultEngineName.value == nil {
            profile?.searchEngines.searchEngineSetup()
        }
        
        // Migration of Yahoo Search Engines
        if !Preferences.Search.yahooEngineMigrationCompleted.value {
            profile?.searchEngines.migrateDefaultYahooSearchEngines()
        }
        
        if isFirstLaunch {
            Preferences.DAU.installationDate.value = Date()
        }
        
        AdblockResourceDownloader.shared.startLoading()
        PlaylistManager.shared.restoreSession()
    }
    
    private func setUserAgent() {
        let userAgent = UserAgent.userAgentForDesktopMode

        // Set the favicon fetcher, and the image loader.
        // This only needs to be done once per runtime. Note that we use defaults here that are
        // readable from extensions, so they can just use the cached identifier.

        SDWebImageDownloader.shared.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        WebcompatReporter.userAgent = userAgent
        
        // Record the user agent for use by search suggestion clients.
        SearchViewController.userAgent = userAgent

        // Some sites will only serve HTML that points to .ico files.
        // The FaviconFetcher is explicitly for getting high-res icons, so use the desktop user agent.
        FaviconFetcher.htmlParsingUserAgent = UserAgent.desktop
    }
    
    private func setUpWebServer(_ profile: Profile) {
        let server = WebServer.sharedInstance
        if server.server.isRunning { return }
        
        ReaderModeHandlers.register(server, profile: profile)
        ErrorPageHelper.register(server, certStore: profile.certStore)
        SafeBrowsingHandler.register(server)
        AboutHomeHandler.register(server)
        AboutLicenseHandler.register(server)
        SessionRestoreHandler.register(server)
        BookmarksInterstitialPageHandler.register(server)

        // Bug 1223009 was an issue whereby CGDWebserver crashed when moving to a background task
        // catching and handling the error seemed to fix things, but we're not sure why.
        // Either way, not implicitly unwrapping a try is not a great way of doing things
        // so this is better anyway.
        do {
            try server.start()
        } catch let err as NSError {
            print("Error: Unable to start WebServer \(err)")
        }
    }
    
    private func applyAppearanceDefaults() {
        // important! for privacy concerns, otherwise UI can bleed through
        UIToolbar.appearance().do {
            $0.tintColor = .braveOrange
            $0.standardAppearance = {
                let appearance = UIToolbarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundColor = .braveBackground
                return appearance
            }()
        }
        
        UINavigationBar.appearance().do {
            $0.tintColor = .braveOrange
            $0.standardAppearance = {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.titleTextAttributes = [.foregroundColor: UIColor.braveLabel]
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.braveLabel]
                appearance.backgroundColor = .braveBackground
                return appearance
            }()
        }
        
        UISwitch.appearance().onTintColor = UIColor.braveOrange
        
        /// Used as color a table will use as the base (e.g. background)
        let tablePrimaryColor = UIColor.braveGroupedBackground
        /// Used to augment `tablePrimaryColor` above
        let tableSecondaryColor = UIColor.secondaryBraveGroupedBackground
        
        UITableView.appearance().backgroundColor = tablePrimaryColor
        UITableView.appearance().separatorColor = .braveSeparator
        
        UITableViewCell.appearance().do {
            $0.tintColor = .braveOrange
            $0.backgroundColor = tableSecondaryColor
        }
        
        UIImageView.appearance(whenContainedInInstancesOf: [SettingsViewController.self])
            .tintColor = .braveLabel

        UIView.appearance(whenContainedInInstancesOf: [UITableViewHeaderFooterView.self])
            .backgroundColor = tablePrimaryColor
        
        UILabel.appearance(whenContainedInInstancesOf: [UITableView.self]).textColor = .braveLabel
        UILabel.appearance(whenContainedInInstancesOf: [UICollectionReusableView.self])
            .textColor = .braveLabel
        
        UITextField.appearance().textColor = .braveLabel
    }
    
    public func getLicenseController() -> UIViewController {
        return SettingsContentViewController().then {
            guard let url = URL(string: WebServer.sharedInstance.base) else { return }
            
            $0.url = url.appendingPathComponent("about").appendingPathComponent("license")
        }
    }
    
}

extension AppConstants {
    public static let embedded: Bool = {
#if MOZ_TARGET_EMBEDDEDCLIENT
        return true
#else
        return false
#endif
    }()
}
