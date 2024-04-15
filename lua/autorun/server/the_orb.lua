local IsValid = IsValid
local rawget = rawget

util.AddNetworkString( "TheOrb_Zap" )
resource.AddWorkshop( "3114953830" )

local minGazeDuration = 3
local maxGazeDuration = 21.15

local function setWeapon( ply, orb )
    if not IsValid( orb ) then return end
    local weapon = ply:GetActiveWeapon()
    if not IsValid( weapon ) then return end

    local weaponClass = weapon:GetClass()
    if weaponClass == "none" then return end
    ply:Give( "none" )
    ply:SelectWeapon( "none" )
end

-- TODO:
-- the nwfloat "StartedGazing" means 'when the player passed the minGazeDuration threshold'
-- but the ply.StartedGazing var means 'when the player originally looked at the orb'
local function handlePlayerView( ply )
    local target = ply:GetEyeTrace().Entity
    local isTargetingOrb = IsValid( target ) and target.IsOrb
    local wasTargetingOrb = ply.TargetingOrb

    if ( not wasTargetingOrb ) and ( not isTargetingOrb ) then return end

    if wasTargetingOrb and isTargetingOrb then
        -- Still looking at an orb

        if wasTargetingOrb == target then
            -- Looking at the same orb
            local duration = CurTime() - ply.StartedGazing

            -- Don't need to do anything yet
            if duration < minGazeDuration then
                return
            end

            local adjustedDuration = duration - minGazeDuration
            local intensity = adjustedDuration / maxGazeDuration

            if not ply.IsGazing then
                -- Is now considered gazing
                ply.IsGazing = true
                ply:SetNW2Bool( "TheOrb_IsGazing", true )
                ply:SetNW2Float( "TheOrb_StartedGazing", CurTime() )
                ply:SetNW2Entity( "TheOrb_GazingAt", target )
                setWeapon( ply, target )
            end

            if intensity >= 0.7 and not ply.OrbLocked then
                -- Player becomes orb-locked
                ply.OrbLocked = true
                ply.ScreamLoop = ply:StartLoopingSound( "ambient/levels/citadel/citadel_ambient_scream_loop1.wav" )
                ply:Lock()
            end

            if intensity >= 1 then
                -- Distribute Judgement
                target:Zap( ply )

                ply.TargetingOrb = nil
                ply.StartedGazing = nil
                ply.IsGazing = nil

                ply:UnLock()
                ply.OrbLocked = nil

                ply:StopLoopingSound( ply.ScreamLoop )
                ply.ScreamLoop = nil

                timer.Simple( 0.15, function()
                    ply:SetNW2Bool( "TheOrb_IsGazing", false )
                    ply:SetNW2Float( "TheOrb_StartedGazing", 0 )
                    ply:SetNW2Entity( "TheOrb_GazingAt", nil )
                end )
            end

            return
        else
            -- Looking at a new orb
            ply.TargetingOrb = target
            ply.StartedGazing = CurTime()
            ply.IsGazing = nil

            if ply.OrbLocked then ply:UnLock() end
            ply.OrbLocked = false

            if ply.ScreamLoop then ply:StopLoopingSound( ply.ScreamLoop ) end
            ply.ScreamLoop = nil

            ply:SetNW2Bool( "TheOrb_IsGazing", false )
            ply:SetNW2Float( "TheOrb_StartedGazing", 0 )
        end

        return
    end

    if wasTargetingOrb and not isTargetingOrb then
        -- Stopped looking at an orb
        ply.TargetingOrb = nil
        ply.StartedGazing = nil
        ply.IsGazing = nil

        if ply.OrbLocked then ply:UnLock() end
        ply.OrbLocked = false

        if ply.ScreamLoop then ply:StopLoopingSound( ply.ScreamLoop ) end
        ply.ScreamLoop = nil

        ply:SetNW2Bool( "TheOrb_IsGazing", false )
        ply:SetNW2Float( "TheOrb_StartedGazing", 0 )
        return
    end

    if ( not wasTargetingOrb ) and isTargetingOrb then
        -- Started looking at an orb
        ply.TargetingOrb = target
        ply.StartedGazing = CurTime()

    end
end

local function orbThink()
    local plys = player.GetAll()
    local plyCount = #plys

    for i = 1, plyCount do
        local ply = rawget( plys, i )
        handlePlayerView( ply )
    end
end

hook.Add( "TheOrb_OrbAdded", "TheOrb_OrbAdded", function()
    hook.Add( "Think", "TheOrb_Think", orbThink )
end )

hook.Add( "TheOrb_LastOrbRemoved", "TheOrb_LastOrbRemoved", function()
    hook.Remove( "Think", "TheOrb_Think" )
end )

hook.Add( "EntityTakeDamage", "TheOrb_Revenge", function( ent, dmg )
    if not ent.IsOrb then return end

    local inflictor = dmg:GetInflictor()
    if IsValid( inflictor ) then
        ent:Zap( inflictor )
    end

    -- timer.Simple( 0.15, function()
    --     local attacker = dmg:GetAttacker()
    --     if IsValid( attacker ) then
    --         ent:Zap( attacker )
    --     end
    -- end )
end )

hook.Add( "PlayerSpawn", "TheOrb_PlayerReset", function( ply )
    if IsValid( ply.ZappedRagdoll ) then
        ply.ZappedRagdoll:Remove()
        ply.ZappedRagdoll = nil
    end

    ply.GotZapped = nil
    ply:UnSpectate()
end )

hook.Add( "CanPlayerSuicide", "TheOrb_PlayerLocked", function( ply )
    if ply.OrbLocked then return false end
end )
