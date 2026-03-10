// Copyright 2026 Link Dupont
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ArgumentParser
import Foundation
import Logging

enum LogLevel: String, ExpressibleByArgument {
    case trace
    case debug
    case info
    case warn
    case error
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Set log level to debug (same as --log-level debug)")
    var verbose = false

    @Option(name: .long, help: "Log level")
    var logLevel: LogLevel = .error
}

@main
struct Applebox: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "box",
        abstract: "Persistent Linux development containers for macOS",
        version: "0.1.0",
        subcommands: [
            Create.self,
            Enter.self,
            List.self,
            Rm.self,
        ],
        defaultSubcommand: nil,
        helpNames: [.long, .short],
    )

    @OptionGroup var options: GlobalOptions

    nonisolated(unsafe) static var logger: Logger = {
        LoggingSystem.bootstrap(StreamLogHandler.standardError)
        var log = Logger(label: "applebox")
        log.logLevel = .error
        return log
    }()

    mutating func run() async throws {
        Self.applyLogging(options)
        throw CleanExit.helpRequest(self)
    }

    static func applyLogging(_ options: GlobalOptions) {
        let level: Logger.Level
        if options.verbose {
            level = .debug
        } else {
            level = Logger.Level(rawValue: options.logLevel.rawValue) ?? .error
        }
        logger.logLevel = level
    }
}
