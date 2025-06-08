Feature: Stopping and resuming sessions

  Background:
    Given I clear all persistent data

  Scenario: When a session is stopped the error has no session information
    When I run "StoppedSessionScenario"
    And I wait to receive a session
    And I wait to receive 2 errors
    Then the session is valid for the session reporting API

    And the received errors match:
        | session.events.handled | exceptions.0.message |
        | 1                      | The operation couldn’t be completed. (First error error 101.) |
        | null                   | The operation couldn’t be completed. (Second error error 101.) |

    And the error is valid for the error reporting API
    And I discard the oldest error
    Then the error is valid for the error reporting API

  Scenario: When a session is resumed the error uses the previous session information
    When I run "ResumedSessionScenario"
    And I wait to receive a session
    And I wait to receive 2 errors
    Then the session is valid for the session reporting API

    And the received errors match:
        | session.events.handled | exceptions.0.message |
        | 1                      | The operation couldn’t be completed. (First error error 101.) |
        | 2                      | The operation couldn’t be completed. (Second error error 101.) |

    And the error payload field "events.0.session.id" is equal for error 0 and error 1
    And the error payload field "events.0.session.startedAt" is equal for error 0 and error 1
    And the error is valid for the error reporting API
    And I discard the oldest error
    Then the error is valid for the error reporting API

  Scenario: When a new session is started the error uses different session information
    When I run "NewSessionScenario"
    And I wait to receive 2 sessions
    And I wait to receive 2 errors

    Then the session is valid for the session reporting API
    And I discard the oldest session

    Then the session is valid for the session reporting API

    And the received errors match:
        | session.events.handled | exceptions.0.message |
        | 1                      | The operation couldn’t be completed. (First error error 101.) |
        | 1                      | The operation couldn’t be completed. (Second error error 101.) |

    And the error payload field "events.0.session.id" is not equal for error 0 and error 1

    Then the error is valid for the error reporting API
    And I discard the oldest error
    Then the error is valid for the error reporting API
