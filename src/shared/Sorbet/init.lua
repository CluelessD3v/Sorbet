--[[
	Figured I put this here, reminder: State transitions ARE EVENTS, not callbacks!
	if ChangeState(newState) called newState.Enter() and Enter() is recursive, everything
	poops itself, so it's safer to use events.
]]--
local Signal = require(script.Parent.Signal)

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

local entityNotAddedMsg = "Has not been added to the state machine! Remember to add the entity into the FSM first through FSM:AddEntity() if it was not added at construction"
local stateNotAddedMsg  = "Has not been added to the state machine! Remember to add the state into the FSM first through FSM:State() if it was not added at construction"
local isNotAStateMsg    = "Is not a state! States can only be created through the State constructor Sorbet.State()"

--==/ Constructors ===============================||>
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

	--# Private events used to change state asyncronously, given that events run
	--# in their own thread, if any of the callbacks are recursives it won't halt
	--# the fsm execution. Also has the potential to be very efficient cause it's 
	--# 2 threads per state instead of one thread for every single entity
	statesData[self] = {
		Entered = self.Entered:Connect(self.Enter),
		Exited  = self.Exited:Connect(self.Exit)
	}
	
	return self
end


function Sorbet.Machine(entities : { Entity }, states : { State }, initialState : State?)
	local self = {}
	assert(type(entities) == "table", "Bad argument #1, expected table") 
	assert(type(states) == "table", "Bad argument #2, expected table")

	for _, state: State in states do
		if not statesData[state] then
			error(tostring(state).."is not a state object! States can only be constructed using Sorbet's State constructor Sorbet.State(StateInfoTable)")
		end
	end

	--[[
		to set self.InitialState I Either:

		A. Get the initial state if given, else
		B. Get the first state of the passed state array, passedStates[1], if it exists, else
		C. create a new empty state, casue there's no init state nor passed states
	]]


	if type(initialState)  == "table" then
		if not statesData[initialState] then
			error(tostring(initialState).." "..isNotAStateMsg)
		end

	elseif #states > 0 then 
		initialState = states[1] -- it's guaranteed it'll be a state
	else
		initialState = Sorbet.State() -- empty placeholder state
		warn("No initial state set")
	end

	--# init priv data tables
	local entitiesStateMap = {}
	local activeEntities   = {}
	local statesLut        = {}
	local entitiesLut      = {}

	for _, entity in entities do
		entitiesLut[entity] = true
		entitiesStateMap[entity] = initialState
	end

	for _, state in states do
		statesLut[state] = true
	end


	fsmData[self] = {
		Activated        = true,
		EntitiesStateMap = entitiesStateMap,
		ActiveEntities   = activeEntities,
		States           = statesLut,
		Entities         = entitiesLut,
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


export type FSM = typeof(Sorbet.Machine({},{}, Sorbet.State()))

--==/ Setters ===============================||>
--# sets the default initial state of the state machine
function Sorbet.SetInitialState(self: FSM, state: State|string?)
	local thisPrivData = fsmData[self]
	local resolvedState = ResolveState(thisPrivData, state)
	if resolvedState then
		thisPrivData.InitialState = resolvedState
	else
		error(tostring(state).." "..stateNotAddedMsg)
	end
end

--# sets the state of the fsm, playing/paused.
function Sorbet.SetMachineActiveState(self: FSM, isActivated: boolean)
	local thisPrivData = fsmData[self]
	assert(type(isActivated) == "boolean", "Bad argument, expected boolean ")
	thisPrivData.Activated = isActivated
end


--==/ Add/Remove State ===============================||>
--//XXX these still feel adhoc... revise these
function Sorbet.AddState(self: FSM, state: State, asInitial: boolean?)
	local thisPrivData = fsmData[self]
	local states = thisPrivData.States
	assert(type(asInitial) == "boolean" or type(asInitial) == "nil", "Bad argument #2, expected boolean or nil")

	if not thisPrivData.States[state] and states[state] then
		states[state] = state
		if asInitial then
			thisPrivData.InitialState = asInitial
		end
	else 
		error(tostring(state).." "..isNotAStateMsg)
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
--# Note that these methods do not start/stop the entity, it just registers/unregisters
--# them from the fsm.


--# Adds an entity to the machine and optionally set it's initial state so it can
--# at any state the user needs to, else it'll use the machine's default initial state 
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


--# Removes the entity from the state machine entirely
function Sorbet.RemoveEntity(self: FSM, entity: Entity)
	local thisPrivData = fsmData[self]
	thisPrivData.ActiveEntities[entity]   = nil
	thisPrivData.EntitiesStateMap[entity] = nil
	thisPrivData.Entities[entity]         = nil
	self.EntityRemoved:Fire(entity)
end

--==/ Start/Stop entity ===============================||>
-- more efficient start/stops if you only have a single entity in the state machine.

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

		--entityState:Enter(entity, self, entityState)
		
		self.EntityStarted:Fire(entity)
	else
		error(tostring(entity).. " "..entityNotAddedMsg)
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
		error(tostring(entity).." ".. entityNotAddedMsg)
	end
end

--==/ Start/Stop machine ===============================||>
--# Starts/Resumes the state machine, calling all entities current state Enter
--# callback
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

--# Stops/Pauses the state machine calling all entities Exit callback
function Sorbet.Stop(self: FSM)
	local thisPrivData = fsmData[self]
	for entity in thisPrivData.ActiveEntities do
		Sorbet.StopEntity(self, entity)
	end

	self.Stopped:Fire()
end

--==/ transforms ===============================||>
--# Prevents recursive state changes wrecking havoc on the fsm... but removes
--# control from the user!
function Sorbet.ChangeStateAsync(self: FSM, entity: Entity, newState: State | string?)
	local thisPrivData   = fsmData[self]
	if not thisPrivData.Activated then return end
	local activeEntities = thisPrivData.ActiveEntities
	local entitiesStates = thisPrivData.EntitiesStateMap
	local entityState    = entitiesStates[entity]

	if entityState then
		newState = ResolveState(thisPrivData, newState) 
		if newState then


			entityState.Exited:Fire(entity, self, entityState)
			--# prevents Entered from firing if the entity was removed 
			--# or the FSM was de-activated
			if not activeEntities[entity] or not thisPrivData.Activated then return end

			local oldState    = entityState
			entityState = newState

			entityState.Entered:Fire(entity, self, entityState)
			thisPrivData.EntitiesStateMap[entity] = entityState

			self.StateChanged:Fire(entity, newState, oldState)
		else
			error(tostring(newState).." "..stateNotAddedMsg)
		end
	else
		error(tostring(entity).." "..entityNotAddedMsg)
	end
end

--# Syncronous State change, allows the user to handle state changes however it
--# sees fit
function Sorbet.ChangeState(self: FSM, entity: Entity, newState: State | string?): true?
	local thisPrivData   = fsmData[self]
	if not thisPrivData.Activated then return end
	local activeEntities = thisPrivData.ActiveEntities
	local entitiesStates = thisPrivData.EntitiesStateMap
	local entityState    = entitiesStates[entity]

	if entityState then
		newState = ResolveState(thisPrivData, newState) 
		if newState then

			entityState.Exit(entity, self, entityState)
			--# prevents Entered from firing if the entity was removed 
			--# or the FSM was de-activated
			if not activeEntities[entity] or not thisPrivData.Activated then return end

			local oldState    = entityState
			entityState = newState

			entityState.Enter(entity, self, entityState)
			thisPrivData.EntitiesStateMap[entity] = entityState

			self.StateChanged:Fire(entity, newState, oldState)

			return true
		else
			error(tostring(newState).." "..stateNotAddedMsg)
		end
	else
		error(tostring(entity).." "..entityNotAddedMsg)
	end
end

--# Calls all entities current state Update callback if the machine is active.
function Sorbet.Update(self: FSM, dt)
	local thisPrivData = fsmData[self]
	for entity in thisPrivData.ActiveEntities do	
		if not thisPrivData.Activated then break end
		local currentState = thisPrivData.EntitiesStateMap[entity] 
		currentState.Update(entity, self, currentState,  dt)
	end
end


--==/ Getters/ bool expressions ===============================||>
--! Warning, don't modify any of these returned tables, it will cause serious bugs.
--//XXX these getters suck... Should rethink better ones
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
