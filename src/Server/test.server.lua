local Sorbet = require(game.ReplicatedStorage.Sorbet)

local person = {
	Name = "Keykay",
	Age = 0,
}

local born = Sorbet.State {
	Name = "Born",
	OnEnter = function(entity, fsm)
		print(entity.Name, "was born")
		fsm:ChangeState(entity, fsm.RegisteredStates.Aging)
	end,

	OnExit = function(entity)
		print(entity.Name, "life journey begins")
	end,
}

local aging = Sorbet.State {
	Name = "Aging",
	OnEnter = function(entity, fsm)
		print(entity.Name, "gets older")
	end,

	OnUpdate = function(entity, fsm)
		entity.Age += 1
		print(entity.Age)

		if entity.Age >= 21 then
			fsm:ChangeState(entity, fsm.RegisteredStates.Legal)
		end
	end,
}

local legal = Sorbet.State {
	Name = "Legal",

	OnEnter = function(entity, fsm)
		fsm.LegalAgePeople[entity] = true
		print(entity.Name, "Is now legal! congrats you can drink now")
	end,

	OnUpdate = function(entity, fsm)
		entity.Age += 1
		print(entity.Age)
	end,
}

local dead = Sorbet.State {
	Name = "Dead",
	OnEnter = function(entity)
		print(entity.Name, "died")
	end,
}

local personFSM = Sorbet.FSM(born, { aging, legal, dead })

personFSM:RegisterEntity(person)
personFSM:ActivateEntity(person)

local ageOfDead = 18
print(ageOfDead)

personFSM.EntityPaused:Connect(function(entity)
	if entity.Age <= 21 then
		print "he died too young"
	end
end)

while task.wait() do
	personFSM:Update(person)
	for entity, state in personFSM.RegisteredEntities do
		if entity.Age >= ageOfDead then
			personFSM:ChangeState(entity, dead)
			personFSM:PauseEntity(entity)
		end
	end
end
