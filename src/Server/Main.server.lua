local RunService = game:GetService("RunService")
local Sorbet = require(game.ReplicatedStorage.Sorbet)

local idleTimestampts = {}
local idleTime = 3
local Idle = Sorbet.State({
	Name = "Idle",
	Enter = function(entity, fsm)
		print("entered")
		idleTimestampts[entity] = os.clock()
	end,

	Update = function(entity, fsm)
		local ts = idleTimestampts[entity] 
		if (os.clock() - ts) >= idleTime then
			fsm:ChangeState(entity, "Roaming")
		end
	end,

	Exit = function(entity)
		idleTimestampts[entity] = os.clock()
	end
})

local roamingDistance = 10
local conns = {}
local Roaming = Sorbet.State({
	Name = "Roaming",
	Enter = function(entity: Model, fsm)
		local Humanoid = entity:FindFirstChild("Humanoid"):: Humanoid
		if Humanoid then
			local randAngle = math.pi * 2 * math.random()
			local x = math.cos(randAngle) 
			local y = Humanoid.HipHeight
			local z = math.sin(randAngle) 
			Humanoid:MoveTo(entity:GetPivot().Position + Vector3.new(x,y,z)  * roamingDistance)

			conns.MoveTo = Humanoid.MoveToFinished:Once(function()
				print"reached destination"
				fsm:ChangeState(entity, "Idle")
			end)

			print("roaming")
		end
	end,

	Exit = function(entity)
		for _, conn in conns do
			conn:Disconnect()
		end
	end

})




local CollectionService = game:GetService("CollectionService")
local knights = CollectionService:GetTagged("Knight")
local movementFsm = Sorbet.FSM({
	Entities = knights,
	States = {Idle, Roaming}
})

movementFsm:Start()

RunService.PostSimulation:Connect(function()
	movementFsm:Update()
end)
