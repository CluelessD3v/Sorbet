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
		local direction = Vector3.new(x, 0, z) * 25
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

local ActivatorPart = workspace.NpcTest.Part
local ClickDetector: ClickDetector = ActivatorPart.ClickDetector
ClickDetector.MouseClick:Connect(function()
	if npcStateMachine.IsRunning then
		Sorbet.Fsm.PauseMachine(npcStateMachine)
	else
		Sorbet.Fsm.ResumeMachine(npcStateMachine)
	end

	print("Is on?", npcStateMachine.IsRunning)
end)

npcStateMachine.MachinePaused:Connect(function()
	for entity in npcStateMachine.RegisteredStates.Idle.Entities do
		idleTimeStamps[entity] = time()
	end

	for entity: any in npcStateMachine.RegisteredStates.Wandering.Entities do
		entity.Humanoid:MoveTo(entity:GetPivot().Position)
	end
end)

npcStateMachine.MachineResumed:Connect(function()
	for entity: any in npcStateMachine.RegisteredStates.Wandering.Entities do
		Wandering.OnEnter(entity, npcStateMachine)
	end
end)
