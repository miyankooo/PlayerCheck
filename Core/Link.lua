local _, ns = ...

-- The regions Forever runs in. China has no Forever characters on any of these sites, so a CN client gets no
-- entry instead of dead links.
local REGIONS = {
    US = "us",
    EU = "eu",
    KR = "kr",
    TW = "tw",
}

-- Each site's character page, in the order the dialog lists them. {region} and {ruleset} take the site's own
-- slug, {name} and {surname} the encoded name parts. A site with a regions table covers only those; a site with
-- a rulesets table needs the player's ruleset. Every site matches names in any case, checked in Chrome on
-- 2026-11-24 with characters on each ruleset in the US, EU, Korea and Taiwan.
ns.SITES = {
    {
        name = "Armory",
        help = "Blizzard's own page: gear with item level, PvP and reputations.",
        url = "https://worldofwarcraft.blizzard.com/forever/{region}/armory/character/{name}-{surname}",
    },
    {
        name = "Raider.IO",
        help = "Profile, gear and leveling history.",
        url = "https://forever.raider.io/characters/{region}/{ruleset}/{name}%20{surname}",
        rulesets = { normal = "normal", pvp = "pvp", rp = "rp", rppvp = "pvp-rp" },
    },
    {
        name = "Warcraft Logs",
        help = "Raid logs and rankings, for characters seen in an uploaded log.",
        url = "https://forever.warcraftlogs.com/character/{region}/{ruleset}/{name}%20{surname}",
        rulesets = { normal = "normal", pvp = "pvp", rp = "roleplay", rppvp = "roleplay-pvp" },
    },
    {
        name = "Armory WoW Forever",
        help = "Gear with gems and enchants, gearscore, item level and talents.",
        url = "https://armorywowforever.com/c/forever/{region}/{ruleset}/{name}-{surname}",
        regions = { US = "us", EU = "eu" },
        rulesets = { normal = "normal", pvp = "pvp", rp = "rp", rppvp = "pvp_rp" },
    },
    {
        name = "aotc.gg",
        help = "Gear score and leaderboard ranks, for characters it has scanned.",
        url = "https://www.aotc.gg/forever/character/{region}/{name}-{surname}",
    },
}

-- The ruleset of the player's own world, which every player in it shares. Hardcore has no page on these sites.
function ns.Ruleset()
    local rule = Enum.GameRule
    if C_GameRules.IsGameRuleActive(rule.HardcoreRuleset) then
        return nil
    end
    local pvp = C_GameRules.IsGameRuleActive(rule.PvPRuleset)
    if C_GameRules.IsGameRuleActive(rule.RPRuleset) then
        return pvp and "rppvp" or "rp"
    end
    return pvp and "pvp" or "normal"
end

-- The sites match names in any case, so lower() only folds ASCII. Every other byte is percent-encoded, so
-- Cyrillic, Hangul and Hanzi names give a valid URL.
local function slug(namePart)
    return (namePart:lower():gsub("[^%w]", function(char)
        return ("%%%02X"):format(char:byte())
    end))
end

-- Every link the player's region and the known ruleset allow, as { site = site, url = url } in SITES order. nil
-- without a surname or a link, so the caller drops the entry instead of offering dead links. A nil ruleset keeps
-- only the sites that need none.
function ns.Links(name, surname, ruleset)
    if not surname or surname == "" then
        return nil
    end
    local regionName = GetCurrentRegionName()
    local values = { name = slug(name), surname = slug(surname) }
    local links = {}
    for _, site in ipairs(ns.SITES) do
        values.region = (site.regions or REGIONS)[regionName]
        values.ruleset = site.rulesets and site.rulesets[ruleset]
        if values.region and (values.ruleset or not site.rulesets) then
            links[#links + 1] = { site = site, url = (site.url:gsub("{(%a+)}", values)) }
        end
    end
    return links[1] and links or nil
end
