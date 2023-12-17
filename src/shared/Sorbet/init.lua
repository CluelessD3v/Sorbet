--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.signal)

local nop = function()end

type Entity = any

export type State = {
    Name: string,
    OnEnter  : (entity: Entity, stateMachine: StateMachine, state: State, fromState: State?) -> nil,
    OnUpdate : (entity: Entity, stateMachine: StateMachine, state: State, dt: number) -> nil,
    OnExit   : (entity: Entity, stateMachine: StateMachine, state: State, toState: State?) -> nil,

    _Enter: typeof(Signal.new()),
    _Exit: typeof(Signal.new()),
    _Connections: {
        Enter: RBXScriptConnection,
        Exit: RBXScriptConnection,
    }
}


export type StateMachine = {
    Entities        : {[Entity]: true},
    States          : {[string]: State},
    ActiveEntities  : {[Entity]: true},
    InitialState    : State,
    EntitiesToState : {[Entity]:State},
    
    AddedEntity   : typeof(Signal.new()),
    RemovedEntity : typeof(Signal.new()),
    StartedEntity : typeof(Signal.new()),
    StoppedEntity : typeof(Signal.new()),
    ChangedState  : typeof(Signal.new()),

    AddState             : (self: StateMachine, newState: State, shouldBeInitial: boolean?) -> nil,
    RemoveState          : (self: StateMachine, state: State) -> nil,
    AddEntity            : (self: StateMachine, entity: Entity, inState: State) -> nil,
    RemoveEntity         : (self: StateMachine, entity: Entity) -> nil,
    StartEntity          : (self: StateMachine, entity: Entity, inState: State) -> nil,
    StopEntity           : (self: StateMachine, entity: Entity) -> nil,
    Start                : (self: StateMachine, inState: State) -> nil,
    Stop                 : (self: StateMachine) -> nil,
    Update               : (self: StateMachine, dt: number) -> nil,
    ChangeState          : (self: StateMachine, entity: Entity, toState: State) -> nil,
    ChangeStateFromEvent : (self: StateMachine, entity: Entity, toState: State) -> nil,
}







local entityNotAddedMsg = "Has not been added to the state machine! Remember to add the entity into the FSM first through FSM:AddEntity() if it was not added at construction"
local stateNotAddedMsg  = "Has not been added to the state machine! Remember to add the state into the FSM first through FSM:State() if it was not added at construction"
local isNotAStateMsg    = "Is not a state! States can only be created through the State constructor Sorbet.State()"


--[[
@param     any        condition    | The result of the condition.
@param     string     message      | The error message to be raised.
@param     number?    level = 2    | The level at which to raise the error.
@return    void

Implements assert with error's level argument.
]]
local function _assertLevel(condition: any, message: string, level: number?)
    if condition == nil then 
        error("Argument #1 missing or nil.", 2)
    end

    if message == nil then 
        error("Argument #2 missing or nil.", 2)
    end

    -- Lifts the error out of this function.
    level = (level or 1) + 1

    if condition then
        return condition
    end

    error(message, level)
end


local function ResolveState(self: StateMachine, stateToResolve: State | string): State | nil
    if type(stateToResolve) == "table" then
        for _, state in self.States do
            if state == stateToResolve then
               return state
            end
        end
        
    elseif type(stateToResolve) == "string" then
        for stateName, state in self.States do
            if stateToResolve == stateName then
                return state
            end          
        end
    else
        error("Given state is not the correct type!".. typeof(stateToResolve), 2)
        return 
    end

    error(tostring(stateToResolve)..stateNotAddedMsg)
    return
end


local function GetSetDifference(a, b)
	local difference = {}
	for v in a do
		if b[v] then
			continue
		end

		difference[v] = true
	end

	return difference
end

-- !== ================================================================================||>
-- !== API
-- !== ================================================================================||>

local Sorbet = {}

--==/ Constructors ===============================||>
Sorbet.state = function(name: string, callbacks:{
    OnEnter  : ((entity: Entity, stateMachine: StateMachine, state: State, fromState: State) -> nil)?,
    OnUpdate : ((entity: Entity, stateMachine: StateMachine, state: State, dt: number?) -> nil)?,
    OnExit   : ((entity: Entity, stateMachine: StateMachine, state: State, toState: State) -> nil)?,
})

    _assertLevel(type(name) == "string", "Bad argument 1# expected string not ".. typeof(name))
	local onEnter = callbacks.OnEnter or nop
	local onUpdate = callbacks.OnUpdate or nop
	local onExit = callbacks.OnExit or nop
    
    local enter = Signal.new()
    local exit = Signal.new()

    
    local self = {
        Name         = name,
        OnEnter      = onEnter,
        OnExit       = onExit,
        OnUpdate     = onUpdate,

        _Enter       = enter,
        _Exit        = exit,
        _Connections = {
            Enter = enter:Connect(onEnter),
            Exit  = exit:Connect(onExit),
        }
    } 


    return self
end


Sorbet.machine = function(entities: {any}, states: {State}, initialState: State?)
    --//XXX states should prob be validated so they're actually states
    _assertLevel(type(states) == "table", "Bad argumetn 2# states must be a table of states not a ".. typeof(states))

    local initState = if initialState then initialState else states[1]
    local statesDictionary = {}
    for _, state in states do 
        statesDictionary[state.Name] = state
    end

    local entitiesLookup  = {}:: {[Entity]: true}
    local entitiesToState = {}:: {[Entity]: State}
    for _, entity: any in entities do
        entitiesToState[entity] = initState
        entitiesLookup[entity] = true
    end

    

    local self = {
        Entities       = entitiesLookup,
        States         = statesDictionary,
        ActiveEntities = {},
        InitialState   = initState,

        AddedEntity   = Signal.new(),
        RemovedEntity = Signal.new(),
        StartedEntity = Signal.new(),
        StoppedEntity = Signal.new(),
        ChangedState  = Signal.new(),

        EntitiesToState = entitiesToState,
    }:: StateMachine
    

    --# inherit sorbet functions
    for k, v in pairs(Sorbet) do
        if v == "state" or v == "machine" then continue end
        self[k] = v 
    end


    return self
end


--==/ Methods ===============================||>
Sorbet.AddState = function(self: StateMachine, newState: State, shouldBeInitial: boolean?)
    self.States[newState.Name] = newState
    if shouldBeInitial then
        self.InitialState = newState
    end
end

Sorbet.RemoveState = function(self: StateMachine, state: State)
    self.States[state.Name] = nil
end



Sorbet.AddEntity = function(self: StateMachine, entity: Entity, initialState: State?)
    if self.Entities[entity] then
        return
    end

    if initialState then
        initialState = ResolveState(self, initialState)
    end

    self.Entities[entity]        = true
    self.EntitiesToState[entity] = initialState or self.InitialState

    self.AddedEntity:Fire(entity, initialState)
end



Sorbet.RemoveEntity = function(self: StateMachine, entity: Entity)
    if not self.Entities[entity] then
        error(entity.. entityNotAddedMsg)
    end


    self.ActiveEntities[entity]  = nil
    self.Entities[entity]        = nil
    self.EntitiesToState[entity] = nil
    

    self.RemovedEntity:Fire(entity)
end



Sorbet.StartEntity = function(self: StateMachine, entity, inState: State)
    local state = ResolveState(self, inState) or self.InitialState

    if not self.Entities[entity] then
        self.Entities[entity] = entity
    end


    self.EntitiesToState[entity] = state
    self.ActiveEntities[entity]   = true
    state._Enter:Fire(entity, self, state, nil :: State?)


    self.StartedEntity:Fire(entity, inState)
end


Sorbet.StopEntity = function(self: StateMachine, entity)
    if not self.Entities[entity] then return end
    local currentState = self.EntitiesToState[entity]
    
    
    self.ActiveEntities[entity] = nil
    currentState._Exit:Fire(entity, self, currentState, nil :: State?)


    self.StoppedEntity:Fire()
end




Sorbet.Start = function(self: StateMachine, inState: State)
    local inactiveEntities = GetSetDifference(self.Entities, self.ActiveEntities)
    for entity in inactiveEntities do
        self:StartEntity(entity, inState)
    end
end

Sorbet.Stop = function(self: StateMachine)
    for entity in self.ActiveEntities do
        self:StopEntity(entity)
    end
end


Sorbet.Update = function(self: StateMachine, dt: number)
    for entity, state in self.EntitiesToState do
        state.OnUpdate(entity, self, state, dt)
    end
end


Sorbet.ChangeState = function(self: StateMachine, entity: Entity, toState: State | string)
    if not self.Entities[entity] then
        warn(entityNotAddedMsg)
        return
    end

    local newState = ResolveState(self, toState)
    if newState then
        local oldState = self.EntitiesToState[entity] 

        
        oldState.OnExit(entity, self, oldState, newState)
        self.EntitiesToState[entity] = newState
        newState.OnEnter(entity, self, newState, oldState)

        self.ChangedState:Fire(entity, newState, oldState)
    end
end


Sorbet.ChangeStateFromEvent = function(self: StateMachine, entity: Entity, toState: State | string)
    if not self.Entities[entity] then
        warn(entityNotAddedMsg)
        return
    end

    local newState = ResolveState(self, toState)
    if newState then
        local oldState = self.EntitiesToState[entity]

        oldState._Exit:Fire(entity, self, oldState, newState)
        self.EntitiesToState[entity] = newState
        newState._Enter:Fire(entity, self, newState, oldState)

        self.ChangedState:Fire(entity, newState, oldState)
    end
end





return Sorbet