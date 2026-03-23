-- =============================================================
-- runtime.lua -- Win PC Control
-- Author: Michael King
--
-- This file contains all live runtime logic that executes inside
-- the Q-SYS Core while the plugin is running. It is NOT used at
-- design time -- only GetControlLayout(), GetProperties(), etc.
-- in plugin.lua run at design time.
--
-- Transport: HTTP via WinPCControlServer.ps1 on the Windows PC.
-- The server listens on a configurable port (default 2207) and
-- accepts GET /status and POST /command requests, protected by
-- a Bearer token stored in C:\QSYS WinPC Control\config.txt on the PC.
--
-- Power on uses Wake-on-LAN (UDP magic packet, port 9).
-- Volume and mute use the Windows Core Audio API via inline C#
-- inside WinPCControlServer.ps1.
-- =============================================================


-- -------------------------------------------------------------
-- Configuration
-- Pull property values once at startup.
-- -------------------------------------------------------------

local host         = Properties["Hostname or IP"].Value
local macProperty  = Properties["MAC Address"].Value
local httpPort     = Properties["HTTP Port"].Value
local authToken    = Properties["Auth Token"].Value
local pollInterval = Properties["Poll Interval"].Value
local debugPrint   = Properties["Debug Print"].Value

local baseUrl    = string.format("http://%s:%d", host, httpPort)
local authHeader = { Authorization = "Bearer " .. authToken }

-- cachedMac holds the MAC address used for Wake-on-LAN.
-- It is seeded from the MAC Address property if the user set one manually.
-- Once the PC comes online, the server reports its MAC in the /status
-- response and we update cachedMac automatically. This means the user
-- only needs to set the property for the very first WOL before the PC
-- has ever been polled successfully.
local cachedMac = (macProperty ~= "") and macProperty or nil


-- -------------------------------------------------------------
-- State machine
--
-- OFFLINE       - no response from the server
-- BOOTING       - WOL sent, waiting for the server to come up
--                 (poll failures here don't immediately flip to OFFLINE)
-- ONLINE        - server responded HTTP 200
-- SHUTTING_DOWN - shutdown accepted, waiting for the PC to drop off
-- -------------------------------------------------------------

local State = "OFFLINE"

local function SetState(newState)
  -- Skip if already in this state to avoid redundant control updates.
  if State == newState then return end
  State = newState

  if debugPrint ~= "None" then
    print("[WinPC] State -> " .. newState)
  end

  -- Update the Controls to reflect the new state.
  if newState == "ONLINE" then
    Controls.OnlineStatus.Boolean = true
    Controls.StatusText.String    = "Online"

  elseif newState == "BOOTING" then
    Controls.OnlineStatus.Boolean = false
    Controls.StatusText.String    = "Booting..."

  elseif newState == "SHUTTING_DOWN" then
    Controls.OnlineStatus.Boolean = false
    Controls.StatusText.String    = "Shutting Down..."

  else
    -- OFFLINE -- also reset audio controls so they don't show stale values.
    Controls.OnlineStatus.Boolean = false
    Controls.StatusText.String    = "Offline"
    Controls.Volume.Value         = 0
    Controls.Mute.Boolean         = false
  end
end


-- -------------------------------------------------------------
-- Debug helper -- prints Tx/Rx when Debug Print is Tx/Rx or All
-- -------------------------------------------------------------

local function dbg(dir, msg)
  if debugPrint == "All" or debugPrint == "Tx/Rx" then
    print("[WinPC][" .. dir .. "] " .. msg)
  end
end


-- -------------------------------------------------------------
-- HTTP transport
-- -------------------------------------------------------------

-- http_post(cmd, callback)
--   Sends a POST request to /command with a plain-text body.
--   "cmd" is a string like "SHUTDOWN", "VOLUME:75", or "MUTE:1".
--   "callback" is optional -- called as callback(httpCode, body, errMsg).
--   If no callback is needed (fire and forget), pass nil.
local function http_post(cmd, callback)
  -- Refuse to send if no token is configured. The server will reject it
  -- anyway, but this gives a clearer message in the log.
  if authToken == "" then
    print("[WinPC] WARNING: Auth Token not set in plugin properties. Run install.ps1 on the PC first.")
    return
  end

  dbg("Tx", "POST /command  body: " .. cmd)

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
      dbg("Rx", "POST /command  HTTP " .. tostring(code))
      if callback then callback(code, data, err) end
    end
  }
end


-- http_get_status(callback)
--   Sends a GET request to /status.
--   The server responds with a plain-text body like:
--     VOLUME:75
--     MUTE:0
--     MAC:AA:BB:CC:DD:EE:FF
--     UPDATED:2026-03-20 14:30:00
--   "callback" is called as callback(httpCode, body, errMsg).
local function http_get_status(callback)
  -- If no token is set, don't bother sending -- it will always fail.
  if authToken == "" then return end

  dbg("Tx", "GET /status")

  HttpClient.Download {
    Url     = baseUrl .. "/status",
    Headers = authHeader,
    Timeout = 5,
    EventHandler = function(tbl, code, data, err)
      dbg("Rx", "GET /status  HTTP " .. tostring(code))
      callback(code, data, err)
    end
  }
end


-- -------------------------------------------------------------
-- Wake-on-LAN
-- Broadcasts the standard 102-byte magic packet on UDP port 9.
-- Requires WOL enabled in BIOS and the NIC driver, and the Core
-- must be on the same L2 segment as the target PC.
-- -------------------------------------------------------------

local function SendWOL()
  local mac = cachedMac

  -- Can't send WOL without knowing the MAC address.
  -- Once the PC has been online at least once, cachedMac will be
  -- populated automatically from the /status response. Until then,
  -- the user can set the MAC Address property manually.
  if not mac or mac == "" then
    print("[WinPC] WOL: MAC address not known yet.")
    print("[WinPC] WOL: Either set the MAC Address property manually,")
    print("[WinPC] WOL: or bring the PC online once so it can be discovered.")
    return
  end

  -- Parse the MAC string (accepts either ":" or "-" as separator)
  -- into an array of six integer byte values.
  local bytes = {}
  for byte in mac:gmatch("[%x][%x]") do
    table.insert(bytes, tonumber(byte, 16))
  end

  if #bytes ~= 6 then
    print("[WinPC] WOL: MAC address is not valid (expected 6 bytes): " .. mac)
    return
  end

  -- Build the magic packet: 6x 0xFF then the 6-byte MAC repeated 16 times.
  local macBytes = string.char(table.unpack(bytes))
  local packet   = string.rep("\xFF", 6) .. string.rep(macBytes, 16)

  -- Send via UDP broadcast. Port 9 is the standard WOL port.
  local udp = UdpSocket.New()
  udp:Open("0.0.0.0", 0)
  udp:Send("255.255.255.255", 9, packet)
  udp:Close()

  dbg("Tx", "WOL magic packet sent to " .. mac)

  -- Optimistically move to BOOTING state. Poll failures will be tolerated
  -- until the PC comes up and responds with HTTP 200.
  SetState("BOOTING")
end


-- -------------------------------------------------------------
-- Command senders
-- -------------------------------------------------------------

-- Tell the PC to shut down. If the server confirms with 200, we move
-- to SHUTTING_DOWN state so polls don't immediately flip back to OFFLINE.
local function SendShutdown()
  dbg("Tx", "Sending SHUTDOWN command")
  http_post("SHUTDOWN", function(code, _, err)
    if code == 200 then
      SetState("SHUTTING_DOWN")
    else
      print("[WinPC] Shutdown command failed. HTTP " .. tostring(code) .. " / " .. tostring(err))
    end
  end)
end

-- Send volume as an integer 0-100. The server maps this to the
-- Windows master volume via the Core Audio API.
local function SendVolume(pct)
  http_post("VOLUME:" .. tostring(math.floor(pct)))
end

-- Send mute state as "1" (muted) or "0" (not muted).
local function SendMute(muted)
  http_post("MUTE:" .. (muted and "1" or "0"))
end


-- -------------------------------------------------------------
-- Poll timer
-- Fires every N seconds, sends GET /status, syncs volume and mute.
-- -------------------------------------------------------------

local pollTimer = Timer.New()

-- ParseStatus: converts the plain-text /status body into a key/value table.
local function ParseStatus(body)
  local status = {}
  for line in body:gmatch("[^\r\n]+") do
    local k, v = line:match("^(%u+):(.+)$")
    if k and v then
      -- Trim any leading/trailing whitespace from the value.
      status[k] = v:match("^%s*(.-)%s*$")
    end
  end
  return status
end

-- DoPoll()
--   Called by pollTimer every N seconds.
--   On success: updates state to ONLINE and syncs volume/mute/MAC.
--   On failure: handles BOOTING tolerance and OFFLINE transition.
local function DoPoll()
  -- Don't bother polling if the hostname was never configured.
  if host == "" then return end

  http_get_status(function(code, data, err)
    if code == 200 and data then
      -- PC is responding. Move to ONLINE if we weren't already.
      if State ~= "ONLINE" then SetState("ONLINE") end

      local status = ParseStatus(data)

      -- Sync volume from server to Q-SYS fader.
      if status.VOLUME then
        local v = tonumber(status.VOLUME)
        if v then Controls.Volume.Value = v end
      end

      -- Sync mute state from server to Q-SYS button.
      if status.MUTE then
        Controls.Mute.Boolean = (status.MUTE == "1")
      end

      -- If the server sent a MAC address, cache it for future WOL use.
      -- This is how auto-discovery works -- no manual entry needed after
      -- the first successful poll.
      if status.MAC and status.MAC ~= "" then
        cachedMac = status.MAC
        dbg("Rx", "MAC auto-discovered and cached: " .. cachedMac)
      end

      -- Record the timestamp of the last successful poll.
      Controls.LastPoll.String = os.date("%Y-%m-%d %H:%M:%S")
      dbg("Rx", "Vol=" .. (status.VOLUME or "?") .. "  Mute=" .. (status.MUTE or "?"))

    else
      -- No HTTP 200 -- the PC is not responding.
      if State == "BOOTING" then
        -- WOL was recently sent. Stay in BOOTING and keep waiting.
        -- The PC may take 30-60 seconds to fully boot and start the server.
        dbg("Rx", "Still booting... (" .. tostring(err or code) .. ")")

      elseif State == "SHUTTING_DOWN" then
        -- We expected this -- the shutdown command was accepted and the
        -- PC is now powering off. Move to OFFLINE.
        SetState("OFFLINE")

      else
        -- Unexpected failure. Mark offline.
        SetState("OFFLINE")
      end

      if debugPrint ~= "None" then
        print("[WinPC] Poll failed: " .. tostring(err or code))
      end
    end
  end)
end

-- Wire up the timer callback and we're ready to start it at the bottom.
pollTimer.EventHandler = DoPoll


-- -------------------------------------------------------------
-- Guard: drops commands silently if the PC isn't ONLINE.
-- -------------------------------------------------------------

local function RequireOnline(label)
  if State ~= "ONLINE" then
    print("[WinPC] Command ignored (" .. label .. ") -- PC is currently: " .. State)
    return false
  end
  return true
end


-- -------------------------------------------------------------
-- Control event handlers
-- -------------------------------------------------------------

-- PowerOn: Sends a Wake-on-LAN magic packet.
-- This works even when the PC is OFFLINE -- that's the whole point.
Controls.PowerOn.EventHandler = function()
  SendWOL()
end

-- Shutdown: Tells the server to initiate a Windows shutdown.
-- Only works when ONLINE -- guard prevents blind commands.
Controls.Shutdown.EventHandler = function()
  if not RequireOnline("Shutdown") then return end
  SendShutdown()
end

-- Volume: Syncs the fader value to Windows master volume (0-100).
Controls.Volume.EventHandler = function()
  if not RequireOnline("Volume") then return end
  SendVolume(Controls.Volume.Value)
end

-- Mute: Syncs the toggle button to Windows master mute.
Controls.Mute.EventHandler = function()
  if not RequireOnline("Mute") then return end
  SendMute(Controls.Mute.Boolean)
end


-- -------------------------------------------------------------
-- Startup
-- -------------------------------------------------------------

SetState("OFFLINE")
pollTimer:Start(pollInterval)
print("[WinPC] Plugin started. Polling " .. (host ~= "" and host or "(no hostname set)") .. " every " .. pollInterval .. "s.")

