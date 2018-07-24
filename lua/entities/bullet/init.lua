
include "agility/util.lua"

AddCSLuaFile "shared.lua"
AddCSLuaFile "cl_init.lua"

include "shared.lua"
include "impactEffects.lua"

local cvar = include "agility/cvars.lua"

function ENT:Initialize()
    self.StartTime = CurTime()

    self:SetModel("models/weapons/w_bullet.mdl")
    self:SetModelScale(2.0)

    self:PhysicsInitSphere(0.25, "metal")
    self:SetCollisionGroup(COLLISION_GROUP_WORLD)

    self.Phys = self:GetPhysicsObject()
    if self.Phys:IsValid() then
        self.Phys:SetMass(1)
        self.Phys:EnableDrag(false)

        self.Phys:Wake()
    end
end

function ENT:SetAttacker(attacker)
    self.Attacker = attacker
    
    self:SetOwner(attacker)
    self:SetShooter(attacker) -- used for networking purposes

    self.OldPos = self.Attacker:EyePos()
end

function ENT:SetDirection(dir)
    self.Direction = dir

    self:SetAngles(dir:Angle())
    self.Phys:SetVelocity(dir * self.InitialSpeed)
end

function ENT:GetVelDir()
    return self:GetVelocity():GetNormalized()
end

function ENT:Expired()
    return CurTime() > self.StartTime + self.LifeTime
end

function ENT:Impact()
    self.Impacted = true

    self:SetRenderMode(RENDERMODE_NONE)
    self:PhysicsDestroy()

    self:NextThink(CurTime())
end

function ENT:ImpactData(dir)
    local oldPos = self.OldPos
    local curPos = self:GetPos()

    local start = oldPos
    local endpos = curPos + dir * 10

    if cvar.BulletDebugDraw:GetBool() then
        debugoverlay.Line(start, endpos, self.LifeTime, Color(0, 255, 0))
    end

    return util.TraceLine {
        start = start,
        endpos = endpos,
        filter = { self, self.Attacker },
        mask = MASK_SHOT,
    }
end

function ENT:Think()
    if not IsValid(self.Attacker) or self.Impacted or self:Expired() then
        self:Remove()
    end
end

function ENT:Damage(target, vel)
    local dmg = DamageInfo()
    local speed = vel:Length()
    local dir = vel:GetNormalized()

    -- During more extensive NPC/Player collision checks in `PhysicsUpdate`, 
    -- we cache the computed impact data
    local impactData = self.CurImpactData

    --
    -- TODO have this set by hook
    --
    dmg:SetDamageType(DMG_BULLET)
    dmg:SetDamage(speed * 0.5e-2 * self.Multipliers.Damage)
    dmg:SetDamageForce(self.Direction * speed * self.Multipliers.Force)

    dmg:SetDamagePosition(impactData.HitPos)
    dmg:SetReportedPosition(impactData.HitPos)

    if IsValid(self.Weapon) then
        dmg:SetInflictor(self.Weapon)
    end

    if IsValid(self.Attacker) then
        dmg:SetAttacker(self.Attacker)
    end

    if not self.Attacker:IsNPC() then
        if target:IsNPC() then
            hook.Run("ScaleNPCDamage", impactData.Entity, impactData.HitGroup, dmg)
        elseif target:IsPlayer() then
            hook.Run("ScalePlayerDamage", impactData.Entity, impactData.HitGroup, dmg)
        end
    end

    target:TakeDamageInfo(dmg)

    self:CreateImpactEffects(impactData)

    if impactData.Entity:IsPlayer() or impactData.Entity:IsNPC() then
        self:Impact()

        if impactData.Entity:Health() - dmg:GetDamage() <= 0 then
            self:SetKillEntity(impactData.Entity)
            self:SetKillBone(impactData.PhysicsBone)
            self:SetKillVelocity(vel)
        end
    end
end

function ENT:FightGravity(phys)
    if not phys:IsValid() or self.FromShotgun then return end

    local gravity = physenv.GetGravity()
    local speed = self:GetVelocity():Length()

    local multiplier = self.Multipliers.Force * speed * 1e-4

    phys:ApplyForceCenter(-gravity * 1.505e-2 * math.Clamp(multiplier, 0, 1))
end

function ENT:PhysicsUpdate(phys)
    if not phys:IsValid() then return end

    self.CurImpactData = self:ImpactData(self:GetVelDir())

    if self.CurImpactData.Hit then
        local hitEnt = self.CurImpactData.Entity

        local impactDir = self.CurImpactData.HitPos - self:GetPos()
        impactDir:Normalize()

        -- This is used to handle firing upon entities that are very close to the
        -- spawn location of the bullet.
        -- If too close, and spawn within the entity, the physics system will miss the collision
        if impactDir:Dot(self.CurImpactData.Normal) < 0 then
            self:Damage(self.CurImpactData.Entity, self:GetVelocity())
        end

        self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    else
        self:SetCollisionGroup(COLLISION_GROUP_WORLD)
    end

    self:FightGravity(phys)
    self.OldPos = self:GetPos() 
end

function ENT:PhysicsCollide(colData, collider)
    if self.Impacted then return end

    local dir = colData.OurOldVelocity:GetNormalized()
    self.CurImpactData = self.CurImpactData or self:ImpactData(dir)

    -- Our impact trace won't properly see the world as we are
    -- probably travelling fast enough to have our trace not
    -- reach the world prior to collision
    if not self.CurImpactData.Hit or colData.HitEntity:IsWorld() then
        self.CurImpactData.Entity = colData.HitEntity
        self.CurImpactData.HitPos = colData.HitPos
        self.CurImpactData.HitNormal = colData.HitNormal
    end
    
    if colData.Speed > self.SpeedToDamage then
        local vel = colData.OurOldVelocity
        self:Damage(colData.HitEntity, vel)

        return
    end

    self:Impact()
end
