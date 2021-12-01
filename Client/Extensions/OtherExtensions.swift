// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
extension String {
    /// Encode a String to Base64
    func toBase64() -> String {
        return Data(self.utf8).base64EncodedString()
    }
}

extension UIButton {
    
    func addHoverEffect(cornerRadius: CGFloat = 5) {
        if cornerRadius != 0 {
            self.layer.cornerRadius = cornerRadius
            self.layer.masksToBounds = true
        }

        self.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(onPointerInteraction(_:))))
    }
    
    @objc private func onPointerInteraction(_ recognizer: UIHoverGestureRecognizer) {
        let lightMode = traitCollection.userInterfaceStyle == .light
        if recognizer.state == .began {
            self.backgroundColor = lightMode ? .black.withAlphaComponent(0.1) : .white.withAlphaComponent(0.1)
        } else if recognizer.state == .ended {
            self.backgroundColor = .clear
        }
    }
    
}
