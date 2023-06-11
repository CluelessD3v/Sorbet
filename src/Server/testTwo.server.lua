local Sorbet = require(game.ReplicatedStorage.Sorbet)

local s1 = Sorbet.State {
	Name = "S1",
	OnEnter = function(e, f)
		task.wait(1)
		print "Entered"
		f:ChangeState(e, f.RegisteredStates.S2)
	end,
}

local s2 = Sorbet.State {
	Name = "S2",
	OnEnter = function(e, f)
		f:ChangeState(e, f.RegisteredStates.S1)
	end,
}

local a = {}
local f = Sorbet.FSM(s1, { s2 }, { a })
f.EntityChangedState:Connect(function(e, n)
	print("changed state", e, n.Name)
end)

f:ActivateEntity(a)
