--//TODO: Fire Entity signals for every entity when machine specific methods are called
--//TODO: Add InitialState param to ActivateMachine,
--//TODO: Add InState param to ResumeMachine,
--//TODO: Add InState param to ResumeMachine,
--//TODO: Sort the signal dependency elephant in the room...

--!strict
--[=[
	@class StateMachine
	the state machine library
]=]
local Signal = require(script.Signal)

type StateName = string
type Signal = typeof(Signal.new())
type LookupTable<k> = { [k]: true }
type Map<k, v> = { [k]: v }
type Dictionary<T> = { [string]: T }

--[=[
	@interface StateMachine 
	@within StateMachine
	
	A state machine class that allows a collection of entities change their states
	based on certain conditions & events.

	.IsRunning          : boolean,
	.InitialState       : State,
	.ActiveEntities     : LookupTable<Entity>,
	.UpdateableEntities : LookupTable<Entity>,
	.RegisteredEntities : Map<Entity, State>,
	.RegisteredStates   {[string]: State},
	.EntityActivated    : Signal,
	.EntityDeactivated  : Signal,
	.EntityResumed      : Signal,
	.EntityPaused       : Signal,
	.EntityRegistered   : Signal,
	.EntityUnregistered : Signal,
	.EntityChangedState : Signal,
	.MachineActivated   : Signal,
	.MachineDeactivated : Signal,
	.MachineResumed     : Signal,
	.MachinePaused      : Signal,

	:::danger

	All these properties should be considered read only!

	:::
]=]





--[=[
	@prop IsRunning boolean
	@within StateMachine
	@readonly

	Flag to determine whether the machine is active or inactive. 
]=]


--[=[
	@interface State
	@within StateMachine
	represents a specific mode of an entity within the state machine.

	.Name: string,
	.OnUpdate : (entity: Entity, fsm: FSM, dt: number) -> nil,
	.OnExit   : (entity: Entity, fsm: FSM) -> nil,
	.Entities : LookupTable<Entity>,

	:::danger
	
	`Entities` is read only

	:::
]=]

--[=[
	@type Entity any
	@within StateMachine
	Literally anything, no for real State Machine objects can register anything as an entity
	but for obvious reasons only things that can be passed by reference would actually
	work
]=]

--[=[
	@type LookupTable {[any]: true}
	@within StateMachine

]=]

--[=[
	@type Map<K, V> {[K]: V}
	@within StateMachine
]=]


-- stylua: ignore start
export type StateMachine = {
	--* properties`
	IsRunning          : boolean,
	InitialState       : State,
	ActiveEntities     : LookupTable<Entity>,
	UpdateableEntities : LookupTable<Entity>,
	RegisteredEntities : Map<Entity, State>,
	RegisteredStates   : {[string]: State},

	--* signals
	EntityActivated    : Signal,
	EntityDeactivated  : Signal,
	EntityResumed      : Signal,
	EntityPaused       : Signal,
	EntityRegistered   : Signal,
	EntityUnregistered : Signal,
	EntityChangedState : Signal,
	
	MachineActivated   : Signal,
	MachineDeactivated : Signal,
	MachineResumed     : Signal,
	MachinePaused      : Signal,

	--* Methods
	RegisterEntity    : (self: StateMachine, entity: Entity, initialState: State) -> nil,
	UnRegisterEntity  : (self: StateMachine, entity: Entity) -> nil,
	ActivateEntity    : (self: StateMachine, entity: Entity, inState: State) -> nil,
	DeactivateEntity  : (self: StateMachine, entity: Entity) -> nil,
	ResumeEntity      : (self: StateMachine, entity: Entity, inState: State) -> nil,
	PauseEntity       : (self: StateMachine, entity: Entity) -> nil,
	
	ActivateMachine   : (self: StateMachine) -> nil,
	DeactivateMachine : (self: StateMachine) -> nil,
	PauseMachine      : (self: StateMachine) -> nil,
	ResumeMachine     : (self: StateMachine) -> nil,
	Update            : (self: StateMachine, dt: number) -> nil,
	ChangeState       : (self: StateMachine, entity: Entity, newState: State, ...any) -> nil,
}


export type State = {
	Name: string,
	OnEnter  : (entity: Entity, stateMachine: StateMachine) -> nil,
	OnUpdate : (entity: Entity, stateMachine: StateMachine, dt: number) -> nil,
	OnExit   : (entity: Entity, stateMachine: StateMachine) -> nil,
	Entities : LookupTable<Entity>,
}
-- stylua: ignore end

type Entity = any

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
-- !== Sorbet
-- !== ================================================================================||>

local Sorbet = {}

--==/ Registering/Unregistering from FSM ===============================||>

--[=[
	@method RegisterEntity
	@within StateMachine
	@param entity Entity -- The entity to register in the state machine.
	@param initialState State --  Optional. The initial state for the entity. If not provided, the FSM's initial state is used.

	Registers an entity in the state machine with an optional initial state.
	If the entity is already registered, a warning is displayed.
	If no initial state is provided, the state machine's initial state is used.
]=]
Sorbet.RegisterEntity = function(stateMachine: StateMachine, entity: Entity, initialState: State?): nil
	if stateMachine.RegisteredEntities[entity] then
		warn(entity, "is already registered in the state machine")
	else
		stateMachine.RegisteredEntities[entity] = if initialState then initialState else stateMachine.InitialState
		stateMachine.RegisteredEntities[entity].Entities[entity] = true
	end
	return nil
end

--[=[
	@method UnregisterEntity
	@within StateMachine
	@param entity Entity -- The entity to unregister from the state machine.

	Unregisters an entity from the state machine.
	Removes the entity entirely from the state machine & the state it was in. 
	If the entity is not registered in the state machine, no action is taken.
]=]
Sorbet.UnregisterEntity = function(stateMachine: StateMachine, entity: Entity): nil
	--# Yeet the entity from the state machine entirely
	stateMachine.UpdateableEntities[entity] = nil
	stateMachine.RegisteredEntities[entity].Entities[entity] = nil
	stateMachine.ActiveEntities[entity] = nil
	stateMachine.RegisteredEntities[entity] = nil
	return nil
end

--==/ Activate/Deactivate Entity ===============================||>

--[=[
	@method ActivateEntity
	@within StateMachine
	@param entity Entity -- The entity to activate in the state machine.
	@param inState State -- Optional. The state to activate the entity in. If not provided, the entity is activated in its original registered state.

	Activates an entity If the entity is already active, OR not in the state machine
	a warning  is displayed. If no state to be activated in is provided, the entity is 
	activated in the state it was de-activated from (yes, the machine spirit remembers.)

	When the entity is activated, the corresponding state's OnEnter function is called.

	:::tip
	use the optional `inState` param in cases where you want to call an specific state `OnEnter` callback 
	:::
]=]
Sorbet.ActivateEntity = function(stateMachine: StateMachine, entity: Entity, inState: State?): nil
	local entityState = stateMachine.RegisteredEntities[entity]
	local entityIsActive = stateMachine.ActiveEntities[entity]

	if entityState then
		if entityIsActive then
			warn(entity, "is already active")
		else
			--stylua: ignore start
			--# activate the entity in passed state, else activate it in the
			--# state it was originally registered in. Also removing it from the
			--# State Entities collection prevents an if statement mess, so just
			--# remove from state and insert to new one regardless if it changed.
			stateMachine.RegisteredEntities[entity].Entities[entity] = nil
			stateMachine.RegisteredEntities[entity] = if inState then inState else stateMachine.RegisteredEntities[entity]
			stateMachine.RegisteredEntities[entity].Entities[entity] = true

			stateMachine.ActiveEntities[entity] = true
			stateMachine.RegisteredEntities[entity].OnEnter(entity, stateMachine)
			stateMachine.UpdateableEntities[entity] = true

			stateMachine.EntityActivated:Fire(entity)
			--stylua: ignore end
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--[=[
	@method DeactivateEntity
	@within StateMachine
	@param entity Entity -- The entity to deactivate in the state machine.
	@param inState State -- Optional. The state to deactivate the entity in. If not provided, the entity will be deactivated in its original registered state.

	Deactivates an entity in the state machine. If the entity is already inactive, a warning is displayed.
	If a specific state is provided, the entity will be deactivated in that state. Otherwise, the entity will be deactivated in its original registered state.
	When the entity is deactivated, the corresponding state's OnExit function is called.

	:::tip
	use the optional `inState` param in cases where you want to call an specific state `OnExit`
	:::

]=]
Sorbet.DeactivateEntity = function(stateMachine: StateMachine, entity: Entity, inState: State?): nil
	local entityState = stateMachine.RegisteredEntities[entity]
	local entityIsActive = stateMachine.ActiveEntities[entity]
	if entityState then
		if not entityIsActive then
			warn(entity, "is already inactive")
		else
			--# Deactivate the entity in passed state, else deactivate it in the
			--# state it was originally registered in. Also removing it from the
			--# State Entities collection prevents an if statement mess, so just
			--# remove from state and insert to new one regardless if it changed.
			stateMachine.RegisteredEntities[entity].Entities[entity] = nil
			stateMachine.RegisteredEntities[entity] = if inState
				then inState
				else stateMachine.RegisteredEntities[entity]
			stateMachine.RegisteredEntities[entity].Entities[entity] = true

			stateMachine.ActiveEntities[entity] = nil
			stateMachine.UpdateableEntities[entity] = nil
			stateMachine.RegisteredEntities[entity].OnExit(entity, stateMachine)

			stateMachine.EntityDeactivated:Fire(entity)
		end
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--==/ Pause/Resume Entity ===============================||>
--[=[
	@method PauseEntity
	@within StateMachine
	@param entity Entity -- The entity to pause in the state machine.
	Pauses an entity in the state machine. If the entity is not registered, a warning is displayed.
	When the entity is paused, it is removed from the list of active and updateable entities. which
	prevents their current state `OnUpdate` callback from being called


	:::danger
	As of time of writing, this WON'T prevent the entity from changing state nor 
	`OnEnter` or `OnExit` callbacks from being called!
	:::
]=]
Sorbet.PauseEntity = function(stateMachine: StateMachine, entity: Entity)
	local entityState = stateMachine.RegisteredEntities[entity]
	if entityState then
		stateMachine.ActiveEntities[entity] = nil
		stateMachine.UpdateableEntities[entity] = nil

		stateMachine.EntityPaused:Fire(entity)
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--[=[
	@method ResumeEntity
	@within StateMachine
	@param entity Entity -- The entity to resume in the state machine.

	Resumes a paused entity in the state machine. If the entity is not registered, a warning is displayed.
	When the entity is resumed, it is added back to the list of active and updateable entities.
]=]
Sorbet.ResumeEntity = function(stateMachine: StateMachine, entity: Entity)
	local entityState = stateMachine.RegisteredEntities[entity]
	if entityState then
		stateMachine.ActiveEntities[entity] = true
		stateMachine.UpdateableEntities[entity] = true

		stateMachine.EntityResumed:Fire()
	else
		warn(entity, "is not registered in the state machine")
	end

	return nil
end

--==/ Activate/Deactivate State Machine ===============================||>

Sorbet.ActivateMachine = function(stateMachine: StateMachine): nil
	if stateMachine.IsRunning then
		warn "The state machine is already running"
		return
	end

	for entity in stateMachine.RegisteredEntities do
		Sorbet.ActivateEntity(stateMachine, entity) --> activate will make them active
	end

	stateMachine.IsRunning = true
	stateMachine.MachineActivated:Fire()
	return nil
end

Sorbet.DeactivateMachine = function(stateMachine: StateMachine): nil
	if not stateMachine.IsRunning then
		warn "The state machine is already NOT running"
		return
	end

	--# matters to put it here, prevents any further state updates & state
	--# changes
	stateMachine.IsRunning = false

	--# allow for any current state transition to complete
	task.defer(function()
		--# Cheeky set operation to just get the active entities, instead of
		--# iterating the entire entities list, it does hurt perf if there are
		--# few entities thooo > - >
		local activeRegisteredEntities =
			GetSetIntersection(stateMachine.RegisteredEntities, stateMachine.ActiveEntities)
		for entity in activeRegisteredEntities do
			stateMachine.UpdateableEntities[entity] = nil
		end
	end)

	stateMachine.MachineDeactivated:Fire()
	return nil
end

--==/ Pause/Resume State Machine ===============================||>

Sorbet.PauseMachine = function(stateMachine: StateMachine)
	if not stateMachine.IsRunning then
		warn "The state machine is already NOT running"
		return
	end

	--# matters to put it here, prevents any further state updates & state
	--# changes
	stateMachine.IsRunning = false

	--# allow for any current state transition to complete
	task.defer(function()
		for entity in stateMachine.UpdateableEntities do
			stateMachine.UpdateableEntities[entity] = nil
		end
	end)

	stateMachine.MachinePaused:Fire()
end

Sorbet.ResumeMachine = function(stateMachine: StateMachine)
	--# insert active entities to updateable before allowing the machine to run
	for entity in stateMachine.ActiveEntities do
		stateMachine.UpdateableEntities[entity] = true
	end

	stateMachine.IsRunning = true
	stateMachine.MachineResumed:Fire()
end

--==/ Change state & update entities ===============================||>

--[=[
	@method Update
	@within StateMachine
	@param dt number? -- Optional. The time elapsed since the last update.

	Updates the state machine by invoking the "OnUpdate" method of all updateable 
	entities. If the state machine is paused (not running), the update process is 
	skipped. Each updateable entity's "OnUpdate" method is called, passing the 
	entity, state machine, and the time elapsed since the last update (if provided).
]=]
Sorbet.Update = function(stateMachine: StateMachine, dt: number?): nil
	for entity in stateMachine.UpdateableEntities do
		--# avoid doing unnecessary iterations if paused
		if stateMachine.IsRunning then
			stateMachine.RegisteredEntities[entity].OnUpdate(entity, stateMachine, dt :: number)
		else
			break
		end
	end

	return nil
end

--[=[
	@method ChangeState
	@within StateMachine
	@param entity Entity -- The entity to change state.
	@param newState State -- The new state to assign to the entity.

	Changes the state of an entity in the state machine to the specified new state.
	If the new state is not registered in the state machine, a warning is displayed 
	and the state change is not performed. The entity's current state is exited, and 
	the new state is entered. The entity is removed from the updateable entities table 
	during the state transition to prevent unexpected behavior.

]=]
Sorbet.ChangeState = function(stateMachine: StateMachine, entity: Entity, newState: State): nil
	if not stateMachine.IsRunning then
		return nil
	end

	if newState then
		if not stateMachine.RegisteredStates[newState.Name] then
			warn(newState.Name, "is not registered in the state machine")
			return nil
		end

		local oldState = stateMachine.RegisteredEntities[entity]

		--# In case the entity is not active, just make it active right away.
		stateMachine.ActiveEntities[entity] = true

		--# Yeet out entity from updateable table while changing state which
		--# prevents un-expected behavior
		stateMachine.UpdateableEntities[entity] = nil
		stateMachine.RegisteredEntities[entity].Entities[entity] = nil
		stateMachine.RegisteredEntities[entity].OnExit(entity, stateMachine)

		stateMachine.RegisteredEntities[entity] = newState

		stateMachine.UpdateableEntities[entity] = true --> make it updateable again
		stateMachine.RegisteredEntities[entity].Entities[entity] = true
		stateMachine.RegisteredEntities[entity].OnEnter(entity, stateMachine)

		stateMachine.EntityChangedState:Fire(entity, newState, oldState)
	else
		warn(entity, "cannot change state, new state is nil!")
	end

	return nil
end

--==/ FSM Constructor ===============================||>
--stylua: ignore start

Sorbet.FSM = function(initialState: State, states: { State }, entities: { Entity }?): StateMachine
	entities = entities or {}
	assert(type(entities) == "table", "entities must be of type table!")
	assert(type(states) == "table", "states must be of type table!")

	local self = {
		IsRunning          = true,
		ActiveEntities     = {} :: { [Entity]: true },
		UpdateableEntities = {},
		RegisteredEntities = {},
		RegisteredStates   = {} :: {[string]: State},
		InitialState       = initialState,
	
		EntityActivated    = Signal.new(),
		EntityDeactivated  = Signal.new(),
		EntityResumed      = Signal.new(),
		EntityPaused       = Signal.new(),
		EntityRegistered   = Signal.new(),
		EntityUnregistered = Signal.new(),
		EntityChangedState = Signal.new(),

		MachineActivated   = Signal.new(),
		MachineDeactivated = Signal.new(),
		MachineResumed     = Signal.new(),
		MachinePaused      = Signal.new(),

		--# No reason to use a metatable, so refs it is
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
	} :: StateMachine


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
type Callback = (entity: Entity, fsm: StateMachine) -> nil
type Update = (entity: Entity, fsm: StateMachine, dt: number) -> nil

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
