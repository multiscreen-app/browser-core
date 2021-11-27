// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import WebKit

public protocol BrowserInstanceDelegate : AnyObject {
    func displayPopup(_ controller: UIViewController, configuration: PopupConfiguration, modal: Bool, dismiss: (() -> Void)?)
    
    func dismissPopup(completion: (() -> Void)?)
    
    func createDragGestureRecognizer() -> UIGestureRecognizer
    
    func createResizeGestureRecognizer() -> UIGestureRecognizer
    
    func close()
    
    func createNewWindow(_ windowFeatures: WKWindowFeatures) -> BrowserInstanceDelegate
    
    func initNewWindow(_ browserInstance: BrowserInstance)
    
}

extension BrowserInstanceDelegate {
    func dismissPopup(completion: (() -> Void)? = nil) {
        dismissPopup(completion: completion)
    }

}
