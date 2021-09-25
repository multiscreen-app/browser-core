// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveShared
import BraveUI
import Shared
import BraveCore

// MARK: - Onboarding

extension BrowserViewController {
    
    func presentOnboardingIntro(_ completion: @escaping () -> Void) {
        // MS show onboarding on debug
        if Preferences.DebugFlag.skipOnboardingIntro == true { return }
        
        // 1. Existing user.
        // 2. User already completed onboarding.
        if Preferences.General.basicOnboardingCompleted.value == OnboardingState.completed.rawValue {
            // The user doesn't have ads in their region and they've completed rewards.
            if !BraveAds.isCurrentLocaleSupported()
                &&
                Preferences.General.basicOnboardingProgress.value == OnboardingProgress.rewards.rawValue {
                return
            }
        }
        
        // The user either skipped or didn't complete onboarding.
        let currentProgress = OnboardingProgress(rawValue: Preferences.General.basicOnboardingProgress.value) ?? .none
        
        // 1. User is brand new
        // 2. User hasn't completed onboarding
        // 3. We don't care how much progress they made. Onboarding is only complete when ALL of it is complete.
        if Preferences.General.basicOnboardingCompleted.value != OnboardingState.completed.rawValue {
            // The user has never completed the onboarding..
            
            guard let onboarding = OnboardingNavigationController(
                profile: profile,
                onboardingType: .newUser(currentProgress)
                ) else { return }
            
            onboarding.onboardingDelegate = self
            present(onboarding, animated: true)
            completion()
            
            return
        }
    }
    
    /// New Tab Page Education screen should load after onboarding is finished and user is on locale JP
    /// - Returns: A tuple which shows NTP Edication is enabled and URL to be loaed
    fileprivate func showNTPEducation() -> (isEnabled: Bool, url: URL?) {
        guard let url = BraveUX.ntpTutorialPageURL else {
            return (false, nil)
        }

        return (Locale.current.regionCode == "JP", url)
    }
}

// MARK: OnboardingControllerDelegate

extension BrowserViewController: OnboardingControllerDelegate {
    
    func onboardingCompleted(_ onboardingController: OnboardingNavigationController) {
        Preferences.General.basicOnboardingCompleted.value = OnboardingState.completed.rawValue
        Preferences.General.basicOnboardingNextOnboardingPrompt.value = nil
        
        switch onboardingController.onboardingType {
        case .newUser:
            Preferences.General.basicOnboardingProgress.value = OnboardingProgress.searchEngine.rawValue
        default:
            break
        }
        
        dismissOnboarding(onboardingController)
    }
    
    func onboardingSkipped(_ onboardingController: OnboardingNavigationController) {
        Preferences.General.basicOnboardingCompleted.value = OnboardingState.skipped.rawValue
        Preferences.General.basicOnboardingNextOnboardingPrompt.value = Date(timeIntervalSinceNow: BrowserViewController.onboardingDaysInterval)
        
        dismissOnboarding(onboardingController)
    }
    
    private func presentEducationNTPIfNeeded() {
        // NTP Education Load after onboarding screen
        if shouldShowNTPEducation,
           showNTPEducation().isEnabled,
           let url = showNTPEducation().url {
            tabManager.selectedTab?.loadRequest(PrivilegedRequest(url: url) as URLRequest)
        }
    }
    
    private func dismissOnboarding(_ onboardingController: OnboardingNavigationController) {
        // Present NTP Education If Locale is JP and onboading is finished or skipped
        // Present private browsing prompt if necessary when onboarding has been skipped
        onboardingController.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            
            self.presentEducationNTPIfNeeded()
        }
    }
    
    // 60 days until the next time the user sees the onboarding..
    static let onboardingDaysInterval = TimeInterval(60.days)
}
