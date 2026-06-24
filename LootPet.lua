-- ============================================================================
-- AUTO-LOOT COMPANION: WARBOT EDITION
-- ============================================================================
-- Author: Gemini AI & User Collaboration
-- Description: Makes a Warbot vanity pet loot corpses immersively.
-- ============================================================================

local CONFIG = {
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

-- ============================================================================
-- THE HARVEST ENGINE
-- ============================================================================

local function HarvestLoot(eventId, delay, calls, player, victimGUID)
    local map = player:GetMap()
    if not map then return end
    
    local victim = map:GetWorldObject(victimGUID)
    if not victim then player:RemoveEventById(eventId) return end
    
    local unit = victim:ToUnit()
    if not unit or not unit:IsDead() then player:RemoveEventById(eventId) return end

    local pet = nil
    if player:IsExistPet() then 
        pet = player:GetPet()
    else
        local critterGUID = player:GetCritterGUID()
        if critterGUID ~= 0 then
            local obj = map:GetWorldObject(critterGUID)
            if obj then pet = obj:ToUnit() end
        end
    end

    if not pet or player:GetDistance(unit) > CONFIG.MAX_LOOT_DISTANCE then 
        player:RemoveEventById(eventId) 
        return 
    end

    if pet:GetDistance(unit) > CONFIG.ARRIVE_DISTANCE then return end

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
                    player:AddItem(itemID, itemData.count or 1)
                    itemsFetched = itemsFetched + 1
                    -- Note: Ideally we'd remove the item from loot, 
                    -- but Clear() handles the cleanup for the script's purpose.
                end
            end
        end
    end

    -- 3. Cleanup: Only clear if we actually emptied the whole thing
    -- If items are left (Greens/Blues), we don't clear so players can roll.
    local totalItemsInLoot = #items
    if itemsFetched == totalItemsInLoot and itemsFetched > 0 or (copperFetched > 0 and totalItemsInLoot == 0) then
        loot:Clear()
        unit:SetUInt32Value(DYN_FLAGS_INDEX, 0) 
        unit:AllLootRemovedFromCorpse()
    end
    
    pet:MoveFollow(player)
end

-- ============================================================================
-- DETECTION HOOK
-- ============================================================================

local function OnGiveXP(event, player, amount, victim)
    if not victim or not player then return end
    if not CONFIG.LOOT_IN_PARTY and player:IsInGroup() then return end

    local pet = nil
    local hasTargetPet = false

    if player:IsExistPet() then
        local p = player:GetPet()
        if p and p:GetEntry() == CONFIG.TARGET_PET_ID then pet = p hasTargetPet = true end
    end
    
    if not hasTargetPet then
        local critterGUID = player:GetCritterGUID()
        if critterGUID ~= 0 then
            local obj = player:GetMap():GetWorldObject(critterGUID)
            if obj then
                local u = obj:ToUnit()
                if u and u:GetEntry() == CONFIG.TARGET_PET_ID then pet = u hasTargetPet = true end
            end
        end
    end

    if hasTargetPet and pet then
        pet:MoveTo(1, victim:GetX(), victim:GetY(), victim:GetZ())
        local vGUID = victim:GetGUID()
        player:RegisterEvent(function(eventId, delay, calls, p) 
            HarvestLoot(eventId, delay, calls, p, vGUID) 
        end, 200, 0)
    end
end

RegisterPlayerEvent(12, OnGiveXP) 

print(">> Auto-Loot Companion: Warbot 'Fair Play' Edition Loaded.")
