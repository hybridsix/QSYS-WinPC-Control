-- =============================================================
-- controls.lua -- Remote PC Control
--
-- Defines all Q-SYS control objects for this plugin.
-- Types, behaviors, and pin visibility.
-- Visual layout lives in layout.lua.
-- =============================================================


-- Pin visibility is controlled by UserPin=true checkboxes in the Properties panel.
-- PinStyle sets the default state: a real style = checked (visible); "None" = unchecked (hidden).


-- -------------------------------------------------------------
-- Power controls
-- PowerOn sends a Wake-on-LAN magic packet.
-- Shutdown sends an HTTP POST to the Windows server.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name        = "PowerOn",
  ControlType = "Button",
  ButtonType  = "Momentary",
  Count       = 1,
  UserPin     = true,
  PinStyle    = "Input",
  Icon        = "Power"
})

table.insert(ctrls, {
  Name        = "Shutdown",
  ControlType = "Button",
  ButtonType  = "Momentary",
  Count       = 1,
  UserPin     = true,
  PinStyle    = "Input",
  Icon        = "Power"
})

table.insert(ctrls, {
  Name        = "Restart",
  ControlType = "Button",
  ButtonType  = "Momentary",
  Count       = 1,
  UserPin     = true,
  PinStyle    = "Input",
  Icon        = "Power"
})


-- -------------------------------------------------------------
-- Status indicators -- all output-only, reflect PC state.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name          = "OnlineStatus",
  ControlType   = "Indicator",
  IndicatorType = "LED",
  Count         = 1,
  UserPin       = true,
  PinStyle      = "Output"
})

table.insert(ctrls, {
  Name          = "StatusText",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = true,
  PinStyle      = "Output"
})

table.insert(ctrls, {
  Name          = "LastPoll",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = true,
  PinStyle      = "Output"
})


-- -------------------------------------------------------------
-- Audio controls -- bidirectional, poll timer keeps them in sync.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name        = "Volume",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min         = 0,
  Max         = 100,
  Count       = 1,
  UserPin     = true,
  PinStyle    = "Both"
})

table.insert(ctrls, {
  Name        = "VolumeMin",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min         = 0,
  Max         = 100,
  Count       = 1,
  UserPin     = false,
  PinStyle    = "None"
})

table.insert(ctrls, {
  Name        = "VolumeMax",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min         = 0,
  Max         = 100,
  Count       = 1,
  UserPin     = false,
  PinStyle    = "None"
})

table.insert(ctrls, {
  Name          = "VolumeWarning",
  ControlType   = "Indicator",
  IndicatorType = "LED",
  Count         = 1,
  UserPin       = false,
  PinStyle      = "None"
})

table.insert(ctrls, {
  Name        = "Mute",
  ControlType = "Button",
  ButtonType  = "Toggle",
  Count       = 1,
  UserPin     = true,
  PinStyle    = "Both"
})


-- -------------------------------------------------------------
-- Volume entry -- editable text box for typing an exact volume.
-- Syncs bidirectionally with the Volume fader.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name        = "VolumeEntry",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min         = 0,
  Max         = 100,
  Count       = 1,
  UserPin     = false,
  PinStyle    = "None"
})


-- -------------------------------------------------------------
-- Discovered hostname -- auto-populated from HOSTNAME: field in
-- each successful /status response. Shown on the Control page.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name          = "DiscoveredName",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = false,
  PinStyle      = "None"
})


-- -------------------------------------------------------------
-- Setup page editable fields - mirror Properties for runtime editing.
-- These are text/integer entry controls placed on the Setup tab.
-- The Update button writes their values back to Properties.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name          = "CfgComputerName",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = false,
  PinStyle      = "None"
})

table.insert(ctrls, {
  Name          = "CfgHostname",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = false,
  PinStyle      = "None"
})

table.insert(ctrls, {
  Name          = "MacDisplay",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = false,
  PinStyle      = "None"
})

table.insert(ctrls, {
  Name        = "CfgHttpPort",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min         = 1024,
  Max         = 65535,
  Count       = 1,
  UserPin     = false,
  PinStyle    = "None"
})

table.insert(ctrls, {
  Name        = "CfgPollInterval",
  ControlType = "Knob",
  ControlUnit = "Integer",
  Min         = 5,
  Max         = 300,
  Count       = 1,
  UserPin     = false,
  PinStyle    = "None"
})

table.insert(ctrls, {
  Name          = "CfgAuthToken",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = false,
  PinStyle      = "None"
})

table.insert(ctrls, {
  Name        = "CfgUpdate",
  ControlType = "Button",
  ButtonType  = "Momentary",
  Count       = 1,
  UserPin     = false,
  PinStyle    = "None"
})

