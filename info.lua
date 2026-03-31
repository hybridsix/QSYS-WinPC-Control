-- =============================================================
-- info.lua -- Win PC Control
--
-- Plugin identity block. Read by PLUGCC at compile time and
-- embedded in the .qplug file. Q-SYS Designer reads this when
-- loading the plugin.
--
-- The build number (fourth field) is auto-incremented by compile_plugin.sh
-- each time the build task runs. Do not edit it manually.
--
-- Id is a stable GUID that uniquely identifies this plugin.
-- Do not change it after the plugin has been deployed, or
-- existing designs will lose the reference and need to be
-- manually reconnected.
-- =============================================================

PluginInfo = {
  Name        = "Hybridsix Plugins~Win PC Control",
  Version     = "0.7.2-beta",
  BuildVersion= "0.7.3.31",
  Id          = "dd941513-d452-416e-95eb-b47d08457b36",
  Author      = "Michael King",
  Description = "Remote control a Windows PC from Q-SYS: Wake-on-LAN power on, volume and mute via HTTP, and live status polling."
}
