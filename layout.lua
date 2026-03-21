local CurrentPage = PageNames[props["page_index"].Value]

-- ============================================================
-- CONTROL PAGE
-- ============================================================
if CurrentPage == "Control" then

  -- Background
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "",
    Fill        = { 43, 43, 43 },   -- Paint it Black
    StrokeWidth = 0,
    Position    = { 0, 0 },
    Size        = { 400, 228 }
  })

  -- ---- Power Control ----
  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "Power Control",
    Fill        = { 3, 75, 88 },    -- Dazzling Blue
    StrokeWidth = 1,
    StrokeColor = { 21, 163, 213 }, -- Patch of Blue
    Position    = { 5, 5 },
    Size        = { 390, 52 }
  })

  layout["PowerOn"] = {
    PrettyName = "Power~Wake (WOL)",
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
    Fill        = { 3, 104, 128 },  -- Blue Suede
    StrokeWidth = 1,
    StrokeColor = { 21, 163, 213 }, -- Patch of Blue
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
    Color       = { 207, 204, 204 } -- Silver Springs
  })

  layout["OnlineStatus"] = {
    PrettyName = "Status~Online",
    Style      = "Indicator",
    Position   = { 70, 85 },
    Size       = { 20, 20 }
  }

  layout["StatusText"] = {
    PrettyName = "Status~Text",
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
    Color      = { 207, 204, 204 } -- Silver Springs
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
    Fill        = { 3, 104, 128 },  -- Blue Suede
    StrokeWidth = 1,
    StrokeColor = { 21, 163, 213 }, -- Patch of Blue
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
    Color      = { 207, 204, 204 } -- Silver Springs
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
    Fill        = { 43, 43, 43 },   -- Paint it Black
    StrokeWidth = 0,
    Position    = { 0, 0 },
    Size        = { 400, 195 }
  })

  table.insert(graphics, {
    Type        = "GroupBox",
    Text        = "Connection Configuration",
    Fill        = { 3, 104, 128 },  -- Blue Suede
    StrokeWidth = 1,
    StrokeColor = { 21, 163, 213 }, -- Patch of Blue
    Position    = { 5, 5 },
    Size        = { 390, 180 }
  })

  local function cfg_label(text, y)
    table.insert(graphics, {
      Type       = "Text",
      Text       = text,
      Position   = { 12, y },
      Size       = { 110, 16 },
      FontSize   = 11,
      HTextAlign = "Right",
      Color      = { 207, 204, 204 } -- Silver Springs
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
      Color      = { 247, 247, 247 } -- White Satin
    })
  end

  cfg_label("Computer Name:",  24)
  cfg_value(props["Computer Name"].Value ~= "" and props["Computer Name"].Value or "(not set)", 24)

  cfg_label("Hostname / IP:",  44)
  cfg_value(props["Hostname or IP"].Value ~= "" and props["Hostname or IP"].Value or "(not set)", 44)

  cfg_label("MAC Address:",    64)
  cfg_value(props["MAC Address"].Value ~= "" and props["MAC Address"].Value or "(auto-discover)", 64)

  cfg_label("HTTP Port:",      84)
  cfg_value(tostring(props["HTTP Port"].Value), 84)

  cfg_label("Poll Interval:", 104)
  cfg_value(tostring(props["Poll Interval"].Value) .. " seconds", 104)

  cfg_label("Auth Token:",    124)
  local tokenSet = props["Auth Token"].Value ~= ""
  cfg_value(tokenSet and "(configured)" or "NOT SET — run install.ps1 on PC first", 124)

  table.insert(graphics, {
    Type       = "Text",
    Text       = "Token is stored in C:\\QSYSControl\\config.txt on the Windows PC.",
    Position   = { 12, 150 },
    Size       = { 375, 14 },
    FontSize   = 9,
    HTextAlign = "Left",
    Color      = { 105, 104, 104 } -- Grey Seal
  })

end
