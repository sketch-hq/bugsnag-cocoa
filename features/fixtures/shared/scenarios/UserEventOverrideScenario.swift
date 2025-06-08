//
//  UserEventOverrideScenario.swift
//  iOSTestApp
//
//  Created by Jamie Lynch on 26/05/2020.
//  Copyright © 2020 Bugsnag. All rights reserved.
//

import Foundation

/**
 * Sends a handled error to Bugsnag which overrides the user information in the event
 */
internal class UserEventOverrideScenario: Scenario {

    override func configure() {
        super.configure()
        self.config.autoTrackSessions = false;
    }

    override func run() {
        Bugsnag.setUser("abc", withEmail: nil, andName: nil)
        let error = NSError(domain: "UserIdScenario", code: 100, userInfo: nil)
        Bugsnag.notifyError(error) { (event) -> Bool in
            event.setUser("customId", withEmail: "customEmail", andName: "customName")
            return true
        }
    }
}
