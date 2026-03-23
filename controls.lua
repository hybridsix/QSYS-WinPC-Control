-- =============================================================
-- controls.lua -- Win PC Control
--
-- Defines all Q-SYS control objects for this plugin.
-- Types, behaviors, and pin visibility.
-- Visual layout lives in layout.lua.
-- =============================================================


local showPower  = props["Show Power Pins"].Value
local showVolume = props["Show Volume Pins"].Value
local showStatus = props["Show Status Pins"].Value


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
  UserPin     = showPower,
  PinStyle    = "Input",
  Icon        = "Power"
})

table.insert(ctrls, {
  Name        = "Shutdown",
  ControlType = "Button",
  ButtonType  = "Momentary",
  Count       = 1,
  UserPin     = showPower,
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
  UserPin       = showStatus,
  PinStyle      = "Output"
})

table.insert(ctrls, {
  Name          = "StatusText",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = showStatus,
  PinStyle      = "Output"
})

table.insert(ctrls, {
  Name          = "LastPoll",
  ControlType   = "Indicator",
  IndicatorType = "Text",
  Count         = 1,
  UserPin       = showStatus,
  PinStyle      = "Output"
})


-- -------------------------------------------------------------
-- Audio controls -- bidirectional, poll timer keeps them in sync.
-- -------------------------------------------------------------
table.insert(ctrls, {
  Name        = "Volume",
  ControlType = "Knob",
  ControlUnit = "Percent",
  Min         = 0,
  Max         = 100,
  Count       = 1,
  UserPin     = showVolume,
  PinStyle    = "Both"
})

table.insert(ctrls, {
  Name        = "Mute",
  ControlType = "Button",
  ButtonType  = "Toggle",
  Count       = 1,
  UserPin     = showVolume,
  PinStyle    = "Both"
})
