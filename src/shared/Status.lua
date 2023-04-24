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

    An entity can be accessed using the GetRegisteredEntities Getter
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
    GetRegisteredEntities : (self: FSM) -> {[Entity]: State},
    GetRegisteredStates   : (self: FSM) -> {State},
    GetEntityCurrentState : (self: FSM, entity: Entity) -> State
}


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
    OnEnter  : (entity: Entity, fsm: FSM, ...any) -> nil?,
    OnUpdate : (entity: Entity, fsm: FSM, dt: number, ...any) -> nil?,
    OnExit   : (entity: Entity, fsm: FSM, ...any) -> nil?,

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

function finiteStateMachine.new(initialState: State, statesList: {[string]: State}): FSM
    local self = setmetatable({}, finiteStateMachine) :: FSM
    self.InitialState     = initialState
    
    self.RegisteredStates   = {}
    self.RegisteredEntities = {}
    self.ActiveEntities     = {}
    self.InactiveEntities   = {}
    self.Collections        = {}


    for name, state in statesList do
        self.Collections[state] = {}
        self.RegisteredStates[name] = state
    end


    self.PrintStateChange = true


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
    initialState = initialState or self.InitialState
    
    if self.RegisteredStates[initialState.Name] then
        self.RegisteredEntities[entity] = initialState
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
    local state = self.RegisteredEntities[entity]
    self.Collections[state][entity] = nil
    self.ActiveEntities[entity]     = nil
    self.RegisteredEntities[entity] = nil
end


--[=[
    @within FSM
    @param entity Entity -- The entity to be Activated
    @param initialState State? -- The state the entity should be Activated in 

    Inserts the Given entity into the FSM ActiveEntities table, which allows it to be updated
    if the optional Initial State argument is passed, then the entity will Enter that state, else
    the entity will enter the state it was originally registered in.
]=]
function finiteStateMachine:ActivateEntity(entity: Entity, initialState: State?, ...): nil
    if not self.RegisteredEntities[entity] then
        warn(entity, "is not registered in the state machine!")
        return
    end

    if initialState then
        if self.RegisteredStates[initialState.Name] then
            self.RegisteredEntities[entity] = initialState
            self.RegisteredEntities[entity]:Enter(entity, self, ...)
        else 
            warn(initialState.Name, "is not registered in the state machine, entering entity's registered state instead.")  
        end
    end

    if not initialState then
        self.RegisteredEntities[entity]:Enter(entity, self, ...)
    end

    self.ActiveEntities[entity] = true
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


    Sets all of the state machine's active entities 
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
    @param onExitData {any} -- Optional array of data passed to the entity's current state OnExit
    @param onEntertData {any} -- Optional array of data passed to the entity's new state OnEnter
    


    Exits the entity from it's current state and enters it into the new given state.
]=]
function finiteStateMachine:ChangeState(entity: Entity, newState: State, onExitData: {any}?, onEnterData: {any}?)
    if not newState then
        print(self.RegisteredStates[newState.Name])
        warn("No new state was passed!")
        return

    elseif not self.RegisteredStates[newState.Name] then
        warn(newState.Name, "is not registered in the state machine!")
        return
    end 
    
    -- print(currentState, newState)

    if self.PrintStateChange then
        local currentState = self.RegisteredEntities[entity] 
        warn(entity, "Coming from:", currentState.Name, "To:", newState.Name)
    end

    onExitData  = onExitData or {}
    onEnterData = onEnterData or {}

    self.RegisteredEntities[entity]:Exit(entity, self, table.unpack(onExitData))
    self.RegisteredEntities[entity] = newState
    self.RegisteredEntities[entity]:Enter(entity, self, table.unpack(onEnterData))


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
function finiteStateMachine:GetRegisteredEntities(): {[Entity]: State}
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
function finiteStateMachine:GetRegisteredStates(): {State}
    return self.RegisteredStates
end


--[=[
    @within FSM
    @param entity Entity -- The entity to ask which state is in

]=]
function finiteStateMachine:GetEntityCurrentState(entity: Entity): State?
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

function state.new(args)
    stateCount += 1

    local self = setmetatable({}, state)
    self.Name     = args.Name or "State"..tostring(stateCount)
    self.OnEnter  = args.OnEnter or function()end
    self.OnUpdate = args.OnUpdate or function()end
    self.OnExit   = args.OnExit or function()end

    return self
end


function state:Enter(subject, fsm)
    self.OnEnter(subject, fsm)
end


function state:Update(subject, fsm, dt)
    self.OnUpdate(subject, fsm, dt)
end
    

function state:Exit(subject, fsm)
    self.OnExit(subject, fsm)
end



return {
    FSM = finiteStateMachine,
    State = state,
}