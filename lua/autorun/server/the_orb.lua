local rawget = rawget

resource.AddSingleFile( "sound/the_orb/chant.mp3" )
resource.AddSingleFile( "sound/the_orb/thunder-1.mp3" )
resource.AddSingleFile( "sound/the_orb/thunder-2.mp3" )
resource.AddSingleFile( "sound/the_orb/thunder-3.mp3" )

OrbManager = {
    Orbs = {},
    OrbCount = 0,
}

local minGazeDuration = 3
local maxGazeDuration = 20.25

function OrbManager:AddOrb( orb )
    self.Orbs[orb] = true
    self.OrbCount = self.OrbCount + 1
end

function OrbManager:RemoveOrb( orb )
    self.Orbs[orb] = nil
    self.OrbCount = self.OrbCount - 1
    assert( self.OrbCount > 0 )
end

local function handlePlayerView( ply )
    local lastOrbTarget = ply.OrbTargeted
    local currentTarget = ply:GetEyeTrace().Entity
    local currentIsOrb = currentTarget.IsOrb

    if currentTarget == lastOrbTarget then
        if currentIsOrb then
            local gazeDuration = CurTime() - ply.StartedGazing

            if gazeDuration >= minGazeDuration then
                local adjustedDuration = math_max( 0.01, gazeDuration - minGazeDuration )
                local intensity = adjustedDuration / maxGazeDuration
                ply:SetNWFloat( "TheOrb_GazeIntensity", intensity )

                if intensity >= 0.85 then
                    ply.OrbLocked = true
                    ply.ScreamLoop = ply:StartLoopingSound( "ambient/levels/citadel/citadel_ambient_scream_loop1.wav" )
                    ply:Lock()
                end
            end

            if gazeDuration >= maxGazeDuration then
                ply.OrbTargeted = nil
                ply.StartedGazing = nil
                ply.OrbLocked = false
                ply:StopLoopingSound( ply.ScreamLoop )
                ply.ScreamLoop = nil
                ply:SetNWBool( "TheOrb_IsGazing", false )
                ply:SetNWFloat( "TheOrb_GazeIntensity", 0 )
                ply:Unlock()
                currentTarget:Zap( ply )
            end
        end

        return
    end

    if currentIsOrb then
        ply.OrbTargeted = currentTarget
        ply.StartedGazing = CurTime()
        ply:SetNWBool( "TheOrb_IsGazing", true )
    end

    if not ply.OrbTargeted then return end

    ply.OrbLocked = false
    ply:StopLoopingSound( ply.ScreamLoop )
    ply.ScreamLoop = nil
    ply:Unlock()

end

hook.Add( "Think", "TheOrb_Think", function()
    local plys = player.GetAll()
    local plyCount = #plys

    for i = 1, plyCount do
        local ply = rawget( plys, i )
        handlePlayerView( ply )
    end
end )

hook.Add( "PlayerSpawn", "TheOrb_PlayerReset", function( ply )
    if ply.ZappedRagdoll then
        ply.ZappedRagdoll:Remove()
        ply.ZappedRagdoll = nil
    end

    ply:UnSpectate()
end )

hook.Add( "CanPlayerSuicide", "TheOrb_PlayerLocked", function( ply )
    local isGazing = ply:GetNWBool( "TheOrb_IsGazing", false )
    if not isGazing then return end

    local intensity = ply:GetNWFloat( "TheOrb_GazeIntensity", 0 )
    if intensity >= 0.85 then return false end
end )
