--[[
	Figured I put this here, reminder: State transitions ARE EVENTS, not callbacks!
	if ChangeState(newState) called newState.Enter() and Enter() is recursive, everything
	poops itself, so it's safer to use events.
]]--
local Signal = require(script.Signal)

-- !== ================================================================================||>
-- !== Type Definitions
-- !== ================================================================================||>
type StateCallback  = (entity: Entity, FSM: FSM, thisState: State) -> ()
type UpdateCallback = (entity: Entity, FSM: FSM, thisState: State, dt: number) -> ()
type Set            = {[any]: any }

type StateInfo = {
	Name   : string?,
	Enter  : StateCallback?,
	Update : UpdateCallback?,
	Exit   : StateCallback?,
}

type Signal = typeof(Signal.new())

type PrivData = {
	EntitiesStateMap: { [Entity]: State },
	ActiveEntities  : { [Entity]: true },
	States          : { [State]: true },
	Entities        : {[Entity]: true},
	InitialState    : State,
	Activated       : boolean,
}
export type State = {
	Name       : string,
	Enter      : StateCallback,
	Update     : UpdateCallback,
	Exit       : StateCallback,
	Entered    : Signal,
	Exited     : Signal,
}

export type FSM = {
	Stopped        : Signal,
	Started        : Signal,
	EntityStarted  : Signal,
	EntityStopped  : Signal,
	StateChanged   : Signal,
	EntityAdded    : Signal,
	EntityRemoved  : Signal,
	StateAdded     : Signal,
	StateRemoved   : Signal,
}

export type Entity = any


-- !== ================================================================================||>
-- !== Aux functions
-- !== ================================================================================||>
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

--# it's not bool function so user can pass the name of a state (a string) 
--#	and still get a state, also makes sure the asked state is actually registered
local function ResolveState(privData: PrivData, stateToGet: State | string?): State | nil
	if stateToGet ~= nil and type(stateToGet) == "table" or type(stateToGet) == "string"  then
		for state in privData.States do
			if type(stateToGet) == "string" and state.Name == stateToGet then
				return state
			elseif stateToGet == state then
				return state
			end
		end
		return nil
	end

	return nil
end

local function nop() end


-- !== ================================================================================||>
-- !== Sorbet
-- !== ================================================================================||>
local Sorbet = {}
Sorbet.__index =  Sorbet

local fsmData    = {} :: { [FSM]: PrivData }
local statesData = {} :: {[State]: {Entered: Signal, Exited: Signal }} -- cheeky way to store both all created states and their connections
local stateCount = 0 --# Simple name/id for unnamed states, shoudn't be an issue lol 

--==/ Constructors ===============================||>

function Sorbet.Machine(creationArguments: {
		Entities      : { Entity }?,
		States       : { State }?,
		InitialState : State?,
	}?)
	local self = {}

	--# smoll Validation pass, make sure these are actually tables
	local args           = creationArguments or {} --> so the type checker is hapi ;-;
	local passedEntities = type(args.Entities) == "table" and args.Entities or {}
	local passedStates   = type(args.States)  == "table" and args.States or {} 

	for _, state: State in passedStates do
		if not statesData[state] then
			error("States table have non state objects!")
		end
	end

	--[[
		to set self.InitialState I Either:

		A. Get the initial state if given, else
		B. Get the first state of the passed state array, passedStates[1], if it exists, else
		C. create a new empty state, casue there's no init state nor passed states
	]]

	local initialState

	if type(args.InitialState)  == "table" then
		if args.InitialState._isState then
			initialState = args.InitialState
		else
			error("Passed Initial state is not a state!")
		end

	elseif #passedStates > 0 then 
		initialState = passedStates[1] -- it's guaranteed it'll be a state
	else
		initialState = Sorbet.State() -- empty placeholder state
		warn("No initial state set")
	end

	--# init priv data tables
	local entitiesStateMap = {}
	local activeEntities   = {}
	local states           = {}

	for _, entity in passedEntities do
		entitiesStateMap[entity] = initialState
	end

	for _, state in passedStates do
		states[state] = true
	end
	
	
	fsmData[self] = {
		Activated        = true,
		EntitiesStateMap = entitiesStateMap,
		ActiveEntities   = activeEntities,
		States           = states,
		Entities         = passedEntities,
		InitialState     = initialState,
	}

	--# Def public fields
	self.Stopped       = Signal.new()
	self.Started       = Signal.new()
	self.EntityStarted = Signal.new()
	self.EntityStopped = Signal.new()
	self.StateChanged  = Signal.new()
	self.EntityAdded   = Signal.new()
	self.EntityRemoved = Signal.new()
	self.StateAdded    = Signal.new()
	self.StateRemoved  = Signal.new()

	return setmetatable(self, Sorbet)
end


function Sorbet.State(stateInfo: StateInfo?)
	local info = stateInfo or {}
	stateCount += 1
	local self = {
		Name        = info.Name or tostring(stateCount),
		Enter       = info.Enter or nop,
		Exit        = info.Exit or nop,
		Update      = info.Update or nop,
		Entered     = Signal.new(),
		Exited      = Signal.new(),
	}

	statesData[self] = {
		Entered = self.Entered:Connect(self.Enter),
		Exited  = self.Exited:Connect(self.Exit)
	}


	return self
end



--==/ Add/Remove State ===============================||>
function Sorbet.AddState(self: FSM, state: State)
	local thisPrivData = fsmData[self]
	local states = thisPrivData.States 
	
	if not thisPrivData.States[state] and states[state] then
		states[state] = state
	else 
		error(tostring(state).. "is not a state!")
	end
end


function Sorbet.RemoveState(self: FSM, state: State|string?)
	local thisPrivData = fsmData[self]
	if ResolveState(thisPrivData, state) then
		if thisPrivData.InitialState == state then
			error("You're attempting to remove the initial state!")
		end
		thisPrivData.States[state] = nil
	end
end

--==/ Add/Remove Entity ===============================||>
function Sorbet.AddEntity(self: FSM, entity: Entity, initialState: State | string?)
	if entity == nil then return end
	local thisPrivData     = fsmData[self]
	local entitiesStateMap = thisPrivData.EntitiesStateMap
	local entities         = thisPrivData.Entities

	initialState             = ResolveState(thisPrivData, initialState)
	entitiesStateMap[entity] = initialState or thisPrivData.InitialState
	entities[entity]         = true
	
	self.EntityAdded:Fire(entity, initialState)
end

function Sorbet.RemoveEntity(self: FSM, entity: Entity)
	local thisPrivData = fsmData[self]
	thisPrivData.ActiveEntities[entity]   = nil
	thisPrivData.EntitiesStateMap[entity] = nil
	thisPrivData.Entities[entity]         = nil
	self.EntityRemoved:Fire(entity)
end

--==/ Start/Stop entity ===============================||>
-- more efficient if you only have a single entity in the state machine.

function Sorbet.StartEntity(self: FSM, entity, startInState: State | string?)
	local thisPrivData = fsmData[self]
	if not thisPrivData.Activated then return end
	
	
	local entitiesStateMap = thisPrivData.EntitiesStateMap
	local entityState = entitiesStateMap[entity]
	startInState = ResolveState(thisPrivData, startInState) --# Validate startInState
	
	if entityState then
		local activeEntities = thisPrivData.ActiveEntities
		entityState              = startInState or entityState
		entitiesStateMap[entity] = entityState
		activeEntities[entity]   = true

		entityState.Entered:Fire(entity, self, entityState)
		self.EntityStarted:Fire(entity)
	else
		error(tostring(entity).. "Has not been added to the state machine!")
	end
end
	

function Sorbet.StopEntity(self: FSM, entity: Entity)
	local thisPrivData   = fsmData[self]
	local entityState    = thisPrivData.EntitiesStateMap[entity]
	local activeEntities = thisPrivData.ActiveEntities

	if entityState then
		local isEntityActive = activeEntities[entity] 
		
		if isEntityActive then
			activeEntities[entity] = nil
			entityState.Exited:Fire(entity, self, entityState)
			self.EntityStopped:Fire(entity)
			return
		else
			--warn(entity, "is already inactive")
		end
	else
		error(tostring(entity).. "Has not been added to the state machine!")
	end
end

--==/ Start/Stop machine ===============================||>
function Sorbet.Start(self: FSM, startInState: State | string?)
	local thisPrivData = fsmData[self]
	if not thisPrivData.Activated then return end

	-- get all entities that are not active 
	local inactiveEntities = GetSetDifference(thisPrivData.EntitiesStateMap, thisPrivData.ActiveEntities)
	for entity in inactiveEntities do
		Sorbet.StartEntity(self, entity, startInState)
	end

	self.Started:Fire()
end

function Sorbet.Stop(self: FSM)
	local thisPrivData = fsmData[self]
	for entity in thisPrivData.ActiveEntities do
		Sorbet.StopEntity(self, entity)
	end

	self.Stopped:Fire()
end

--==/ transforms ===============================||>
function Sorbet.ChangeState(self: FSM, entity: Entity, newState: State | string?)
	local thisPrivData   = fsmData[self]
	if not thisPrivData.Activated then return end
	local activeEntities = thisPrivData.ActiveEntities
	local entitiesStates = thisPrivData.EntitiesStateMap
	local entityState    = entitiesStates[entity]

	if entityState then
		newState = ResolveState(thisPrivData, newState) 
		if newState then
			local oldState = entityState

			entityState.Exited:Fire(entity, self, entityState)
			--# prevents Entered from firing if the entity was removed 
			--# or the FSM was de-activated
			if not activeEntities[entity] or not thisPrivData.Activated then return end

			oldState    = entityState
			entityState = newState
			
			entityState.Entered:Fire(entity, self, entityState)
			thisPrivData.EntitiesStateMap[entity] = entityState

			self.StateChanged:Fire(entity, newState, oldState)
		end
	else
		error(tostring(entity).. "Has not been added to the state machine!")
	end
end

function Sorbet.Update(self: FSM, dt)
	local thisPrivData = fsmData[self]
	for entity in thisPrivData.ActiveEntities do	
		if not thisPrivData.Activated then break end
		local currentState = thisPrivData.EntitiesStateMap[entity] 
		currentState.Update(entity, self, currentState,  dt)
	end
end


--==/ Getters/ bool expressions ===============================||>
function Sorbet.GetCurrentState(self: FSM, entity: Entity)
	local thisPrivData = fsmData[self]
	return thisPrivData.EntitiesStateMap[entity]
end

function Sorbet.GetStates(self: FSM)
	local thisPrivData = fsmData[self]
	return thisPrivData.States
end

function Sorbet.GetEntities(self: FSM)
	return fsmData[self].Entities
end

function Sorbet.GetActiveEntities(self: FSM)
	return fsmData[self].ActiveEntities
end

function Sorbet.IsRegistered(self: FSM, entity: Entity)
	local thisPrivData = fsmData[self]
	return if thisPrivData.EntitiesStateMap[entity] then true else false
end

function Sorbet.IsActive(self: FSM, entity: Entity)
	local thisPrivData = fsmData[self]
	return if thisPrivData.ActiveEntities[entity] then true else false
end

return Sorbet
