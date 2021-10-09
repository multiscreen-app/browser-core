/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

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

let LatestAppVersionProfileKey = "latestAppVersion"

class AppDelegate: UIResponder, UIApplicationDelegate, UIViewControllerRestoration {
    public static func viewController(withRestorationIdentifierPath identifierComponents: [String], coder: NSCoder) -> UIViewController? {
        return nil
    }

    var window: UIWindow?
    var browserViewController: BrowserViewController!
    var rootViewController: UIViewController!
    var playlistRestorationController: UIViewController? // When Picture-In-Picture is enabled, we need to store a reference to the controller to keep it alive, otherwise if it deallocates, the system automatically kills Picture-In-Picture.
    weak var profile: Profile?
    var tabManager: TabManager!
    var braveCore: BraveCoreMain?

    weak var application: UIApplication?
    var launchOptions: [AnyHashable: Any]?

    let appVersion = Bundle.main.infoDictionaryString(forKey: "CFBundleShortVersionString")

    var receivedURLs: [URL]?
    
    var shutdownWebServer: DispatchSourceTimer?

    @discardableResult func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Hold references to willFinishLaunching parameters for delayed app launch
        self.application = application
        self.launchOptions = launchOptions
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window!.backgroundColor = .black
        
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
        
        return startApplication(application, withLaunchOptions: launchOptions)
    }

    @discardableResult fileprivate func startApplication(_ application: UIApplication, withLaunchOptions launchOptions: [AnyHashable: Any]?) -> Bool {
        log.info("startApplication begin")
        
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

        let profile = getProfile(application)
        let profilePrefix = profile.prefs.getBranchPrefix()
        Migration.launchMigrations(keyPrefix: profilePrefix)
        
        setUpWebServer(profile)
        
        var imageStore: DiskImageStore?
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

        self.tabManager = TabManager(prefs: profile.prefs, imageStore: imageStore)

        // Make sure current private browsing flag respects the private browsing only user preference
        PrivateBrowsingManager.shared.isPrivateBrowsing = Preferences.Privacy.privateBrowsingOnly.value
        
        // Don't track crashes if we're building the development environment due to the fact that terminating/stopping
        // the simulator via Xcode will count as a "crash" and lead to restore popups in the subsequent launch
        let crashedLastSession = !Preferences.AppState.backgroundedCleanly.value && AppConstants.buildChannel != .debug
        Preferences.AppState.backgroundedCleanly.value = false
        browserViewController = BrowserViewController(profile: self.profile!, tabManager: self.tabManager, crashedLastSession: crashedLastSession)
        browserViewController.edgesForExtendedLayout = []

        // Add restoration class, the factory that will return the ViewController we will restore with.
        browserViewController.restorationIdentifier = NSStringFromClass(BrowserViewController.self)
        browserViewController.restorationClass = AppDelegate.self

        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.delegate = self
        navigationController.isNavigationBarHidden = true
        navigationController.edgesForExtendedLayout = UIRectEdge(rawValue: 0)
//        rootViewController = TestViewController(controller: navigationController, controller2: UIViewController(nibName: nil, bundle: nil))
        rootViewController = navigationController
        self.window!.rootViewController = rootViewController

        SystemUtils.onFirstRun()
        
        // Schedule Brave Core Priority Tasks
        self.braveCore?.scheduleLowPriorityStartupTasks()

        log.info("startApplication end")
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // We have only five seconds here, so let's hope this doesn't take too long.
        self.profile?.shutdown()

        // Allow deinitializers to close our database connections.
        self.profile = nil
        self.tabManager = nil
        self.browserViewController = nil
        self.rootViewController = nil
//        SKPaymentQueue.default().remove(iapObserver)
        
        // Clean up BraveCore
        BraveSyncAPI.removeAllObservers()
        self.braveCore = nil
    }

    /**
     * We maintain a weak reference to the profile so that we can pause timed
     * syncs when we're backgrounded.
     *
     * The long-lasting ref to the profile lives in BrowserViewController,
     * which we set in application:willFinishLaunchingWithOptions:.
     *
     * If that ever disappears, we won't be able to grab the profile to stop
     * syncing... but in that case the profile's deinit will take care of things.
     */
    func getProfile(_ application: UIApplication) -> Profile {
        if let profile = self.profile {
            return profile
        }
        let p = BrowserProfile(localName: "profile")
        self.profile = p
        return p
    }
    
    private var cancellables: Set<AnyCancellable> = []
    
    private var expectedThemeOverride: UIUserInterfaceStyle {
        let themeOverride = DefaultTheme(
            rawValue: Preferences.General.themeNormalMode.value
        )?.userInterfaceStyleOverride ?? .unspecified
        let isPrivateBrowsing = PrivateBrowsingManager.shared.isPrivateBrowsing
        return isPrivateBrowsing ? .dark : themeOverride
    }
    
    private func updateTheme() {
        guard let window = window else { return }
        UIView.transition(with: window, duration: 0.15, options: [.transitionCrossDissolve], animations: {
            window.overrideUserInterfaceStyle = self.expectedThemeOverride
        }, completion: nil)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // IAPs can trigger on the app as soon as it launches,
        // for example when a previous transaction was not finished and is in pending state.
//        SKPaymentQueue.default().add(iapObserver)
        
        // Override point for customization after application launch.
        var shouldPerformAdditionalDelegateHandling = true
        
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
        applyAppearanceDefaults()
        
        Preferences.General.themeNormalMode.objectWillChange
            .merge(with: PrivateBrowsingManager.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTheme()
            }
            .store(in: &cancellables)
        
        window?.overrideUserInterfaceStyle = expectedThemeOverride
        window?.tintColor = UIColor {
            if $0.userInterfaceStyle == .dark {
                return .braveLighterBlurple
            }
            return .braveBlurple
        }
        window?.makeKeyAndVisible()
        
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
        
        if !Preferences.VPN.popupShowed.value {
            Preferences.VPN.appLaunchCountForVPNPopup.value += 1
        }
        
        browserViewController.shouldShowIntroScreen =
            DefaultBrowserIntroManager.prepareAndShowIfNeeded(isNewUser: isFirstLaunch)
        
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
      
        return shouldPerformAdditionalDelegateHandling
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let routerpath = NavigationPath(url: url) else {
            return false
        }
        self.browserViewController.handleNavigationPath(path: routerpath)
        return true
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if let presentedViewController = rootViewController.presentedViewController {
            return presentedViewController.supportedInterfaceOrientations
        } else {
            return rootViewController.supportedInterfaceOrientations
        }
    }

    // We sync in the foreground only, to avoid the possibility of runaway resource usage.
    // Eventually we'll sync in response to notifications.
    func applicationDidBecomeActive(_ application: UIApplication) {
        shutdownWebServer?.cancel()
        shutdownWebServer = nil
        
        Preferences.AppState.backgroundedCleanly.value = false

        if let profile = self.profile {
            profile.reopen()
            setUpWebServer(profile)
        }
        
        self.receivedURLs = nil
        application.applicationIconBadgeNumber = 0
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        syncOnDidEnterBackground(application: application)
    }

    fileprivate func syncOnDidEnterBackground(application: UIApplication) {
        guard let profile = self.profile else {
            return
        }
      
        // BRAVE TODO: Decide whether or not we want to use this for our own sync down the road

        var taskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier(rawValue: 0)
        taskId = application.beginBackgroundTask {
            print("Running out of background time, but we have a profile shutdown pending.")
            self.shutdownProfileWhenNotActive(application)
            application.endBackgroundTask(taskId)
        }

        profile.shutdown()
        application.endBackgroundTask(taskId)
        
        let singleShotTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        // 2 seconds is ample for a localhost request to be completed by GCDWebServer. <500ms is expected on newer devices.
        singleShotTimer.schedule(deadline: .now() + 2.0, repeating: .never)
        singleShotTimer.setEventHandler {
            WebServer.sharedInstance.server.stop()
            self.shutdownWebServer = nil
        }
        singleShotTimer.resume()
        shutdownWebServer = singleShotTimer
    }

    fileprivate func shutdownProfileWhenNotActive(_ application: UIApplication) {
        // Only shutdown the profile if we are not in the foreground
        guard application.applicationState != .active else {
            return
        }

        profile?.shutdown()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // The reason we need to call this method here instead of `applicationDidBecomeActive`
        // is that this method is only invoked whenever the application is entering the foreground where as
        // `applicationDidBecomeActive` will get called whenever the Touch ID authentication overlay disappears.
        AdblockResourceDownloader.shared.startLoading()
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        Preferences.AppState.backgroundedCleanly.value = true
    }

    fileprivate func setUpWebServer(_ profile: Profile) {
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

    fileprivate func setUserAgent() {
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

    fileprivate func presentEmailComposerWithLogs() {
        if let buildNumber = Bundle.main.object(forInfoDictionaryKey: String(kCFBundleVersionKey)) as? NSString {
            let mailComposeViewController = MFMailComposeViewController()
            mailComposeViewController.mailComposeDelegate = self
            mailComposeViewController.setSubject("Debug Info for iOS client version v\(appVersion) (\(buildNumber))")

            self.window?.rootViewController?.present(mailComposeViewController, animated: true, completion: nil)
        }
    }
}

// MARK: - Root View Controller Animations
extension AppDelegate: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push:
            return BrowserToTrayAnimator()
        case .pop:
            return TrayToBrowserAnimator()
        default:
            return nil
        }
    }
}

extension AppDelegate: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        // Dismiss the view controller and start the app up
        controller.dismiss(animated: true, completion: nil)
        startApplication(application!, withLaunchOptions: self.launchOptions)
    }
}
