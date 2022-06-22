DEFINE_BASECLASS( "base_gmodentity" )
ENT.Type = "anim"
ENT.PrintName = "The Orb"
ENT.Purpose = "???"
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Material = "models/XQM/LightLinesRed_tool"
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

function ENT:Initialize()
    self:SetModel( self.Model )
    self:DrawShadow( false )

    if CLIENT then return end

    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:Activate()

    self:GetPhysicsObject():EnableMotion( false )
end