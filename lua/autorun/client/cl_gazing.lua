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

local surface_SetMaterial = surface.SetMaterial
local surface_GetAlphaMultiplier = surface.GetAlphaMultiplier
local surface_SetAlphaMultiplier = surface.SetAlphaMultiplier
local surface_DrawPoly = surface.DrawPoly

local cam_Start3D2D = cam.Start3D2D
local cam_End3D2D = cam.End3D2D

local peakBrightness = -0.15
local peakContrast = 2
local peakVolume = 6
local peakLightShake = 5
local peakHeavyShake = 10
local overlayMat = Material( "effects/tp_eyefx/tpeye2" )
local beamMat = Material( "effects/tp_eyefx/tpeye" )
local linesMat = Material( "models/XQM/LightLinesRed_tool" )

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
local ourOrb

local function drawCircle( x, y, radius, seg, intensity )
    intensity = intensity / 2
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

    surface_DrawPoly( cir )
end

local function drawOrbOverlay( orb, intensity )
    local displacement = orb:GetPos() - LocalPlayer():EyePos()
    local right        = displacement:Angle():Right()
    local surfacePos = orb:GetPos() - displacement:GetNormalized() * orb:BoundingRadius()
    local surfaceAng = displacement:Cross( right ):Angle()

    cam_Start3D2D( surfacePos, surfaceAng, 1 )

    local alpha = surface_GetAlphaMultiplier()
    surface.SetDrawColor( 255, 255, 255, 255 * intensity )
    surface_SetMaterial( overlayMat )
    surface_SetAlphaMultiplier( intensity )
    drawCircle( 0, 0, 20 * intensity, ( 220 * intensity ) + 20, intensity )
    surface_SetAlphaMultiplier( alpha )

    cam_End3D2D()
end

local function updateEffectTable( intensity )
    local brightness = peakBrightness * intensity
    rawset( currentTable, "$pp_colour_brightness", brightness )

    local contrast = 1 + ( peakContrast * intensity )
    rawset( currentTable, "$pp_colour_contrast", contrast )

    local color = math.max( 0.25, 1 - intensity )
    rawset( currentTable, "$pp_colour_colour", color )
end

local function adjustForGaze( intensity )
    if chantSound then
        chantSound:SetPos( LocalPlayer():GetPos() )
        chantSound:SetVolume( intensity * peakVolume )
    end

    if screamSound:IsPlaying() then
        screamSound:ChangeVolume( intensity * peakVolume, 0 )
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
    local sobel = 1.5 - intensity
    _G.DrawSobel( sobel )
end

local orbMat = CreateMaterial( "THEORB", "UnlitGeneric", {
    ["$basetexture"] = "models/xqm/lightlinesred",
    ["$detail"] = "maxofs2d/terrain_detail",
    ["$surfaceprop"] = "metal",
    ["$bumpmap"] = "models/xqm/lightlinesred_normal",
    ["$phong"] = 1,
    ["$phongexponent"] = 30,
    ["$phongboost"] = 2,
    ["$phongfresnelranges"] = Vector( 0.05, 0.6, 1 ),
    ["$nofog"] = 1,
    ["$model"] = 1,
    ["$ignorez"] = 1,
    ["$flags"] = 134219840,
    ["$flags2"] = 262226,
} )

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
                    -- blend = render.GetBlend()
                    -- render_MaterialOverride( orbMat )
                    -- render_SetBlend( intensity )
                    -- orb:DrawModel()
                    -- render_MaterialOverride()
                    -- render_SetBlend( blend )

                    drawOrbOverlay( orb, intensity )
                else
                    local segments = generateSegments( orb, ply, 0.6, 0.35 )
                    local segmentCount = #segments

                    render_StartBeam( segmentCount )
                    render_SetMaterial( beamMat )

                    for j = 1, segmentCount do
                        local segment = rawget( segments, j )
                        local distanceFromCenter
                        if j > segmentCount / 2 then
                            distanceFromCenter = j - segmentCount / 2
                        else
                            distanceFromCenter = segmentCount / 2 - j
                        end

                        local beamWidth = 2 + ( 30 - distanceFromCenter )

                        render_AddBeam( segment, beamWidth, j / segmentCount )
                    end
                    render_EndBeam()
                end
            end
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

        timer.Create( "TheOrb_DelayScreaming", 8, 1, function()
            screamSound:PlayEx( 0.1, 100 )
            screamSound:SetSoundLevel( 140 )
        end )

        local fogFunc = function( mod )
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

        hook.Add( "SetupWorldFog", "TheOrb_Gazing", fogFunc )
        hook.Add( "SetupSkyboxFog", "TheOrb_Gazing", fogFunc )
        hook.Add( "CalcView", "TheOrb_Gazing", calcView )
        hook.Add( "RenderScreenspaceEffects", "TheOrb_Gazing", screenEffects )

    else
        -- just looked away
        isGazing = false

        hook.Remove( "SetupWorldFog", "TheOrb_Gazing" )
        hook.Remove( "SetupSkyboxFog", "TheOrb_Gazing" )
        hook.Remove( "CalcView", "TheOrb_Gazing" )
        hook.Remove( "RenderScreenspaceEffects", "TheOrb_Gazing" )
        timer.Remove( "TheOrb_DelayScreaming" )

        if chantSound then
            chantSound:Stop()
            chantSound = nil
        end

        screamSound:Stop()

        if ourOrb then
            ourOrb = nil
        end
    end
end

function setupOrbGazing()
    screamSound = CreateSound( LocalPlayer(), "ambient/levels/citadel/citadel_ambient_scream_loop1.wav" )
    screamSound:Stop()

    hook.Add( "Tick", "TheOrb_Gazing", gazeTick )
end


hook.Add( "InitPostEntity", "TheOrb_Setup", setupOrbGazing )
