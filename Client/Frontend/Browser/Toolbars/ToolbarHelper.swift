// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit
import Shared

@objcMembers
class ToolbarHelper: NSObject {
    unowned let toolbar: ToolbarProtocol
    
    init(toolbar: ToolbarProtocol) {
        self.toolbar = toolbar
        super.init()
        
        toolbar.backButton.setImage(UIImage(systemName: "arrow.backward"), for: .normal)
        toolbar.backButton.accessibilityLabel = Strings.tabToolbarBackButtonAccessibilityLabel
        let longPressGestureBackButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressBack))
        toolbar.backButton.addGestureRecognizer(longPressGestureBackButton)
        toolbar.backButton.addTarget(self, action: #selector(didClickBack), for: .touchUpInside)
        
        toolbar.tabsButton.addTarget(self, action: #selector(didClickTabs), for: .touchUpInside)
        let longPressGestureTabsButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressTabs))
        toolbar.tabsButton.addGestureRecognizer(longPressGestureTabsButton)
        
        toolbar.shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        toolbar.shareButton.accessibilityLabel = Strings.tabToolbarShareButtonAccessibilityLabel
        toolbar.shareButton.addTarget(self, action: #selector(didClickShare), for: UIControl.Event.touchUpInside)
        
        toolbar.addTabButton.setImage(#imageLiteral(resourceName: "add_tab").template, for: .normal)
        toolbar.addTabButton.accessibilityLabel = Strings.tabToolbarAddTabButtonAccessibilityLabel
        toolbar.addTabButton.addTarget(self, action: #selector(didClickAddTab), for: UIControl.Event.touchUpInside)
        toolbar.addTabButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressAddTab(_:))))
        
        toolbar.searchButton.setImage(#imageLiteral(resourceName: "ntp-search").template, for: .normal)
        // Accessibility label not needed, since overriden in the bottom tool bar class.
        toolbar.searchButton.addTarget(self, action: #selector(didClickSearch), for: UIControl.Event.touchUpInside)
        // Same long press gesture allows creating tab on NTP, esp private tab easily
        toolbar.searchButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressAddTab(_:))))

        toolbar.menuButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        toolbar.menuButton.accessibilityLabel = Strings.tabToolbarMenuButtonAccessibilityLabel
        toolbar.menuButton.addTarget(self, action: #selector(didClickMenu), for: UIControl.Event.touchUpInside)
        
        toolbar.forwardButton.setImage(UIImage(systemName: "arrow.forward"), for: .normal)
        toolbar.forwardButton.accessibilityLabel = Strings.tabToolbarForwardButtonAccessibilityLabel
        let longPressGestureForwardButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressForward))
        toolbar.forwardButton.addGestureRecognizer(longPressGestureForwardButton)
        toolbar.forwardButton.addTarget(self, action: #selector(didClickForward), for: .touchUpInside)
    }
    
    func didClickMenu() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressMenu(toolbar)
    }
    
    func didClickBack() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressBack(toolbar, button: toolbar.backButton)
    }
    
    func didLongPressBack(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressBack(toolbar, button: toolbar.backButton)
        }
    }
    
    func didClickTabs() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressTabs(toolbar, button: toolbar.tabsButton)
    }
    
    func didLongPressTabs(_ recognizer: UILongPressGestureRecognizer) {
        toolbar.tabToolbarDelegate?.tabToolbarDidLongPressTabs(toolbar, button: toolbar.tabsButton)
    }
    
    func didClickForward() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressForward(toolbar, button: toolbar.forwardButton)
    }
    
    func didLongPressForward(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressForward(toolbar, button: toolbar.forwardButton)
        }
    }
    
    func didClickShare() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressShare()
    }
    
    func didClickAddTab() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressAddTab(toolbar, button: toolbar.shareButton)
    }
    
    func didClickSearch() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressSearch(toolbar, button: toolbar.searchButton)
    }
    
    func didLongPressAddTab(_ longPress: UILongPressGestureRecognizer) {
        if longPress.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressAddTab(toolbar, button: toolbar.shareButton)
        }
    }
}
