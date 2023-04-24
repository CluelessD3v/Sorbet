local status = require(game.ReplicatedStorage.Status)


local adding = status.State.new({
    OnUpdate = function(entity, fsm: status.FSM)
        entity.Pos = entity.Pos + Vector2.new(10, 0)
        if entity.Pos.X >= 10 then
            fsm:ChangeState(entity, fsm.RegisteredStates.State2)
        end
    end
})


local scaling = status.State.new({
    OnUpdate = function(entity)
        entity.Pos = entity.Pos * 2
        print(entity.Pos)
    end
})

local testFSM = status.FSM.new(adding, {
    adding,
    scaling,
})


local a = {Pos = Vector2.new()}
local b = {Pos = Vector2.new()}
testFSM:RegisterEntity(a, adding)
testFSM:RegisterEntity(b, adding)
testFSM:TurnOn()
testFSM:Update()
testFSM:Update()

print(a.Pos, b.Pos)

-- local dt = task.wait()
-- while true do
--     print(a, b)
--     dt = task.wait(1)
-- end