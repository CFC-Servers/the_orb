AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include( "shared.lua" )

local IsValid = IsValid
local rawget = rawget
local StartWith = string.StartWith

ENT.MaxZapsPerCheck = 4
ENT.SpawnOffset = Vector( 0, 0, 150 )
ENT.ExtraRagdollVelocity = Vector( 0, 0, 1250 )
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
}

function ENT:CanZap( e )
    if not IsValid( e ) then return false end
    local eClass = e:GetClass()

    if rawget( self.ZapClassBlacklist, eClass ) then
        return false
    end

    if e:MapCreationID() ~= -1 then return false end

    if e:IsWeapon() then
        return IsValid( e:GetOwner() )
    end

    if StartWith( eClass, "env_" ) then return false end
    if StartWith( eClass, "func_" ) then return false end
    if StartWith( eClass, "shadow_" ) then return false end
    if StartWith( eClass, "info_" ) then return false end
    if StartWith( eClass, "point_" ) then return false end
    if StartWith( eClass, "path_" ) then return false end
    if StartWith( eClass, "scene_" ) then return false end
    if StartWith( eClass, "logic_" ) then return false end
end

function ENT:Initialize()
    self:SetModel( self.Model )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:GetPhysicsObject():EnableMotion( false )
    self:SetPos( self:GetPos() + self.SpawnOffset )
    self:DrawShadow( false )

    OrbManager:AddOrb( self )
end

function ENT:TossRagdoll( ragdoll, vel )
    local boneCount = ragdoll:GetPhysicsObjectCount() - 1

    for i = 0, boneCount do
        local bonePhys = ragdoll:GetPhysicsObjectNum( i )

        if IsValid( bonePhys ) then
            bonePhys:SetVelocity( vel + VectorRand() )
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
    local vel = -( ( diff * 3.5 ) + self.ExtraRagdollVelocity )

    local ragdoll = ents.Create( "prop_ragdoll" )
    ragdoll.ZapImmune = true
    ragdoll:SetPos( plyPos )
    ragdoll:SetModel( self:GetRandomRagdoll() )
    ragdoll:SetAngles( ply:GetAngles() )
    ragdoll:SetVelocity( vel )
    ragdoll:Spawn()

    ply:Spectate( OBS_MODE_CHASE )
    ply:SpecateEntity( ragdoll )

    if ply.ZappedRagdoll then
        ply.ZappedRagdoll:Remove()
    end
    ply.ZappedRagdoll = ragdoll

    self:TossRagdoll( ragdoll )
end

function ENT:BroadcastZap( target )
    local recipients = RecipientFilter()
    recipients:AddPVS()

    net.Start( "TheOrb_Zap" )
    net.WriteEntity( self )
    net.WriteEntity( target )
    net.Send( recipients )
end

function ENT:HandlePlayerZap( ply )
    local plyPos = ply:GetPos()
    local owner = self:GetOwner()

    local dmg = DamageInfo()
    dmg:SetAttacker( owner )
    dmg:SetInflictor( self )
    dmg:SetDamageType( DMG_SHOCK + DMG_ENERGYBEAM )
    dmg:SetDamageForce( 69420 )
    dmg:SetDamage( 10000 )
    dmg:SetDamagePosition( plyPos )
    dmg:SetReportedPosition( plyPos )

    ply:KillSilent()
    self:MakePlayerRagdoll( ply )

    hook.Run( "DoPlayerDeath", ply, owner, dmg )
    hook.Run( "PlayerDeath", ply, self, owner )
end

function ENT:Zap( target )
    local targetPhys = phys:GetPhysicsObject()
    if IsValid( targetPhys ) then
        targetPhys:EnableMotion( false )
    end

    self:BroadcastZap( target )

    local targetPos = target:GetPos()
    local normal = ( self:GetPos() - targetPos ):GetNormal()

    util.ScreenShake( targetPos, 2, 5, 1, 750 )

    timer.Simple( 0.3, function()
        if not IsValid( target ) then return end
        if target:IsPlayer() then
            self:HandlePlayerZap( target )
            return
        end

        local chance = math.random( 0, 100 )
        if chance >= 70 then
            ACF_HEKill( target, normal, 500, targetPos )
        else
            target:Remove()
        end
    end )
end

function ENT:Think()
    if not IsValid( self ) then return end

    local nearby = ents.FindInSphere( self:GetPos(), self:GetRadius() )
    local nearbyCount = #nearby

    local maxZaps = self.MaxZapsPerCheck
    local zapCount = 0

    for i = 1, nearbyCount do
        if zapCount >= maxZaps then
            return
        end

        local ent = rawget( nearby, i )
        if not ent.GotZapped and self:CanZap( ent ) then
            zapCount = zapCount + 1
            ent.GotZapped = true
        end
    end
end

function ENT:OnRemove()
    OrbManager:RemoveOrb( self )
end
