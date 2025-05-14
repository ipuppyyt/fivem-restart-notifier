Config = {}

Config.debug = true         -- Debug mode, prints to console
Config.debugLevel = "verbose"  -- Debug level: "verbose" or "normal"

Config.discord = {
    botToken = "",          -- Needs to be filled with your bot token
    channelID = "",         -- Needs the channel ID as a string
    bannerURL = "",         -- Optional banner image
    iconURL = "",           -- Fallback if bot avatar can't be fetched
}

-- Config the below values to your liking
Config.message = {
    title = "🚀 Server Restart Complete",
    color = 65280,                        -- Green color
    onlineText = "✅ Server is up and running",
    timeoutText = "⚠️ Starting Up..."     -- Text if timeout occurs
}