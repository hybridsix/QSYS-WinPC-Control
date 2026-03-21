-- QSYS WinPC Control Plugin
-- Author: Michael King
-- Q-SYS Designer v10+ / Core 8 Flex

--[[ #include "info.lua" ]]

function GetColor(props)
  return { 30, 90, 160 }
end

function GetPrettyName(props)
  local name = props["Computer Name"].Value
  if name ~= "" then
    return "WinPC Control  |  " .. name
  end
  return "WinPC Control  |  (unconfigured)"
end

PageNames = { "Control", "Setup" }

function GetPages(props)
  local pages = {}
  --[[ #include "pages.lua" ]]
  return pages
end

function GetModel(props)
  local model = {}
  --[[ #include "model.lua" ]]
  return model
end

function GetProperties()
  local props = {}
  --[[ #include "properties.lua" ]]
  return props
end

function GetPins(props)
  local pins = {}
  --[[ #include "pins.lua" ]]
  return pins
end

function RectifyProperties(props)
  --[[ #include "rectify_properties.lua" ]]
  return props
end

function GetComponents(props)
  local components = {}
  --[[ #include "components.lua" ]]
  return components
end

function GetWiring(props)
  local wiring = {}
  --[[ #include "wiring.lua" ]]
  return wiring
end

function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end

function GetControlLayout(props)
  local layout   = {}
  local graphics = {}
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

if Controls then
  --[[ #include "runtime.lua" ]]
end
