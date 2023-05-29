local signal = require(game:GetService("ReplicatedStorage").Packages.signal) or require(script.Parent.signal)

--[=[
    @class Sorbet
    Status is the package itself, it contains both State and FSM.
]=]
type Sorbet = {
	State: {
		new: () -> State,
	},

	FSM: {
		new: () -> FSM,
	},
}

--[=[
    @type Entity any 
    @within Status

    An entity is a unique identifier used to create an entity, state pair. It is created when the through the Register/RegisterAndActivateEntity
    functions.

    An entity can be accessed using the GetEntities Getter
]=]
export type Entity = any

--[=[
    @interface FSM 
    @within Status

    Finite state machine interface

    .InitialState State -- Default state entities are registered/activated in
    .RegisteredEntities {[Entity]:State} -- Map of entity - state pairs
    .RegisteredStates {[string]: State} -- Dictionary of registered states in the state machine
    .Collections {[State]:{[Entity]: true}} -- Map state - Look up table pairs, the look up tables contains all the instances in their associated state key. 
    .ActiveEntities {[Entity]: true} -- Look up table of all active entities in the state machine
    .InactiveEntities {[Entity]: true} -- Look up table of all inactive entities in the state machine
    .PrintStateChange boolean -- debug function to print state transitions
]=]
export type FSM = {
	-- Properties
	InitialState: State,
	RegisteredStates: { [string]: State },
	InactiveEntities: { [Entity]: true },
	ActiveEntities: { [Entity]: true },

	-- _RegisteredEntitiesState : {[Entity]:State},
	-- _StateToEntityCollection : {[State]:{[Entity]: true}},
	-- _PrintStateChange        : boolean,

	EntityStateChanged: typeof(signal.new()),
	EntityRegistered: typeof(signal.new()),
	EntityUnregistered: typeof(signal.new()),
	EntityActivated: typeof(signal.new()),
	EntityDeactivated: typeof(signal.new()),
}

type LifeCycleFunction = (entity: Entity, fsm: FSM) -> nil

export type State = {
	Name: string,

	--> Callbacks
	OnEnter: LifeCycleFunction?,
	OnUpdate: LifeCycleFunction?,
	OnExit: LifeCycleFunction?,
}

function GetSetIntersection(set1, set2)
	local result = {}
	for k in pairs(set1) do
		if set2[k] then
			result[k] = true
		end
	end
	return result
end

function GetSetDifference(set1, set2)
	local result = {}
	for element in pairs(set1) do
		if not set2[element] then
			result[element] = true
		end
	end
	return result
end

-- !== ================================================================================||>
-- !==                                      FSM
-- !== ================================================================================||>

--[=[
    @class FSM
]=]
local finiteStateMachine = {}
finiteStateMachine.__index = finiteStateMachine

function finiteStateMachine.new(initialState: State, statesList: { State }): FSM
	statesList = if statesList and type(statesList) == "table" then statesList else {}

	local self = setmetatable({}, finiteStateMachine) :: FSM
	self.InitialState = initialState

	self.RegisteredStates = {}
	self._RegisteredEntitiesState = {}
	self.ActiveEntities = {}
	self.InactiveEntities = {}
	self._StateToEntityCollection = {}

	self.EntityActivated = signal.new()
	self.EntityDeactivated = signal.new()
	self.EntityRegistered = signal.new()
	self.EntityUnregistered = signal.new()
	self.EntityStateChanged = signal.new()

	for _, state in statesList do
		self._StateToEntityCollection[state] = {}
		self.RegisteredStates[state.Name] = state
	end

	--# in case the initial state was not registered
	if not self:GetState(initialState.Name) then
		self.RegisteredStates[initialState.Name] = initialState
	end

	self._PrintStateChange = false
	return self
end

--[=[
    @within FSM
    @param entity Entity -- The entity to be registered
    @param initialState State? -- (Optional) The initial state to assign to the entity. Defaults to the FSM's default initial state.

    The entity will be added to the FSM's list of registered entities but will not immediately transition to the initial state. 
    Instead, it will be inactive until explicitly activated by calling the 'ActivateEntity' method. If the initial state is not 
    registered in the FSM, an error will be thrown.
    
]=]
function finiteStateMachine:RegisterEntity(entity: Entity, initialState: State?): nil
	self = self :: FSM
	initialState = initialState or self.InitialState

	if self.RegisteredStates[initialState.Name] then
		self._RegisteredEntitiesState[entity] = initialState
		self.EntityRegistered:Fire(entity, initialState)
	else
		error(initialState.Name .. " is not registered in the state machine! ")
	end
end

--[=[
    @within FSM
    @param entity Entity -- The entity to be unregistered

    The entity will be completely removed from the FSM, and its current state's 'Exit' method will not be called.
    If the entity is not currently registered in the FSM, a warning message will be displayed.

]=]
function finiteStateMachine:UnRegisterEntity(entity: Entity): nil
	if self._RegisteredEntitiesState[entity] then
		local state = self._RegisteredEntitiesState[entity]
		self._StateToEntityCollection[state][entity] = nil
		self.ActiveEntities[entity] = nil
		self._RegisteredEntitiesState[entity] = nil
		self.EntityUnregistered:Fire(entity)
	else
		warn(entity, "is not registered in the machine!")
	end
end

--[=[
    @within FSM
    @param entity Entity -- The entity to be Activated
    @param initialState State? -- (optional) The state the entity should be activated in

    Activates the given entity by inserting it into the FSM's ActiveEntities table, which allows it to be updated.
    If the optional initial state argument is passed, then the entity will enter that state. Otherwise, it will enter the 
    state it was originally registered in. 
]=]
function finiteStateMachine:ActivateEntity(entity: Entity, initialState: State?): nil
	if not self._RegisteredEntitiesState[entity] then
		warn(entity, "is not registered in the state machine!")
		return
	end

	if initialState then
		if self.RegisteredStates[initialState.Name] then
			self._RegisteredEntitiesState[entity] = initialState
			self._RegisteredEntitiesState[entity]:Enter(entity, self)
			self.EntityActivated:Fire(entity, initialState)
		else
			warn(
				initialState.Name,
				"is not registered in the state machine, entering entity's registered state instead."
			)
		end
	end

	--# the entity is guaranteed to be registered in the state machine at this point
	--# so enter the given initial state or if non is passed enter whatever state it
	--# is paired with
	if not initialState then
		self._RegisteredEntitiesState[entity]:Enter(entity, self)
	end

	self.ActiveEntities[entity] = true
	self.EntityActivated:Fire(entity, self:GetEntityCurrentState(entity))
end

--[=[
    @within FSM
    @param entity Entity -- The entity to be deactivated

    Removes the entity from the FSM's ActiveEntities table, which prevents it from being updated. 
    The entity's current state's Exit function will be called, and it will be added to the FSM's Inactive table.
]=]
function finiteStateMachine:DeactivateEntity(entity): nil
	if self._RegisteredEntitiesState[entity] and self.ActiveEntities[entity] then
		self._RegisteredEntitiesState[entity]:Exit(entity, self)
		self.ActiveEntities[entity] = nil
		self.InactiveEntities[entity] = true
		self.EntityDeactivated:Fire(entity)
	elseif self._RegisteredEntitiesState[entity] and not self.ActiveEntities[entity] then
		warn(entity, "is not active")
	else
		warn(entity, "is not registered in the machine")
	end
end

--[=[
    @within FSM
    @param entity Entity -- The entity to be registered & activated
    @param initialState State? -- The state the entity should be Activated in 


    Registers and activates the given entity in the state machine. If the initial state
    parameter is passed then it will enter that state, else it will enter the FSM inital state
    The entity's Enter method will be called.
]=]
function finiteStateMachine:RegisterAndActivateEntity(entity: Entity, initialState: State): nil
	initialState = initialState or self.InitialState
	self:RegisterEntity(entity, initialState)
	self:ActivateEntity(entity, initialState)
end

--[=[
    @within FSM
    @param entity Entity -- The entity to unregister from the state machine

    Deactivates the given entity and removes it from the state machine.
    The entity's current state Exit method will be called.
]=]
function finiteStateMachine:UnRegisterAndDeactivateEntity(entity: Entity)
	if not self._RegisteredEntitiesState[entity] then
		warn(entity, "is not registered in the machine!")
		return
	end
	self:DeactivateEntity(entity)
	self:UnRegisterEntity(entity)
end

--[=[
    @within FSM
    
    Sets all registered entities in the state machine as Active
]=]
function finiteStateMachine:TurnOn()
	local inactiveRegisteredInstances = GetSetDifference(self._RegisteredEntitiesState, self.ActiveEntities)
	for entity in inactiveRegisteredInstances do
		self:ActivateEntity(entity, nil)
	end
end

--[=[
    @within FSM


    Sets all registered entities in the state machine as Inactive 
]=]
function finiteStateMachine:TurnOff()
	local activeRegisteredEntities = GetSetIntersection(self._RegisteredEntitiesState, self.ActiveEntities)
	for entity in activeRegisteredEntities do
		self:DeactivateEntity(entity)
	end
end

--[=[
    @within FSM
    @param entity Entity -- The entity to change state of.
    @param newState State -- The new state the entity will enter.

    Changes the state of the given entity to the new state. This function exits the entity from
    its current state and enters it into the new state. If the new state is not registered in
    the state machine, the function will warn the user and do nothing. If the 
]=]
function finiteStateMachine:ChangeState(entity: Entity, newState: State): nil
	if not self:GetState(newState.Name) then
		warn(entity, "attempted to change state, but", newState, "is not registered in the state machine!")
		return
	end

	if self._PrintStateChange then
		local currentState = self._RegisteredEntitiesState[entity]
		warn(entity, "Coming from:", currentState.Name, "To:", newState.Name)
	end

	local oldState = self:GetEntityCurrentState(entity)

	self._RegisteredEntitiesState[entity]:Exit(entity, self)
	self._RegisteredEntitiesState[entity] = newState
	self._RegisteredEntitiesState[entity]:Enter(entity, self)

	self.EntityStateChanged:Fire(entity, newState, oldState)
end

--[=[
    @within FSM
    @param dt number -- delta time

    Updates all active entities in the state machine by calling their Update method with the given delta time. Only 
    entities that are both registered and active will be updated.
]=]
function finiteStateMachine:Update(dt: number)
	local activeRegisteredEntities = GetSetIntersection(self._RegisteredEntitiesState, self.ActiveEntities)
	for entity in activeRegisteredEntities do
		self._RegisteredEntitiesState[entity]:Update(entity, self, dt)
	end
end

--[=[
    @within FSM
    @param state string | State -- The name or reference of the state to get the collection of entities from.
    
    Returns a table of entities that are currently registered in the given state. 
    The returned table has the entities as keys and the value true. 
    If the state is not registered in the state machine, a warning is displayed and an empty table 
    is returned.
]=]
function finiteStateMachine:GetEntitiesInState(state: string | State): { Entity: true } | {}
	local stateName = if type(state) == "string" then state else state.Name

	if not stateName then
		warn(stateName, "is not registered in the state machine!")
		return {}
	end

	local collection = self._StateToEntityCollection[stateName]
	return collection
end

--[=[
    @within FSM
    @param entity Entity -- The entity to get the state from.
    Retrieves the current state for the given entity, if it is registered in the state machine. 
    Returns nil the entity is not registered.
]=]
function finiteStateMachine:GetEntityCurrentState(entity: Entity): State | nil
	return self._RegisteredEntitiesState[entity] or warn(entity, "is not registered in the state machine") and nil
end

--[=[
    @within FSM
    @param stateName string -- The name of the state to retrieve.

    Returns the state with the given name, or `nil` if no such state is found in the state machine. 
    Note that the state must be registered in the state machine before it can be retrieved with this function.
]=]
function finiteStateMachine:GetState(stateName: string): State | nil
	local state = self.RegisteredStates[stateName]
	return state or warn(state, "is not registered in the state machine!") and nil
end

-- !== ================================================================================||>
-- !==                                      State
-- !== ================================================================================||>
--[=[
    @interface State
    @within Status

    .Name: string -- state name used as identifier
    .OnEnter (entity: Entity, fsm: FSM, ...any) -> nil?
    .OnUpdate (entity: Entity, fsm: FSM, dt: number, ...any) -> nil?
    .OnExit (entity: Entity, fsm: FSM, ...any) -> nil?

]=]

type stateProperties = {
	Name: string,
	OnEnter: (entity: Entity, fsm: FSM) -> nil,
	OnUpdate: (entity: Entity, fsm: FSM, dt: number) -> nil,
	OnExit: (entity: Entity, fsm: FSM) -> nil,
}

local state = {}
state.__index = state

local stateCount = 0

function state.new(args: State): State
	stateCount += 1

	local self = setmetatable({}, state)
	self.Name = args.Name or "State" .. tostring(stateCount)
	self.OnEnter = args.OnEnter or function() end
	self.OnUpdate = args.OnUpdate or function() end
	self.OnExit = args.OnExit or function() end

	return self
end

--[=[
    @within State
    @param entity Entity -- The entity that is entering the state.
    @param fsm FSM -- The state machine that is operating on this state.

    This function is called when the entity enters this state in the state machine.
]=]
function state:Enter(entity: Entity, fsm: FSM)
	self.OnEnter(entity, fsm)
end

--[=[
    @within State
    @param entity Entity -- The entity that is currently in this state.
    @param fsm FSM -- The state machine that is operating on this state.
    @param dt number -- The delta time since the last frame.

    This function is called every frame while the entity is in this state in the state machine.
]=]
function state:Update(entity: Entity, fsm: FSM, dt: number)
	self.OnUpdate(entity, fsm, dt)
end

--[=[
    @within State
    @param entity Entity -- The entity that is exiting the state.
    @param fsm FSM -- The state machine that is operating on this state.

    This function is called when the entity exits this state in the state machine.
]=]
function state:Exit(entity: Entity, fsm: FSM)
	self.OnExit(entity, fsm)
end

return {
	FSM = finiteStateMachine,
	State = state,
}
