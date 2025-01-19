if SERVER then
	resource.AddWorkshop("3410249572")

	AddCSLuaFile("colortree/shared/helpers.lua")
	AddCSLuaFile("colortree/shared/proxytransformers.lua")
	AddCSLuaFile("colortree/client/proxyconvars.lua")
	AddCSLuaFile("colortree/client/colorui.lua")
	AddCSLuaFile("colortree/client/modelui.lua")
	AddCSLuaFile("colortree/client/materialui.lua")

	include("colortree/server/net.lua")
end
