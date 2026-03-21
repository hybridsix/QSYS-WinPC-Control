local CurrentPage = PageNames[props["page_index"].Value]

-- ============================================================
-- CONTROL PAGE
-- ============================================================
if CurrentPage == "Control" then

  -- Background
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "",
    Fill        = { 220, 220, 220 },
    StrokeWidth = 0,
    Position    = { 0, 0 },
    Size        = { 400, 228 }
  })

  -- ---- Power Control ----
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "Power Control",
    Fill        = { 200, 215, 235 },
    StrokeWidth = 1,
    StrokeColor = { 120, 140, 170 },
    Position    = { 5, 5 },
    Size        = { 390, 52 }
  })

  layout["PowerOn"] = {
    PrettyName = "Power~Power On",
    Style      = "Button",
    Legend     = "Power On",
    Position   = { 12, 23 },
    Size       = { 115, 26 },
    Color      = { 0, 180, 0 }
  }

  layout["Shutdown"] = {
    PrettyName = "Power~Shutdown",
    Style      = "Button",
    Legend     = "Shutdown",
    Position   = { 135, 23 },
    Size       = { 115, 26 },
    Color      = { 200, 70, 30 }
  }

  -- ---- Connection Status ----
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "Connection Status",
    Fill        = { 235, 235, 235 },
    StrokeWidth = 1,
    StrokeColor = { 150, 150, 150 },
    Position    = { 5, 65 },
    Size        = { 390, 82 }
  })

  table.insert(graphics, {
    Type        = "Text",
    Text        = "Status:",
    Position    = { 12, 84 },
    Size        = { 52, 18 },
    FontSize    = 12,
    HTextAlign  = "Right",
    Color       = { 50, 50, 50 }
  })

  layout["OnlineStatus"] = {
    PrettyName = "Status~Online LED",
    Style      = "Indicator",
    Position   = { 70, 85 },
    Size       = { 20, 20 }
  }

  layout["StatusText"] = {
    PrettyName = "Status~Status Text",
    Style      = "Text",
    Position   = { 97, 85 },
    Size       = { 190, 20 },
    FontSize   = 12
  }

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Last Poll:",
    Position   = { 12, 113 },
    Size       = { 72, 16 },
    FontSize   = 11,
    HTextAlign = "Right",
    Color      = { 80, 80, 80 }
  })

  layout["LastPoll"] = {
    PrettyName = "Status~Last Poll",
    Style      = "Text",
    Position   = { 90, 113 },
    Size       = { 200, 16 },
    FontSize   = 11
  }

  -- ---- Audio ----
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "Audio",
    Fill        = { 235, 235, 235 },
    StrokeWidth = 1,
    StrokeColor = { 150, 150, 150 },
    Position    = { 5, 155 },
    Size        = { 390, 62 }
  })

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Volume:",
    Position   = { 12, 175 },
    Size       = { 60, 16 },
    FontSize   = 12,
    HTextAlign = "Right",
    Color      = { 50, 50, 50 }
  })

  layout["Volume"] = {
    PrettyName = "Audio~Volume",
    Style      = "Fader",
    Position   = { 77, 173 },
    Size       = { 215, 22 }
  }

  layout["Mute"] = {
    PrettyName = "Audio~Mute",
    Style      = "Button",
    Legend     = "Mute",
    Position   = { 300, 171 },
    Size       = { 88, 28 },
    Color      = { 200, 50, 50 }
  }

-- ============================================================
-- SETUP PAGE
-- ============================================================
elseif CurrentPage == "Setup" then

  -- Background
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "",
    Fill        = { 220, 220, 220 },
    StrokeWidth = 0,
    Position    = { 0, 0 },
    Size        = { 400, 175 }
  })

  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "Connection Configuration",
    Fill        = { 235, 235, 235 },
    StrokeWidth = 1,
    StrokeColor = { 150, 150, 150 },
    Position    = { 5, 5 },
    Size        = { 390, 160 }
  })

  local function cfg_label(text, y)
    table.insert(graphics, {
      Type       = "Text",
      Text       = text,
      Position   = { 12, y },
      Size       = { 110, 16 },
      FontSize   = 11,
      HTextAlign = "Right",
      Color      = { 80, 80, 80 }
    })
  end

  local function cfg_value(text, y)
    table.insert(graphics, {
      Type       = "Text",
      Text       = text,
      Position   = { 127, y },
      Size       = { 260, 16 },
      FontSize   = 11,
      HTextAlign = "Left",
      Color      = { 20, 20, 20 }
    })
  end

  cfg_label("IP Address:",     24)
  cfg_value(props["IP Address"].Value ~= "" and props["IP Address"].Value or "(not set)", 24)

  cfg_label("MAC Address:",    44)
  cfg_value(props["MAC Address"].Value ~= "" and props["MAC Address"].Value or "(not set)", 44)

  cfg_label("HTTP Port:",      64)
  cfg_value(tostring(props["HTTP Port"].Value), 64)

  cfg_label("Poll Interval:",  84)
  cfg_value(tostring(props["Poll Interval"].Value) .. " seconds", 84)

  cfg_label("Auth Token:",    104)
  local tokenSet = props["Auth Token"].Value ~= ""
  cfg_value(tokenSet and "(configured)" or "NOT SET — run install.ps1 on PC first", 104)

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Token is stored in C:\\QSYSControl\\config.txt on the Windows PC.",
    Position   = { 12, 130 },
    Size       = { 375, 14 },
    FontSize   = 9,
    HTextAlign = "Left",
    Color      = { 110, 110, 110 }
  })

end
