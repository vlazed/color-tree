if SERVER then
	AddCSLuaFile("colortree/shared/helpers.lua")
	AddCSLuaFile("colortree/shared/proxyTransformers.lua")
	AddCSLuaFile("colortree/client/proxyConVars.lua")
	AddCSLuaFile("colortree/client/colorui.lua")

	include("colortree/server/net.lua")
end
