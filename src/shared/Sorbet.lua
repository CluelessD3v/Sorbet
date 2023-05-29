--!strict
local Packages = game.ReplicatedStorage.Packages
local Signal = require(Packages.signal)

type Entity = any
type StateName = string

type FSM = {
	InitialState: State,
	ActiveEntities: { [Entity]: true },
	InactiveEntities: { [Entity]: true },
	RegisteredEntities: { [Entity]: State },
	RegisteredStates: { [StateName]: State },
}

export type State = {
	Name: string,
	OnEnter: (entity: Entity, fsm: FSM) -> nil,
	OnUpdate: (entity: Entity, fsm: FSM, dt: number) -> nil,
	OnExit: (entity: Entity, fsm: FSM) -> nil,
}

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

-- local function GetSetDifference(set1: Set, set2: Set): Set
-- 	local result: Set = {}
-- 	for k in pairs(set1) do
-- 		if not set2[k] then
-- 			result[k] = true
-- 		end
-- 	end
-- 	return result
-- end

local Sorbet = {}

local Fsm = {}
Fsm.new = function(initialState: State, states: { State }?): FSM
	local self = {} :: FSM

	self.ActiveEntities = {}
	self.InactiveEntities = {}
	self.RegisteredEntities = {}
	self.RegisteredStates = {} :: { [StateName]: State }
	self.InitialState = initialState

	states = states or {}

	for _, state in states :: { State } do
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
	if not fsm.RegisteredEntities[entity] then
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
		Fsm.ActivateEntity(fsm, entity)
	end

	return nil
end

Fsm.TurnOff = function(fsm: FSM): nil
	--# Gets all entities in both the registered & active table same deal as
	--# Turn on it hurts performance if there are not many entities.
	local activeRegisteredEntities = GetSetIntersection(fsm.RegisteredEntities, fsm.ActiveEntities)
	for entity in activeRegisteredEntities do
		Fsm.DeactivateEntity(fsm, entity)
	end

	return nil
end

--==/ Change state & update entities ===============================||>
Fsm.Update = function(fsm: FSM, dt: number?): nil
	for entity in fsm.ActiveEntities do
		fsm.RegisteredEntities[entity].OnUpdate(entity, fsm, dt :: number)
	end

	return nil
end

Fsm.ChangeState = function(fsm: FSM, entity: Entity, newState: State): nil
	if not fsm.RegisteredStates[newState.Name] then
		warn(newState.Name, "is not registered in the state machine")
		return nil
	end

	fsm.RegisteredEntities[entity].OnExit(entity, fsm)
	fsm.RegisteredEntities[entity] = newState
	fsm.RegisteredEntities[entity].OnEnter(entity, fsm)
	return nil
end

Sorbet.Fsm = Fsm

-- !== ================================================================================||>
-- !== State
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

Sorbet.State = State

return Sorbet
