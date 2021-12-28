// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Storage
import UIKit
import BraveShared
import WebKit
import Combine

public class BrowserInstance {

    unowned var delegate: BrowserInstanceDelegate?

    let client: EmbeddedClient
    var launchOptions: LaunchOptions

    var profile: Profile
    var tabManager: TabManager!
    var browserViewController: BrowserViewController!

    private var cancellables: [AnyCancellable] = []

    init(_ client: EmbeddedClient, delegate: BrowserInstanceDelegate?, profile: Profile, store: DiskImageStore, launchOptions: LaunchOptions) {
        self.client = client
        self.delegate = delegate
        self.profile = profile
        self.tabManager = TabManager(prefs: profile.prefs, imageStore: store)
        self.launchOptions = launchOptions
        create()
    }

    func create() {
        if !client.restoredTabs {
            launchOptions.restoreTabs = true
            client.restoredTabs = true
        }

        browserViewController = BrowserViewController(profile: self.profile, tabManager: self.tabManager, historyAPI: client.braveCore.historyAPI, bookmarksAPI: client.braveCore.bookmarksAPI, crashedLastSession: false, launchOptions: launchOptions)
        browserViewController.edgesForExtendedLayout = []
        browserViewController.browserInstance = self

        cancellables.append(Preferences.General.themeNormalMode.objectWillChange
                .merge(with: browserViewController.privateBrowsingManager.objectWillChange)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                self?.updateTheme()
            }
        )

        Preferences.AppState.backgroundedCleanly.value = false
    }

    public func getBrowserViewController() -> UIViewController {
        return browserViewController
    }

    public func getSelectedTabWebview() -> WKWebView? {
        return browserViewController.tabManager.selectedTab?.webView
    }

    public func windowResize() {
        browserViewController.tabsBar.collectionView.collectionViewLayout.invalidateLayout()
    }
    
    public func activeStateUpdated() {
        let activeState = delegate?.getActiveState() ?? false
        if !activeState {
            if browserViewController.topToolbar.inOverlayMode {
                browserViewController.topToolbar.leaveOverlayMode()
            }
            if !browserViewController.privateBrowsingManager.isPrivateBrowsing {
                browserViewController.topToolbar.backgroundColor = .secondaryBraveBackgroundInactive
                browserViewController.topToolbar.locationView.backgroundColor = .braveBackgroundInactive
            } else {
                browserViewController.topToolbar.backgroundColor = .privateModeBackground.darker(by: 8)
                browserViewController.topToolbar.locationView.backgroundColor = .braveBackgroundInactive.darker(by: 8)
            }
        } else {
            if !browserViewController.privateBrowsingManager.isPrivateBrowsing {
                browserViewController.topToolbar.backgroundColor = .secondaryBraveBackground
                browserViewController.topToolbar.locationView.backgroundColor = .braveBackground
            } else {
                browserViewController.topToolbar.backgroundColor = .privateModeBackground
                browserViewController.topToolbar.locationView.backgroundColor = .braveBackgroundInactive
            }
        }
    }

    private var expectedThemeOverride: UIUserInterfaceStyle {
        let themeOverride = DefaultTheme(
            rawValue: Preferences.General.themeNormalMode.value
        )?.userInterfaceStyleOverride ?? .unspecified
        let isPrivateBrowsing = browserViewController.privateBrowsingManager.isPrivateBrowsing
        return isPrivateBrowsing ? .dark : themeOverride
    }

    private func updateTheme() {
        guard let window = browserViewController.view else { return }
        UIView.transition(with: window, duration: 0.15, options: [.transitionCrossDissolve], animations: {
                window.overrideUserInterfaceStyle = self.expectedThemeOverride
            }, completion: nil)
    }

    deinit {
        print("Browser Instance deinit")
        tabManager.allTabs.forEach {
            tabManager.removeTab($0, false)
        }
        tabManager = nil
        browserViewController.view.subviews.forEach {
            $0.removeFromSuperview()
        }
        browserViewController = nil
    }

}
