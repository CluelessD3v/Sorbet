local RunService = game:GetService("RunService")
local status = require(game.ReplicatedStorage.Status)


print("ran")
local idleTS = {}
local idle = status.State.new({
    Name = "Idle",
    OnEnter = function(entity, fsm)
        idleTS[entity] = time()
    end,

    OnUpdate = function(entity, fsm, dt)
        local currentTime = time() -  idleTS[entity]
        print(currentTime) 
        if currentTime >= 3 then
            fsm:ChangeState(entity, fsm:GetState("Wandering"))
            return
        end
    end
})

print("ran")

local conns = {}
local wandering = status.State.new({
    Name = "Wandering",
    OnEnter = function(entity, fsm)
        conns[entity] = entity.Humanoid.MoveToFinished:Connect(function()
            fsm:ChangeState(entity, fsm:GetState("Idle"))
        end)

        local randAngle = math.pi * 2 * math.random()
        local x, z = math.sin(randAngle), math.cos(randAngle)
        entity.Humanoid:MoveTo(entity:GetPivot().Position + Vector3.new(x, 3, z) * 5)
    end,

})

local noobsFsm =  status.FSM.new(idle, {idle, wandering})

print(noobsFsm.RegisteredStates)

for _, noob in workspace.Noobs:GetChildren() do
    noobsFsm:RegisterAndActivateEntity(noob)
end

RunService.PostSimulation:Connect(function()
    noobsFsm:Update()
end)