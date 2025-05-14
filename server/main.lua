local DISCORD_API = "https://discord.com/api/v10"

-- Configuration validation
if Config == nil or Config.discord == nil then
    print("^1[ERROR]^0 Configuration not loaded properly")
    return
end

if Config.discord.botToken == "" then
    print("^1[ERROR]^0 Discord bot token not configured in config.lua")
    return
end

if Config.discord.channelID == "" then
    print("^1[ERROR]^0 Discord channel ID not configured in config.lua")
    return
end

-- Function to get server information
local function GetServerInfo()
    return {
        name = (GetConvar("sv_hostname", "FiveM Server"):gsub('%^%d', '')), -- Remove color codes
        iconURL = GetConvar("sv_iconUrl", ""),
        maxPlayers = GetConvarInt("sv_maxClients", 32)
    }
end

-- Function to send Discord embed
local function SendDiscordEmbed(embedData, attempt)
    attempt = attempt or 1
    local maxAttempts = 3
    
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

        -- Rate limit handling
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

        -- Error handling
        if err ~= 200 and err ~= 204 then
            local errorMsg = "Unknown error"
            if text then
                local response = json.decode(text)
                if response and response.message then
                    errorMsg = response.message
                end
            end
            print(("^1[DISCORD BOT]^0 Error sending embed (HTTP %s): %s"):format(err or "unknown", errorMsg))
            
            -- Retry on server errors
            if err >= 500 and err < 600 and attempt < maxAttempts then
                local retryDelay = math.min(2 ^ attempt, 30)
                print(("^3[DISCORD BOT]^0 Server error - Retrying in %d seconds"):format(retryDelay))
                Citizen.Wait(retryDelay * 1000)
                SendDiscordEmbed(embedData, attempt + 1)
            end
            return
        end

        -- Success
        if Config.debug then
            print("^2[DISCORD BOT]^0 Embed sent successfully")
        end
    end, 'POST', json.encode(data), headers)

    return true
end

-- Get bot avatar
local function GetBotAvatar(callback)
    local url = DISCORD_API .. "/users/@me"
    local headers = {
        ["Authorization"] = "Bot " .. Config.discord.botToken,
        ["Content-Type"] = "application/json"
    }
    
    PerformHttpRequest(url, function(err, text, headers)
        if err == 200 then
            local data = json.decode(text)
            if data and data.avatar and data.id then
                callback(string.format("https://cdn.discordapp.com/avatars/%s/%s.png", data.id, data.avatar))
                return
            end
        elseif Config.debug then
            print(("^1[DISCORD BOT]^0 Error fetching bot info (HTTP %s): %s"):format(err, text))
        end
        callback(nil)
    end, 'GET', "", headers)
end

-- Main thread
Citizen.CreateThread(function()
    -- Wait a moment to ensure everything is ready
    Citizen.Wait(3000)
    
    if Config.debug then
        print("^3[RESTART NOTIFIER]^0 Sending startup notification...")
    end

    local serverInfo = GetServerInfo()

    GetBotAvatar(function(avatarURL)
        local messageConfig = Config.message or {}
        local embed = {
            title = messageConfig.title or "🚀 Server Restart Complete",
            description = string.format("**%s**", messageConfig.onlineText),
            color = messageConfig.color or 65280, -- Default green
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {
                text = "Server Restart Notification",
                icon_url = avatarURL or (Config.discord.iconURL or "")
            }
        }

        -- Add thumbnail if server icon exists or fallback icon is configured
        if serverInfo.iconURL ~= "" or Config.discord.iconURL ~= "" then
            embed.thumbnail = { url = serverInfo.iconURL ~= "" and serverInfo.iconURL or Config.discord.iconURL }
        end

        -- Add banner if configured
        if Config.discord.bannerURL and Config.discord.bannerURL ~= "" then
            embed.image = { url = Config.discord.bannerURL }
        end

        SendDiscordEmbed(embed)
    end)
end)