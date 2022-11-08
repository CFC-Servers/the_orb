local util_ScreenShake = util.ScreenShake
local IsValid = IsValid
local rawget = rawget
local rawset = rawset

local math_max = math.max

local render_StartBeam = render.StartBeam
local render_AddBeam = render.AddBeam
local render_EndBeam = render.EndBeam
local render_SetMaterial = render.SetMaterial
local render_MaterialOverride = render.MaterialOverride
local render_SetBlend = render.SetBlend
local render_SetShadowsDisabled = render.SetShadowsDisabled
local render_SetLightingMode = render.SetLightingMode

local peakBrightness = -0.5
local peakContrast = 2.35
local peakVolume = 6
local peakLightShake = 5
local peakHeavyShake = 10

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


local function updateEffectTable( intensity )
    local brightness = peakBrightness * intensity
    rawset( currentTable, "$pp_colour_brightness", brightness )

    local contrast = 1 + ( peakContrast * intensity )
    rawset( currentTable, "$pp_colour_contrast", contrast )

    local color = 1 - intensity
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

local beamMat = Material( "effects/tp_eyefx/tpeye" )
local linesMat = Material( "models/XQM/LightLinesRed_tool" )

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

                render_MaterialOverride( linesMat )
                render_SetBlend( intensity )
                ply:DrawModel()
                render_MaterialOverride( nil )

                local orb = ply:GetNW2Entity( "TheOrb_GazingAt" )
                if IsValid( orb ) then
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

                    if ply == LocalPlayer() then
                        local blend = render.GetBlend()
                        render_SetLightingMode( 1 )
                        render.SuppressEngineLighting( true )

                        render_SetBlend( 1 - intensity )
                        render_MaterialOverride( linesMat )
                        orb:DrawModel()

                        render_SetBlend( intensity / 2 )
                        render_MaterialOverride( "debug/env_cubemap_model" )
                        orb:DrawModel()

                        render_SetBlend( intensity )
                        render_MaterialOverride( "pp/sunbeams" )
                        orb:DrawModel()

                        render_SetShadowsDisabled( true )
                        render_SetLightingMode( 0 )
                        render.SuppressEngineLighting( false )
                        render_SetBlend( blend )
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

        ourOrb:SetNoDraw( true )
        ourOrb:DrawShadow( false )

        local fogFunc = function( mod )
            mod = mod or 1
            render.FogMode( MATERIAL_FOG_LINEAR )

            local intensity = gazeIntensity()

            local fogStart, fogEnd

            if intensity <= 0.25 then
                fogStart = 85000 - math.Remap( intensity, 0, 0.25, 0, 80000 )
                fogEnd = 100000 - math.Remap( intensity, 0, 0.25, 0, 93000 )
            else
                fogStart = 5000 - math.Remap( intensity, 0.25, 1, 0, 5000 )
                fogEnd = 7000 - math.Remap( intensity, 0.25, 1, 0, 6000 )
            end

            print( fogStart, fogEnd )

            render.FogStart( fogStart * mod )
            render.FogEnd( fogEnd * mod )
            render.FogMaxDensity( math.Remap( intensity, 0, 1, 0.75, 0.9 ) )
            render.FogColor( 125, 15, 15 )
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
            ourOrb:SetNoDraw( false )
            ourOrb:DrawShadow( true )
            ourOrb = nil
        end
    end
end

hook.Add( "Tick", "TheOrb_Setup", function()
    if not LocalPlayer then return end
    hook.Remove( "Tick", "TheOrb_Setup" )

    screamSound = CreateSound( LocalPlayer(), "ambient/levels/citadel/citadel_ambient_scream_loop1.wav" )
    screamSound:Stop()

    hook.Add( "Tick", "TheOrb_Gazing", gazeTick )
end )
