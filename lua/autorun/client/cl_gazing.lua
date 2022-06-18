local DrawColorModify = DrawColorModify
local DrawSobel = DrawSobel
local util_ScreenShake = util.ScreenShake
local IsValid = IsValid
local rawset = rawset

local math_max = math.max

local peakBrightness = -0.5
local peakContrast = 2.35
local peakVolume = 6
local peakLightShake = 5
local peakHeavyShake = 10

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

    if intensity >= 0.58 then
        util_ScreenShake( myPos, peakLightShake, peakLightShake, 0.1, 0 )
    end

    if intensity >= 0.91 then
        util_ScreenShake( myPos, peakHeavyShake, peakHeavyShake, 0.1, 0 )
    end

end

local isGazing = false

local function calcView( _, pos, angles, fov )
    if not isGazing then
        hook.Remove( "CalcView", "TheOrb_Gazing" )
        return
    end

    local intensity = localplayer():getnwfloat( "theorb_gazeintensity", 0 )

    local newFov = fov * ( 1 - intensity )
    newFov = math_max( 15, newFov )

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

    DrawColorModify( currentTable )
    local intensity = localplayer():getnwfloat( "theorb_gazeintensity", 0 )
    local sobel = 1.5 - intensity
    DrawSobel( sobel )
end

hook.Add( "PostDrawOpaqueRenderables", "TheOrb_Gazing", function( _, skybox, skybox3d )
    if skybox then return end
    if skybox3d then return end
    local plys = player.GetAll()
    local plyCount = #plys

    cam.Start3D()
        for i = 1, plyCount do
            local ply = rawget( plys, i )
            local plyIsGazing = ply:GetNWBool( "TheOrb_IsGazing", false )
            if plyIsGazing then
                local intensity = ply:GetNWFloat( "TheOrb_GazeIntensity", 0 )

                render.MaterialOverride( "models/XQM/LightLinesRed_tool" )
                render.SetBlend( intensity )
                ply:DrawModel()

                render.MaterialOverride( nil )
            end
        end
    cam.End3D()
end )

hook.Add( "CalcMainActivity", "TheOrb_Gazing", function( ply )
    local plyIsGazing = ply:GetNWBool( "TheOrb_IsGazing", false )
    if not plyIsGazing then return end

    local intensity = ply:GetNWFloat( "TheOrb_GazeIntensity", 0 )
    if intensity >= 0.2 then
        return ACT_HL2MP_IDLE_ZOMBIE, nil
    end

    if intensity >= 0.85 then
        return ACT_INVALID, nil
    end
end )

local function gazeTick()
    local target = LocalPlayer():GetEyeTrace().Entity
    local targetingOrb = target and target:GetClass() == "the_orb"

    if ( not targetingOrb ) and ( not isGazing ) then return end

    if targetingOrb and isGazing then
        local intensity = LocalPlayer():GetNWFloat( "TheOrb_GazeIntensity", 0 )
        adjustForGaze( intensity )
        updateEffectTable( intensity )
        return
    end

    if targetingOrb then
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

        hook.Add( "CalcView", "TheOrb_Gazing", calcView )
        hook.Add( "RenderScreenspaceEffects", "TheOrb_Gazing", screenEffects )
    else
        -- just looked away
        isGazing = false

        hook.Remove( "CalcView", "TheOrb_Gazing" )
        hook.Remove( "RenderScreenspaceEffects", "TheOrb_Gazing" )
        timer.Remove( "TheOrb_DelayScreaming" )

        chantSound:Stop()
        chantSound = nil

        screamSound:Stop()
    end
end

hook.Add( "InitPostEntity", "TheOrb_Setup",function()
    screamSound = CreateSound( LocalPlayer(), "ambient/levels/citadel/citadel_ambient_scream_loop1.wav" )
    screamSound:Stop()

    hook.Add( "Tick", "TheOrb_Gazing", gazeTick )
end )
