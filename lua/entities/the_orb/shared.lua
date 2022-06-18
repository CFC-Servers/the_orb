DEFINE_BASECLASS( "base_anim" )
ENT.Type = "anim"
ENT.PrintName = "The Orb"
ENT.Purpose = "???"
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Spawnable = true
ENT.AdminOnly = false

ENT.Model = "models/hunter/misc/sphere1x1.mdl"
ENT.IsOrb = true

function ENT:SetupDataTables()
    self:NetworkVar( "Float", 0, "Radius" )
    self:NetworkVar( "Bool", 0, "Enabled" )
    self:NetworkVar( "Bool", 1, "RevengeZap" )
    self:NetworkVar( "Vector", 0, "EnergyColor" )

    if SERVER then
        self:SetRadius( 750 )
        self:SetEnabled( false )
        self:SetRevengeZap( true )
        self:SetEnergyColor( Vector( 255, 0, 0 ) )
    end
end
