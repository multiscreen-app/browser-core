// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Static
import BraveShared
import Shared
import BraveCore

class NTPTableViewController: TableViewController {
    enum BackgroundImageType: RepresentableOptionType {
        
        case defaultImages
        
        var key: String {
            displayString
        }
        
        public var displayString: String {
            switch self {
            case .defaultImages: return "(\(Strings.NTP.settingsDefaultImagesOnly))"
            }
        }
    }
    
    init() {
        super.init(style: .grouped)
    }
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Hides unnecessary empty rows
        tableView.tableFooterView = UIView()
        
        navigationItem.title = Strings.NTP.settingsTitle
        tableView.accessibilityIdentifier = "NewTabPageSettings.tableView"
        loadSections()
        
        Preferences.NewTabPage.backgroundImages.observe(from: self)
    }
    
    private func loadSections() {
        var section = Section(rows: [Row.boolRow(title: Strings.NTP.settingsBackgroundImages,
                                                 option: Preferences.NewTabPage.backgroundImages)])
        
        if Preferences.NewTabPage.backgroundImages.value {
            section.rows.append(backgroundImagesSetting(section: section))
        }
        
        dataSource.sections = [section]
    }
    
    private func selectedItem() -> BackgroundImageType {
        return .defaultImages
    }
    
    private lazy var backgroundImageOptions: [BackgroundImageType] = {
        var available: [BackgroundImageType] = [.defaultImages]
        return available
    }()
    
    private func backgroundImagesSetting(section: Section) -> Row {
        var row = Row(
            text: Strings.NTP.settingsBackgroundImageSubMenu,
            detailText: selectedItem().displayString,
            accessory: .disclosureIndicator,
            cellClass: MultilineSubtitleCell.self)
        
        row.selection = { [unowned self] in
            // Show options for tab bar visibility
            let optionsViewController = OptionSelectionViewController<BackgroundImageType>(
                options: self.backgroundImageOptions,
                selectedOption: self.selectedItem(),
                optionChanged: { _, option in
                    self.dataSource.reloadCell(row: row, section: section, displayText: option.displayString)
                }
            )
            optionsViewController.navigationItem.title = Strings.NTP.settingsBackgroundImageSubMenu
            self.navigationController?.pushViewController(optionsViewController, animated: true)
        }
        return row
    }
}

extension NTPTableViewController: PreferencesObserver {
    func preferencesDidChange(for key: String) {
        loadSections()
    }
}
