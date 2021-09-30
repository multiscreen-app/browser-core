// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Storage

class BrowserInstance {
    
    var profile: Profile
    var tabManager: TabManager!
    var browserViewController: BrowserViewController!
    
    init(profile: Profile, store: DiskImageStore) {
        self.profile = profile
        self.tabManager = TabManager(prefs: profile.prefs, imageStore: store)
    }
    
    public func create() -> BrowserViewController {
        browserViewController = BrowserViewController(profile: self.profile, tabManager: self.tabManager, crashedLastSession: false)
        browserViewController.edgesForExtendedLayout = []
        return browserViewController
    }
    
}
