
include "agility/util.lua"
local cvars = include "agility/cvars.lua"

local bullets = {}
local signatureHullSize = 42069

local tracerTypes = {
    Normal = 1,
    AR2 = 2,
    Gunship = 3,
}

local ammoTypeToTracer = {
    AR2 = tracerTypes.AR2,
    HelicopterGun = tracerTypes.Gunship,
    CombineCannon = tracerTypes.Gunship,
}

if SERVER then
    util.AddNetworkString "AddBullet"
    util.AddNetworkString "RemoveBullet"
end

-- Very simple, with a natural and purposeful bias towards center of circle
local function ApplySpread(data, right, up, seed)
    local radius = util.SharedRandom(seed, 0, 1)
    local ang = util.SharedRandom(seed, 0, 2 * math.pi)
    
    local x, y = math.cos(ang) * radius, math.sin(ang) * radius
    return data.Dir + right * x * data.Spread.x + up * y * data.Spread.y
end

local function BulletTimeEnabled()
    if not game.SinglePlayer() then return false end

    local ply = SERVER and player.GetAll()[1] or LocalPlayer()
    return ply.BulletTimeActive
end

local function BulletId(owner, count)
    return bit.lshift(owner:EntIndex(), 16) + count
end

local function AddBullet(bulletId, pos, vel, tracerType, owner, data)
    -- TOOD this probably doesn't work in MP, client-side bullet IDs won't match server ones
    bullets[bulletId] = {
        Pos = pos,
        Vel = vel,

        TracerType = tracerType,
        Owner = owner,
        Data = data,
    }
    return bullets[bulletId]
end

local function RemoveBullet(bulletId)
    local bullet = bullets[bulletId]
    if bullet.BubbleEmitter then
        bullet.BubbleEmitter:Finish()
    end

    bullets[bulletId] = nil
end

local function UpdateBullet(bulletId, bullet)
    local nextPos = bullet.Pos + bullet.Vel * FrameTime()
    local dir = bullet.Vel:GetNormalized()

    if SERVER then
        if cvars.BulletDebugDraw:GetBool() then
            debugoverlay.Line(bullet.Pos, nextPos, 3, Color(0, 0, 255))
        end

        local tr = util.TraceLine {
            start = bullet.Pos,
            endpos = nextPos,
            filter = bullet.Owner,
            mask = MASK_SHOT,
        }

        if tr.Hit then
            -- Override some fields here
            bullet.Data.Src = bullet.Pos
            bullet.Data.Dir = dir
            bullet.Data.Distance = (nextPos - bullet.Pos):Length() * 1.2
            bullet.Data.Num = 1
            bullet.Data.Tracer = 0
            bullet.Data.HullSize = signatureHullSize + bullet.Data.HullSize

            if IsValid(bullet.Owner) then
                -- Quite janky, recursively invoke `FireBullets` to do the normal bullet behavior on contact
                -- We set a special value in `HullSize` to avoid infinite recursion
                bullet.Owner:FireBullets(bullet.Data)
            end

            RemoveBullet(bulletId)

            net.Start("RemoveBullet")
                net.WriteUInt(bulletId, 32)
            net.Send(player.GetAll())
        end
    end

    -- If we weren't deleted in the SERVER-specific update
    if bullets[bulletId] ~= nil then
        bullet.Pos = nextPos
        
        if cvars.BulletGravity:GetBool() then
            bullet.Vel = bullet.Vel + physenv.GetGravity() * FrameTime()
        end
    end
end

local function UpdateAllBullets()
    for bulletId, bullet in pairs(bullets) do
        UpdateBullet(bulletId, bullet)
    end 
end

hook.Add("EntityFireBullets", "agility_FireBullets", function(ent, data)
    if CLIENT and not IsFirstTimePredicted() then return true end
    if not cvars.BulletEnable:GetBool() then return true end
    if cvars.BulletNpcOnly:GetBool() and not ent:IsNPC() then return true end
    if cvars.BulletSlomoOnly:GetBool() and not BulletTimeEnabled() then return true end
    
    -- Avoids recursive calls
    -- This is a bad hack lmao
    -- Unfortunately keys that aren't recognized as a part of the Bullet structure get trimmed out
    if data.HullSize >= signatureHullSize then
        data.HullSize = data.HullSize - signatureHullSize
        return true
    end

    local speed = cvars.BulletSpeed:GetFloat()
    local right = data.Dir:Cross(ent:GetUp())
    local up = data.Dir:Cross(right)

    right:Normalize()
    up:Normalize()

    local tracerType = ammoTypeToTracer[data.AmmoType] or tracerTypes.Normal

    ent.BulletCount = ent.BulletCount or 0
    for i = 1, data.Num do
        ent.BulletCount = ent.BulletCount + 1

        local dir = ApplySpread(data, right, up, ent.BulletCount)

        local bulletId = BulletId(ent, ent.BulletCount)
        local bullet = AddBullet(bulletId, data.Src, dir * speed, tracerType, ent, data)

        -- TODO batch these up
        if SERVER then
            net.Start("AddBullet")
                net.WriteFloat(CurTime())
                net.WriteVector(bullet.Pos)
                net.WriteVector(bullet.Vel)
                net.WriteEntity(bullet.Owner)
                net.WriteUInt(ent.BulletCount, 32) -- TODO make 16 bits and gracefully overflow?
                net.WriteUInt(tracerType, 8)
            net.Send(player.GetAll())
        end
    end

    return false
end)

if SERVER then
    hook.Add("Tick", "agility_sv_BulletTick", UpdateAllBullets)

    hook.Add("ScaleNPCDamage", "agility_sv_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
        if cvars.BulletEnable:GetBool() and cvars.BulletEnableDamageScale:GetBool() then
            if hitgroup == HITGROUP_HEAD then
                dmginfo:ScaleDamage(2.0)
            end
        end
    end)
elseif CLIENT then
    local bubbleMat = Material("effects/bubble")
    local splashMat = Material("effects/splash2")

    local normalTracerMat = Material("effects/spark")
    local combineTracerMat = Material("effects/gunshiptracer")

    local function IsPlayerBehindHit(tr, bullet, ply)
        local plyToHit = tr.HitPos - ply:GetPos()
        plyToHit.z = 0
        plyToHit:Normalize()

        local bulletToHit = tr.HitPos - bullet.Pos 
        bulletToHit.z = 0
        bulletToHit:Normalize()

        return plyToHit:Dot(bulletToHit) < 0
    end

    local function ComputeVolume(dist, loudestDist, quiestestDist)
        local quietFactor = math.Remap(dist, loudestDist, quiestestDist, 0.0, 1.0)
        return math.Clamp(1.0 - quietFactor, 0.0, 1.0)
    end

    local function ProjectPointToLine(lineStart, lineEnd, point)
        local lineDir = (lineEnd - lineStart):GetNormalized()
        local lineStartToPoint = point - lineStart

        return lineStart + lineDir * lineDir:Dot(lineStartToPoint)
    end

    net.Receive("AddBullet", function(len)
        local spawnTime = net.ReadFloat()
        local pos = net.ReadVector()
        local vel = net.ReadVector()
        local owner = net.ReadEntity()
        local count = net.ReadUInt(32)
        local tracerType = net.ReadUInt(8)

        local bulletId = BulletId(owner, count)
        local timeDelta = CurTime() - spawnTime

        if cvars.BulletGravity:GetBool() then
            pos = pos + vel * timeDelta + 0.5 * physenv.GetGravity() * timeDelta * timeDelta
            vel = vel + physenv.GetGravity() * timeDelta
        else
            pos = pos + vel * timeDelta
        end

        AddBullet(bulletId, pos, vel, tracerType, owner)
    end)

    net.Receive("RemoveBullet", function(len)
        local bulletId = net.ReadUInt(32)
        RemoveBullet(bulletId)
    end)

    -- Do the bullet update on the client in `Think` to get per-frame smoothness
    hook.Add("Think", "agility_cl_BulletThink", UpdateAllBullets)

    -- We don't have to do this every frame, just do it every tick instead for efficiency
    hook.Add("Tick", "agility_cl_BulletEffects", function()
        local ply = LocalPlayer()
        for bulletId, bullet in pairs(bullets) do
            local oldPos = bullet.OldPos or (bullet.Pos - bullet.Vel * engine.TickInterval())
            local dir = bullet.Vel:GetNormalized() 

            -- TODO do less traces
            local waterTr = util.TraceLine {
                start = oldPos,
                endpos = bullet.Pos,
                mask = MASK_WATER,
            }

            if waterTr.Hit then
                -- TODO this is pretty hacky, like the bubbles can float above the water
                -- This is based on `CWaterBullet` - I don't even know if its actually used in HL2 or not
                if not bullet.Splashed and bullet.SeenTick then
                    local effectData = EffectData()
                    effectData:SetOrigin(waterTr.HitPos)
                    effectData:SetScale(10)
                    util.Effect("watersplash", effectData)

                    local plyDistSqr = (ply:GetPos() - waterTr.HitPos):LengthSqr()
                    local waterWhizDistSqr = 1000 * 1000
                    if ply:WaterLevel() >= 3 then
                        local volume = ComputeVolume(plyDistSqr, 100 * 100, waterWhizDistSqr)
                        EmitSound("Underwater.BulletImpact", waterTr.HitPos, -1, CHAN_AUTO, volume)
                    end

                    bullet.Splashed = true
                elseif not bullet.SeenTick then
                    -- If its our first tick and we're already under-water, don't do the splash
                    bullet.Splashed = true
                end

                if not bullet.BubbleEmitter then
                    bullet.BubbleEmitter = ParticleEmitter(bullet.Pos)
                end
                bullet.BubbleEmitter:SetPos(bullet.Pos)

                local length = (bullet.Pos - oldPos):Length()
                local density = 0.2

                local numBubbles = length * density
                for i = 1, numBubbles do
                    local offset = oldPos + dir * (i / numBubbles) * length

                    local randomOffset = Vector(1, 1, 1) * math.Rand(-2.5, 2.5)
                    local bubbleParticle = bullet.BubbleEmitter:Add(bubbleMat, offset + randomOffset)
                    bubbleParticle:SetLifeTime(0.0)
                    bubbleParticle:SetDieTime(math.Rand(2.75, 3.25))

                    bubbleParticle:SetStartAlpha(255)
                    bubbleParticle:SetEndAlpha(0)

                    bubbleParticle:SetVelocity(dir * 64.0 + Vector(0, 0, 32))

                    randomOffset = Vector(1, 1, 1) * math.Rand(-2.5, 2.5)
                    local splashParticle = bullet.BubbleEmitter:Add(splashMat, offset)
                    splashParticle:SetLifeTime(0.0)
                    splashParticle:SetDieTime(2.0)

                    splashParticle:SetStartAlpha(128)
                    splashParticle:SetEndAlpha(0)

                    splashParticle:SetStartSize(2.0)
                    splashParticle:SetEndSize(0.0)

                    splashParticle:SetRoll(math.random(0, 359))
                    splashParticle:SetRollDelta(math.random(-4, 4))

                    splashParticle:SetVelocity(dir * 64.0 + Vector(0, 0, 32))
                end
            else
                local plyDistSqr = (ply:GetPos() - bullet.Pos):LengthSqr()

                local whizDist = 75
                local whizDistSqr = whizDist * whizDist

                if bullet.Owner ~= ply and not bullet.Whizzed and plyDistSqr <= whizDistSqr then
                    -- If we're close to the player and probably not going to hit them, play the whiz
                    local whizTr = util.TraceLine {
                        start = bullet.Pos,
                        endpos = bullet.Pos + bullet.Vel:GetNormalized() * whizDist * 1.1,
                        mask = MASK_SHOT,
                    }

                    if not whizTr.Hit or (whizTr.Entity ~= ply and not IsPlayerBehindHit(whizTr, bullet, ply)) then
                        local proj = ProjectPointToLine(oldPos, bullet.Pos, ply:GetPos())
                        local projDistSqr = (proj - ply:GetPos()):LengthSqr()
                        local volume = ComputeVolume(projDistSqr, 25 * 25, 100 * 100)
                        
                        EmitSound("Bullets.DefaultNearmiss", ply:GetPos(), -1, CHAN_AUTO, 0.8 * volume)
                        bullet.Whizzed = true
                    end
                end
            end

            bullet.OldPos = bullet.Pos
            bullet.SeenTick = true
        end
    end)

    hook.Add("PostDrawTranslucentRenderables", "agility_DrawBullets", function()
        for bulletId, bullet in pairs(bullets) do
            local dir = bullet.Vel:GetNormalized()

            local mat = normalTracerMat
            local width = 1.2
            local length = 50.0

            if bullet.TracerType == tracerTypes.AR2 then
                mat = combineTracerMat
                width = 1.5
                length = 75.0
            elseif bullet.TracerType == tracerTypes.Gunship then
                mat = combineTracerMat
                width = 5.0
                length = 100.0
            end

            render.SetMaterial(mat)
            render.DrawBeam(bullet.Pos - dir * length, bullet.Pos + dir * 5.0, width, 0.0, 1.0)
        end
    end)
end
