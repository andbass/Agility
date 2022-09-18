
AddCSLuaFile()

local cvars = {
    BulletEnable = CreateConVar("agility_bullet_enable", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Enables physical bullets for (most) SWEPS and HL2 weapons"),
    BulletNpcOnly = CreateConVar("agility_bullet_npc_only", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "If set to one, only NPCs will fire physical bullets"),
    BulletSlomoOnly = CreateConVar("agility_bullet_slomo_only", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "If set to one, physical bullets are only active in bullet-time"),
    BulletSpeed = CreateConVar("agility_bullet_speed", 5e3, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "The speed for bullet projectiles to use"),
    BulletGravity = CreateConVar("agility_bullet_gravity_enabled", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "If enabled, bullets will experience gravity"),
    BulletDebugDraw = CreateConVar("agility_bullet_debug_draw", 0, { FCVAR_CHEAT, FCVAR_REPLICATED }, "Enables the drawing of bullet paths. Must have 'developer 1' enabled as well"),
    BulletEnableDamageScale = CreateConVar("agility_bullet_headshots_enabled", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Enables custom damage scaling for bullets, essentially makes headshots do double damage"),

    PlayerDamageMultiplier = CreateConVar("agility_player_dmg_multiplier", 1.0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Scales the amount of damage that the player takes from bullets. Is applied even if projectile bullets are disabled"),
    NpcHealthMultiplier = CreateConVar("agility_npc_health_multiplier", 1.0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Scales the amount of health for spawned NPCs"),

    DisintegrateDroppedWeapons = CreateConVar("agility_disintegrate_dropped_wepaons", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "When NPCs die, their dropped weapons are disintegrated"),
    InfiniteBulletTime = CreateConVar("agility_infinite_slomo", 0, { FCVAR_CHEAT, FCVAR_REPLICATED }, "Disables bullet-time draining, granting you unlimited bullet-time"),
}

if CLIENT then
    table.Merge(cvars, {
        HideKillFeedInSP = CreateClientConVar("agility_cl_hide_killfeed_singleplayer", 1, true, false, "If non-zero, hides the killfeed in single player but keeps it on for multiplayer"),
    })
end

return cvars