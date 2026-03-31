local CurrentPage = PageNames[props["page_index"].Value]

-- ============================================================
-- CONTROL PAGE
-- ============================================================
  -- Layout constants - 5px grid, panel width = 500px (boxes x=5, w=490):
  --
  --  Power Control box:   y=5,   h=80  → bottom=85
  --  gap=10
  --  Status box:          y=95,  h=125  → bottom=220
  --  gap=10
  --  Audio box:           y=230, h=110
  --
  local W          = 490   -- box interior width
  local statusY    = 95
  local statusBoxH = 125
  local audioY     = 230
  local panelH     = audioY + 110 + 10

if CurrentPage == "Control" then

  -- ---- Power Control box: y=5, h=80 ----
  table.insert(graphics, {
    Type         = "GroupBox",
    Text         = "Power Control",
    Fill         = { 195, 195, 195 },
    StrokeWidth  = 2,
    StrokeColor  = { 0, 210, 255 },
    CornerRadius = 8,
    Position     = { 5, 5 },
    Size         = { W, 80 }
  })

  -- Buttons: 130px wide each, 20px gap, centered in W=490
  -- total = 2*130+20 = 280; left edge = (490-280)/2 + 5 = 110
  layout["PowerOn"] = {
    PrettyName = "Power~WOL",
    Style      = "Button",
    Legend     = "Power On (WOL)",
    Position   = { 110, 35 },
    Size       = { 130, 30 },
    Color      = { 0, 200, 220 }
  }

  layout["Shutdown"] = {
    PrettyName = "Power~Shutdown",
    Style      = "Button",
    Legend     = "Shutdown",
    Position   = { 260, 35 },
    Size       = { 130, 30 },
    Color      = { 255, 140, 0 }
  }

  -- ---- Connection Status box: y=95 ----
  table.insert(graphics, {
    Type         = "GroupBox",
    Text         = "Connection Status",
    Fill         = { 200, 200, 200 },
    StrokeWidth  = 2,
    StrokeColor  = { 0, 210, 255 },
    CornerRadius = 8,
    Position     = { 5, statusY },
    Size         = { W, statusBoxH }
  })

  -- Label column: right-aligned, x=10, w=75, ends at x=85
  -- LED:          x=90, w=20, ends at x=110
  -- Text box:     x=115, w=355 (fills to box right edge 5+490-10=485 → 485-115=370, snap to 355 leaving 15px margin)
  local labelX  = 10
  local labelW  = 75
  local ledX    = 90
  local textX   = 115
  local textW   = 355

  table.insert(graphics, {
    Type        = "Text",
    Text        = "Status:",
    Position    = { labelX, statusY + 30 },
    Size        = { labelW, 20 },
    FontSize    = 11,
    HTextAlign  = "Right",
    Color       = { 60, 60, 60 }
  })

  layout["OnlineStatus"] = {
    PrettyName = "Status~Online",
    Style      = "Indicator",
    Color      = { 0, 200, 0 },
    Position   = { ledX, statusY + 32 },
    Size       = { 16, 16 }
  }

  layout["StatusText"] = {
    PrettyName = "Status~Text",
    Style      = "Text",
    Color      = { 180, 0, 0 },
    Position   = { textX, statusY + 30 },
    Size       = { textW, 20 },
    FontSize   = 11
  }

  table.insert(graphics, {
    Type       = "Text",
    Text       = "PC Name:",
    Position   = { labelX, statusY + 55 },
    Size       = { labelW, 20 },
    FontSize   = 11,
    HTextAlign = "Right",
    Color      = { 60, 60, 60 }
  })

  layout["DiscoveredName"] = {
    PrettyName = "Status~PC Hostname",
    Style      = "Text",
    Position   = { textX, statusY + 55 },
    Size       = { textW, 20 },
    FontSize   = 11
  }

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Last Poll:",
    Position   = { labelX, statusY + 80 },
    Size       = { labelW, 20 },
    FontSize   = 11,
    HTextAlign = "Right",
    Color      = { 60, 60, 60 }
  })

  layout["LastPoll"] = {
    PrettyName = "Status~Last Poll",
    Style      = "Text",
    Position   = { textX, statusY + 80 },
    Size       = { textW, 20 },
    FontSize   = 11
  }

  -- ---- Audio box: y=audioY, h=110 ----
  table.insert(graphics, {
    Type         = "GroupBox",
    Text         = "Audio",
    Fill         = { 195, 195, 195 },
    StrokeWidth  = 2,
    StrokeColor  = { 0, 210, 255 },
    CornerRadius = 8,
    Position     = { 5, audioY },
    Size         = { W, 110 }
  })

  -- Volume row: label | fader | digit box | Mute button
  -- Fader: from x=75, 240px wide
  -- Digit box: x=320, 55px wide (type exact volume)
  -- Mute: 100px wide at x=385
  table.insert(graphics, {
    Type       = "Text",
    Text       = "Volume:",
    Position   = { 10, audioY + 30 },
    Size       = { 60, 20 },
    FontSize   = 12,
    HTextAlign = "Right",
    Color      = { 60, 60, 60 }
  })

  layout["Volume"] = {
    PrettyName = "Audio~Vol",
    Style      = "Fader",
    Position   = { 75, audioY + 30 },
    Size       = { 240, 20 }
  }

  layout["VolumeEntry"] = {
    PrettyName = "Audio~Vol Entry",
    Style      = "TextBox",
    Position   = { 320, audioY + 28 },
    Size       = { 55, 24 },
    FontSize   = 12
  }

  layout["Mute"] = {
    PrettyName = "Audio~Mute",
    Style      = "Button",
    Legend     = "Mute",
    Position   = { 385, audioY + 25 },
    Size       = { 100, 30 },
    Color      = { 213, 0, 0 }
  }

  -- Min/Max row: label | field | spacer | label | field | warning LED
  -- Min label+field on left, Max label+field centered-ish, warning LED on far right
  table.insert(graphics, {
    Type       = "Text",
    Text       = "Vol Min:",
    Position   = { 10, audioY + 70 },
    Size       = { 60, 20 },
    FontSize   = 11,
    HTextAlign = "Right",
    Color      = { 60, 60, 60 }
  })

  layout["VolumeMin"] = {
    PrettyName = "Audio~Volume Min",
    Style      = "TextBox",
    Position   = { 75, audioY + 70 },
    Size       = { 70, 20 },
    FontSize   = 11
  }

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Vol Max:",
    Position   = { 165, audioY + 70 },
    Size       = { 60, 20 },
    FontSize   = 11,
    HTextAlign = "Right",
    Color      = { 60, 60, 60 }
  })

  layout["VolumeMax"] = {
    PrettyName = "Audio~Volume Max",
    Style      = "TextBox",
    Position   = { 230, audioY + 70 },
    Size       = { 70, 20 },
    FontSize   = 11
  }

  -- Warning LED + label: shown when PC volume is outside min/max
  table.insert(graphics, {
    Type       = "Text",
    Text       = "Out of range:",
    Position   = { 315, audioY + 70 },
    Size       = { 80, 20 },
    FontSize   = 10,
    HTextAlign = "Right",
    Color      = { 60, 60, 60 }
  })

  layout["VolumeWarning"] = {
    PrettyName = "Audio~Out of Range",
    Style      = "Indicator",
    Position   = { 400, audioY + 72 },
    Size       = { 16, 16 },
    Color      = { 255, 140, 0 }
  }

-- ============================================================
-- SETUP PAGE
-- ============================================================
elseif CurrentPage == "Setup" then

  table.insert(graphics, {
    Type         = "GroupBox",
    Text         = "Connection Configuration",
    Fill         = { 200, 200, 200 },
    StrokeWidth  = 2,
    StrokeColor  = { 0, 210, 255 },
    CornerRadius = 8,
    Position     = { 5, 5 },
    Size         = { 490, 200 }
  })

  local function cfg_label(text, y)
    table.insert(graphics, {
      Type       = "Text",
      Text       = text,
      Position   = { 12, y },
      Size       = { 110, 16 },
      FontSize   = 11,
      HTextAlign = "Right",
      Color      = { 60, 60, 60 }
    })
  end

  -- Auto-populated / read-only fields - grey styling, no border.
  local function cfg_auto(name, y)
    return {
      PrettyName  = "Setup~" .. name,
      Style       = "Text",
      Position    = { 127, y },
      Size        = { 250, 16 },
      FontSize    = 11,
      HTextAlign  = "Left",
      Color       = { 160, 160, 160 },
      StrokeWidth = 0,
      Fill        = { 40, 40, 40 }
    }
  end

  -- Editable fields - black fill, white text, cyan border.
  local function cfg_edit(name, y)
    return {
      PrettyName  = "Setup~" .. name,
      Style       = "Text",
      Position    = { 127, y },
      Size        = { 250, 16 },
      FontSize    = 11,
      HTextAlign  = "Left",
      Color       = { 255, 255, 255 },
      StrokeColor = { 0, 210, 255 },
      StrokeWidth = 1,
      Fill        = { 0, 0, 0 }
    }
  end

  cfg_label("Computer Name:",  35)
  layout["CfgComputerName"] = cfg_auto("Computer Name", 35)

  cfg_label("Hostname / IP:",  55)
  layout["CfgHostname"] = cfg_auto("Hostname", 55)

  cfg_label("MAC Address:",    75)
  layout["MacDisplay"] = cfg_auto("MAC Display", 75)

  cfg_label("HTTP Port:",      95)
  layout["CfgHttpPort"] = cfg_edit("HTTP Port", 95)

  cfg_label("Poll Interval:", 115)
  layout["CfgPollInterval"] = cfg_edit("Poll Interval", 115)

  cfg_label("Auth Token:",    135)
  layout["CfgAuthToken"] = cfg_auto("Auth Token", 135)

  -- Update button
  layout["CfgUpdate"] = {
    PrettyName  = "Setup~Update",
    Style       = "Button",
    ButtonStyle = "Normal",
    Legend      = "Update",
    Position    = { 380, 155 },
    Size        = { 107, 25 },
    FontSize    = 12,
    Color       = { 255, 255, 255 },
    UnvisibleColor = { 0, 0, 0 },
    StrokeColor = { 0, 210, 255 },
    StrokeWidth = 2,
    CornerRadius = 4
  }

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Grey fields are auto-populated.  Cyan-bordered fields can be changed at runtime.",
    Position   = { 12, 160 },
    Size       = { 365, 14 },
    FontSize   = 9,
    HTextAlign = "Left",
    Color      = { 105, 104, 104 }
  })

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Token is stored in C:\\QSYS Remote PC Control\\config.txt on the Windows PC.",
    Position   = { 12, 175 },
    Size       = { 475, 14 },
    FontSize   = 9,
    HTextAlign = "Left",
    Color      = { 105, 104, 104 }
  })

end
