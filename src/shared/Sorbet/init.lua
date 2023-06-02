--!strict
local Packages = game.ReplicatedStorage.Packages
local Signal = require(script.Signal)

type Entity = any
type StateName = string

export type FSM = {
	ActiveEntities: { [Entity]: true },
	UpdateableEntities: { [Entity]: true },
	InactiveEntities: { [Entity]: true },

	InitialState: State,
	RegisteredEntities: { [Entity]: State },
	RegisteredStates: { [StateName]: State },
}

export type State = {
	Name: string,
	OnEnter: (entity: Entity, fsm: FSM) -> nil,
	OnUpdate: (entity: Entity, fsm: FSM, dt: number) -> nil,
	OnExit: (entity: Entity, fsm: FSM) -> nil,
}

--==/ Aux functions ===============================||>
type Set = { [any]: any }

local function GetSetIntersection(set1: Set, set2: Set): Set
	local result: Set = {}
	for k in pairs(set1) do
		if set2[k] then
			result[k] = true
		end
	end
	return result
end

-- !== ================================================================================||>
-- !== Fsm namespace
-- !== ================================================================================||>

--# "Trays" used so the state machine can "remember" entities state when calling
--# `Pause()`/`Resume()`. useful when i.e: an entity is inactive and you resume
--# the state machine, it will remain inactive.

local stateMachineTrays = {} :: {
	[FSM]: {
		ActiveWhenPaused: { [Entity]: true },
		InactiveWhenPaused: { [Entity]: true },
	},
}

local Fsm = {}
Fsm.new = function(initialState: State, states: { State }, entities: { Entity }?): FSM
	entities = entities or {}
	assert(type(entities) == "table", "entities must be of type table!")
	assert(type(states) == "table", "states must be of type table!")

	local self = {} :: FSM

	self.ActiveEntities = {}
	self.InactiveEntities = {}
	self.UpdateableEntities = {}

	self.RegisteredEntities = {}
	self.RegisteredStates = {} :: { [StateName]: State }
	self.InitialState = initialState

	--# Register entities
	for _, entity in entities do
		self.RegisteredEntities[entity] = initialState
	end

	--# Register all states
	for _, state in states do
		if self.RegisteredStates[state.Name] then
			warn(state.Name, "found duplicate state")
			continue
		end

		self.RegisteredStates[state.Name] = state
	end

	--# Register the initial state if the user forgot... Or simply could not be
	--# bothered to include it in the list :>
	if not self.RegisteredStates[initialState.Name] then
		self.RegisteredStates[initialState.Name] = initialState
	end

	return self
end

--==/ Registering/Unregistering from FSM ===============================||>

Fsm.RegisterEntity = function(fsm: FSM, entity: Entity, initialState: State?): nil
	if fsm.RegisteredEntities[entity] then
		warn(entity, "is already registered in the state machine")
	else
		fsm.RegisteredEntities[entity] = if initialState then initialState else fsm.InitialState
	end
	return nil
end

Fsm.UnregisterEntity = function(fsm: FSM, entity: Entity): nil
	--# Yeet the entity from the state machine entirely
	fsm.RegisteredEntities[entity] = nil
	fsm.ActiveEntities[entity] = nil
	fsm.InactiveEntities[entity] = nil
	return nil
end

--==/ Activation/Deactivation of behavior ===============================||>

Fsm.ActivateEntity = function(fsm: FSM, entity: Entity, initialState: State?): nil
	local entityState = fsm.RegisteredEntities[entity]
	local entityIsActive = fsm.ActiveEntities[entity]

	if entityState then
		if entityIsActive then
			warn(entity, "is already active")
		else
			fsm.InactiveEntities[entity] = nil
			fsm.ActiveEntities[entity] = true
			entityState.OnEnter(entity, fsm)
			fsm.UpdateableEntities[entity] = true
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

Fsm.DeactivateEntity = function(fsm: FSM, entity: Entity): nil
	local entityState = fsm.RegisteredEntities[entity]
	local entityIsInactive = fsm.InactiveEntities[entity]
	if entityState then
		if entityIsInactive then
			warn(entity, "is already inactive")
		else
			fsm.ActiveEntities[entity] = nil
			fsm.InactiveEntities[entity] = true
			fsm.UpdateableEntities[entity] = nil
			entityState.OnExit(entity, fsm)
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--==/ Turn On & Off State machine ===============================||>
Fsm.TurnOn = function(fsm: FSM): nil
	--# Gets all entities in both the registered & inactive table
	--# it hurts performance if there are few entities tho.
	local inactiveRegisteredInstances = GetSetIntersection(fsm.RegisteredEntities, fsm.InactiveEntities)
	for entity in inactiveRegisteredInstances do
		Fsm.ActivateEntity(fsm, entity) --> activate will make them active
	end

	return nil
end

Fsm.TurnOff = function(fsm: FSM): nil
	--# Gets all entities in both the registered & active table same deal as
	--# TurnOn(), it hurts performance if there are not many entities.
	local activeRegisteredEntities = GetSetIntersection(fsm.RegisteredEntities, fsm.ActiveEntities)
	for entity in activeRegisteredEntities do
		Fsm.DeactivateEntity(fsm, entity) --> deactivate will make them inactive
	end

	return nil
end

--==/ Pause/Resume ===============================||>
Fsm.Pause = function(fsm: FSM)
	local fsmTrays = stateMachineTrays[fsm]

	for entity in fsm.UpdateableEntities do
		fsm.UpdateableEntities[entity] = nil

		--# optimization: Logically, if an entity's updateable then it's also
		--# active, so slide it into the ActiveWhenPaused tray while at it.
		fsmTrays.ActiveWhenPaused[entity] = true
	end

	for entity in fsm.InactiveEntities do
		fsmTrays.InactiveWhenPaused[entity] = true
	end
end

Fsm.Resume = function(fsm)
	local fsmTrays = stateMachineTrays[fsm]
	for entity in fsm.InactiveEntities do
		fsmTrays.InactiveWhenPaused[entity] = nil
	end

	for entity in fsmTrays.ActiveWhenPaused do
		fsmTrays.ActiveWhenPaused[entity] = nil
		fsm.UpdateableEntities[entity] = true
	end
end

--==/ Change state & update entities ===============================||>
Fsm.Update = function(fsm: FSM, dt: number?): nil
	for entity in fsm.UpdateableEntities do
		fsm.RegisteredEntities[entity].OnUpdate(entity, fsm, dt :: number)
	end

	return nil
end

Fsm.ChangeState = function(fsm: FSM, entity: Entity, newState: State): nil
	if newState then
		if not fsm.RegisteredStates[newState.Name] then
			warn(newState.Name, "is not registered in the state machine")
			return nil
		end

		--# In case the entity is not active, just make it active right away.
		fsm.ActiveEntities[entity] = true

		--# Yeet out entity from updateable table while changing state which
		--# prevents un-expected behavior
		fsm.UpdateableEntities[entity] = nil
		fsm.RegisteredEntities[entity].OnExit(entity, fsm)
		fsm.RegisteredEntities[entity] = newState
		fsm.RegisteredEntities[entity].OnEnter(entity, fsm)
		fsm.UpdateableEntities[entity] = true --> make it updateable again
	else
		warn(entity, "cannot change state, new state is nil!")
	end

	return nil
end

-- !== ================================================================================||>
-- !== State namespace
-- !== ================================================================================||>
type Callback = (entity: Entity, fsm: FSM) -> nil
type Update = (entity: Entity, fsm: FSM, dt: number) -> nil

local State = {}
State.new = function(constructArguments: {
	Name: string,
	OnEnter: Callback?,
	OnUpdate: Update?,
	OnExit: Callback?,
}): State
	assert(constructArguments.Name ~= nil, "You must give the state a name!")

	local self = {
		Name = constructArguments.Name,
		OnEnter = constructArguments.OnEnter or function() end,
		OnUpdate = constructArguments.OnUpdate or function() end,
		OnExit = constructArguments.OnExit or function() end,
	} :: State

	return self
end

return {
	Fsm = Fsm,
	State = State,
}
