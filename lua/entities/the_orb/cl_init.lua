local IsValid = IsValid
local CurTime = CurTime
local DynamicLight = DynamicLight

local math_Rand = math.Rand
local math_random = math.random
local table_insert = table.insert
local util_Effect = util.Effect
local sound_Play = sound.Play
local sound_PlayFile = sound.PlayFile

include( "shared.lua" )

ENT.EmitOnZap = "ambient/machines/thumper_hit.wav"
ENT.LightOffset = Vector( 0, 0, 45 )
ENT.ExplosionScale = 8 * 50

-- This table is only used to keep thunder sounds
-- in memory so they don't get garbage collected
ENT.ThunderSounds = {}

function ENT:PlayThunderSound( pos )
    local thunderIndex = math_random( 1, 3 )
    local thunderPath = "sound/the_orb/thunder-" .. thunderIndex .. ".mp3"

    sound_PlayFile( thunderPath, "3d", function( audio )
        if not IsValid( audio ) then return end
        table_insert( self.ThunderSounds, audio )

        audio:Set3DFadeDistance( 400, 5000 )
        audio:SetVolume( 2.75 )
        audio:SetPos( pos, pos - self:GetPos() )
        audio:Play()
    end )
end

function ENT:PlaySparkSound( pos )
    local sparkIndex = math_random( 1, 9 )
    local zapPath = "ambient/energy/zap" .. sparkIndex .. ".wav"
    sound_Play( zapPath, pos, 75, 100, 1 )
end

function ENT:MakeFlash( pos )
    local light = DynamicLight()
    if not light then return end

    light.Pos = pos + self.LightOffset

    local col = self:GetEnergyColor()
    light.r = col[1]
    light.g = col[2]
    light.b = col[3]
    light.Brightness = 8.75
    light.Size = self:GetRadius()
    light.DieTime = CurTime() + 0.75
    light.Decay = 750
end

function ENT:MakeHitExplosion( pos )
    local normal = ( pos - self:GetPos() ):GetNormal()

    local explosion = EffectData()
    explosion:SetOrigin( pos )
    explosion:SetNormal( normal )
    explosion:SetScale( self.ExplosionScale )
    explosion:SetRadius( 0 )

    util_Effect( "ACF_Explosion", explosion )
end

function ENT:Zap( target )
    local targetPos = target:GetPos()
    self:PlayThunderSound( targetPos )
    self:PlaySparkSound( targetPos )
    self:MakeFlash( targetPos )
    self:MakeHitExplosion( targetPos )
end

function ENT:StartZap( target )
    self:EmitSound( self.EmitOnZap, 75, 100, 1, CHAN_WEAPON )
    timer.Simple( math_Rand( 0.05, 0.2 ), function()
        if not IsValid( target ) then return end
        self:Zap( target )
    end )
end
