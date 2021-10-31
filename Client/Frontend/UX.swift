/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit

struct UX {
    struct TabsBar {
        static let buttonWidth = UIDevice.current.userInterfaceIdiom == .pad ? 40 : 0
        static let height: CGFloat = 33
        static let minimumWidth: CGFloat =  UIDevice.current.userInterfaceIdiom == .pad ? 180 : 160
    }
}

class RoundInterfaceButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2.0
    }
}

class RoundInterfaceView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.height, bounds.width) / 2.0
    }
}
