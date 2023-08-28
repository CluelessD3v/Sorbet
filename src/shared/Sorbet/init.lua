--[[
	Figured I put this here, reminder: State transitions ARE EVENTS, not callbacks!
	if ChangeState(newState) called newState.Enter() and Enter() is recursive, everything
	poops itself, so it's safer to use events.
]]--

local ReplicatedStorage = game:GetService "ReplicatedStorage"
local Packages          = ReplicatedStorage.Packages
local Signal            = require(Packages.signal)

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
}
export type State = {
	Name       : string,
	Enter      : StateCallback,
	Update     : UpdateCallback,
	Exit       : StateCallback,
	Entered    : Signal,
	Exited     : Signal,
	Connections: { Entered: Signal, Exited: Signal },
	_isState   : boolean, --> Guetto type checking lol.
}
export type FSM = {
	InitialState   : State,
	Activated      : boolean,
	Stopped        : Signal,
	Started        : Signal,
	EntityStarted  : Signal,
	EntityStopped  : Signal,
	StateChanged   : Signal,
	EntityAdded    : Signal,
	EntityRemoved  : Signal,
	StateAdded     : Signal,
	StateRemoved   : Signal,
	
	AddState       : (self: FSM, state: State) -> (),
	RemoveState    : (self: FSM, state: State) -> (),
	AddEntity      : (self: FSM, entity: Entity, inState: State?|string?) -> (),
	RemoveEntity   : (self: FSM, entity: Entity) -> (),
	StartEntity    : (self: FSM, entity: Entity, inState: State?|string?) -> (),
	StopEntity     : (self: FSM, entity: Entity) -> (),
	Start          : (self: FSM, inState: State?|string?) -> (),
	Stop           : (self: FSM) -> (),

	ChangeState    : (self: FSM, entity: Entity, toState: State|string?) -> (),
	Update         : (self: FSM, dt: number) -> (),

	GetCurrentState: (self:FSM, entity: Entity) -> State?,
	GetStates      : (self: FSM) -> State,
	IsRegistered   : (self: FSM, entity: Entity) -> boolean,
	IsActive       : (self: FSM, entity: Entity) -> boolean,
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
		warn(stateToGet, "Has not been added to the state machine!")
		return nil
	end

	return nil
end

local function nop() end


-- !== ================================================================================||>
-- !== Sorbet
-- !== ================================================================================||>
local Sorbet = {}
Sorbet.__index = Sorbet

Sorbet.Stopped       = Signal.new()
Sorbet.Started       = Signal.new()
Sorbet.EntityStarted = Signal.new()
Sorbet.EntityStopped = Signal.new()
Sorbet.StateChanged  = Signal.new()
Sorbet.EntityAdded   = Signal.new()
Sorbet.EntityRemoved = Signal.new()
Sorbet.StateAdded    = Signal.new()
Sorbet.StateRemoved  = Signal.new()

local privateData = {} :: { [FSM]: PrivData }


local init = {} 
init.__index = init

--==/ Constructors ===============================||>

function Sorbet.FSM(creationArguments: {
		Entities      : { Entity }?,
		States       : { State }?,
		InitialState : State?,
	}?): FSM
	local self = setmetatable({}, Sorbet)

	--# smoll Validation pass, make sure these are actually tables
	local args           = creationArguments or {} --> so the type checker is hapi ;-;
	local passedEntities = type(args.Entities) == "table" and args.Entities or {}
	local passedStates   = type(args.States)  == "table" and args.States or {} 

	for _, state: State in passedStates do
		if not state._isState then
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
	
	
	privateData[self] = {
		EntitiesStateMap = entitiesStateMap,
		ActiveEntities  = activeEntities,
		States          = states,
	}

	--# Def public fields
	self.InitialState = initialState
	self.Activated    = true

	return self
end

--# Simple name/id for unnamed states, shoudn't be an issue lol 
local stateCount = 0
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
		Connections = {},
		_isState    = true,
	}

	self.Connections.Entered = self.Entered:Connect(self.Enter)
	self.Connections.Exited  = self.Exited:Connect(self.Exit)
	return self
end


--==/ Add/Remove State ===============================||>
function Sorbet.AddState(self: FSM, state: State)
	local thisPrivData = privateData[self]
	local states = thisPrivData.States 
	
	if not thisPrivData.States[state] and state._isState then
		states[state] = state
	else 
		error(tostring(state).. "is not a state!")
	end
end


function Sorbet.RemoveState(self: FSM, state: State|string?)
	local thisPrivData = privateData[self]
	if ResolveState(thisPrivData, state) then
		if self.InitialState == state then
			error("You're attempting to remove the initial state!")
		end
		thisPrivData.States[state] = nil
	end
end

--==/ Add/Remove Entity ===============================||>
function Sorbet.AddEntity(self: FSM, entity: Entity, initialState: State | string?)
	if entity == nil then return end
	local thisPrivData     = privateData[self]
	local EntitiesStateMap = thisPrivData.EntitiesStateMap

	initialState             = ResolveState(thisPrivData, initialState)
	EntitiesStateMap[entity] = initialState or self.InitialState
	
	self.EntityAdded:Fire(entity, initialState)
end

function Sorbet.RemoveEntity(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	thisPrivData.ActiveEntities[entity]   = nil
	thisPrivData.EntitiesStateMap[entity] = nil
	self.EntityRemoved:Fire(entity)
end

--==/ Start/Stop entity ===============================||>
-- more efficient if you only have a single entity in the state machine.

function Sorbet.StartEntity(self: FSM, entity, startInState: State | string?)
	if not self.Activated then return end

	local thisPrivData = privateData[self]
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
	local thisPrivData   = privateData[self]
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
	if not self.Activated then return end

	local thisPrivData = privateData[self]

	-- get all entities that are not active 
	local inactiveEntities = GetSetDifference(thisPrivData.EntitiesStateMap, thisPrivData.ActiveEntities)
	for entity in inactiveEntities do
		Sorbet.StartEntity(self, entity, startInState)
	end


	self.Started:Fire()
end

function Sorbet.Stop(self: FSM)
	local thisPrivData = privateData[self]
	for entity in thisPrivData.ActiveEntities do
		Sorbet.StopEntity(self, entity)
	end

	self.Stopped:Fire()
end

--==/ transforms ===============================||>
function Sorbet.ChangeState(self: FSM, entity: Entity, newState: State | string?)
	if not self.Activated then return end
	local thisPrivData   = privateData[self]
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
			if not activeEntities[entity] or not self.Activated then return end

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
	local thisPrivData = privateData[self]
	for entity in thisPrivData.ActiveEntities do	
		if not self.Activated then break end
		local currentState = thisPrivData.EntitiesStateMap[entity] 
		currentState.Update(entity, self, currentState,  dt)
	end
end


--==/ Getters/ bool expressions ===============================||>
function Sorbet.GetCurrentState(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	return thisPrivData.EntitiesStateMap[entity]
end

function Sorbet.GetStates(self: FSM)
	local states = {}
	local thisPrivData = privateData[self]

	for state in thisPrivData do
		table.insert(states, state)
	end

	return states
end

function Sorbet.IsRegistered(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	return if thisPrivData.EntitiesStateMap[entity] then true else false
end

function Sorbet.IsActive(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	return if thisPrivData.ActiveEntities[entity] then true else false
end


return Sorbet
