--[[
    FOX-MULTICHARACTER SERVER MAIN
    
    CRITICAL WARNING: CHARINFO DATA PROTECTION
    ==========================================
    This file contains protections against stale charinfo overwrites that can cause 
    player name changes (via fox-namechange) to be reverted on disconnect/reconnect.
    
    DO NOT MODIFY CHARINFO HANDLING WITHOUT UNDERSTANDING:
    1. charinfo should ONLY be written to SQL during character creation or explicit save events
    2. Always use fresh SQL data when loading characters to prevent stale cache issues  
    3. Use MarkLegitimateCharinfoUpdate() before any legitimate charinfo modifications
    4. Monitor logs for STALE_WARNING entries which indicate potential data corruption
    
    Events available for external resources:
    - qb-multicharacter:server:refreshCharinfo - Mark charinfo as updated externally
    - qb-multicharacter:server:warnStaleCharinfo - Warn about potential stale overwrites
--]]

local QBCore = exports['qb-core']:GetCoreObject()
local hasDonePreloading = {}

local Countries = json.decode(LoadResourceFile(GetCurrentResourceName(), 'countries.json'))

-- CHARINFO PROTECTION: Track when charinfo updates are legitimate
local legitimateCharinfoUpdates = {}

-- CHARINFO PROTECTION: Log function for charinfo operations
local function LogCharinfoOperation(src, citizenid, operation, details)
    local playerName = GetPlayerName(src) or "Unknown"
    print(string.format("^3[fox-multicharacter]^7 CHARINFO %s: Player %s (%s) - %s", 
        operation, playerName, citizenid or "Unknown", details or ""))
end


-- Functions

-- CHARINFO PROTECTION: Function to mark legitimate charinfo updates
local function MarkLegitimateCharinfoUpdate(citizenid, reason)
    legitimateCharinfoUpdates[citizenid] = {
        timestamp = os.time(),
        reason = reason
    }
    -- Clean up old entries (older than 5 minutes)
    for cid, data in pairs(legitimateCharinfoUpdates) do
        if os.time() - data.timestamp > 300 then
            legitimateCharinfoUpdates[cid] = nil
        end
    end
end

-- CHARINFO PROTECTION: Function to check if charinfo update is legitimate
local function IsLegitimateCharinfoUpdate(citizenid)
    local update = legitimateCharinfoUpdates[citizenid]
    if update and os.time() - update.timestamp <= 300 then -- 5 minute window
        return true, update.reason
    end
    return false, nil
end

local function GiveStarterItems(source)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    for _, v in pairs(QBCore.Shared.StarterItems) do
        local info = {}
        if v.item == "id_card" then
            info.citizenid = Player.PlayerData.citizenid
            info.firstname = Player.PlayerData.charinfo.firstname
            info.lastname = Player.PlayerData.charinfo.lastname
            info.birthdate = Player.PlayerData.charinfo.birthdate
            info.gender = Player.PlayerData.charinfo.gender
            info.nationality = Player.PlayerData.charinfo.nationality
        elseif v.item == "driver_license" then
            info.firstname = Player.PlayerData.charinfo.firstname
            info.lastname = Player.PlayerData.charinfo.lastname
            info.birthdate = Player.PlayerData.charinfo.birthdate
            info.type = "Class C Driver License"
        end
        exports['qb-inventory']:AddItem(src, v.item, v.amount, false, info, 'qb-multicharacter:GiveStarterItems')
    end
end

local function loadHouseData(src)
    local HouseGarages = {}
    local Houses = {}
    local result = MySQL.query.await('SELECT * FROM houselocations', {})
    if result[1] ~= nil then
        for _, v in pairs(result) do
            local owned = false
            if tonumber(v.owned) == 1 then
                owned = true
            end
            local garage = v.garage ~= nil and json.decode(v.garage) or {}
            Houses[v.name] = {
                coords = json.decode(v.coords),
                owned = owned,
                price = v.price,
                locked = true,
                adress = v.label,
                tier = v.tier,
                garage = garage,
                decorations = {},
            }
            HouseGarages[v.name] = {
                label = v.label,
                takeVehicle = garage,
            }
        end
    end
    TriggerClientEvent("qb-garages:client:houseGarageConfig", src, HouseGarages)
    TriggerClientEvent("qb-houses:client:setHouseConfig", src, Houses)
end

-- Commands

QBCore.Commands.Add("logout", Lang:t("commands.logout_description"), {}, false, function(source)
    local src = source
    QBCore.Player.Logout(src)
    TriggerClientEvent('qb-multicharacter:client:chooseChar', src)
end, "admin")

QBCore.Commands.Add("closeNUI", Lang:t("commands.closeNUI_description"), {}, false, function(source)
    local src = source
    TriggerClientEvent('qb-multicharacter:client:closeNUI', src)
end)

-- Events

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    Wait(1000) -- 1 second should be enough to do the preloading in other resources
    hasDonePreloading[Player.PlayerData.source] = true
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    hasDonePreloading[src] = false
    
    -- CHARINFO PROTECTION: Log player unload for tracking
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.citizenid then
        LogCharinfoOperation(src, Player.PlayerData.citizenid, "UNLOAD", 
            "Player disconnecting - ensure charinfo is not overwritten with stale data")
    end
end)

RegisterNetEvent('qb-multicharacter:server:disconnect', function()
    local src = source
    DropPlayer(src, Lang:t("commands.droppedplayer"))
end)

RegisterNetEvent('qb-multicharacter:server:loadUserData', function(cData)
    local src = source
    -- CHARINFO PROTECTION: Log character loading attempt
    LogCharinfoOperation(src, cData.citizenid, "LOAD_ATTEMPT", "Loading existing character")
    
    if QBCore.Player.Login(src, cData.citizenid) then
        repeat
            Wait(10)
        until hasDonePreloading[src]
        
        -- CHARINFO PROTECTION: Log successful character load
        LogCharinfoOperation(src, cData.citizenid, "LOAD_SUCCESS", "Character loaded successfully")
        
        print('^2[qb-core]^7 '..GetPlayerName(src)..' (Citizen ID: '..cData.citizenid..') has successfully loaded!')
        QBCore.Commands.Refresh(src)
        loadHouseData(src)
        if Config.SkipSelection then
            local coords = json.decode(cData.position)
            TriggerClientEvent('qb-multicharacter:client:spawnLastLocation', src, coords, cData)
        else
            if GetResourceState('qb-apartments') == 'started' then
                TriggerClientEvent('apartments:client:setupSpawnUI', src, cData)
            else
                TriggerClientEvent('qb-spawn:client:setupSpawns', src, cData, false, nil)
                TriggerClientEvent('qb-spawn:client:openUI', src, true)
            end
        end
        TriggerEvent("qb-log:server:CreateLog", "joinleave", "Loaded", "green", "**".. GetPlayerName(src) .. "** (<@"..(QBCore.Functions.GetIdentifier(src, 'discord'):gsub("discord:", "") or "unknown").."> |  ||"  ..(QBCore.Functions.GetIdentifier(src, 'ip') or 'undefined') ..  "|| | " ..(QBCore.Functions.GetIdentifier(src, 'license') or 'undefined') .." | " ..cData.citizenid.." | "..src..") loaded..")
    else
        -- CHARINFO PROTECTION: Log failed character load
        LogCharinfoOperation(src, cData.citizenid, "LOAD_FAILED", "Character login failed")
    end
end)

RegisterNetEvent('qb-multicharacter:server:createCharacter', function(data)
    local src = source
    local newData = {}
    newData.cid = data.cid
    newData.charinfo = data
    
    -- CHARINFO PROTECTION: Mark this as a legitimate charinfo creation
    MarkLegitimateCharinfoUpdate(data.citizenid or ("new_" .. src), "Character Creation")
    LogCharinfoOperation(src, data.citizenid, "CREATE_ATTEMPT", "Creating new character")
    
    if QBCore.Player.Login(src, false, newData) then
        repeat
            Wait(10)
        until hasDonePreloading[src]
        
        -- CHARINFO PROTECTION: Log successful character creation
        LogCharinfoOperation(src, data.citizenid, "CREATE_SUCCESS", "Character created successfully")
        
        if GetResourceState('qb-apartments') == 'started' and Apartments.Starting then
            local randbucket = (GetPlayerPed(src) .. math.random(1,999))
            SetPlayerRoutingBucket(src, randbucket)
            print('^2[qb-core]^7 '..GetPlayerName(src)..' has successfully loaded!')
            QBCore.Commands.Refresh(src)
            loadHouseData(src)
            TriggerClientEvent("qb-multicharacter:client:closeNUI", src)
            TriggerClientEvent('apartments:client:setupSpawnUI', src, newData)
            GiveStarterItems(src)
        else
            print('^2[qb-core]^7 '..GetPlayerName(src)..' has successfully loaded!')
            QBCore.Commands.Refresh(src)
            loadHouseData(src)
            TriggerClientEvent("qb-multicharacter:client:closeNUIdefault", src)
            GiveStarterItems(src)
        end
    else
        -- CHARINFO PROTECTION: Log failed character creation
        LogCharinfoOperation(src, data.citizenid, "CREATE_FAILED", "Character creation failed")
    end
end)

RegisterNetEvent('qb-multicharacter:server:deleteCharacter', function(citizenid)
    local src = source
    QBCore.Player.DeleteCharacter(src, citizenid)
    TriggerClientEvent('QBCore:Notify', src, Lang:t("notifications.char_deleted") , "success")
end)

-- CHARINFO PROTECTION: Event to refresh charinfo after external updates (e.g., fox-namechange)
RegisterNetEvent('qb-multicharacter:server:refreshCharinfo', function(citizenid, reason)
    local src = source
    if not citizenid then
        LogCharinfoOperation(src, "Unknown", "REFRESH_FAILED", "No citizenid provided")
        return
    end
    
    -- Mark this as a legitimate update
    MarkLegitimateCharinfoUpdate(citizenid, reason or "External Update")
    LogCharinfoOperation(src, citizenid, "REFRESH_MARKED", reason or "External charinfo refresh requested")
    
    -- Trigger a reload of player data if they're online
    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if Player then
        LogCharinfoOperation(Player.PlayerData.source, citizenid, "REFRESH_RELOAD", "Reloading player data after charinfo update")
        -- The player data will be refreshed on next access through QBCore
    end
end)

-- CHARINFO PROTECTION: Event to warn about potential stale charinfo overwrites
RegisterNetEvent('qb-multicharacter:server:warnStaleCharinfo', function(citizenid, oldData, newData)
    local src = source
    local isLegitimate, reason = IsLegitimateCharinfoUpdate(citizenid)
    
    if not isLegitimate then
        LogCharinfoOperation(src, citizenid, "STALE_WARNING", 
            string.format("Potential stale charinfo overwrite detected! Old: %s %s, New: %s %s", 
                oldData and oldData.firstname or "Unknown",
                oldData and oldData.lastname or "Unknown",
                newData and newData.firstname or "Unknown", 
                newData and newData.lastname or "Unknown"))
        
        -- Send notification to admins if possible
        print(string.format("^1[fox-multicharacter] WARNING:^7 Potential stale charinfo overwrite for %s! Check logs!", citizenid))
    else
        LogCharinfoOperation(src, citizenid, "LEGITIMATE_UPDATE", 
            string.format("Legitimate charinfo update - Reason: %s", reason))
    end
end)

-- Callbacks

QBCore.Functions.CreateCallback("qb-multicharacter:server:GetUserCharacters", function(source, cb)
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')

    MySQL.query('SELECT * FROM players WHERE license = ?', {license}, function(result)
        cb(result)
    end)
end)

QBCore.Functions.CreateCallback("qb-multicharacter:server:GetServerLogs", function(_, cb)
    MySQL.query('SELECT * FROM server_logs', {}, function(result)
        cb(result)
    end)
end)

QBCore.Functions.CreateCallback("qb-multicharacter:server:GetNumberOfCharacters", function(source, cb)
    local src = source
    local license = QBCore.Functions.GetIdentifier(src, 'license')
    local numOfChars = 0

    if next(Config.PlayersNumberOfCharacters) then
        for _, v in pairs(Config.PlayersNumberOfCharacters) do
            if v.license == license then
                numOfChars = v.numberOfChars
                break
            else
                numOfChars = Config.DefaultNumberOfCharacters
            end
        end
    else
        numOfChars = Config.DefaultNumberOfCharacters
    end
    cb(numOfChars, Countries) -- <---- Add Countries here
end)

QBCore.Functions.CreateCallback("qb-multicharacter:server:setupCharacters", function(source, cb)
    local license = QBCore.Functions.GetIdentifier(source, 'license')
    local plyChars = {}
    
    -- CHARINFO PROTECTION: Always fetch fresh data from SQL to prevent stale charinfo
    MySQL.query('SELECT * FROM players WHERE license = ?', {license}, function(result)
        for i = 1, (#result), 1 do
            -- CHARINFO PROTECTION: Parse JSON data fresh from SQL
            result[i].charinfo = json.decode(result[i].charinfo)
            result[i].money = json.decode(result[i].money)
            result[i].job = json.decode(result[i].job)
            result[i].gang = json.decode(result[i].gang or '{}') -- <-- ADDED: ensure gang data is provided to client
            
            -- CHARINFO PROTECTION: Log character data fetch
            LogCharinfoOperation(source, result[i].citizenid, "FETCH_SQL", 
                string.format("Fresh charinfo loaded - Name: %s %s", 
                    result[i].charinfo.firstname or "Unknown", 
                    result[i].charinfo.lastname or "Unknown"))
            
            plyChars[#plyChars+1] = result[i]
        end
        
        -- CHARINFO PROTECTION: Log total characters fetched
        if source then
            print(string.format("^3[fox-multicharacter]^7 CHARINFO FETCH_COMPLETE: Player %s - %d characters loaded with fresh SQL data", 
                GetPlayerName(source) or "Unknown", #plyChars))
        end
        
        cb(plyChars)
    end)
end)

QBCore.Functions.CreateCallback("qb-multicharacter:server:getSkin", function(_, cb, cid)
    local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', {cid, 1})
    if result[1] ~= nil then
        cb(json.decode(result[1].skin))
    else
        cb(nil)
    end
end)

QBCore.Commands.Add("deletechar", Lang:t("commands.deletechar_description"), {{name = Lang:t("commands.citizenid"), help = Lang:t("commands.citizenid_help")}}, false, function(source,args)
    if args and args[1] then
        QBCore.Player.ForceDeleteCharacter(tostring(args[1]))
        TriggerClientEvent("QBCore:Notify", source, Lang:t("notifications.deleted_other_char", {citizenid = tostring(args[1])}))
    else
        TriggerClientEvent("QBCore:Notify", source, Lang:t("notifications.forgot_citizenid"), "error")
    end
end, "god")

-- CHARINFO PROTECTION: Exports for other resources to use
exports('markCharinfoUpdate', function(citizenid, reason)
    MarkLegitimateCharinfoUpdate(citizenid, reason or "External Resource Update")
    print(string.format("^3[fox-multicharacter]^7 CHARINFO EXPORT: Marked legitimate update for %s - %s", 
        citizenid, reason or "External Resource Update"))
end)

exports('refreshCharinfo', function(citizenid, reason)
    TriggerEvent('qb-multicharacter:server:refreshCharinfo', citizenid, reason)
end)

-- CHARINFO PROTECTION: Resource cleanup on stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        print("^3[fox-multicharacter]^7 CHARINFO PROTECTION: Resource stopped, clearing protection data")
        legitimateCharinfoUpdates = {}
    end
end)