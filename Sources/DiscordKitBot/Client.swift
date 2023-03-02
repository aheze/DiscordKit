//
//  Client.swift
//
//
//  Created by Vincent Kwok on 21/11/22.
//

import DiscordKitCore
import Foundation
import Logging

/// The main client class for bots to interact with Discord's API
public final class Client {
    // REST handler
    public let rest = DiscordREST()

    // MARK: Gateway vars

    fileprivate var gateway: RobustWebSocket?
    private var evtHandlerID: EventDispatch.HandlerIdentifier?

    // MARK: Application Command Handlers

    fileprivate var appCommandHandlers: [Snowflake: NewAppCommand.Handler] = [:]

    // MARK: Event publishers

    private let notificationCenter = NotificationCenter()
    public let ready: NCWrapper<Void>
    public let messageCreate: NCWrapper<Message>
    public let messageReactAdd: NCWrapper<Reaction>

    // MARK: Configuration Members

    public let intents: Intents

    // Logger
    private static let logger = Logger(label: "Client", level: nil)

    // MARK: Information about the bot

    /// The user object of the bot
    public fileprivate(set) var user: User?
    /// The application ID of the bot
    ///
    /// This is used for registering application commands, among other actions.
    public fileprivate(set) var applicationID: String?

    public init(intents: Intents = .unprivileged) {
        self.intents = intents
        // Override default config for bots
        DiscordKitConfig.default = .init(
            properties: .init(browser: DiscordKitConfig.libraryName, device: DiscordKitConfig.libraryName),
            intents: intents
        )

        // Init event wrappers
        ready = .init(.ready, notificationCenter: notificationCenter)
        messageCreate = .init(.messageCreate, notificationCenter: notificationCenter)
        messageReactAdd = .init(.messageReactAdd, notificationCenter: notificationCenter)
    }

    deinit {
        disconnect()
    }

    /// Login to the Discord API with a token
    ///
    /// Calling this function will cause a connection to the Gateway to be attempted.
    ///
    /// > Warning: Ensure this function is called _before_ any calls to the API are made,
    /// > and _after_ all event sinks have been registered. API calls made before this call
    /// > will fail, and no events will be received while the gateway is disconnected.
    public func login(token: String) {
        rest.setToken(token: token)
        gateway = .init(token: token)
        evtHandlerID = gateway?.onEvent.addHandler { [weak self] data in
            self?.handleEvent(data)
        }
    }

    /// Login to the Discord API with a token from the environment
    ///
    /// This method attempts to retrieve the token from the `DISCORD_TOKEN` environment
    /// variable, and calls ``login(token:)`` if it was found.
    ///
    /// ## See Also
    /// - ``login(token:)`` If you'd like to manually provide a token instead
    public func login() {
        let token = ProcessInfo.processInfo.environment["DISCORD_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(token != nil, "The \"DISCORD_TOKEN\" environment variable was not found.")
        precondition(!token!.isEmpty, "The \"DISCORD_TOKEN\" environment variable is empty.")
        // We force unwrap here since that's the best way to inform the developer that they're missing a token
        login(token: token!)
    }

    /// Disconnect from the gateway, undoes ``login(token:)``
    ///
    /// Request that the gateway connection be gracefully closed. Also destroys
    /// the REST hander. Following this call, none of the APIs would function. Subsequently,
    /// connection can be restored by calling ``login(token:)`` again.
    public func disconnect() {
        // Remove event listeners and gracefully disconnect from Gateway
        gateway?.close(code: .normalClosure)
        if let evtHandlerID = evtHandlerID { _ = gateway?.onEvent.removeHandler(handler: evtHandlerID) }
        // Clear member vars
        gateway = nil
        rest.setToken(token: nil)
        applicationID = nil
        user = nil
    }
}

// Gateway API
extension Client {
    public var isReady: Bool { gateway?.sessionOpen == true }

    /// Invoke the handler associated with the respective commands
    private func invokeCommandHandler(_ commandData: Interaction.Data.AppCommandData, id: Snowflake, token: String, channelID: String?, userID: String?) {
        if let handler = appCommandHandlers[commandData.id] {
            Self.logger.trace("Invoking application handler", metadata: ["command.name": "\(commandData.name)"])
            Task {
                await handler(.init(
                    optionValues: commandData.options ?? [],
                    rest: rest, applicationID: applicationID!, interactionID: id, token: token, channelID: channelID, userID: userID
                ))
            }
        }
    }

    /// Handle a subset of gateway events
    private func handleEvent(_ data: GatewayIncoming.Data) {
        
        switch data {
        case .botReady(let readyEvt):
            let firstTime = applicationID == nil
            // Set several members with info about the bot
            applicationID = readyEvt.application.id
            user = readyEvt.user
            if firstTime {
                Self.logger.info("Bot client ready", metadata: [
                    "user.id": "\(readyEvt.user.id)",
                    "application.id": "\(readyEvt.application.id)"
                ])
                ready.emit()
            }
        case .messageReactAdd(let reaction):
            messageReactAdd.emit(value: reaction)
        case .messageCreate(let message):
//            let botMessage = BotMessage(from: message, rest: rest)
            messageCreate.emit(value: message)
        case .interaction(let interaction):
            
            Self.logger.trace("Received interaction", metadata: ["interaction.id": "\(interaction.id)"])
            // Handle interactions based on type
            switch interaction.data {
            case .applicationCommand(let commandData):
                invokeCommandHandler(commandData, id: interaction.id, token: interaction.token, channelID: interaction.channelID, userID: interaction.member?.user?.id)
            case .messageComponent(let componentData):
                print("Component interaction: \(componentData.custom_id)")
            default: break
            }
        default:
            break
        }
    }
}

// MARK: - REST-related API

public extension Client {
    // MARK: Interactions

    /// Register Application Commands with a result builder
    func registerApplicationCommands(
        guild: Snowflake? = nil, @AppCommandBuilder _ commands: () -> [NewAppCommand]
    ) async throws {
        try await registerApplicationCommands(guild: guild, commands())
    }

    /// Register Application Commands with the provided application command create structs
    func registerApplicationCommands(guild: Snowflake? = nil, _ commands: [NewAppCommand]) async throws {
        let registeredCommands = try await rest.bulkOverwriteCommands(commands, applicationID: applicationID!, guildID: guild)
        for command in commands {
            // Find the actual registered command
            // By comparing both the type and name, we ensure there is no ambiguity.
            guard let registeredCommand = registeredCommands.first(where: {
                $0.type == command.type && $0.name == command.name
            }) else {
                Self.logger.warning("Could not find registered command corresponding to new command", metadata: [
                    "command.name": "\(command.name)",
                    "command.type": "\(command.type)"
                ])
                continue
            }
            appCommandHandlers[registeredCommand.id] = command.handler
        }
    }
}
