-- ============================================================================
-- AUTO-LOOT COMPANION: WARBOT EDITION
-- ============================================================================
-- Author: Gemini AI & User Collaboration
-- Description: Makes a specific vanity pet walk to dead mobs and loot them.
-- ============================================================================

local CONFIG = {
    -- The Entry ID of the creature/pet that will perform the looting.
    -- Default: 34587 (Warbot)
    TARGET_PET_ID       = 34587, 
    
    -- Maximum distance (in yards) between the player and the corpse.
    -- If you are further than this, the pet will ignore the loot.
    MAX_LOOT_DISTANCE   = 60,   
    
    -- Distance (in yards) the pet must reach before the loot is "picked up."
    -- 2.5 is a safe range to ensure it fires without the pet getting stuck.
    ARRIVE_DISTANCE     = 2.5,
    
    -- If true, the pet loots while in a party (triggered by group kills).
    -- If false, the pet only loots when you are playing solo.
    LOOT_IN_PARTY       = true,  
}

-- Internal Index for Dynamic Flags (0x1 = Lootable/Sparkle)
local DYN_FLAGS_INDEX = 0x0006 + 0x0020

-- ============================================================================
-- THE HARVEST ENGINE
-- ============================================================================

local function HarvestLoot(eventId, delay, calls, player, victimGUID)
    local map = player:GetMap()
    if not map then return end
    
    local victim = map:GetWorldObject(victimGUID)
    if not victim then 
        player:RemoveEventById(eventId)
        return 
    end
    
    local unit = victim:ToUnit()
    if not unit or not unit:IsDead() then 
        player:RemoveEventById(eventId)
        return 
    end

    -- Attempt to find the pet (Check combat pet slot first, then vanity slot)
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

    -- Stop the script if the pet is dismissed or player moves too far
    if not pet or player:GetDistance(unit) > CONFIG.MAX_LOOT_DISTANCE then 
        player:RemoveEventById(eventId) 
        return 
    end

    -- Wait until pet is physically "on top" of the corpse
    if pet:GetDistance(unit) > CONFIG.ARRIVE_DISTANCE then 
        return 
    end

    -- Arrival reached: Stop the repeating timer
    player:RemoveEventById(eventId)

    local loot = unit:GetLoot()
    if not loot then return end

    -- 1. Process Money
    local copper = loot:GetMoney()
    if copper and copper > 0 then
        player:ModifyMoney(copper)
        loot:SetMoney(0) 
    end

    -- 2. Process Items
    local items = loot:GetItems()
    local itemsFetched = 0
    if items and #items > 0 then
        for _, itemData in ipairs(items) do
            local itemID = itemData.id 
            if itemID and itemID > 0 then
                player:AddItem(itemID, itemData.count or 1)
                itemsFetched = itemsFetched + 1
            end
        end
    end

    -- 3. Cleanup: Empty the loot container and clear sparkles
    if itemsFetched > 0 or (copper and copper > 0) then
        loot:Clear()
        unit:SetUInt32Value(DYN_FLAGS_INDEX, 0) 
        unit:AllLootRemovedFromCorpse()
    end
    
    -- Command pet to return to owner
    pet:MoveFollow(player)
end

-- ============================================================================
-- DETECTION HOOK
-- ============================================================================

local function OnGiveXP(event, player, amount, victim)
    if not victim or not player then return end

    -- Check configuration for Party/Solo mode
    if not CONFIG.LOOT_IN_PARTY and player:IsInGroup() then 
        return 
    end

    local pet = nil
    local hasTargetPet = false

    -- Check if the player currently has the Warbot summoned
    if player:IsExistPet() then
        local p = player:GetPet()
        if p and p:GetEntry() == CONFIG.TARGET_PET_ID then 
            pet = p 
            hasTargetPet = true 
        end
    end
    
    if not hasTargetPet then
        local critterGUID = player:GetCritterGUID()
        if critterGUID ~= 0 then
            local obj = player:GetMap():GetWorldObject(critterGUID)
            if obj then
                local u = obj:ToUnit()
                if u and u:GetEntry() == CONFIG.TARGET_PET_ID then 
                    pet = u 
                    hasTargetPet = true 
                end
            end
        end
    end

    -- If Warbot is present, initiate the fetch sequence
    if hasTargetPet and pet then
        -- Move pet to corpse location
        pet:MoveTo(1, victim:GetX(), victim:GetY(), victim:GetZ())
        
        -- Start arrival monitoring
        local vGUID = victim:GetGUID()
        player:RegisterEvent(function(eventId, delay, calls, p) 
            HarvestLoot(eventId, delay, calls, p, vGUID) 
        end, 200, 0)
    end
end

-- ============================================================================
-- REGISTRATION
-- ============================================================================
-- Player Event 12 = ON_GIVE_XP (Reliable for Solo and Party kills)
RegisterPlayerEvent(12, OnGiveXP) 

print(">> Auto-Loot Companion: Warbot Edition (34587) Loaded.")