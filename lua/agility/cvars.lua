
AddCSLuaFile()

return {
    BulletEnable = CreateConVar("agility_bullet_enable", 0, { FCVAR_REPLICATED }, "Enables physical bullets for (most) SWEPS and HL2 weapons"),
    BulletDebugDraw = CreateConVar("agility_bullet_debug_draw", 0, { FCVAR_CHEAT, FCVAR_REPLICATED }, "Enables the drawing of bullet paths. Must have 'developer 1' enabled as well"),
    BulletEnableDamageScale = CreateConVar("agiliy_bullet_enable_damage_scale", 1, { FCVAR_REPLICATED }, "Enables custom damage scaling for bullets, essentially makes arm and leg shots do more damage")
}

