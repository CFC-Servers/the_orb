AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

local IsValid = IsValid
local rawget = rawget
local StartWith = string.StartWith
local math_random = math.random

local blastOffset = Vector( 0, 0, 25 )

ENT.AutomaticFrameAdvance = true
ENT.MaxZapsPerCheck = 24
ENT.SpawnOffset = Vector( 0, 0, 50 )
ENT.ExtraRagdollVelocity = Vector( 0, 0, 2250 )
ENT.RagdollOptions = {
    "models/Humans/Charple01.mdl",
    "models/Humans/Charple02.mdl",
    "models/Humans/Charple03.mdl",
}

ENT.ZapClassBlacklist = {
    hint = true,
    beam = true,
    none = true,
    light = true,
    network = true,
    worldspawn = true,
    sky_camera = true,
    gmod_gamerules = true,
    player_manager = true,
    predicted_viewmodel = true,
    physgun_beam = true,
    filter_activator_name = true,
    spotlight_end = true,
    lua_run = true,
    water_lod_control = true,
    hl2mp_ragdoll = true,
    gmod_hands = true,
    base_entity = true,
    soundent = true,
    bodyque = true,
    keyframe_rope = true
}

function ENT:SpawnFunction( ply, tr, className )
    if not tr.Hit then return end

    local spawnPos = tr.HitPos + Vector( 0, 0, 175 )

    local ent = ents.Create( className )
    ent:SetPos( spawnPos )
    ent:SetMaterial( self.Material )
    ent:SetPlayer( ply )

    if CPPI then
        ent:CPPISetOwner( ply )
    else
        ent:SetOwner( ply )
    end

    ent:Spawn()

    return ent
end

function ENT:CanZap( e )
    if not IsValid( e ) then return false end
    if e == self then return false end
    if e.ZapImmune then return false end

    local orbOwner = CPPI and self:CPPIGetOwner() or self:GetOwner()
    if e == orbOwner then return false end
    if e.CPPIGetOwner and e:CPPIGetOwner() == orbOwner then
        return false
    end

    local eClass = e:GetClass()

    if rawget( self.ZapClassBlacklist, eClass ) then
        return false
    end

    if e:MapCreationID() ~= -1 then return false end

    if e:IsWeapon() then
        return not IsValid( e:GetOwner() )
    end

    if StartWith( eClass, "env_" ) then return false end
    if StartWith( eClass, "func_" ) then return false end
    if StartWith( eClass, "shadow_" ) then return false end
    if StartWith( eClass, "info_" ) then return false end
    if StartWith( eClass, "point_" ) then return false end
    if StartWith( eClass, "path_" ) then return false end
    if StartWith( eClass, "scene_" ) then return false end
    if StartWith( eClass, "logic_" ) then return false end

    return true
end

function ENT:TossRagdoll( ragdoll, vel )
    local boneCount = ragdoll:GetPhysicsObjectCount() - 1

    for i = 0, boneCount do
        local bonePhys = ragdoll:GetPhysicsObjectNum( i )

        if IsValid( bonePhys ) then
            bonePhys:SetVelocity( vel + ( VectorRand() * 25 ) )
        end
    end
end

function ENT:GetRandomRagdoll()
    local options = self.RagdollOptions
    return options[math.random( 1, #options )]
end

function ENT:MakePlayerRagdoll( ply )
    local plyPos = ply:GetPos()

    local diff = self:GetPos() - plyPos
    local vel = -( diff * 43 ) + self.ExtraRagdollVelocity

    local ragdoll = ents.Create( "prop_ragdoll" )
    ragdoll.ZapImmune = true
    ragdoll:SetPos( plyPos )
    ragdoll:SetModel( self:GetRandomRagdoll() )
    ragdoll:SetAngles( ply:GetAngles() )
    ragdoll:SetVelocity( vel )
    ragdoll:Spawn()

    ply:Spectate( OBS_MODE_CHASE )
    ply:SpectateEntity( ragdoll )

    if IsValid( ply.ZappedRagdoll ) then
        ply.ZappedRagdoll:Remove()
    end
    ply.ZappedRagdoll = ragdoll

    self:TossRagdoll( ragdoll, vel )
end

function ENT:BroadcastZap( target )
    local recipients = RecipientFilter()
    recipients:AddPVS( target:GetPos() )

    net.Start( "TheOrb_Zap" )
    net.WriteEntity( self )
    net.WriteEntity( target )
    net.Send( recipients )
end

function ENT:HandlePlayerZap( ply )
    local plyPos = ply:GetPos()
    local owner = CPPI and self:CPPIGetOwner() or self:GetOwner()

    local dmg = DamageInfo()
    dmg:SetAttacker( owner )
    dmg:SetInflictor( self )
    dmg:SetDamageType( DMG_SHOCK + DMG_ENERGYBEAM )
    dmg:SetDamage( 55000 )
    dmg:SetDamagePosition( plyPos )
    dmg:SetReportedPosition( plyPos )

    ply:KillSilent()
    self:MakePlayerRagdoll( ply )

    hook.Run( "DoPlayerDeath", ply, owner, dmg )
    hook.Run( "PlayerDeath", ply, self, owner )
end

function ENT:Zap( target )
    local targetPhys = target:GetPhysicsObject()
    if IsValid( targetPhys ) then
        targetPhys:EnableMotion( false )
    end

    if target:IsPlayer() then
        target.ZapBuzzSound = target:StartLoopingSound( "ambient/levels/citadel/zapper_ambient_loop1.wav" )
        target:Lock()
    end

    timer.Simple( 0.1, function()
        if not IsValid( self ) then return end
        if not IsValid( target ) then return end
        self:BroadcastZap( target )
    end )

    local targetPos = target:GetPos()
    local normal = ( self:GetPos() - targetPos ):GetNormal()

    util.ScreenShake( targetPos, 125, 25, 0.5, 1200 )

    if target.IsOrb then return end

    timer.Simple( 0.4, function()
        if not IsValid( self ) then return end
        if not IsValid( target ) then return end
        if target:IsPlayer() then
            target:UnLock()
            if target.ZapBuzzSound then
                target:StopLoopingSound( target.ZapBuzzSound )
            end

            self:HandlePlayerZap( target )
            return
        end

        local chance = math.random( 0, 100 )
        if chance >= 75 and ACF_HEKill then
            ACF_HEKill( target, normal, 25000, targetPos + blastOffset )
        else
            target:Remove()
        end
    end )
end

function ENT:Think()
    if not IsValid( self ) then return end

    local here = self:GetPos()
    local nearby = ents.FindInSphere( here, self:GetRadius() )
    local nearbyCount = #nearby

    local maxZaps = self.MaxZapsPerCheck
    local zapCount = 0
    local maxZapsThisTime = math_random( 1, maxZaps )

    for i = 1, nearbyCount do
        if zapCount >= maxZapsThisTime then
            return
        end

        local ent = rawget( nearby, i )
        if not ent.GotZapped and self:CanZap( ent ) then
            zapCount = zapCount + 1

            if ent.IsOrb then
                local distance = ent:GetPos():Distance( here )
                local chance = math_random( 0, distance / 5 )
                if chance == 0 then
                    self:Zap( ent )
                end
            else
                ent.GotZapped = true
                self:Zap( ent )
            end
        end
    end

    self:NextThink( CurTime() )

    return true
end
