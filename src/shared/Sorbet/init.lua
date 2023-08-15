--[[
	Figured I put this here, reminder: State transitions ARE EVENTS, not callbacks!
	if ChangeState(newState) called newState.Enter() and Enter() is recursive, everything
	poops itself, so it's safer to use events.
]]--

local ReplicatedStorage = game:GetService "ReplicatedStorage"
local Packages          = ReplicatedStorage.Packages
local Sigal             = require(Packages.signal)

-- !== ================================================================================||>
-- !== Type Definitions
-- !== ================================================================================||>
type StateCallback  = (entity: Entity, FSM: FSM, thisState: State) -> ()
type UpdateCallback = (entity: Entity, FSM: FSM, thisState: State, dt: number) -> ()
type Set            = { [any]: any }

type StateInfo = {
	Name   : string?,
	Enter  : StateCallback?,
	Update : UpdateCallback?,
	Exit   : StateCallback?,
}

type Signal = typeof(Sigal.new())
type CreationInfo = {
	Entities      : { Entity }?,
	States       : { State }?,
	InitialState : State?,
}

type PrivData = {
	EntitiesToState : { [Entity]: State },
	ActiveEntities  : { [Entity]: true },
	States          : { [string]: State },
}
export type State = {
	Name        : string,
	Enter       : StateCallback,
	Update      : UpdateCallback,
	Exit        : StateCallback,
	Entered     : Signal,
	Exited      : Signal,
	Connections : { Entered: Signal, Exited: Signal },
	_isState    : boolean, --> Guetto type checking lol.
}
export type FSM = {
	InitialState: State,
	Stopped       : Signal,
	Started       : Signal,
	EntityStarted : Signal,
	EntityStopped : Signal,
	ChangedState  : Signal,
	EntityAdded   : Signal,
	EntityRemoved : Signal,
	StateAdded    : Signal,
	StateRemoved  : Signal,

	AddEntity       : (self: FSM, entity: Entity, inState: State?|string?) -> (),
	RemoveEntity    : (self: FSM, entity: Entity) -> (),
	StartEntity     : (self: FSM, entity: Entity, inState: State?|string?) -> (),
	StopEntity      : (self: FSM, entity: Entity) -> (),
	Start           : (self: FSM, inState: State?|string?) -> (),
	Stop            : (self: FSM) -> (),
	ChangeState     : (self: FSM, entity: Entity, toState: State|string?) -> (),
	Update          : (self: FSM, dt: number) -> (),
	GetCurrentState : (self:FSM, entity: Entity) -> State?,
	GetStates       : (self: FSM) -> State,
	IsRegistered    : (self: FSM, entity: Entity) -> boolean,
	IsActive        : (self: FSM, entity: Entity) -> boolean,
	
}

export type Entity = any


-- !== ================================================================================||>
-- !== Aux functions
-- !== ================================================================================||>
local function GetSetIntersection(set1: Set, set2: Set): Set
	local result: Set = {}
	for k in pairs(set1) do
		if set2[k] then
			result[k] = true
		end
	end
	return result
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

local function GetRegisteredState(privData: PrivData, stateToGet: State| string| nil): State| nil
	if stateToGet == nil then
		return nil
	end

	for name, state in privData.States do
		if type(stateToGet) == "string" and name == stateToGet then
			return state
		elseif stateToGet == state then
			return state
		end
	end

	return nil
end

local function nop() end


-- !== ================================================================================||>
-- !== Sorbet
-- !== ================================================================================||>
local Sorbet = {}
Sorbet.__index = Sorbet

local privateData = {} :: { [FSM]: PrivData }

function Sorbet.FSM(creationInfo: CreationInfo?): FSM
	local self = setmetatable({}, Sorbet)

	--# Validation pass, make sure these are actually tables
	local info           = creationInfo or {} --> so the type checker is hapi ;-;
	local passedEntities = type(info.Entities) == "table" and info.Entities or {}
	local passedStates   = type(info.States)  == "table" and info.States or {}

	--# remove non state values from the passed states array
	for index, state: State in passedStates do
		if not state._isState then
			table.remove(passedStates, index)
		end
	end

	--[[
		to set  self.InitialState I Either:

		A. Get the initial state if given, else
		B. Get the first state of the passed state array if it exists, else
		C. create a new empty state, casue there's no init state nor passed states
	]]

	local initialState 

	if type(info.InitialState)  == "table" then
		if info.InitialState._isState then
			initialState = info.InitialState
		end
	elseif #passedStates > 0 then
		initialState = passedStates[1]
	else
		initialState = Sorbet.State()
	end

	--# init priv data tables
	local entitiesToState = table.create(#passedEntities)
	local activeEntities  = table.create(#passedEntities)
	local states = table.create(#passedStates) 

	for _, entity in passedEntities do
		entitiesToState[entity] = initialState
	end

	for _, state in passedStates do
		states[state.Name] = state
	end
	
	
	self.InitialState = initialState
	privateData[self] = {
		EntitiesToState = entitiesToState,
		ActiveEntities  = activeEntities,
		States          = states
	}

	return self
end

--# Simple name/id for unnamed states, shoudn't be an issue lol 
local stateCount = 0
function Sorbet.State(stateInfo: StateInfo?, fsm: FSM?)
	local info = stateInfo or {}
	stateCount += 1
	local self = {
		Name        = info.Name or tostring(stateCount),
		Enter       = info.Enter or nop,
		Exit        = info.Exit or nop,
		Update      = info.Update or nop,
		Entered     = Sigal.new(),
		Exited      = Sigal.new(),
		Connections = {},
		_isState = true,
	}

	self.Connections.Entered = self.Entered:Connect(self.Enter)
	self.Connections.Exited  = self.Exited:Connect(self.Exit)

	if fsm and  privateData[fsm] then
		 privateData[fsm].States[self] = true
	end

	return self
end


--==/ Add/Remove ===============================||>
function Sorbet.AddEntity(self: FSM, entity: Entity, initialState: State)
	local thisPrivData = privateData[self]
	thisPrivData.EntitiesToState[entity] = if type(initialState) == "table" and initialState._isState then initialState else self.InitialState
end

function Sorbet.RemoveEntity(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	thisPrivData.ActiveEntities[entity] = nil
	thisPrivData.EntitiesToState[entity] = nil
end

--==/ Start/Stop entity ===============================||>
-- more efficient if you only have a single entity in the state machine.

function Sorbet.StartEntity(self: FSM, entity, startInState: State? | string?)
	local thisPrivData = privateData[self]
	local registeredStartState = GetRegisteredState(thisPrivData, startInState) 
	
	if startInState then
		if registeredStartState then --# make sure the state is actually registered in the fsm
			startInState = registeredStartState
		else 
			warn(startInState, "has not been added into the state machine")
			return
		end
	end

	local currentState = thisPrivData.EntitiesToState[entity] 
	if currentState  then 
		currentState = startInState or currentState
		thisPrivData.EntitiesToState[entity] = currentState	--# overwrites the state if startInState was passed	
		thisPrivData.ActiveEntities[entity] = true
		currentState.Entered:Fire(entity, self, currentState)
	else
		warn(entity, "has not been added to the state machine")
	end
end
	

function Sorbet.StopEntity(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	local currentState = thisPrivData.EntitiesToState[entity]
	local activeEntities = thisPrivData.ActiveEntities

	if currentState then
		local isEntityActive = activeEntities[entity] 
		print(isEntityActive)
		if isEntityActive == true then
			activeEntities[entity] = nil
			currentState.Exited:Fire(entity, self, currentState)
			return
		else
			warn(entity, "is already inactive")
		end
	else
		warn(entity, "has not been added to the state machine")
	end
end

--==/ Start/Stop machine ===============================||>
function Sorbet.Start(self: FSM, startInState: State?|string?)
	local thisPrivData = privateData[self]
	local inactiveEntities = GetSetDifference(thisPrivData.EntitiesToState, thisPrivData.ActiveEntities)
	for entity in inactiveEntities do
		Sorbet.StartEntity(self, entity, startInState)
	end
end

function Sorbet.Stop(self: FSM)
	local thisPrivData = privateData[self]
	for entity in thisPrivData.ActiveEntities do
		Sorbet.StopEntity(self, entity)
	end
end

--==/ transforms ===============================||>
function Sorbet.ChangeState(self: FSM, entity: Entity, newState: State | string?)
	local thisPrivData = privateData[self]
	local activeEntities = thisPrivData.ActiveEntities
	local currentState = thisPrivData.EntitiesToState[entity]

	if currentState then
		--# validate next state and or get state object from the given name
		newState = GetRegisteredState(thisPrivData, newState) 
		if newState then
			currentState.Exited:Fire(entity, self, currentState)
			local entityIsActive = activeEntities[entity]
			
			--# prevents Entered from firing if the entity was removed
			if not entityIsActive then return end
			
			currentState = newState
			currentState.Entered:Fire(entity, self, currentState)
			thisPrivData.EntitiesToState[entity] = currentState
		else
			warn("Can't change state to!", newState)
		end
	else
		warn(entity, "is not registered in the state machine!")
	end
end

function Sorbet.Update(self: FSM, dt)
	local thisPrivData = privateData[self]
	for entity in thisPrivData.ActiveEntities do
		local currentState = thisPrivData.EntitiesToState[entity] 
		currentState.Update(entity, self, currentState,  dt)
	end
end


--==/ Getters/ bool expressions ===============================||>
function Sorbet.GetCurrentState(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	return thisPrivData.EntitiesToState[entity]
end

function Sorbet.GetStates(self: FSM)
	local thisPrivData = privateData[self]
	return thisPrivData.States
end


function Sorbet.IsRegistered(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	return if thisPrivData.EntitiesToState[entity] then true else false
end

function Sorbet.IsActive(self: FSM, entity: Entity)
	local thisPrivData = privateData[self]
	return if thisPrivData.ActiveEntities[entity] then true else false
end


return Sorbet
