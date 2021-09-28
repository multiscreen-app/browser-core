// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit

class TestViewController: UIViewController {

    let partial = UIView()
    let controller: UIViewController
    
    init(controller: UIViewController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(partial)
        partial.snp.makeConstraints {
            $0.top.equalToSuperview().offset(100)
            $0.left.equalToSuperview().offset(100)
            $0.bottom.equalToSuperview().offset(-100)
            $0.right.equalToSuperview().offset(-100)
        }
        
        addChildC()
    }
    
    public func addChildC() -> TestViewController {
        self.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        partial.addSubview(controller.view)
        partial.clipsToBounds = true
        controller.didMove(toParent: self)
        controller.view.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        return self
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
