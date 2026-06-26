-- ============================================================================
-- AUTO-LOOT COMPANION: WARBOT EDITION
-- ============================================================================
-- Author: Gemini AI & User Collaboration
-- Description: Makes a Warbot vanity pet loot corpses immersively.
-- ============================================================================

local CONFIG = {
    -- mirror mod-junk-to-gold for Lua pet-looted grey items.
    JUNK_TO_GOLD_COMPAT = true,

    -- Mirror mod-quest-loot-party for pet-looted normal-quality quest items.
    QUEST_LOOT_PARTY_COMPAT = true,

    -- The Entry ID of the pet (34587 = Warbot).
    TARGET_PET_ID       = 34587,

    -- Max distance between player and corpse for pet to trigger.
    MAX_LOOT_DISTANCE   = 60,

    -- Distance pet must reach to "loot" the body.
    ARRIVE_DISTANCE     = 2.5,

    -- Party Settings
    LOOT_IN_PARTY       = true,  -- If true, pet loots during group play.

    -- RARITY FILTER (Party Only)
    -- When in a group, the pet will ONLY loot items of this quality or lower.
    -- 0 = Poor (Grey), 1 = Normal (White), 2 = Uncommon (Green), etc.
    -- Default 1 ensures it leaves Greens+ for the group roll.
    MAX_QUALITY_IN_PARTY = 1,
}

local DYN_FLAGS_INDEX = 0x0006 + 0x0049
local QUEST_STATUS_INCOMPLETE = 3
local pendingHarvests = {}
local questItemRequirements = {}

local function IsWorldObject(obj)
    return obj and type(obj) == "userdata" and pcall(obj.GetGUID, obj)
end

local function HarvestKey(player, victim)
    return tostring(player:GetGUID()) .. ":" .. tostring(victim:GetGUID())
end

local function GetTargetPet(player)
    local map = player:GetMap()
    if not map then return nil end

    if player:IsExistPet() then
        local pet = player:GetPet()
        if pet and pet:GetEntry() == CONFIG.TARGET_PET_ID then return pet end
    end

    local critterGUID = player:GetCritterGUID()
    if critterGUID ~= 0 then
        local obj = map:GetWorldObject(critterGUID)
        if obj then
            local pet = obj:ToUnit()
            if pet and pet:GetEntry() == CONFIG.TARGET_PET_ID then return pet end
        end
    end

    return nil
end

local function CountLootEntries(loot)
    local items = loot:GetItems()
    local questItems = loot:GetQuestItems()
    return (items and #items or 0) + (questItems and #questItems or 0)
end

local function GetQuestRequirementsForItem(itemID)
    if questItemRequirements[itemID] ~= nil then
        return questItemRequirements[itemID]
    end

    local requirements = {}
    local query = WorldDBQuery(string.format([[
        SELECT
            `ID`,
            CASE
                WHEN `RequiredItemId1` = %d THEN `RequiredItemCount1`
                WHEN `RequiredItemId2` = %d THEN `RequiredItemCount2`
                WHEN `RequiredItemId3` = %d THEN `RequiredItemCount3`
                WHEN `RequiredItemId4` = %d THEN `RequiredItemCount4`
                WHEN `RequiredItemId5` = %d THEN `RequiredItemCount5`
                WHEN `RequiredItemId6` = %d THEN `RequiredItemCount6`
                ELSE 0
            END
        FROM `quest_template`
        WHERE `RequiredItemId1` = %d
           OR `RequiredItemId2` = %d
           OR `RequiredItemId3` = %d
           OR `RequiredItemId4` = %d
           OR `RequiredItemId5` = %d
           OR `RequiredItemId6` = %d
    ]], itemID, itemID, itemID, itemID, itemID, itemID,
        itemID, itemID, itemID, itemID, itemID, itemID))

    if query then
        repeat
            local questID = query:GetUInt32(0)
            local requiredCount = query:GetUInt32(1)
            if questID and questID > 0 and requiredCount and requiredCount > 0 then
                requirements[#requirements + 1] = { questID = questID, requiredCount = requiredCount }
            end
        until not query:NextRow()
    end

    questItemRequirements[itemID] = requirements
    return requirements
end

local function GetNeededQuestItemCount(player, itemID, count)
    local requirements = GetQuestRequirementsForItem(itemID)
    if not requirements or #requirements == 0 then return 0 end

    local currentCount = player:GetItemCount(itemID, true)
    local neededCount = 0

    for _, requirement in ipairs(requirements) do
        if player:GetQuestStatus(requirement.questID) == QUEST_STATUS_INCOMPLETE then
            local missingCount = requirement.requiredCount - currentCount
            if missingCount > neededCount then
                neededCount = missingCount
            end
        end
    end

    if neededCount <= 0 then return 0 end
    if count and count > 0 and neededCount > count then return count end
    return neededCount
end

local function GetEligibleQuestLootPartyMembers(player, victim, itemID, count)
    local members = {}
    if not player:IsInGroup() then return members end
    local playerGUID = tostring(player:GetGUID())

    local group = player:GetGroup()
    if not group then return members end

    local groupMembers = group:GetMembers()
    if not groupMembers then return members end

    for _, member in ipairs(groupMembers) do
        if member and tostring(member:GetGUID()) ~= playerGUID and member:IsAtGroupRewardDistance(victim) then
            local neededCount = GetNeededQuestItemCount(member, itemID, count)
            if neededCount > 0 then
                members[#members + 1] = { player = member, count = neededCount }
            end
        end
    end

    return members
end

local function ResolveLootingPlayer(killer, victim)
    if not IsWorldObject(killer) or not IsWorldObject(victim) then return nil end
    if GetTargetPet(killer) then return killer end
    if not killer:IsInGroup() then return nil end

    local group = killer:GetGroup()
    if not group then return nil end

    local members = group:GetMembers()
    if not members then return nil end

    for _, member in ipairs(members) do
        if member and not member:IsBot() and member:IsAtGroupRewardDistance(victim) and GetTargetPet(member) then
            return member
        end
    end

    for _, member in ipairs(members) do
        if member and member:IsAtGroupRewardDistance(victim) and GetTargetPet(member) then
            return member
        end
    end

    return nil
end

-- ============================================================================
-- THE HARVEST ENGINE
-- ============================================================================

local function HarvestLoot(eventId, delay, calls, player, victimGUID, harvestKey)
    local map = player:GetMap()
    if not map then
        pendingHarvests[harvestKey] = nil
        player:RemoveEventById(eventId)
        return
    end

    local victim = map:GetWorldObject(victimGUID)
    if not victim then
        pendingHarvests[harvestKey] = nil
        player:RemoveEventById(eventId)
        return
    end

    local unit = victim:ToUnit()
    if not unit or not unit:IsDead() then
        pendingHarvests[harvestKey] = nil
        player:RemoveEventById(eventId)
        return
    end

    local pet = GetTargetPet(player)

    if not pet or player:GetDistance(unit) > CONFIG.MAX_LOOT_DISTANCE then
        pendingHarvests[harvestKey] = nil
        player:RemoveEventById(eventId)
        return
    end

    if pet:GetDistance(unit) > CONFIG.ARRIVE_DISTANCE then return end

    pendingHarvests[harvestKey] = nil
    player:RemoveEventById(eventId)

    local loot = unit:GetLoot()
    if not loot then return end

    local inGroup = player:IsInGroup()
    local copperFetched = 0
    local itemsFetched = 0

    -- 1. Process Money (Always loot money)
    local copper = loot:GetMoney()
    if copper and copper > 0 then
        player:ModifyMoney(copper)
        loot:SetMoney(0)
        copperFetched = copper
    end

    -- 2. Process Items
    local items = loot:GetItems()
    if items and #items > 0 then
        for _, itemData in ipairs(items) do
            local itemID = itemData.id
            if itemID and itemID > 0 then
                local itemTemplate = GetItemTemplate(itemID)
                local quality = itemTemplate and itemTemplate:GetQuality() or 0

                -- Check if we should loot this item based on party status
                local shouldLoot = true
                if inGroup and quality > CONFIG.MAX_QUALITY_IN_PARTY then
                    shouldLoot = false
                end

                if shouldLoot then
                    local count = itemData.count or 1
                    local looted = false
                    if CONFIG.JUNK_TO_GOLD_COMPAT and quality == 0 then
                        local sellPrice = itemTemplate and itemTemplate:GetSellPrice() or 0
                        player:ModifyMoney(sellPrice * count)
                        looted = true
                    else
                        looted = player:AddItem(itemID, count) ~= nil
                    end

                    if looted then
                        loot:RemoveItem(itemID, true, count)
                        itemsFetched = itemsFetched + 1
                    end
                end
            end
        end
    end

    -- Process Quest Items (e.g., Red Burlap Bandana)
    local questItems = loot:GetQuestItems()
    if questItems and #questItems > 0 then
        for _, itemData in ipairs(questItems) do
            local itemID = itemData.id
            if itemID and itemID > 0 then
                local count = itemData.count or 1
                local itemTemplate = GetItemTemplate(itemID)
                local quality = itemTemplate and itemTemplate:GetQuality() or 0
                local partyMembers = {}

                if CONFIG.QUEST_LOOT_PARTY_COMPAT and inGroup and quality == 1 then
                    partyMembers = GetEligibleQuestLootPartyMembers(player, unit, itemID, count)
                end

                if player:AddItem(itemID, count) ~= nil then
                    for _, memberData in ipairs(partyMembers) do
                        memberData.player:AddItem(itemID, memberData.count)
                    end

                    loot:RemoveItem(itemID, true, count)
                    itemsFetched = itemsFetched + 1
                end
            end
        end
    end

    if itemsFetched > 0 then
        loot:UpdateItemIndex()
        loot:SetUnlootedCount(CountLootEntries(loot))
    end

    -- Cleanup only when the pet removed every remaining item. Higher-quality
    -- party loot stays on the corpse for normal group rolling/manual looting.
    if loot:IsLooted() or loot:IsEmpty() then
        loot:Clear()
        unit:SetUInt32Value(DYN_FLAGS_INDEX, 0)
        unit:AllLootRemovedFromCorpse()
    end

    pet:MoveFollow(player)
end

-- ============================================================================
-- DETECTION HOOK
-- ============================================================================

local function QueueHarvest(player, victim)
    if not victim or not player then return end
    if not IsWorldObject(player) or not IsWorldObject(victim) then return end
    if not CONFIG.LOOT_IN_PARTY and player:IsInGroup() then return end

    local lootingPlayer = ResolveLootingPlayer(player, victim)
    if not lootingPlayer then return end

    local pet = GetTargetPet(lootingPlayer)
    if not pet then return end

    local key = HarvestKey(lootingPlayer, victim)
    if pendingHarvests[key] then return end
    pendingHarvests[key] = true

    pet:MoveTo(1, victim:GetX(), victim:GetY(), victim:GetZ())
    local vGUID = victim:GetGUID()
    lootingPlayer:RegisterEvent(function(eventId, delay, calls, p)
        HarvestLoot(eventId, delay, calls, p, vGUID, key)
    end, 200, 0)
end

local function OnKillCreature(event, player, victim)
    QueueHarvest(player, victim)
end

local function OnGiveXP(event, player, amount, victim)
    QueueHarvest(player, victim)
    return amount
end

RegisterPlayerEvent(7, OnKillCreature)
RegisterPlayerEvent(12, OnGiveXP)

print(">> Auto-Loot Companion: Warbot 'Fair Play' Edition Loaded.")
