
hook.Add("EntityEmitSound", "agility_PitchSounds", function(sndData)
    local timescale = game.GetTimeScale()
    if timescale ~= 1 then
        sndData.Pitch = sndData.Pitch * timescale 
        sndData.Pitch = math.Clamp(sndData.Pitch, 0, 255)

        return true
    end
end)