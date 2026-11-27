local addonName, ns = ...

-- The addon has no window or settings page: its one surface is its entry on player menus. So the welcome
-- line has no link; it says what the addon does, where to start and where the commands are. The help line
-- opens with the same where-to-start sentence.
local START = "Right-click a player's portrait or chat name and pick PlayerCheck."
local WELCOME = "Shows links to any player's gear, logs and rankings, ready to copy into your browser. " .. START
    .. " Type /pc help for the commands."
local HELP = START .. " Type /pc intro to see the welcome line again, or /pc help for this list."
local UNKNOWN = "Unknown command. Type /pc help for the list."

-- No saved table yet means the account's first login with the addon. The table holds only the dialog's
-- Close After Copying choice; the addon has no help tip whose flag it would hold.
local firstRun = false

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    firstRun = PlayerCheckDB == nil
    PlayerCheckDB = PlayerCheckDB or {}
end)

-- At login the client's own load lines are already in chat.
EventUtil.ContinueOnPlayerLogin(function()
    if firstRun then
        ns.Print(WELCOME)
    end
end)

-- With nothing to open, the bare command prints the help line. intro replays the welcome line; there is no
-- tip flag to clear.
SLASH_PLAYERCHECK1, SLASH_PLAYERCHECK2 = "/playercheck", "/pc"
SlashCmdList.PLAYERCHECK = function(message)
    local command = strtrim(message or ""):lower()
    if command == "" or command == "help" or command == "?" then
        ns.Print(HELP)
    elseif command == "intro" then
        ns.Print(WELCOME)
    else
        ns.Print(UNKNOWN)
    end
end
