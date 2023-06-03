local RunService = game:GetService "RunService"
local Sorbet = require(game.ReplicatedStorage.Sorbet)

local idleTimeStamps = {}
local idleConns = {}
local idle = Sorbet.State.new {
	Name = "Idle",

	OnEnter = function(entity)
		print "Am idle!"
		idleTimeStamps[entity] = time()
	end,

	OnUpdate = function(entity, fsm)
		if time() - idleTimeStamps[entity] >= 5 then
			Sorbet.Fsm.ChangeState(fsm, entity, fsm.RegisteredStates.Wandering)
			return
		end

		print(time() - idleTimeStamps[entity])
	end,

	OnExit = function(entity)
		idleTimeStamps[entity] = time()
		for conn in idleConns do
			conn:Disconnect()
		end
	end,
}

local wanderingCons = {}
local Wandering = Sorbet.State.new {
	Name = "Wandering",
	OnEnter = function(entity: Model & { Humanoid: Humanoid }, fsm)
		print "Wandering"
		local randAngle = math.random() * math.pi * 2
		local x = math.cos(randAngle)
		local z = math.sin(randAngle)

		local myPos = entity:GetPivot().Position
		local direction = Vector3.new(x, 0, z) * 15
		local targetPos = (myPos + direction)
		entity.Humanoid:MoveTo(targetPos)

		wanderingCons[entity.Humanoid.MoveToFinished:Once(function()
			Sorbet.Fsm.ChangeState(fsm, entity, fsm.RegisteredStates.Idle)
		end)] =
			true
	end,

	OnExit = function(entity)
		for conn in wanderingCons do
			conn:Disconnect()
		end
	end,
}

local npcStateMachine = Sorbet.Fsm.new(idle, { Wandering }, { workspace.NpcTest.Knight })

for entity in npcStateMachine.RegisteredEntities do
	Sorbet.Fsm.ActivateEntity(npcStateMachine, entity)
end

RunService.Heartbeat:Connect(function()
	Sorbet.Fsm.Update(npcStateMachine)
end)

local Part = workspace.NpcTest.Part
local CD: ClickDetector = Part.ClickDetector
local running = true
CD.MouseClick:Connect(function()
	running = not running
	print(running)
	if running then
		Sorbet.Fsm.PauseEntity(npcStateMachine, workspace.NpcTest.Knight)
	else
		Sorbet.Fsm.ResumeEntity(npcStateMachine, workspace.NpcTest.Knight)
	end
end)
