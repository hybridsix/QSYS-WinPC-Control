-- =============================================================
-- runtime.lua  —  QSYS WinPC Control
-- Runs inside Q-SYS Core when the plugin is active.
-- Transport: HTTP (QSYSControlServer.ps1 on Windows side)
-- =============================================================

-- -----------------------------------------------------------
-- CONFIG (from Properties)
-- -----------------------------------------------------------
local ip           = Properties["IP Address"].Value
local mac          = Properties["MAC Address"].Value
local httpPort     = Properties["HTTP Port"].Value
local authToken    = Properties["Auth Token"].Value
local pollInterval = Properties["Poll Interval"].Value
local debugPrint   = Properties["Debug Print"].Value

local baseUrl    = string.format("http://%s:%d", ip, httpPort)
local authHeader = { Authorization = "Bearer " .. authToken }

-- -----------------------------------------------------------
-- STATE MACHINE
-- States: OFFLINE, BOOTING, ONLINE, SHUTTING_DOWN
-- -----------------------------------------------------------
local State = "OFFLINE"

local function SetState(newState)
  if State == newState then return end
  State = newState
  if debugPrint ~= "None" then
    print("[WinPC] State → " .. newState)
  end

  if newState == "ONLINE" then
    Controls.OnlineStatus.Boolean = true
    Controls.StatusText.String    = "Online"
  elseif newState == "BOOTING" then
    Controls.OnlineStatus.Boolean = false
    Controls.StatusText.String    = "Booting..."
  elseif newState == "SHUTTING_DOWN" then
    Controls.OnlineStatus.Boolean = false
    Controls.StatusText.String    = "Shutting Down..."
  else  -- OFFLINE
    Controls.OnlineStatus.Boolean = false
    Controls.StatusText.String    = "Offline"
    Controls.Volume.Value         = 0
    Controls.Mute.Boolean         = false
  end
end

-- -----------------------------------------------------------
-- DEBUG HELPER
-- -----------------------------------------------------------
local function dbg(dir, msg)
  if debugPrint == "All" or debugPrint == "Tx/Rx" then
    print("[WinPC][" .. dir .. "] " .. msg)
  end
end

-- -----------------------------------------------------------
-- HTTP TRANSPORT
-- -----------------------------------------------------------

-- POST /command — fire and forget with optional callback(code, data, err)
local function http_post(cmd, callback)
  if authToken == "" then
    print("[WinPC] WARNING: Auth Token not configured in properties")
    return
  end
  dbg("Tx", "POST /command → " .. cmd)
  HttpClient.Download {
    Url     = baseUrl .. "/command",
    Headers = {
      Authorization    = "Bearer " .. authToken,
      ["Content-Type"] = "text/plain"
    },
    Method  = "POST",
    Body    = cmd,
    Timeout = 5,
    EventHandler = function(tbl, code, data, err)
      dbg("Rx", "POST /command ← " .. tostring(code))
      if callback then callback(code, data, err) end
    end
  }
end

-- GET /status — calls callback(code, data, err)
local function http_get_status(callback)
  if authToken == "" then return end
  dbg("Tx", "GET /status")
  HttpClient.Download {
    Url     = baseUrl .. "/status",
    Headers = authHeader,
    Timeout = 5,
    EventHandler = function(tbl, code, data, err)
      dbg("Rx", "GET /status ← " .. tostring(code))
      callback(code, data, err)
    end
  }
end
-- -----------------------------------------------------------
-- WOL  (Wake-on-LAN magic packet via UDP broadcast)
-- -----------------------------------------------------------
local function SendWOL()
  if mac == "" then
    print("[WinPC] WOL: MAC address not configured")
    return
  end

  local bytes = {}
  for byte in mac:gmatch("[%x][%x]") do
    table.insert(bytes, tonumber(byte, 16))
  end
  if #bytes ~= 6 then
    print("[WinPC] WOL: Invalid MAC address: " .. mac)
    return
  end

  local packet   = string.rep("\xFF", 6)
  local macBytes = string.char(table.unpack(bytes))
  packet = packet .. string.rep(macBytes, 16)

  local udp = UdpSocket.New()
  udp:Open("0.0.0.0", 0)
  udp:Send("255.255.255.255", 9, packet)
  udp:Close()

  dbg("Tx", "WOL magic packet → " .. mac)
  SetState("BOOTING")
end

-- -----------------------------------------------------------
-- COMMAND SENDERS
-- -----------------------------------------------------------

local function SendShutdown()
  dbg("Tx", "Sending SHUTDOWN")
  http_post("SHUTDOWN", function(code, _, err)
    if code == 200 then
      SetState("SHUTTING_DOWN")
    else
      print("[WinPC] Shutdown failed: " .. tostring(err or code))
    end
  end)
end

local function SendVolume(pct)
  http_post("VOLUME:" .. tostring(math.floor(pct)))
end

local function SendMute(muted)
  http_post("MUTE:" .. (muted and "1" or "0"))
end

-- -----------------------------------------------------------
-- POLL TIMER  (HTTP GET /status every N seconds)
-- -----------------------------------------------------------
local pollTimer = Timer.New()

local function ParseStatus(body)
  local status = {}
  for line in body:gmatch("[^\r\n]+") do
    local k, v = line:match("^(%u+):(.+)$")
    if k and v then status[k] = v:match("^%s*(.-)%s*$") end
  end
  return status
end

local function DoPoll()
  if ip == "" then return end

  http_get_status(function(code, data, err)
    if code == 200 and data then
      -- Server responded — PC is online
      if State ~= "ONLINE" then SetState("ONLINE") end

      local status = ParseStatus(data)
      if status.VOLUME then
        local v = tonumber(status.VOLUME)
        if v then Controls.Volume.Value = v end
      end
      if status.MUTE then
        Controls.Mute.Boolean = (status.MUTE == "1")
      end
      Controls.LastPoll.String = os.date("%Y-%m-%d %H:%M:%S")
      dbg("Rx", "Vol=" .. (status.VOLUME or "?") .. " Mute=" .. (status.MUTE or "?"))

    else
      -- HTTP failed — PC offline, booting, or service not running
      if State ~= "SHUTTING_DOWN" then
        if State == "BOOTING" then
          -- Stay in BOOTING — WOL was recently sent, keep waiting
        else
          SetState("OFFLINE")
        end
      end
      if debugPrint ~= "None" then
        print("[WinPC] Poll failed: " .. tostring(err or code))
      end
    end
  end)
end

pollTimer.EventHandler = DoPoll

-- Guard: don't send audio/power commands when PC isn't up
local function RequireOnline(label)
  if State ~= "ONLINE" then
    print("[WinPC] " .. label .. " ignored — PC is " .. State)
    return false
  end
  return true
end

-- -----------------------------------------------------------
-- CONTROL EVENT HANDLERS
-- -----------------------------------------------------------
Controls.PowerOn.EventHandler = function()
  SendWOL()
end

Controls.Shutdown.EventHandler = function()
  if not RequireOnline("Shutdown") then return end
  SendShutdown()
end

Controls.Volume.EventHandler = function()
  if not RequireOnline("Volume") then return end
  SendVolume(Controls.Volume.Value)
end

Controls.Mute.EventHandler = function()
  if not RequireOnline("Mute") then return end
  SendMute(Controls.Mute.Boolean)
end

-- -----------------------------------------------------------
-- STARTUP
-- -----------------------------------------------------------
SetState("OFFLINE")
pollTimer:Start(pollInterval)
print("[WinPC] Plugin started — polling every " .. pollInterval .. "s → " .. (ip ~= "" and ip or "(no IP)"))

