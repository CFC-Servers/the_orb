local Vector = Vector
local VectorRand = VectorRand
local CurTime = CurTime
local IsValid = IsValid
local rawget = rawget
local math_ceil = math.ceil
local math_random = math.random
local table_insert = table.insert
local table_remove = table.remove
local render_SetMaterial = render.SetMaterial
local render_DrawBeam = render.DrawBeam

local zapMat = Material( "cable/redlaser" )
local zapLifetime = 1
local baseWidth = 45
local plyOffset = Vector( 0, 0, 45 )
local zaps = {}

local function generateSegments( orb, target )
    local startPos = orb:GetPos()
    local endPos = target:GetPos()

    if target:IsPlayer() then
        endPos = endPos + plyOffset
    end

    local segments = {}
    local segmentLength = 25
    local segmentCount = math_ceil( startPos:Distance( endPos ) / segmentLength ) + 2

    for i = 1, segmentCount do
        local t = i / segmentCount

        local lerpedPos = startPos * ( 1 - t ) + endPos * t

        if i == 1 then
            lerpedPos = startPos
        end

        local segmentOffset = Vector( 0, 0, 0 )
        if ( i ~= 1 ) and ( i ~= segmentCount ) then
            local ziggy = math_random( 10, 30 )
            segmentOffset = VectorRand() * ziggy
        end

        table_insert( segments, lerpedPos + segmentOffset )
    end

    table_insert( zaps, { segments = segments, created = CurTime() } )
end

local function drawZaps()
    for z = #zaps, 1, -1 do
        local zapStruct = rawget( zaps, z )
        local created = rawget( zapStruct, "created" )
        local lifetime = CurTime() - created

        if lifetime > zapLifetime then
            table_remove( zaps, z )
        else
            local segments = rawget( zapStruct, "segments" )
            local segmentCount = #segments

            for i = 1, segmentCount do
                local segment = rawget( segments, i )
                local lastPos = rawget( segments, i - 1 ) or segment
                -- local t = i / segmentCount

                local width = baseWidth * ( 1 - lifetime / zapLifetime )

                render_SetMaterial( zapMat )
                render_DrawBeam( lastPos, segment, width, 0, 0, zapCol )
            end
        end
    end
end

hook.Add( "PostDrawTranslucentRenderables", "TheOrb_DrawZaps", drawZaps )

net.Receive( "TheOrb_Zap", function()
    local orb = net.ReadEntity()
    if not IsValid( orb ) then return end

    local target = net.ReadEntity()
    if not IsValid( target ) then return end

    generateSegments( orb, target )

    local targetPos = target:GetPos()

    if target:IsPlayer() then
        target.DiedFromOrb = true
        targetPos = targetPos + plyOffset
    end

    orb:StartZap( target )
end )

hook.Add( "CreateClientsideRagdoll", "TheOrb_ZapRagdoll", function( ent, ragdoll )
    if not ent.DiedFromOrb then return end

    ragdoll:SetNoDraw( true )
    ent.DiedFromOrb = false
end )
