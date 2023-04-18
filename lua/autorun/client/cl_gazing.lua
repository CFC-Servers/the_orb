local Lerp = Lerp

local rawget = rawget
local rawset = rawset
local IsValid = IsValid
local EyeAngles = EyeAngles
local LocalPlayer = LocalPlayer
local util_ScreenShake = util.ScreenShake

local table_insert = table.insert

local math_max = math.max
local math_rad = math.rad
local math_sin = math.sin
local math_cos = math.cos
local math_random = math.random

local draw_NoTexture = draw.NoTexture

local render_Clear = render.Clear
local render_AddBeam = render.AddBeam
local render_EndBeam = render.EndBeam
local render_GetBlend = render.GetBlend
local render_SetBlend = render.SetBlend
local render_StartBeam = render.StartBeam
local render_RenderView = render.RenderView
local render_SetMaterial = render.SetMaterial
local render_ClearStencil = render.ClearStencil
local render_PopRenderTarget = render.PopRenderTarget
local render_SetLightingMode = render.SetLightingMode
local render_SetColorMaterial = render.SetColorMaterial
local render_PushRenderTarget = render.PushRenderTarget
local render_MaterialOverride = render.MaterialOverride
local render_SetStencilEnable = render.SetStencilEnable
local render_SetStencilTestMask = render.SetStencilTestMask
local render_OverrideDepthEnable = render.OverrideDepthEnable
local render_SetStencilWriteMask = render.SetStencilWriteMask
local render_DrawTextureToScreen = render.DrawTextureToScreen
local render_WorldMaterialOverride = render.WorldMaterialOverride
local render_BrushMaterialOverride = render.BrushMaterialOverride
local render_ModelMaterialOverride = render.ModelMaterialOverride
local render_SetStencilFailOperation = render.SetStencilFailOperation
local render_SetStencilPassOperation = render.SetStencilPassOperation
local render_SetStencilReferenceValue = render.SetStencilReferenceValue
local render_SetStencilZFailOperation = render.SetStencilZFailOperation
local render_SetStencilCompareFunction = render.SetStencilCompareFunction

local STENCIL_KEEP = STENCIL_KEEP
local STENCIL_NEVER = STENCIL_NEVER
local STENCIL_REPLACE = STENCIL_REPLACE
local IMAGE_FORMAT_RGBA8888 = IMAGE_FORMAT_RGBA8888
local MATERIAL_RT_DEPTH_SHARED = MATERIAL_RT_DEPTH_SHARED
local CREATERENDERTARGETFLAGS_UNFILTERABLE_OK = CREATERENDERTARGETFLAGS_UNFILTERABLE_OK

local surface_SetDrawColor = surface.SetDrawColor
local surface_DrawPoly = surface.DrawPoly

local cam_End3D = cam.End3D
local cam_Start3D = cam.Start3D
local cam_End3D2D = cam.End3D2D
local cam_Start3D2D = cam.Start3D2D

local vec_zero = Vector( 0, 0, 0 )

local peakBrightness = -0.25
local peakContrast = 1.075
local peakVolume = 7
local peakLightShake = 4.5
local peakHeavyShake = 4

local bloomDarken = 0.8
local bloomMultiply = 0
local bloomColorMultiply = 1
local bloomPasses = 1
local bloomR = 0.25

local beamMat = Material( "effects/tp_eyefx/tpeye" )
local linesMat = Material( "models/XQM/LightLinesRed_tool" )
local lineworldModelMat = Material( "models/props_combine/tprings_globe" )

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

local function resetStencils()
  render_SetStencilWriteMask( 0xFF )
  render_SetStencilTestMask( 0xFF )
  render_SetStencilReferenceValue( 0 )
  render_SetStencilCompareFunction( STENCIL_ALWAYS )
  render_SetStencilPassOperation( STENCIL_KEEP )
  render_SetStencilFailOperation( STENCIL_KEEP )
  render_SetStencilZFailOperation( STENCIL_KEEP )
  render_ClearStencil()
end

--- @param radius number The radius of the circle
--- @param seg number The number of segments to use for the circle
--- @param instability number The amount of randomness to add to the circle ( 0-1, 0 = perfect circle )
local function makeCircle( radius, seg, instability )
  local cir = {}
  instability = instability or 0

  table_insert( cir, { x = 0, y = 0, u = 0.5, v = 0.5 } )

  local minRadMod = 0.1
  local maxRadMod = 0.5

  local a, sin_a, cos_a, segRadius, radModifier
  for i = 0, seg do
    a = math_rad( ( i / seg ) * -360 )
    sin_a = math_sin( a )
    cos_a = math_cos( a )

    segRadius = radius
    if instability > 0 then
      radModifier = math_random() * ( maxRadMod - minRadMod )
      segRadius = Lerp( instability, radius, radius * radModifier )
    end

    table_insert( cir, {
      x = sin_a * segRadius,
      y = cos_a * segRadius,
      u = sin_a / 2 + 0.5,
      v = cos_a / 2 + 0.5
    } )
  end

  a = math_rad( 0 )
  table_insert( cir, {
    x = math_sin( a ) * radius,
    y = math_cos( a ) * radius,
    u = math_sin( a ) / 2 + 0.5,
    v = math_cos( a ) / 2 + 0.5
  } )

  return cir
end

local isDrawingLineWorld = false
local renderViewParams = { drawviewmodel = false, drawhud = false, }

local lineWorldRT = GetRenderTargetEx(
  "the_orb_lineworld", ScrW(), ScrH(),
  RT_SIZE_OFFSCREEN,
  MATERIAL_RT_DEPTH_SHARED,
  0,
  0,
  IMAGE_FORMAT_RGBA8888
)

local function drawOrbOverlay( orb, intensity )
  if isDrawingLineWorld then return end

  local trace = LocalPlayer():GetEyeTrace()
  local orbPos = orb:GetPos()
  local camAngle = EyeAngles()
  camAngle.roll = 0
  camAngle:RotateAroundAxis( camAngle:Up(), -90 )
  camAngle:RotateAroundAxis( camAngle:Forward(), 90 )

  local camPos = orbPos - ( trace.Normal * ( orb:BoundingRadius() + 3 ) )

  local function getCircle( scaleMod, instability, segments )
    scaleMod = scaleMod or 1
    segments = segments or 12
    return makeCircle( ( scaleMod * 22 ) * intensity, segments, instability )
  end

  isDrawingLineWorld = true
  -- Create the line world
  render_PushRenderTarget( lineWorldRT )
    render_Clear( 0, 0, 0, 255, true, false )

    -- Setup material overrides
    render_SetLightingMode( 1 )
    render_MaterialOverride( linesMat )
    render_WorldMaterialOverride( linesMat )
    render_BrushMaterialOverride( linesMat )
    render_ModelMaterialOverride( lineworldModelMat )

    -- Draw the line world
    render_RenderView( renderViewParams )

    -- Reset overrides
    render_SetLightingMode( 0 )
    render_MaterialOverride( nil )
    render_WorldMaterialOverride( nil )
    render_BrushMaterialOverride( nil )
    render_ModelMaterialOverride( nil )

    draw.NoTexture()
    orb:DrawModel()
  render_PopRenderTarget()
  isDrawingLineWorld = false

  -- Draw outer container circle
  local circle
  cam_Start3D2D( camPos, camAngle, 1 )
    circle = getCircle( 29, 0.025, 1024 )
    surface_SetDrawColor( 0, 0, 0, 255 )
    render.SetColorMaterial()
    surface_DrawPoly( circle )
  cam_End3D2D()

  resetStencils()

  -- Enable stencil
  render_SetStencilEnable( true )
  render_SetStencilWriteMask( 0xFF )
  render_SetStencilTestMask( 0xFF )
  render_SetStencilReferenceValue( 1 )
  render_SetStencilCompareFunction( STENCIL_NEVER )
  render_SetStencilFailOperation( STENCIL_REPLACE )
  render_SetStencilZFailOperation( STENCIL_KEEP )
  render_SetStencilPassOperation( STENCIL_KEEP )

  -- Draw the growing circle
  cam_Start3D2D( camPos, camAngle, 1 )
    circle = getCircle( 32, 0.35, 512 )
    surface_SetDrawColor( 240, 240, 240, 255 )
    draw_NoTexture()
    surface_DrawPoly( circle )
  cam_End3D2D()

  -- Set up stencil to punch through real world
  render_SetStencilCompareFunction( STENCIL_EQUAL )
  render_SetStencilFailOperation( STENCIL_KEEP )

  -- Draw the Lines world
  render_DrawTextureToScreen( lineWorldRT )

  -- Let everything render normally again
  render_SetStencilEnable( false )
end

local function updateEffectTable( intensity )
  local isLocked = intensity > 0.88

  local contrast = isLocked and 1 or 1 + ( peakContrast * intensity )
  rawset( currentTable, "$pp_colour_contrast", contrast )

  local brightness = isLocked and ( peakBrightness * 0.25 ) or peakBrightness * intensity
  rawset( currentTable, "$pp_colour_brightness", brightness )

  local color = isLocked and 1 or math.max( 0.75, 1 - intensity )
  rawset( currentTable, "$pp_colour_colour", color )

  bloomDarken = isLocked and 0.4 or 1 - ( 0.85 * intensity )
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
  local sobel = 3 - intensity
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

hook.Add( "PostDraw2DSkyBox", "TheOrb_LineWorld", function()
  -- Draw black over the skybox if we're drawing LineWorld
  if not isDrawingLineWorld then return end
  render_OverrideDepthEnable( true, false )
  render_SetLightingMode( 2 )

  cam_Start3D( vec_zero, EyeAngles() )
      render_SetColorMaterial()
      render_Clear( 0, 0, 0, 255, true, false )
  cam_End3D()

  render_OverrideDepthEnable( false, false )
  render_SetLightingMode( 0 )
end)

hook.Add( "PostDrawTranslucentRenderables", "TheOrb_Gazing", function( _, skybox, skybox3d )
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

    LocalPlayer():SetDSP( 16 )

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

print( "The Orb loaded gazing module!" )
