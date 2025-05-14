local DISCORD_API = "https://discord.com/api/v10"

if Config.discord.botToken == "" then
    print("^1[ERROR]^0 Discord bot token not configured in config.lua")
    return
end

if Config.discord.channelID == "" then
    print("^1[ERROR]^0 Discord channel ID not configured in config.lua")
    return
end


local function GetServerInfo()
    return {
        name = GetConvar("sv_hostname", "FiveM Server"):gsub('%^%d', ''),
        iconURL = GetConvar("sv_iconUrl", ""),
        maxPlayers = GetConvarInt("sv_maxClients", 32)
    }
end


local function SendDiscordEmbed(embedData, attempt)
    attempt = attempt or 1
    local maxAttempts = 3  -- Maximum retry attempts
    
    if not Config or not Config.discord then
        print("^1[DISCORD BOT]^0 Configuration not loaded properly")
        return false
    end

    if Config.discord.botToken == "" or Config.discord.channelID == "" then
        if Config.debug then
            print("^1[DISCORD BOT]^0 Missing bot token or channel ID in config")
        end
        return false
    end


    local url = ("%s/channels/%s/messages"):format(DISCORD_API, Config.discord.channelID)
    local headers = {
        ["Authorization"] = "Bot " .. Config.discord.botToken,
        ["Content-Type"] = "application/json"
    }

    local data = {
        embeds = {embedData}
    }


    PerformHttpRequest(url, function(err, text, headers)
        if Config.debug then
            print(("^5[DISCORD BOT]^0 Attempt %d/%d - Status: %s"):format(attempt, maxAttempts, err or "unknown"))
        end

        if err == 429 then
            local retryAfter = tonumber(headers["retry-after"]) or 5
            if attempt >= maxAttempts then
                print("^1[DISCORD BOT]^0 Max retry attempts reached for rate limit")
                return
            end
            
            print(("^3[DISCORD BOT]^0 Rate limited - Retrying after %d seconds"):format(retryAfter))
            Citizen.Wait(retryAfter * 1000)
            SendDiscordEmbed(embedData, attempt + 1)
            return
        end

        if err ~= 200 and err ~= 204 then
            local errorMsg = "Unknown error"
            if text then
                local response = json.decode(text)
                if response and response.message then
                    errorMsg = response.message
                end
            end
            
            print(("^1[DISCORD BOT]^0 Error sending embed (HTTP %s): %s"):format(
                err or "unknown", 
                errorMsg
            ))
            
            if err >= 500 and err < 600 and attempt < maxAttempts then
                local retryDelay = math.min(2 ^ attempt, 30)
                print(("^3[DISCORD BOT]^0 Server error - Retrying in %d seconds"):format(retryDelay))
                Citizen.Wait(retryDelay * 1000)
                SendDiscordEmbed(embedData, attempt + 1)
            end
            return
        end

        if Config.debug then
            print("^2[DISCORD BOT]^0 Embed sent successfully")
            
            if Config.debugLevel == "verbose" then
                print("^5[DEBUG]^0 Embed data:")
                print(json.encode(embedData, {indent = true}))
            end
        end
    end, 'POST', json.encode(data), headers)

    return true
end


local function AllResourcesStarted()
    local resources = GetResources()
    for _, resource in ipairs(resources) do
        if GetResourceState(resource) ~= "started" then
            return false
        end
    end
    return true
end


local function GetBotAvatar(callback)
    if Config.discord.botToken == "" then
        return callback(nil)
    end
    
    local url = DISCORD_API .. "/users/@me"
    local headers = {
        ["Authorization"] = "Bot " .. Config.discord.botToken,
        ["Content-Type"] = "application/json"
    }
    
    PerformHttpRequest(url, function(err, text, headers)
        if err == 200 then
            local data = json.decode(text)
            local avatarId = data.avatar
            local botId = data.id
            
            if avatarId then
                local avatarURL = string.format("https://cdn.discordapp.com/avatars/%s/%s.png", botId, avatarId)
                callback(avatarURL)
            else
                callback(nil)
            end
        else
            if Config.debug then
                print(("^1[DISCORD BOT]^0 Error fetching bot info (HTTP %s): %s"):format(err, text))
            end
            callback(nil)
        end
    end, 'GET', "", headers)
end

Citizen.CreateThread(function()
    Citizen.Wait(5000)

    if Config.debug then
        print("^3[RESTART NOTIFIER]^0 Starting up...")
    end

    local attempts = 0
    while not AllResourcesStarted() and attempts < 10 do
        attempts = attempts + 1
        if Config.debug then
            print("^3[RESTART NOTIFIER]^0 Waiting for all resources to start... Attempt " .. attempts)
        end
        Citizen.Wait(10000)
    end

    local serverInfo = GetServerInfo()
    local playerCount = GetNumPlayerIndices()

    GetBotAvatar(function(avatarURL)
        local embed = {
            title = Config.message.title,
            description = string.format("%s is now online!", serverInfo.name),
            color = Config.message.color,
            image = {
                url = Config.discord.bannerURL
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {
                text = "Server Restart Notification",
                icon_url = avatarURL or Config.discord.iconURL
            }
        }

        if serverInfo.iconURL ~= "" then
            embed.thumbnail = {
                url = serverInfo.iconURL
            }
        end

        local success = SendDiscordEmbed(embed)
        
        if Config.debug then
            if success then
                print("^2[RESTART NOTIFIER]^0 Server restart notification sent")
            else
                print("^1[RESTART NOTIFIER]^0 Failed to send server restart notification")
            end
        end
    end)
end)