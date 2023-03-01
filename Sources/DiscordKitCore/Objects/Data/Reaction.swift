//
//  Reaction.swift
//  DiscordAPI
//
//  Created by Vincent Kwok on 19/2/22.
//

import Foundation

public struct Reaction: Codable, GatewayData {
    public let user_id: Snowflake
    public let channel_id: Snowflake
    public let message_id: Snowflake
    public let guild_id: Snowflake
    public let member: Member
    public let emoji: Emoji
}
