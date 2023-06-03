--!strict
local ReplicatedStorage = game:GetService "ReplicatedStorage"
local Packages = game.ReplicatedStorage.Packages
local signal = require(ReplicatedStorage.Packages.signal)
local Signal = require(script.Signal)

type Entity = any
type StateName = string

export type FSM = {
	--* properties
	IsRunning: boolean,
	InitialState: State,
	ActiveEntities: { [Entity]: true },
	UpdateableEntities: { [Entity]: true },

	--* signals
	RegisteredEntities: { [Entity]: State },
	RegisteredStates: { [StateName]: State },
	EntityActivated: typeof(signal.new()),
	EntityDeactivated: typeof(signal.new()),
	EntityResumed: typeof(signal.new()),
	EntityPaused: typeof(signal.new()),
	EntityRegistered: typeof(signal.new()),
	EntityUnregistered: typeof(signal.new()),
	EntityChangedState: typeof(signal.new()),
	MachineActivated: typeof(signal.new()),
	MachineDeactivated: typeof(signal.new()),
	MachineResumed: typeof(signal.new()),
	MachinePaused: typeof(signal.new()),
}

type FSMClass = typeof(setmetatable({} :: FSM, {}))

export type State = {
	Name: string,
	OnEnter: (entity: Entity, fsm: FSM) -> nil,
	OnUpdate: (entity: Entity, fsm: FSM, dt: number) -> nil,
	OnExit: (entity: Entity, fsm: FSM) -> nil,
	Entities: { [Entity]: true },
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

	self.IsRunning = true
	self.ActiveEntities = {}
	self.UpdateableEntities = {}

	self.RegisteredEntities = {}
	self.RegisteredStates = {} :: { [StateName]: State }
	self.InitialState = initialState

	self.EntityActivated = signal.new()
	self.EntityDeactivated = signal.new()
	self.EntityResumed = signal.new()
	self.EntityPaused = signal.new()
	self.EntityRegistered = signal.new()
	self.EntityUnregistered = signal.new()
	self.EntityChangedState = signal.new()
	self.MachineActivated = signal.new()
	self.MachineDeactivated = signal.new()
	self.MachineResumed = signal.new()
	self.MachinePaused = signal.new()

	--# Register entities & put them in the initial state
	for _, entity in entities do
		self.RegisteredEntities[entity] = initialState
		initialState.Entities[entity] = true
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
		fsm.RegisteredEntities[entity].Entities[entity] = true
	end
	return nil
end

Fsm.UnregisterEntity = function(fsm: FSM, entity: Entity): nil
	--# Yeet the entity from the state machine entirely
	fsm.UpdateableEntities[entity] = nil
	fsm.RegisteredEntities[entity].Entities[entity] = nil
	fsm.ActiveEntities[entity] = nil
	fsm.RegisteredEntities[entity] = nil
	return nil
end

--==/ Activate/Deactivate Entity ===============================||>

Fsm.ActivateEntity = function(fsm: FSM, entity: Entity, inState: State?): nil
	local entityState = fsm.RegisteredEntities[entity]
	local entityIsActive = fsm.ActiveEntities[entity]

	if entityState then
		if entityIsActive then
			warn(entity, "is already active")
		else
			--# activate the entity in passed state, else activate it in the
			--# state it was originally registered in. Also removing it from the
			--# State Entities collection prevents an if statement mess, so just
			--# remove from state and insert to new one regardless if it changed.
			fsm.RegisteredEntities[entity].Entities[entity] = nil
			entityState = if inState then inState else fsm.RegisteredEntities[entity]
			fsm.RegisteredEntities[entity].Entities[entity] = true

			fsm.ActiveEntities[entity] = true
			entityState.OnEnter(entity, fsm)
			fsm.UpdateableEntities[entity] = true

			fsm.EntityActivated:Fire(entity)
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

Fsm.DeactivateEntity = function(fsm: FSM, entity: Entity, inState: State?): nil
	local entityState = fsm.RegisteredEntities[entity]
	local entityIsActive = fsm.ActiveEntities[entity]
	if entityState then
		if not entityIsActive then
			warn(entity, "is already inactive")
		else
			--# Deactivate the entity in passed state, else deactivate it in the
			--# state it was originally registered in. Also removing it from the
			--# State Entities collection prevents an if statement mess, so just
			--# remove from state and insert to new one regardless if it changed.
			fsm.RegisteredEntities[entity].Entities[entity] = nil
			entityState = if inState then inState else fsm.RegisteredEntities[entity]
			fsm.RegisteredEntities[entity].Entities[entity] = true

			fsm.ActiveEntities[entity] = nil
			fsm.UpdateableEntities[entity] = nil
			entityState.OnExit(entity, fsm)

			fsm.EntityDeactivated:Fire(entity)
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--==/ Pause/Resume Entity ===============================||>
Fsm.PauseEntity = function(fsm: FSM, entity: Entity)
	local entityState = fsm.RegisteredEntities[entity]
	if entityState then
		fsm.ActiveEntities[entity] = nil
		fsm.UpdateableEntities[entity] = nil

		fsm.EntityPaused:Fire(entity)
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

Fsm.ResumeEntity = function(fsm: FSM, entity: Entity)
	local entityState = fsm.RegisteredEntities[entity]
	if entityState then
		fsm.ActiveEntities[entity] = true
		fsm.UpdateableEntities[entity] = true

		fsm.EntityResumed:Fire()
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--==/ Activate/Deactivate State Machine ===============================||>

Fsm.ActivateMachine = function(fsm: FSM): nil
	if fsm.IsRunning then
		warn "The state machine is already running"
		return
	end

	for entity in fsm.RegisteredEntities do
		Fsm.ActivateEntity(fsm, entity) --> activate will make them active
	end

	fsm.IsRunning = true
	fsm.MachineActivated:Fire()
	return nil
end

Fsm.DeactivateMachine = function(fsm: FSM): nil
	if not fsm.IsRunning then
		warn "The state machine is already NOT running"
		return
	end

	--# matters to put it here, prevents any further state updates & state
	--# changes
	fsm.IsRunning = false

	--# allow for any current state transition to complete
	task.defer(function()
		--# Cheeky set operation to just get the active entities, instead of
		--# iterating the entire entities list, it does hurt perf if there are
		--# few entities thooo > - >
		local activeRegisteredEntities = GetSetIntersection(fsm.RegisteredEntities, fsm.ActiveEntities)
		for entity in activeRegisteredEntities do
			fsm.UpdateableEntities[entity] = nil
		end
	end)

	fsm.MachineDeactivated:Fire()
	return nil
end

--==/ Pause/Resume State Machine ===============================||>
Fsm.PauseMachine = function(fsm: FSM)
	if not fsm.IsRunning then
		warn "The state machine is already NOT running"
		return
	end

	--# matters to put it here, prevents any further state updates & state
	--# changes
	fsm.IsRunning = false

	--# allow for any current state transition to complete
	task.defer(function()
		for entity in fsm.UpdateableEntities do
			fsm.UpdateableEntities[entity] = nil
		end
	end)

	fsm.MachinePaused:Fire()
end

Fsm.ResumeMachine = function(fsm: FSM)
	--# insert active entities to updateable before allowing the machine to run
	for entity in fsm.ActiveEntities do
		fsm.UpdateableEntities[entity] = true
	end

	fsm.IsRunning = true
	fsm.MachineResumed:Fire()
end

--==/ Change state & update entities ===============================||>
Fsm.Update = function(fsm: FSM, dt: number?): nil
	for entity in fsm.UpdateableEntities do
		--# avoid doing unnecessary iterations if paused
		if fsm.IsRunning then
			fsm.RegisteredEntities[entity].OnUpdate(entity, fsm, dt :: number)
		else
			break
		end
	end

	return nil
end

Fsm.ChangeState = function(fsm: FSM, entity: Entity, newState: State): nil
	if not fsm.IsRunning then
		return nil
	end

	if newState then
		if not fsm.RegisteredStates[newState.Name] then
			warn(newState.Name, "is not registered in the state machine")
			return nil
		end

		local oldState = fsm.RegisteredEntities[entity]

		--# In case the entity is not active, just make it active right away.
		fsm.ActiveEntities[entity] = true

		--# Yeet out entity from updateable table while changing state which
		--# prevents un-expected behavior
		fsm.UpdateableEntities[entity] = nil
		fsm.RegisteredEntities[entity].Entities[entity] = nil
		fsm.RegisteredEntities[entity].OnExit(entity, fsm)

		fsm.RegisteredEntities[entity] = newState

		fsm.UpdateableEntities[entity] = true --> make it updateable again
		fsm.RegisteredEntities[entity].Entities[entity] = true
		fsm.RegisteredEntities[entity].OnEnter(entity, fsm)

		fsm.EntityChangedState:Fire(entity, newState, oldState)
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
		Entities = {},
	} :: State

	return self
end

return {
	Fsm = Fsm,
	State = State,
}
