//
//  UserFromClientScenario.swift
//  iOSTestApp
//
//  Created by Jamie Lynch on 26/05/2020.
//  Copyright © 2020 Bugsnag. All rights reserved.
//

import Foundation

/**
 * Sends a session to Bugsnag which contains a user set from the Client
 */
internal class UserFromClientScenario: Scenario {

    override func configure() {
        super.configure()
        self.config.autoTrackSessions = false;
    }

    override func run() {
        Bugsnag.setUser("def", withEmail: "sue@gmail.com", andName: "Sue")
        Bugsnag.startSession()
    }
}
