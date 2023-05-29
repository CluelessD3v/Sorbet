local RunService = game:GetService "RunService"
local Sorbet = require(game.ReplicatedStorage.Sorbet)

local Born = Sorbet.State.new {
	Name = "Born",
	OnEnter = function(entity, fsm)
		print "You were born!"
		entity.Age = 1

		Sorbet.Fsm.ChangeState(fsm, entity, fsm.RegisteredStates.Aging)
	end,
	OnExit = function(entity: any, fsm)
		print "you are now aging!"
	end,
}

local Aging = Sorbet.State.new {
	Name = "Aging",
	OnEnter = function(entity, fsm)
		print "You're aging!"
	end,

	OnUpdate = function(entity, fsm)
		entity.Age += 1
		print(entity, "aged 1 year", entity.Age)

		if entity.Age >= 21 then
			print "you're legal"
			Sorbet.Fsm.ChangeState(fsm, entity, fsm.RegisteredStates.Born)
		end
	end,

	OnExit = function(entity, fsm)
		print "you stopped aging!"
		-- body
	end,
}

local Person = { Name = "Enrique", Age = 21 }
local newFSM = Sorbet.Fsm.new(Born, {}, { Aging })

Sorbet.Fsm.RegisterEntity(newFSM, Person, Born)
Sorbet.Fsm.ActivateEntity(newFSM, Person)

task.spawn(function()
	while task.wait(1) do
		Sorbet.Fsm.Update(newFSM)
	end
end)
