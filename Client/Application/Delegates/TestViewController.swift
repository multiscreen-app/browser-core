// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit

class TestViewController: UIViewController {

    let partial = UIView()
    let partial2 = UIView()
    let controller: UIViewController
    let controller2: UIViewController
    
    init(controller: UIViewController, controller2: UIViewController) {
        self.controller = controller
        self.controller2 = controller2
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()        self.view.addSubview(partial)
        self.view.addSubview(partial2)
        partial.snp.makeConstraints {
            $0.top.equalToSuperview()
            $0.left.equalToSuperview()
            $0.bottom.equalToSuperview().offset(-self.view.bounds.height / 2)
            $0.right.equalToSuperview()
        }
        
        partial2.snp.makeConstraints {
            $0.top.equalToSuperview().offset(self.view.bounds.height / 2)
            $0.left.equalToSuperview()
            $0.bottom.equalToSuperview()
            $0.right.equalToSuperview()
        }
        
        addChildC()
        addChildC2()
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
    
    public func addChildC2() -> TestViewController {
        self.addChild(controller2)
        controller2.view.translatesAutoresizingMaskIntoConstraints = false
        partial2.addSubview(controller2.view)
        partial2.clipsToBounds = true
        controller2.didMove(toParent: self)
        controller2.view.snp.makeConstraints {
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
