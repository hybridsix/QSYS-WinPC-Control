-- Identity
table.insert(props, {
  Name  = "Computer Name",
  Type  = "string",
  Value = ""
})

-- Network
table.insert(props, {
  Name  = "Hostname or IP",
  Type  = "string",
  Value = ""
})

table.insert(props, {
  Name  = "MAC Address",
  Type  = "string",
  Value = ""
  -- Optional: auto-discovered from /status when PC is online.
  -- Only required for WOL before the PC has ever been seen online.
})

-- HTTP listener
table.insert(props, {
  Name  = "HTTP Port",
  Type  = "integer",
  Min   = 1024,
  Max   = 65535,
  Value = 2207
})

table.insert(props, {
  Name  = "Auth Token",
  Type  = "string",
  Value = ""
})

-- Polling
table.insert(props, {
  Name  = "Poll Interval",
  Type  = "integer",
  Min   = 5,
  Max   = 300,
  Value = 30
})

-- Pin visibility toggles
table.insert(props, {
  Name  = "Show Power Pins",
  Type  = "boolean",
  Value = true
})

table.insert(props, {
  Name  = "Show Volume Pins",
  Type  = "boolean",
  Value = true
})

table.insert(props, {
  Name  = "Show Status Pins",
  Type  = "boolean",
  Value = true
})

-- Debug
table.insert(props, {
  Name    = "Debug Print",
  Type    = "enum",
  Choices = { "None", "Tx/Rx", "All" },
  Value   = "None"
})
