ipc = require 'ipc'
path = require 'path'
objectsRegistry = require './objects_registry.js'

# Convert a real value into a POD structure which carries information of this
# value.
class Meta
  constructor: (process_id, routing_id, value) ->
    @type = typeof value
    @type = 'value' if value is null
    @type = 'array' if Array.isArray value

    if @type is 'array'
      @members = []
      @members.push new Meta(process_id, routing_id, el) for el in value
    else if @type is 'object' or @type is 'function'
      @name = value.constructor.name

      # Reference the original value if it's an object, because when it's
      # passed to renderer we would assume the renderer keeps a reference of
      # it.
      @storeId = objectsRegistry.add process_id, routing_id, value
      @id = value.id

      @members = []
      @members.push { name: prop, type: typeof field } for prop, field of value
    else
      @type = 'value'
      @value = value

ipc.on 'ATOM_INTERNAL_REQUIRE', (event, process_id, routing_id, module) ->
  try
    event.result = new Meta(process_id, routing_id, require(module))
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_CONSTRUCTOR', (event, process_id, routing_id, id, args) ->
  try
    constructor = objectsRegistry.get id
    # Call new with array of arguments.
    # http://stackoverflow.com/questions/1606797/use-of-apply-with-new-operator-is-this-possible
    obj = new (Function::bind.apply(constructor, [null].concat(args)))
    event.result = new Meta(process_id, routing_id, obj)
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_FUNCTION_CALL', (event, process_id, routing_id, id, args) ->
  try
    func = objectsRegistry.get id
    ret = func.apply global, args
    event.result = new Meta(process_id, routing_id, ret)
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_MEMBER_CALL', (event, process_id, routing_id, id, method, args) ->
  try
    obj = objectsRegistry.get id
    ret = obj[method].apply(obj, args)
    event.result = new Meta(process_id, routing_id, ret)
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_MEMBER_SET', (event, process_id, routing_id, id, name, value) ->
  try
    obj = objectsRegistry.get id
    obj[name] = value
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_MEMBER_GET', (event, process_id, routing_id, id, name) ->
  try
    obj = objectsRegistry.get id
    event.result = new Meta(process_id, routing_id, obj[name])
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_REFERENCE', (event, process_id, routing_id, id) ->
  try
    obj = objectsRegistry.get id
    event.result = new Meta(process_id, routing_id, obj)
  catch e
    event.result = type: 'error', value: e.message

ipc.on 'ATOM_INTERNAL_DEREFERENCE', (process_id, routing_id, storeId) ->
  objectsRegistry.remove process_id, routing_id, storeId
