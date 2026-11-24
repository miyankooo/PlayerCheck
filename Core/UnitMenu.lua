local _, ns = ...

local ENTRY_TEXT = "Armory Links"
local ENTRY_HELP = "Shows %s's armory links to copy, so you can see their gear and logs in your browser."

-- Every unit menu Forever opens on a player: "MENU_UNIT_" plus the name UnitPopup_OpenMenu receives.
local MENU_TAGS = {
    "MENU_UNIT_SELF",
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_RAID",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_FRIEND",
    "MENU_UNIT_FRIEND_OFFLINE",
    "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_PVP_SCOREBOARD",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
    "MENU_UNIT_RECENT_ALLY",
    "MENU_UNIT_RECENT_ALLY_OFFLINE",
}

-- Unit menus pass the name and surname apart. Chat, rosters and the scoreboard pass one joined name,
-- "First Surname" or the link form "First-Surname". Names hold no spaces or hyphens, so the first two
-- parts are the name and surname, and anything after them is dropped.
local function linksFor(name, surname, ruleset)
    if not name then
        return nil
    end
    local first, second = name:match("^([^%s%-]+)[%s%-]+([^%s%-]+)")
    if first then
        name, surname = first, second
    end
    local links = ns.Links(name, surname, ruleset)
    if links then
        return NameUtil.GetFullNameWithoutRealm(name, surname), links
    end
end

-- An NPC, such as a focused one, has no armory page. Every other menu shows a player from the player's own
-- world, so they share the player's ruleset.
local function readUnitPlayer(context)
    local unit = context.unit
    if unit and UnitExists(unit) and not UnitIsPlayer(unit) then
        return nil
    end
    return linksFor(context.name, context.surname, ns.Ruleset())
end

-- A Battle.net friend's menu carries the account, so the links need the WoW character they play in this
-- region. characterName may hold the joined name; otherwise the surname comes from the character's GUID. The
-- account says nothing of their ruleset, so only the sites that need none are offered.
local function readBNetPlayer(context)
    local info = context.bnetIDAccount and C_BattleNet.GetAccountInfoByID(context.bnetIDAccount)
    local game = info and info.gameAccountInfo
    if not game or game.clientProgram ~= BNET_CLIENT_WOW or not game.isInCurrentRegion then
        return nil
    end
    local surname = game.playerGuid and select(7, GetPlayerInfoByGUID(game.playerGuid))
    return linksFor(game.characterName, surname)
end

-- Blizzard's unit menus open with the player's name as their first element (UnitPopupShared.lua:112), so
-- the entry goes right under it.
local FIRST_ENTRY = 2

-- A name under identity restriction is a secret value, and any string operation on it throws, so the
-- read runs in pcall. canaccessvalue cannot guard it: it rejects secrets from tainted callers.
local function entryFrom(readPlayer)
    return function(_, root, context)
        local ok, displayName, links = pcall(readPlayer, context)
        if not ok or not links then
            return
        end
        -- Deferred so the menu closes before the dialog takes keyboard focus.
        local button = MenuUtil.CreateButton(ENTRY_TEXT, function()
            C_Timer.After(0, function()
                ns.ShowCopyDialog(displayName, links)
            end)
        end)
        button:SetTooltip(function(tooltip)
            GameTooltip_SetTitle(tooltip, ENTRY_TEXT)
            GameTooltip_AddNormalLine(tooltip, ENTRY_HELP:format(displayName))
        end)

        -- Insert is the description's own method that CreateButton appends with (Menu.lua:427), here given
        -- the index under the name. Menu.PopulateDescription runs this after Blizzard's generator, so the
        -- name is already in place. A menu that already has a divider under the name, such as a recent
        -- ally's (hasMainTitleDivider, UnitPopupShared.lua:133), gets no second one.
        root:Insert(MenuUtil.CreateTitle(ns.title), FIRST_ENTRY)
        root:Insert(button, FIRST_ENTRY + 1)
        if not context.hasMainTitleDivider then
            root:Insert(MenuUtil.CreateDivider(), FIRST_ENTRY + 2)
        end
    end
end

-- Group Finder listings get no entry: Blizzard_LFGVanilla_Browse.lua builds that menu without a tag.
local addUnitEntry = entryFrom(readUnitPlayer)
for _, tag in ipairs(MENU_TAGS) do
    Menu.ModifyMenu(tag, addUnitEntry)
end
Menu.ModifyMenu("MENU_UNIT_BN_FRIEND", entryFrom(readBNetPlayer))
