local ReplicatedStorage = game:GetService "ReplicatedStorage"
local Packages = ReplicatedStorage.Packages
local Sigal = require(Packages.signal)

--==/ Aux functions ===============================||>
type Set = { [any]: any }
local function GetSetIntersection(set1: Set, set2: Set): Set
	local result: Set = {}
	for k in pairs(set1) do
		if set2[k] then
			result[k] = true
		end
	end
	return result
end

local Sorbet = {}
Sorbet.__index = Sorbet

local privData = {}

Sorbet.new = function() end

return Sorbet
