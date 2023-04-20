local Vector = Vector
local VectorRand = VectorRand
local CurTime = CurTime
local IsValid = IsValid
local rawget = rawget
local math_ceil = math.ceil
local math_sin = math.sin
local math_random = math.random
local table_insert = table.insert
local table_remove = table.remove
local render_SetMaterial = render.SetMaterial
local render_DrawBeam = render.DrawBeam

local vecZero = Vector( 0, 0, 0 )

local zapMat = Material( "cable/redlaser" )
local zapCol = Color( 255, 100, 100, 255 )
local zapLifetime = 1
local baseWidth = 60
local plyOffset = Vector( 0, 0, 45 )
local plyNegativeOffset = Vector( 0, 0, 10 )
local zaps = {}

function generateSegments( orb, target, segmentMod, ziggyMod )
    local startPos = orb:GetPos()
    local endPos = target:WorldSpaceCenter()
    if target:IsPlayer() then
        endPos = target:EyePos() - plyNegativeOffset
    end

    segmentMod = segmentMod or 1
    ziggyMod = ziggyMod or 1

    local segments = {}
    local segmentLength = 50
    local segmentCount = math_ceil( startPos:Distance( endPos ) / segmentLength ) + 2
    segmentCount = segmentCount * segmentMod

    for i = 1, segmentCount do
        local t = i / segmentCount

        local lerpedPos = startPos * ( 1 - t ) + endPos * t

        if i == 1 then
            lerpedPos = startPos
        end

        local segmentOffset = vecZero
        if ( i ~= 1 ) and ( i ~= segmentCount ) then
            local ziggy = math_random( 7, 22 )
            ziggy = ziggy * ziggyMod
            segmentOffset = VectorRand() * ziggy
        end

        table_insert( segments, lerpedPos + segmentOffset )
    end

    return segments
end

local zapColOutline = Color( 0, 0, 0, 255 )

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
                local t = i / segmentCount

                local randomWidthFactor = math_random() * 0.5 + 0.75
                local width = baseWidth * ( 1 - lifetime / zapLifetime ) * randomWidthFactor
                local outlineWidth = width / 6.5 -- Adjust this value to control the outline thickness

                local freq = 2 -- frequency of the sine wave
                local amp = 0.5 -- amplitude of the sine wave
                local sinOffset = math_sin( t * math.pi * freq ) * amp

                zapCol.a = zapCol.a * ( 1 - sinOffset )

                -- Draw outline
                render.SetColorMaterial()
                render_DrawBeam( lastPos, segment, outlineWidth, 0, 0, zapColOutline )

                -- Draw original bolt
                render_SetMaterial(zapMat)
                render_DrawBeam( lastPos, segment, width, 0, 0, zapCol )
            end
        end
    end
end

hook.Add( "PostDrawTranslucentRenderables", "TheOrb_DrawZaps", drawZaps )

net.Receive( "TheOrb_Zap", function()
    local orb = net.ReadEntity()
    if not IsValid( orb ) then return end
    if not orb.StartZap then return end

    local target = net.ReadEntity()
    if not IsValid( target ) then return end

    local segments = generateSegments( orb, target, 2, 0.6 )
    table_insert( zaps, { segments = segments, created = CurTime() } )

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
