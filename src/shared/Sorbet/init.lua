local Signal = require(script.Signal)
local nop = function()end


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


local function ResolveState(self: StateMachine, stateToResolve: State | string)
    
    if type(stateToResolve) == "table" then
        for _, state in self.States do
            if state == stateToResolve then
                return stateToResolve
            end
        end
        
    elseif type(stateToResolve) == "string" then
        for stateName in self.States do
            if stateToResolve.Name == stateName then
                return stateToResolve
            end          
        end
    else
        warn("Given state is not the correct type!", typeof(stateToResolve))
        return
    end

    warn(stateToResolve, stateNotAddedMsg)
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
Sorbet.States   = {}

--==/ Constructors ===============================||>
Sorbet.state = function(name: string, callbacks:{
    OnEnter  : (entity: Entity, stateMachine: StateMachine, state: State, fromState: State) -> nil?,
    OnUpdate : (entity: Entity, stateMachine: StateMachine, state: State, dt: number?) -> nil?,
    OnExit   : (entity: Entity, stateMachine: StateMachine, state: State, toState: State) -> nil?,
})

    _assertLevel(type(name) == "string", "Bad argument 1# expected string not ".. typeof(name))
    callbacks.OnEnter  = callbacks.OnEnter or nop
    callbacks.OnUpdate = callbacks.OnUpdate or nop
    callbacks.OnExit   = callbacks.OnExit or nop
    
    
    local self: State = {
        Name         = name,
        OnEnter      = callbacks.OnEnter,
        OnExit       = callbacks.OnExit,
        OnUpdate     = callbacks.OnUpdate,

        _Enter       = Signal.new(),
        _Exit        = Signal.new(),
        _Connections = {}
    }

    self._Connections._Enter = self.Entered:Connect(self.OnEnter)
    self._Connections._Exit  = self.Exited:Connect(self.OnExit)

    return self
end


Sorbet.machine = function(entities: Array<any>, states: Array<State>, initialState: State)
    --//XXX states should prob be validated so they're actually states
    _assertLevel(type(states) == "table", "Bad argumetn 2# states must be a table of states not a ".. typeof(states))

    initialState = if initialState then initialState else states[1]
    local statesDictionary = {}
    for _, state in states do 
        statesDictionary[state.Name] = state
    end

    local entitiesLookup  = {}
    local entitiesToState = {}
    for _, entity in entities do
        entitiesToState[entity] = initialState
        entitiesLookup[entity] = true
    end

    

    local self: StateMachine = {
        Entities       = entitiesLookup,
        States         = statesDictionary,
        ActiveEntities = {},
        InitialState   = initialState,


        EntityAdded    = Signal.new(),

        EntitiesToState = entitiesToState,
    }
    

    --# inherit sorbet functions
    for k, v in Sorbet do
        if v == "state" then continue end
        self[k] = v 
    end


    return self
end


--==/ Methods ===============================||>

Sorbet.AddEntity = function(self: StateMachine, entity: Entity, initialState: State?)
    if self.Entities[entity] then
        return
    end

    if initialState then
        initialState = ResolveState(self, initialState)
    end

    self.Entities[entity]        = true
    self.EntitiesToState[entity] = initialState or self.InitialState

    self.EntityAdded:Fire(entity, initialState)
end



Sorbet.RemoveEntity = function(self: StateMachine, entity: Entity)
    if not self.Entities[entity] then
        error(entity.. entityNotAddedMsg)
    end


    self.ActiveEntities[entity]   = nil
    self.Entities[entity]         = nil
    self.EntitiesToState[entity] = nil
    

    self.EntityRemoved:Fire(entity)
end



Sorbet.StartEntity = function(self: StateMachine, entity, inState: State)
    local state = ResolveState(inState) or self.InitialState

    if not self.Entities[entity] then
        self.Entities[entity] = entity
    end


    self.EntitiesToState[entity] = state
    self.ActiveEntities[entity]   = true
    state._Enter:Fire(entity, self, state, nil)


    self.ActivatedEntity:Fire(entity, inState)
end


Sorbet.StopEntity = function(self: StateMachine, entity)
    if not self.Entities[entity] then return end
    local currentState = self.EntitiesToState[entity]
    
    
    self.ActiveEntities[entity] = nil
    currentState._Exit:Fire(entity, self, currentState, nil)


    self.EntityStopped:Fire()
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


Sorbet.Update = function(self: StateMachine, dt: number?)
    for entity, state in self.EntitiesToState do
        state.OnUpdate(entity, self, state, dt)
    end
end


Sorbet.ChangeState = function(self: StateMachine, entity: Entity, toState: State)
    if not self.Entities[entity] then
        warn(entityNotAddedMsg)
        return
    end


    if ResolveState(toState) then
        local oldState = self.EntitiesToState[entity] 

        
        oldState.OnExit(entity, self, oldState, toState)
        self.EntitiesToState[entity] = toState
        toState.OnEnter(entity, self, toState, oldState)

        self.ChangedState:Fire(entity, toState, oldState)
    end
end


Sorbet.ChangeStateFromEvent = function(self: StateMachine, entity: Entity, toState: State)
    if not self.Entities[entity] then
        warn(entityNotAddedMsg)
        return
    end

    if ResolveState(toState) then
        local oldState = self.EntitiesToState[entity] 


        oldState._Exit:Fire(entity, self, oldState, toState)
        self.EntitiesToState[entity] = toState
        toState._Enter:Fire(entity, self, toState, oldState)


        self.ChangedState:Fire(entity, toState, oldState)
    end
end





export type StateMachine = {
    Entities        : Array<Entity>,
    States          : Dictionary<State>,
    ActiveEntities  : Array<Entity>,
    InitialState    : State,
    EntitiesToState : Map<Entity, State>,
}


export type State = {
    Name: string,
    OnEnter  : (entity: Entity, stateMachine: StateMachine, state: State, fromState: State) -> nil,
    OnUpdate : (entity: Entity, stateMachine: StateMachine, state: State, dt: number?) -> nil,
    OnExit   : (entity: Entity, stateMachine: StateMachine, state: State, toState: State) -> nil,
}

type Entity        = any
type Array<T>      = {T}
type Dictionary<T> = {[string]: T}
type Map<K, V> = {[K]: V}


return Sorbet