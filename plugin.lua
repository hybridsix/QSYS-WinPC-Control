-- =============================================================
-- plugin.lua -- Win PC Control
-- Author: Michael King
--
-- This is the ENTRY POINT for the Q-SYS plugin compiler (PLUGCC).
-- PLUGCC reads this file and expands all the #include directives
-- into a single .qplug output file that Q-SYS Designer loads.
--
-- The functions in this file define how the plugin appears and
-- behaves at DESIGN TIME (in Q-SYS Designer). Runtime behavior
-- lives in runtime.lua and only executes on a running Core.
--
-- File structure:
--   info.lua            -- Plugin name, version, GUID, author
--   properties.lua      -- User-configurable properties (IP, port, token, etc.)
--   controls.lua        -- Control definitions (buttons, LEDs, faders)
--   layout.lua          -- Visual layout of controls on the plugin panel pages
--   pages.lua           -- Defines the tab pages shown in Designer
--   model.lua           -- Hardware model entry shown in Designer
--   pins.lua            -- External signal pins (audio, video -- unused here)
--   components.lua      -- Internal Q-SYS components (mixer, etc. -- unused here)
--   wiring.lua          -- Internal component wiring (unused here)
--   rectify_properties.lua -- Post-processing of property visibility
--   runtime.lua         -- All live runtime logic executed on the Core
-- =============================================================

--[[ #include "info.lua" ]]


-- -------------------------------------------------------------
-- GetColor(props)
-- Returns the RGB color of the colored bar on the plugin block
-- in the Q-SYS Designer schematic view.
-- Using Clair Global "Patch of Blue" brand color: #15a3d5
-- Change to a different RGB triple if branding changes.
-- -------------------------------------------------------------
function GetColor(props)
  return { 0, 210, 255 }
end


-- -------------------------------------------------------------
-- GetPrettyName(props)
-- Returns the label shown on the plugin block face in Designer.
-- We show the Computer Name property so the operator can tell
-- at a glance which PC this block controls.
-- If Computer Name hasn't been set yet, show "(unconfigured)"
-- as a reminder that setup is needed.
-- -------------------------------------------------------------
function GetPrettyName(props)
  local name = props["Computer Name"].Value
  if name ~= "" then
    return "Win PC Control\n" .. name
  end
  return "Win PC Control\n(unconfigured)"
end


-- -------------------------------------------------------------
-- PageNames
-- Fixed page list: Control and Setup only.
-- Referenced by layout.lua at design time, so must be declared
-- at module scope (not only inside GetPages).
-- -------------------------------------------------------------
PageNames = { "Control", "Setup" }


-- -------------------------------------------------------------
-- GetPages(props)
-- Populates the pages table from PageNames via pages.lua.
-- -------------------------------------------------------------
function GetPages(props)
  local pages = {}
  --[[ #include "pages.lua" ]]
  return pages
end


-- -------------------------------------------------------------
-- GetModel(props)
-- Returns the hardware model list shown in the Designer
-- plugin properties panel. We use a single fixed model entry.
-- -------------------------------------------------------------
function GetModel(props)
  local model = {}
  --[[ #include "model.lua" ]]
  return model
end


-- -------------------------------------------------------------
-- GetProperties()
-- Returns all user-configurable property definitions.
-- These appear in the plugin's Properties panel in Designer.
-- -------------------------------------------------------------
function GetProperties()
  local props = {}
  --[[ #include "properties.lua" ]]
  return props
end


-- -------------------------------------------------------------
-- GetPins(props)
-- Returns any external signal pins (audio, video, etc.).
-- This plugin has no audio/video pins -- only control pins.
-- -------------------------------------------------------------
function GetPins(props)
  local pins = {}
  --[[ #include "pins.lua" ]]
  return pins
end


-- -------------------------------------------------------------
-- RectifyProperties(props)
-- Called by Designer after properties are loaded. Lets us
-- show/hide or modify properties dynamically based on values.
-- For example: hiding the Debug Print property when set to None.
-- -------------------------------------------------------------
function RectifyProperties(props)
  --[[ #include "rectify_properties.lua" ]]
  return props
end


-- -------------------------------------------------------------
-- GetComponents(props)
-- Returns any internal Q-SYS components used by the plugin
-- (e.g. mixers, delays). This plugin has none.
-- -------------------------------------------------------------
function GetComponents(props)
  local components = {}
  --[[ #include "components.lua" ]]
  return components
end


-- -------------------------------------------------------------
-- GetWiring(props)
-- Returns wiring between internal components.
-- This plugin has no internal components, so nothing to wire.
-- -------------------------------------------------------------
function GetWiring(props)
  local wiring = {}
  --[[ #include "wiring.lua" ]]
  return wiring
end


-- -------------------------------------------------------------
-- GetControls(props)
-- Returns all control definitions (buttons, LEDs, knobs, etc.)
-- and their pin visibility settings.
-- -------------------------------------------------------------
function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end


-- -------------------------------------------------------------
-- GetControlLayout(props)
-- Returns the visual layout of controls for the plugin panel.
-- layout  = table of control positions/styles/labels
-- graphics = table of background shapes, text labels, group boxes
-- -------------------------------------------------------------
function GetControlLayout(props)
  local layout   = {}
  local graphics = {}
  --[[ #include "layout.lua" ]]
  return layout, graphics
end


-- -------------------------------------------------------------
-- Runtime inclusion
-- The "if Controls then" guard ensures runtime.lua only runs
-- on a live Core (where Controls are instantiated). It is skipped
-- during design-time evaluation in Q-SYS Designer.
-- -------------------------------------------------------------
if Controls then
  --[[ #include "runtime.lua" ]]
end
