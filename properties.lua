-- Network
table.insert(props, {
  Name  = "IP Address",
  Type  = "string",
  Value = ""
})

table.insert(props, {
  Name  = "MAC Address",
  Type  = "string",
  Value = ""
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
