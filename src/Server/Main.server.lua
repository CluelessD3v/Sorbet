local RunService = game:GetService("RunService")
local Sorbet = require(game.ReplicatedStorage.Sorbet)

-- local Person = {
-- 	Age = 0,
-- }

-- local Born = Sorbet.State({
-- 	Name = "Born",
-- 	Enter = function(entity, fsm)
-- 		print("Entered")
-- 		entity.Age += 1
-- 		entity.Birthday = os.date()
-- 		fsm:ChangeState(entity, "Aging")
-- 	end,

-- 	Update = function(entity, fsm)
-- 	end,

-- 	Exit = function(entity, fsm)
-- 		print "Bye, have a good life"
-- 	end,
-- } :: Sorbet.State)


-- local ageInterval = 10
-- local ageTS
-- local Aging = Sorbet.State({
-- 	Name = "Aging",
-- 	Enter = function(entity, fsm)
-- 		ageTS = os.clock()
-- 		print("Daym son, you now aging!")
-- 	end,

-- 	Update = function(entity, fsm, dt)
-- 		if ageTS >= ageInterval then
-- 			entity.Age  += 1
-- 			print("happy birthday!", entity.Age)		
-- 		end
-- 		-- fsm:ChangeState(entity, "Aging")
-- 	end,

-- 	Exit = function(entity, fsm)
-- 	end,
-- } :: Sorbet.State)


-- local myLife = Sorbet.FSM({
-- 	Entities = {Person},
-- 	States = {Born, Aging},
-- 	InitialState = Born
-- })

-- myLife:AddEntity(Person)
-- myLife:StartEntity(Person)
-- -- myLife:StopEntity(Person)


-- myLife:Update()

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
