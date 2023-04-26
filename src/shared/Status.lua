local signal = require(game:GetService("ReplicatedStorage").Packages.signal) or require(script.Parent.signal)


--[=[
    @class Status
    Status is the package itself, it contains both State and FSM.
]=]
type Status = {
    State: {
        new: () -> State
    },

    FSM: {
        new: () -> FSM
    }
}



--[=[
    @type Entity any 
    @within Status

    An entity is a unique identifier used to create an entity, state pair. It is created when the through the Register/RegisterAndActivateEntity
    functions.

    An entity can be accessed using the GetEntities Getter
]=]
export type Entity = any


--[=[
    @interface FSM 
    @within Status

    Finite state machine interface

    .InitialState State -- Default state entities are registered/activated in
    .RegisteredEntities {[Entity]:State} -- Map of entity - state pairs
    .RegisteredStates {[string]: State} -- Dictionary of registered states in the state machine
    .Collections {[State]:{[Entity]: true}} -- Map state - Look up table pairs, the look up tables contains all the instances in their associated state key. 
    .ActiveEntities {[Entity]: true} -- Look up table of all active entities in the state machine
    .InactiveEntities {[Entity]: true} -- Look up table of all inactive entities in the state machine
    .PrintStateChange boolean -- debug function to print state transitions
]=]

export type FSM = {
    -- Properties
    InitialState       : State,
    RegisteredEntities : {[Entity]:State},
    RegisteredStates   : {[string]: State},
    Collections        : {[State]:{[Entity]: true}},
    ActiveEntities     : {[Entity]: true},
    InactiveEntities   : {[Entity]: true},
	PrintStateChange   : boolean,

	ChangedState       : typeof(signal.new()),
	EntityRegistered   : typeof(signal.new()),
	EntityUnregistered : typeof(signal.new()),
	EntityActivated    : typeof(signal.new()),
	EntityDeactivated  : typeof(signal.new()),



    --> Methods
    RegisterEntity                : (self: FSM, entity: Entity, initialState: State) -> nil,
    UnRegisterEntity              : (self: FSM, entity: Entity) -> nil,
    RegisterAndActivateEntity     : (self: FSM, entity: Entity, initialState: State) -> nil,
    UnRegisterAndDeactivateEntity : (self: FSM, entity: Entity) -> nil,
    ActivateEntity                : (self: FSM, entity: Entity, initialState: State) -> nil,
    DeactivateEntity              : (self: FSM, entity: Entity) -> nil,
    TurnOn                        : (self: FSM) -> nil,
    TurnOff                       : (self: FSM) -> nil,
    Update                        : (self: FSM, dt: number) -> nil,
    ChangeState                   : (self: FSM, entity: Entity, newState: State, onExitData:{any}, onEnterData:{any}) -> nil,

    --> Getters
    GetEntitiesInState    : (self: FSM, stateName: string) -> {Entity},
    GetEntities : (self: FSM) -> {[Entity]: State},
    GetStates   : (self: FSM) -> {State},
    GetCurrentState : (self: FSM, entity: Entity) -> State
}


type LifeCycleFunction = (entity: Entity, fsm: FSM) -> nil


--[=[
    @interface State
    @within Status

    .OnEnter (entity: Entity, fsm: FSM, ...any) -> nil?
    .OnUpdate (entity: Entity, fsm: FSM, dt: number, ...any) -> nil?
    .OnExit (entity: Entity, fsm: FSM, ...any) -> nil?

]=]
export type State = {
    Name: string,
    
    --> Callbacks
    OnEnter  : LifeCycleFunction?,
    OnUpdate : LifeCycleFunction?,
    OnExit   : LifeCycleFunction?,

    --> Methods
    Enter  : (self: State, entity: Entity, fsm: FSM, ...any) -> nil?,
    Exit   : (self: State, entity: Entity, fsm: FSM, ...any) -> nil?,
    Update : (self: State, entity: Entity, fsm: FSM, dt: number, ...any) -> nil?,
}







function GetSetIntersection(set1, set2)
    local result = {}
    for k in pairs(set1) do
      if set2[k] then
        result[k] = true
      end
    end
    return result
  end


function GetSetDifference(set1, set2)
    local result = {}
    for element in pairs(set1) do
        if not set2[element] then
            result[element] = true
        end
    end
    return result
end



-- !== ================================================================================||>
-- !==                                      FSM
-- !== ================================================================================||>


--[=[
    @class FSM
]=]
local finiteStateMachine = {} 
finiteStateMachine.__index = finiteStateMachine

function finiteStateMachine.new(initialState: State, statesList: {State}): FSM
    local self = setmetatable({}, finiteStateMachine) :: FSM
    self.InitialState     = initialState
    
    self.RegisteredStates   = {}
    self.RegisteredEntities = {}
    self.ActiveEntities     = {}
    self.InactiveEntities   = {}
    self.Collections        = {}


    self.EntityActivated    = signal.new()
    self.EntityDeactivated  = signal.new()
    self.EntityRegistered   = signal.new()
    self.EntityUnregistered = signal.new()
    self.ChangedState       = signal.new()


    for _, state in statesList do
        self.Collections[state] = {}
        self.RegisteredStates[state.Name] = state
    end


    self.PrintStateChange = false


    return self 
end



--[=[
    @within FSM
    @param entity Entity -- The entity to be registered
    @param initialState State? -- The initial state the entity should be registered in 

    Registers the entity into the state machine without initializing it. if the optional
    initial state argument is given then the entity will be registered in that state, else
    it will be registered in the FSM Initial State
]=]
function finiteStateMachine:RegisterEntity(entity: Entity, initialState: State?): nil
    self = self ::FSM
    initialState = initialState or self.InitialState
    
    if self.RegisteredStates[initialState.Name] then
        self.RegisteredEntities[entity] = initialState
        self.EntityRegistered:Fire(entity, initialState)
    else
        error(initialState.Name .." is not registered in the state machine! ")
    end
end


--[=[
    @within FSM
    @param entity Entity -- The entity to be unregistered

    Completely Removes the entity from the state machine. 
    The entity current state Exit method WILL NOT BE CALLED.
]=]
function finiteStateMachine:UnRegisterEntity(entity: Entity): nil
    self = self :: FSM
    if self.RegisteredEntities[entity] then
        local state = self.RegisteredEntities[entity]
        self.Collections[state][entity] = nil
        self.ActiveEntities[entity]     = nil
        self.RegisteredEntities[entity] = nil
        self.EntityUnregistered:Fire(entity)
    else
        warn(entity, "is not registered in the machine!")  
    end
end


--[=[
    @within FSM
    @param entity Entity -- The entity to be Activated
    @param initialState State? -- The state the entity should be Activated in 

    Inserts the Given entity into the FSM ActiveEntities table, which allows it to be updated
    if the optional Initial State argument is passed, then the entity will Enter that state, else
    the entity will enter the state it was originally registered in.
]=]
function finiteStateMachine:ActivateEntity(entity: Entity, initialState: State?): nil
    if not self.RegisteredEntities[entity] then
        warn(entity, "is not registered in the state machine!")
        return
    end

    if initialState then
        if self.RegisteredStates[initialState.Name] then
            self.RegisteredEntities[entity] = initialState
            self.RegisteredEntities[entity]:Enter(entity, self)
            self.EntityActivated:Fire(entity, initialState)
        else 
            warn(initialState.Name, "is not registered in the state machine, entering entity's registered state instead.")  
        end
    end

    --# for the entity to be activated, it has to be registered first into the FSM
    --# first. So eve if no initial state is passed, it's guaranteed the entity will
    --# is registered and paired with a state, so enter that one instead.

    if not initialState then
        self.RegisteredEntities[entity]:Enter(entity, self)
    end

    self.ActiveEntities[entity] = true
    self.EntityActivated:Fire(entity, self:GetCurrentState(entity))
end


--[=[
    @within FSM
    @param entity Entity -- The entity to be deactivated



    Inserts the entity's into the FSM Inactive table, which will prevent it from being updated.
    The entity's current state Exit function will be called.
]=]
function finiteStateMachine:DeactivateEntity(entity): nil
    if self.RegisteredEntities[entity] and self.ActiveEntities[entity] then
        self.RegisteredEntities[entity]:Exit(entity, self)
        self.ActiveEntities[entity]   = nil
        self.InactiveEntities[entity] = true
        self.EntityDeactivated:Fire(entity)

    elseif self.RegisteredEntities[entity] and not self.ActiveEntities[entity] then
        warn(entity, "is not active")
    else
        warn(entity, "is not registered in the machine")
    end
end



--[=[
    @within FSM
    @param entity Entity -- The entity to be registered & activated
    @param initialState State? -- The state the entity should be Activated in 



    Registers and activates the given entity in the state machine. If the initial state
    parameter is passed then it will enter that state, else it will enter the FSM inital state

    The entity's Enter method will be called.
]=]
function finiteStateMachine:RegisterAndActivateEntity(entity: Entity, initialState: State): nil
    initialState = initialState or self.InitialState
    self:RegisterEntity(entity, initialState)
    self:ActivateEntity(entity, initialState)
end

--[=[
    @within FSM
    @param entity Entity -- The entity to unregister from the state machine



    Removes the given entity from the FSM, the entity's current state Exit method will be called.
]=]
function finiteStateMachine:UnRegisterAndDeactivateEntity(entity: Entity)
    if not self.RegisteredEntities[entity] then
        warn(entity, "is not registered in the machine!")
        return
    end
    self:DeactivateEntity(entity)
    self:UnRegisterEntity(entity)
end


--[=[
    @within FSM
    
    Sets all registered entities in the state machine as Active
]=]
function finiteStateMachine:TurnOn()
    local inactiveRegisteredInstances = GetSetDifference(self.RegisteredEntities, self.ActiveEntities)
    for entity in inactiveRegisteredInstances do
        self:ActivateEntity(entity, nil)
    end
end


--[=[
    @within FSM


    Sets all registered entities in the state machine as Inactive 
]=]
function finiteStateMachine:TurnOff()
    local activeRegisteredEntities = GetSetIntersection(self.RegisteredEntities, self.ActiveEntities)
    for entity in activeRegisteredEntities do
        self:DeactivateEntity(entity)
    end
end



--[=[
    @within FSM
    @param entity Entity -- The entity to change state of.
    @param newState State -- The new state the entity will enter.
    


    Exits the entity from it's current state and enters it into the new given state.
]=]
function finiteStateMachine:ChangeState(entity: Entity, newState: State)
    if not newState then
        warn("No new state was passed!")
        return

    elseif not self.RegisteredStates[newState.Name] then
        warn(newState.Name, "is not registered in the state machine!")
        return
    end 
    

    if self.PrintStateChange then
        local currentState = self.RegisteredEntities[entity]
        warn(entity, "Coming from:", currentState.Name, "To:", newState.Name)
    end


    self.RegisteredEntities[entity]:Exit(entity, self)
    self.RegisteredEntities[entity] = newState
    self.RegisteredEntities[entity]:Enter(entity, self)
    self.ChangedState:Fire(entity, newState)
end


--[=[
    @within FSM
    @param dt number -- delta time

    Updates all active entities in the State machine.
]=]
function finiteStateMachine:Update(dt)
    local activeRegisteredEntities = GetSetIntersection(self.RegisteredEntities, self.ActiveEntities)
    for entity in activeRegisteredEntities do
        self.RegisteredEntities[entity]:Update(entity, self, dt)
    end
end



--[=[
    @within FSM
    
    Returns an entity-state map of all entities registered in the state machine and their current state
]=]
function finiteStateMachine:GetEntities(): {[Entity]: State}
    return self.RegisteredEntities
end


--[=[
    @within FSM
    @param state State -- The state the entities will be gotten from.

    Returns an array of entities in the given state
]=]
function finiteStateMachine:GetEntitiesInState(state: State): {Entity}
    local entitiesInState = self.Collections[state] 
    return entitiesInState
end

--[=[
    @within FSM

    Returns all registered states in the state machine
]=]
function finiteStateMachine:GetStates(): {State}
    return self.RegisteredStates
end


--[=[
    @within FSM
    @param entity Entity -- The entity to ask which state is in

]=]
function finiteStateMachine:GetCurrentState(entity: Entity): State?
    local currentState = self.RegisteredEntities[entity]
    if currentState then
        return currentState
    end
end


--[=[
    @within FSM
    @param entity Entity -- The entity to ask which state is in
    @param state State -- The state to get entity from

    Returns either true or false depending whether the given entity finds itself in the given
    state
]=]
function finiteStateMachine:IsInState(entity: Entity, state: State): boolean
    return if self.Collections[state][entity] then true else false
end





-- !== ================================================================================||>
-- !==                                      State
-- !== ================================================================================||>


local state = {} 
state.__index = state

local stateCount = 0

function state.new(args: State): State
    stateCount += 1

    local self = setmetatable({}, state)
    self.Name     = args.Name or "State"..tostring(stateCount)
    self.OnEnter  = args.OnEnter or function()end
    self.OnUpdate = args.OnUpdate or function()end
    self.OnExit   = args.OnExit or function()end

    return self 
end


function state:Enter(entity: Entity, fsm: FSM)
    self.OnEnter(entity, fsm)
end


function state:Update(entity: Entity, fsm: FSM, dt: number)
    self.OnUpdate(entity, fsm, dt)
end
    

function state:Exit(entity: Entity, fsm: FSM)
    self.OnExit(entity, fsm)
end



return {
    FSM = finiteStateMachine,
    State = state,
}