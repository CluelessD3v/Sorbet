--//TODO: Fire Entity signals for every entity when machine specific methods are called
--//TODO: Add InitialState param to ActivateMachine,
--//TODO: Add InState param to ResumeMachine,
--//TODO: Add InState param to ResumeMachine,

--!strict
local ReplicatedStorage = game:GetService "ReplicatedStorage"
local Packages = game.ReplicatedStorage.Packages
local signal = require(ReplicatedStorage.Packages.signal)
local Signal = require(script.Signal)

type Entity = any
type StateName = string

-- stylua: ignore start
export type FSM = {
	--* properties`
	IsRunning          : boolean,
	InitialState       : State,
	ActiveEntities     : { [Entity]: true },
	UpdateableEntities : { [Entity]: true },
	RegisteredEntities : { [Entity]: State },
	RegisteredStates   : { [StateName]: State },

	--* signals
	EntityActivated    : typeof(signal.new()),
	EntityDeactivated  : typeof(signal.new()),
	EntityResumed      : typeof(signal.new()),
	EntityPaused       : typeof(signal.new()),
	EntityRegistered   : typeof(signal.new()),
	EntityUnregistered : typeof(signal.new()),
	EntityChangedState : typeof(signal.new()),
	
	MachineActivated   : typeof(signal.new()),
	MachineDeactivated : typeof(signal.new()),
	MachineResumed     : typeof(signal.new()),
	MachinePaused      : typeof(signal.new()),

	--* Methods
	RegisterEntity    : (self: FSM, entity: Entity, initialState: State) -> nil,
	UnRegisterEntity  : (self: FSM, entity: Entity) -> nil,
	ActivateEntity    : (self: FSM, entity: Entity, inState: State) -> nil,
	DeactivateEntity  : (self: FSM, entity: Entity) -> nil,
	ResumeEntity      : (self: FSM, entity: Entity, inState: State) -> nil,
	PauseEntity       : (self: FSM, entity: Entity) -> nil,
	
	ActivateMachine   : (self: FSM) -> nil,
	DeactivateMachine : (self: FSM) -> nil,
	PauseMachine      : (self: FSM) -> nil,
	ResumeMachine     : (self: FSM) -> nil,
	Update            : (self: FSM, dt: number) -> nil,
	ChangeState       : (self: FSM, entity: Entity, newState: State, ...any) -> nil,
}

export type State = {
	Name: string,
	OnEnter  : (entity: Entity, fsm: FSM) -> nil,
	OnUpdate : (entity: Entity, fsm: FSM, dt: number) -> nil,
	OnExit   : (entity: Entity, fsm: FSM) -> nil,
	Entities : { [Entity]: true },
}
-- stylua: ignore end

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

local Sorbet = {}

--==/ Registering/Unregistering from FSM ===============================||>

Sorbet.RegisterEntity = function(fsm: FSM, entity: Entity, initialState: State?): nil
	if fsm.RegisteredEntities[entity] then
		warn(entity, "is already registered in the state machine")
	else
		fsm.RegisteredEntities[entity] = if initialState then initialState else fsm.InitialState
		fsm.RegisteredEntities[entity].Entities[entity] = true
	end
	return nil
end

Sorbet.UnregisterEntity = function(fsm: FSM, entity: Entity): nil
	--# Yeet the entity from the state machine entirely
	fsm.UpdateableEntities[entity] = nil
	fsm.RegisteredEntities[entity].Entities[entity] = nil
	fsm.ActiveEntities[entity] = nil
	fsm.RegisteredEntities[entity] = nil
	return nil
end

--==/ Activate/Deactivate Entity ===============================||>

Sorbet.ActivateEntity = function(fsm: FSM, entity: Entity, inState: State?): nil
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
			fsm.RegisteredEntities[entity] = if inState then inState else fsm.RegisteredEntities[entity]
			fsm.RegisteredEntities[entity].Entities[entity] = true

			fsm.ActiveEntities[entity] = true
			fsm.RegisteredEntities[entity].OnEnter(entity, fsm)
			fsm.UpdateableEntities[entity] = true

			fsm.EntityActivated:Fire(entity)
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

Sorbet.DeactivateEntity = function(fsm: FSM, entity: Entity, inState: State?): nil
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
			fsm.RegisteredEntities[entity] = if inState then inState else fsm.RegisteredEntities[entity]
			fsm.RegisteredEntities[entity].Entities[entity] = true

			fsm.ActiveEntities[entity] = nil
			fsm.UpdateableEntities[entity] = nil
			fsm.RegisteredEntities[entity].OnExit(entity, fsm)

			fsm.EntityDeactivated:Fire(entity)
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--==/ Pause/Resume Entity ===============================||>

Sorbet.PauseEntity = function(fsm: FSM, entity: Entity)
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

Sorbet.ResumeEntity = function(fsm: FSM, entity: Entity)
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

Sorbet.ActivateMachine = function(fsm: FSM): nil
	if fsm.IsRunning then
		warn "The state machine is already running"
		return
	end

	for entity in fsm.RegisteredEntities do
		Sorbet.ActivateEntity(fsm, entity) --> activate will make them active
	end

	fsm.IsRunning = true
	fsm.MachineActivated:Fire()
	return nil
end

Sorbet.DeactivateMachine = function(fsm: FSM): nil
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

Sorbet.PauseMachine = function(fsm: FSM)
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

Sorbet.ResumeMachine = function(fsm: FSM)
	--# insert active entities to updateable before allowing the machine to run
	for entity in fsm.ActiveEntities do
		fsm.UpdateableEntities[entity] = true
	end

	fsm.IsRunning = true
	fsm.MachineResumed:Fire()
end

--==/ Change state & update entities ===============================||>

Sorbet.Update = function(fsm: FSM, dt: number?): nil
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

Sorbet.ChangeState = function(fsm: FSM, entity: Entity, newState: State): nil
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

--==/ FSM Constructor ===============================||>
--stylua: ignore start

Sorbet.FSM = function(initialState: State, states: { State }, entities: { Entity }?): FSM
	entities = entities or {}
	assert(type(entities) == "table", "entities must be of type table!")
	assert(type(states) == "table", "states must be of type table!")

	local self = {
		IsRunning          = true,
		ActiveEntities     = {} :: { [Entity]: true },
		UpdateableEntities = {},
		RegisteredEntities = {},
		RegisteredStates   = {} :: { [StateName]: State },
		InitialState       = initialState,
	
		EntityActivated    = signal.new(),
		EntityDeactivated  = signal.new(),
		EntityResumed      = signal.new(),
		EntityPaused       = signal.new(),
		EntityRegistered   = signal.new(),
		EntityUnregistered = signal.new(),
		EntityChangedState = signal.new(),

		MachineActivated   = signal.new(),
		MachineDeactivated = signal.new(),
		MachineResumed     = signal.new(),
		MachinePaused      = signal.new(),

		RegisterEntity     = Sorbet.RegisterEntity,
		UnRegisterEntity   = Sorbet.UnregisterEntity,
		ActivateEntity     = Sorbet.ActivateEntity,
		DeactivateEntity   = Sorbet.DeactivateEntity,
		ResumeEntity       = Sorbet.ResumeEntity,
		PauseEntity        = Sorbet.PauseEntity,

		ActivateMachine    = Sorbet.ActivateMachine,
		DeactivateMachine  = Sorbet.DeactivateMachine,
		ResumeMachine      = Sorbet.ResumeMachine,
		PauseMachine       = Sorbet.PauseMachine,
		Update             = Sorbet.Update,
		ChangeState        = Sorbet.ChangeState,
	} :: FSM

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
--stylua: ignore end

--==/ State Constructor ===============================||>
type Callback = (entity: Entity, fsm: FSM) -> nil
type Update = (entity: Entity, fsm: FSM, dt: number) -> nil

--stylua: ignore start
Sorbet.State = function(constructArguments: {
	Name     : string,
	OnEnter  : Callback?,
	OnUpdate : Update?,
	OnExit   : Callback?,
}): State

	assert(constructArguments.Name ~= nil and type(constructArguments.Name) == "string", "You must give the state a name!")

	local self = {
		Name     = constructArguments.Name,
		OnEnter  = constructArguments.OnEnter or function() end,
		OnUpdate = constructArguments.OnUpdate or function() end,
		OnExit   = constructArguments.OnExit or function() end,
		Entities = {},
	} :: State

	return self
end
--stylua: ignore end

return Sorbet
