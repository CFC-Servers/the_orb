local util_ScreenShake = util.ScreenShake
local IsValid = IsValid
local rawget = rawget
local rawset = rawset

local table_insert = table.insert

local math_max = math.max
local math_rad = math.rad
local math_sin = math.sin
local math_cos = math.cos
local math_Rand = math.Rand

local render_StartBeam = render.StartBeam
local render_AddBeam = render.AddBeam
local render_EndBeam = render.EndBeam
local render_SetMaterial = render.SetMaterial
local render_MaterialOverride = render.MaterialOverride
local render_GetBlend = render.GetBlend
local render_SetBlend = render.SetBlend
local render_SetColorModulation = render.SetColorModulation
local render_GetColorModulation = render.GetColorModulation

local surface_SetMaterial = surface.SetMaterial
local surface_SetDrawColor = surface.SetDrawColor
local surface_DrawPoly = surface.DrawPoly

local cam_Start3D2D = cam.Start3D2D
local cam_End3D2D = cam.End3D2D

local peakBrightness = -0.65
local peakContrast = 1.25
local peakVolume = 7
local peakLightShake = 4.5
local peakHeavyShake = 4

local bloomDarken = 1
local bloomMultiply = 0
local bloomColorMultiply = 1
local bloomPasses = 1
local bloomR = 0.25

local beamMat = Material( "effects/tp_eyefx/tpeye" )
local linesMat = Material( "models/XQM/LightLinesRed_tool" )
local sunMat = Material( "effects/lensflare/flare" )
--local centerMat = Material( "effects/tp_eyefx/tpeye2" )
local centerMat = Material( "lights/hazzardred001a" )
local centerMat2 = Material( "effects/tp_eyefx/tpeye" )
local colorMat = Material( "models/debug/debugwhite" )
-- local fuzzyMat = Material( "effects/flashlight/caustics" )

-- TODO: Make this var shared somehow
local maxGazeDuration = 21.15

local baseTable = {
    ["$pp_colour_addr"] = 0,
    ["$pp_colour_addg"] = 0,
    ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = normalBrightness,
    ["$pp_colour_contrast"] = 1,
    ["$pp_colour_colour"] = normalColor,
    ["$pp_colour_mulr"] = 0,
    ["$pp_colour_mulg"] = 0,
    ["$pp_colour_mulb"] = 0
}

local currentTable = table.Copy( baseTable )

local chantSound
local screamSound
local passiveNoise
local ourOrb

local function makeCircle( x, y, radius, seg, intensity )
    intensity = intensity * 1.75
    local cir = {}

    table_insert( cir, { x = x, y = y, u = 0.5, v = 0.5 } )
    for i = 0, seg do
        local a = math_rad( ( i / seg ) * -360 )
        table_insert( cir, {
            x = ( x + math_Rand( -intensity, intensity ) ) + math_sin( a ) * radius,
            y = ( y + math_Rand( -intensity, intensity ) ) + math_cos( a ) * radius,
            u = math_sin( a ) / 2 + 0.5,
            v = math_cos( a ) / 2 + 0.5
        } )
    end

    local a = math_rad( 0 )
    table_insert( cir, {
        x = x + math_sin( a ) * radius,
        y = y + math_cos( a ) * radius,
        u = math_sin( a ) / 2 + 0.5,
        v = math_cos( a ) / 2 + 0.5
    } )

    return cir
end

local function drawOrbOverlay( orb, intensity )
    local displacement = orb:GetPos() - LocalPlayer():EyePos()
    local right        = displacement:Angle():Right()
    local surfacePos = orb:GetPos() - displacement:GetNormalized() * orb:BoundingRadius()
    local surfaceAng = displacement:Cross( right ):Angle()

    local function getCircle( scaleMod )
        scaleMod = scaleMod or 1
        return makeCircle( 0, 0, ( scaleMod * 22 ) * intensity, ( 150 * intensity ) + 75, intensity )
    end

    cam_Start3D2D( surfacePos, surfaceAng, 1 )

    local circle
    if intensity < 0.88 then
        circle = getCircle( 8 )
        surface_SetMaterial( sunMat )
        surface_SetDrawColor( 135, 135, 135, 255 )
        surface_DrawPoly( circle )
        surface_DrawPoly( circle )

        surface_SetMaterial( centerMat2 )
        for _ = 1, 4 do
            circle = getCircle( math.Rand( 0.1, 0.6 ) )
            surface_DrawPoly( circle )
        end

        circle = getCircle( 0.1 * intensity )
        surface_SetDrawColor( 0, 0, 0, 255 )
        surface_SetMaterial( colorMat )
        surface_DrawPoly( circle )
        surface_DrawPoly( circle )
    else
        surface_SetDrawColor( 255, 5, 5, 255 )
        surface_SetMaterial( centerMat )
        for _ = 1, 8 do
            circle = getCircle( math.Rand( 0.3, 0.65 ) )
            surface_DrawPoly( circle )
        end

        circle = getCircle( 0.2 )
        surface_SetDrawColor( 0, 0, 0, 255 )
        surface_SetMaterial( colorMat )
        surface_DrawPoly( circle )
    end

    cam_End3D2D()
end

local function updateEffectTable( intensity )
    local isLocked = intensity > 0.88

    local contrast = isLocked and 1 or 1 + ( peakContrast * intensity )
    rawset( currentTable, "$pp_colour_contrast", contrast )

    local brightness = isLocked and ( peakBrightness * 0.25 ) or peakBrightness * intensity
    rawset( currentTable, "$pp_colour_brightness", brightness )

    local color = isLocked and 1 or math.max( 0.45, 1 - intensity )
    rawset( currentTable, "$pp_colour_colour", color )

    bloomDarken = isLocked and 0.1 or 1 - ( 0.75 * intensity )
    bloomMultiply = isLocked and 2.75 or 2 * intensity
    bloomColorMultiply = 1.75 * intensity
    bloomPasses = isLocked and 3 or 2 * intensity
    bloomR = isLocked and 0.5 or intensity
end

local function adjustForGaze( intensity )
    if chantSound then
        chantSound:SetPos( LocalPlayer():GetPos() )
        chantSound:SetVolume( intensity * peakVolume )
    end

    if screamSound:IsPlaying() then
        screamSound:ChangeVolume( intensity * peakVolume, 0 )
    end

    if passiveNoise:IsPlaying() then
        passiveNoise:ChangeVolume( intensity * ( peakVolume / 4 ), 0 )
    end

    local myPos = LocalPlayer():GetPos()

    if intensity >= 0.3 then
        local shakeStrength = intensity * peakLightShake
        util_ScreenShake( myPos, shakeStrength, shakeStrength / 2, 0.05, 0 )
    end

    if intensity >= 0.89 then
        local shakeStrength = intensity * peakHeavyShake
        util_ScreenShake( myPos, shakeStrength, shakeStrength / 2, 0.1, 0 )
    end
end

local isGazing = false

local function checkIsGazing()
    if not IsValid( LocalPlayer() ) then return end
    local hasFlag = LocalPlayer():GetNW2Bool( "TheOrb_IsGazing" )
    local target = LocalPlayer():GetEyeTrace().Entity
    local isLooking = target and target.IsOrb

    local gazing = hasFlag and isLooking
    if gazing then ourOrb = target end

    return gazing
end

local function gazeIntensity( ply )
    ply = ply or LocalPlayer()
    local started = ply:GetNW2Float( "TheOrb_StartedGazing", CurTime() )
    if started == 0 then return 0 end

    local diff = CurTime() - started
    local intensity = diff / maxGazeDuration

    return intensity
end

local function calcView( _, pos, angles, fov )
    if not isGazing then
        hook.Remove( "CalcView", "TheOrb_Gazing" )
        return
    end

    local intensity = gazeIntensity()

    local newFov = fov * ( 1 - intensity )
    newFov = math_max( 10, newFov )

    local view = {
        origin = pos,
        angles = angles,
        fov = newFov,
        drawviewer = false
    }

    return view
end

local function screenEffects()
    if not isGazing then
        hook.Remove( "RenderScreenspaceEffects", "TheOrb_Gazing" )
        return
    end

    _G.DrawColorModify( currentTable )
    local intensity = gazeIntensity()
    local sobel = 2 - intensity
    _G.DrawSobel( sobel )

    if intensity > 0.88 then
        _G.DrawSharpen( 3, 2 )
    else
        _G.DrawBloom( bloomDarken, bloomMultiply, 12, 9, bloomPasses, bloomColorMultiply, bloomR, 0.25, 0.25 )
    end
end

local function drawGazingPlayer( ply )
    local intensity = gazeIntensity( ply )
    local blend = render_GetBlend()

    render_SetBlend( intensity )
    render_MaterialOverride( linesMat )
    ply:DrawModel()
    render_MaterialOverride()
    render_SetBlend( blend )

    local orb = ply:GetNW2Entity( "TheOrb_GazingAt" )
    if IsValid( orb ) then
        if ply == LocalPlayer() then
            if intensity > 0.88 then
                local o_r, o_g, o_b = render_GetColorModulation()
                blend = render.GetBlend()

                render_MaterialOverride( colorMat )
                render_SetColorModulation( 0, 0, 0 )
                render_SetBlend( intensity )
                orb:DrawModel()
                render_MaterialOverride()
                render_SetBlend( blend )
                render_SetColorModulation( o_r, o_g, o_b )
            end

            drawOrbOverlay( orb, intensity )
        else
            local segments = generateSegments( orb, ply, 0.6, 0.35 )
            local segmentCount = #segments

            render_StartBeam( segmentCount )
            render_SetMaterial( beamMat )

            for i = 1, segmentCount do
                local segment = rawget( segments, i )
                local distanceFromCenter
                if i > segmentCount / 2 then
                    distanceFromCenter = i - segmentCount / 2
                else
                    distanceFromCenter = segmentCount / 2 - i
                end

                local beamWidth = 2 + ( 30 - distanceFromCenter )

                render_AddBeam( segment, beamWidth, i / segmentCount )
            end

            render_EndBeam()
        end
    end
end

hook.Add( "PostDrawOpaqueRenderables", "TheOrb_Gazing", function( _, skybox, skybox3d )
    if skybox then return end
    if skybox3d then return end
    local plys = player.GetAll()
    local plyCount = #plys

    cam.Start3D()
    for i = 1, plyCount do
        local ply = rawget( plys, i )
        local plyIsGazing = ply:GetNW2Bool( "TheOrb_IsGazing" )

        if plyIsGazing then
            drawGazingPlayer( ply )
        end
    end
    cam.End3D()
end )

hook.Add( "CalcMainActivity", "TheOrb_Gazing", function( ply )
    local plyIsGazing = ply:GetNW2Bool( "TheOrb_IsGazing", false )
    if not plyIsGazing then return end

    local intensity = gazeIntensity( ply )
    if intensity >= 0.1 then
        return ACT_HL2MP_IDLE_ZOMBIE, -1
    end
end )

local function gazeTick()
    local wasGazing = isGazing
    local isNowGazing = checkIsGazing()

    if not wasGazing and not isNowGazing then return end

    if wasGazing and isNowGazing then
        local intensity = gazeIntensity()
        adjustForGaze( intensity )
        updateEffectTable( intensity )
        return
    end

    if isNowGazing then
        -- just started looking
        isGazing = true
        sound.PlayFile( "sound/the_orb/chant.mp3", "mono", function( audio )
            if not IsValid( audio ) then return end
            audio:SetVolume( 0.1 )
            audio:Play()
            chantSound = audio
        end  )

        screamSound = screamSound or CreateSound( LocalPlayer(), "ambient/levels/citadel/citadel_ambient_scream_loop1.wav" )
        screamSound:Stop()

        passiveNoise = passiveNoise or CreateSound(
            LocalPlayer(),
            "synth/brown_noise.wav"
        )
        passiveNoise:PlayEx( 0.1, 100 )
        passiveNoise:SetSoundLevel( 120 )

        timer.Create( "TheOrb_DelayScreaming", 8, 1, function()
            screamSound:PlayEx( 0.1, 100 )
            screamSound:SetSoundLevel( 140 )
        end )

        local fogFunc = function( mod )
            do return end
            mod = mod or 1
            render.FogMode( MATERIAL_FOG_LINEAR )

            local intensity = gazeIntensity()

            local fogStart, fogEnd

            if intensity <= 0.15 then
                fogStart = 85000 - math.Remap( intensity, 0, 0.15, 0, 80000 )
                fogEnd = 100000 - math.Remap( intensity, 0, 0.15, 0, 93000 )
            else
                fogStart = 5000 - math.Remap( intensity, 0.25, 1, 0, 5000 )
                fogEnd = 7000 - math.Remap( intensity, 0.25, 1, 0, 6000 )
            end

            render.FogStart( fogStart * mod )
            render.FogEnd( fogEnd * mod )
            render.FogMaxDensity( math.Remap( intensity, 0, 1, 0.75, 0.9 ) )
            render.FogColor( 35, 0, 0 )
            return true
        end

        LocalPlayer():SetDSP( 16 )

        hook.Add( "SetupWorldFog", "TheOrb_Gazing", fogFunc )
        hook.Add( "SetupSkyboxFog", "TheOrb_Gazing", fogFunc )
        hook.Add( "CalcView", "TheOrb_Gazing", calcView )
        hook.Add( "RenderScreenspaceEffects", "TheOrb_Gazing", screenEffects )
        hook.Add( "PreDrawHalos", "TheOrb_Gazing", function()
            halo.Add( { LocalPlayer():GetNW2Entity( "TheOrb_GazingAt" ) }, Color( 0, 0, 0 ), 2, 2, 8, false, true )
        end )
        hook.Add( "HUDShouldDraw", "TheOrb_Gazing", function()
            return false
        end )

    else
        -- just looked away
        isGazing = false
        hook.Remove( "SetupWorldFog", "TheOrb_Gazing" )
        hook.Remove( "SetupSkyboxFog", "TheOrb_Gazing" )
        hook.Remove( "CalcView", "TheOrb_Gazing" )
        hook.Remove( "RenderScreenspaceEffects", "TheOrb_Gazing" )
        hook.Remove( "HUDShouldDraw", "TheOrb_Gazing" )
        hook.Remove( "PreDrawHalos", "TheOrb_Gazing" )
        timer.Remove( "TheOrb_DelayScreaming" )
        timer.Remove( "TheOrb_Bell" )

        if chantSound then
            chantSound:Stop()
            chantSound = nil
        end

        screamSound:Stop()
        passiveNoise:Stop()
        LocalPlayer():SetDSP( 0, true )

        if ourOrb then
            ourOrb = nil
        end
    end
end

hook.Add( "Tick", "TheOrb_Gazing", gazeTick )
