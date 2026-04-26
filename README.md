# Eluna Auto-Loot Companion (Warbot Edition)

An immersive auto-loot script for AzerothCore (Eluna) that turns your vanity pet into a functional looting companion. 

## Features
* **Immersive Movement**: The pet physically walks to the corpse to "retrieve" loot.
* **Party Aware**: Configurable support for solo play or group/bot party play.
* **Smart Detection**: Hooks into XP gains to ensure looting triggers even if you don't land the killing blow.
* **Clean Cleanup**: Automatically clears corpse sparkles and loot data once the pet finishes. (BUGGED FOR NOW)

## Requirements:
- Azerothcore
- Azerothcore ALE

## Configuration
Open `LootPet.lua` to adjust:
- `TARGET_PET_ID`: The Entry ID of the pet (Default: 34587 - Warbot), summoned from item 46767
- `MAX_LOOT_DISTANCE`: How far the pet is willing to travel.
- `LOOT_IN_PARTY`: Toggle whether the pet loots while you are in a group.

## Installation
1. Place `LootPet.lua` into your server's `lua_scripts` folder.
2. Restart the server or type `.reload ale` ingame.
3. Summon your Warbot and start hunting!
