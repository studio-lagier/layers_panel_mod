var script_class = "tool"

# Various controls we want to persist through different parts of the panel
# setup/teardown/refresh lifecycle
var panel = null
var panels_root = null
var tree = null
var root = null
var search_input = null

# Some utils. This isn't a great way of storing these methods, we'll likely
# replace it in the future.
var Utils = null

# Alias for select tool
var select_tool = null

# Throttle our refresh so we're not constantly refreshing on mouse movement
var timeout = 0
var active = false
var dirty = false

# Store a hash of our current tree so we can make better decisions about when
# to refresh it.
var treehash = null

# Store a dict of node_id: TreeItem so we can easily select and deselect individual
# nodes in the tree
var node_dict = {}

# We only initialize things that stay constant through the life of the mod in start
func start():
  Utils = load(Global.Root + "scripts/utils.gd").new()
  select_tool = Global.Editor.Tools["SelectTool"]
  panels_root = Global.Editor.get_node("VPartition/Panels")

  var tool_panel = Global.Editor.Toolset.GetToolPanel("SelectTool")
  var button = tool_panel.CreateButton("Toggle Layers Panel", Global.Root + "icons/question.png")
  tool_panel.Align.move_child(button, 0)
  button.connect("pressed", self, "toggle_panel")

# This does the work of building our tree. It might be expensive, so we try to limit
# calling it until we know the scene has changed.
#
# Force gets set by the search textbox - we always want to rerender when the search
# string has changed, even if the canvas has not.
func refresh_tree(force = false):
    var level = get_current_level()

    # We take a hash of the level's current tree-renderable children and compare it
    # with our last hash. If it's changed, we know we need to rerender.
    var new_treehash = get_tree_hash(level)

    if(force != true and treehash == new_treehash):
      return

    treehash = new_treehash
    print('Refreshed layer tree')

    # We save out the selected nodes so we can maintain a selection when we change
    # layers or node ordering.
    var selected_node_ids = get_selected_node_ids()

    # TODO: We should also select any nodes that are currently selected by the select
    # tool. Ideally we do this separately from the refresh loop so we don't have to rerender
    # the tree just to select some nodes.

    # Clear and recreate our tree. It would be more efficient to calculate a diff
    # in objects and manipulate the tree to reflect the diff, but that's too much
    # work for me to figure out how to do, so we just rebuild it and try to limit
    # how often we rerender.
    tree.clear()

    root = tree.create_item()
    root.set_text(0, "Root")

    # Parent nodes. The heirarchy goes layer -> prefab -> node
    # Currently we display objects before patterns before paths. That might not
    # be the case on the actual canvas though - I'm not sure.
    var layer_parents = {};
    var prefab_parents = {};

    # We have a constant list of layers because custom layers are not currently
    # supported. We create a new parent for each user-editable layer.
    for layer in Utils.layers.keys():
      var user_editable = Utils.layers[layer]
      if !user_editable:
        continue

      var child = tree.create_item(root)
      child.set_text(0, Utils.layer_names[layer] + " (" + String(layer) + ")")
      layer_parents[String(layer)] = child

    # Iterate over all of the selectable objects in the level and append them to the tree.
    # Save out any nodes that we know should be selected from the previous state.
    var selected_nodes = []

    for pattern_data in get_pattern_data(level):
      add_tree_child(layer_parents, prefab_parents, pattern_data, selected_node_ids, selected_nodes)

    for path_data in get_path_data(level):
      add_tree_child(layer_parents, prefab_parents, path_data, selected_node_ids, selected_nodes)

    for object_data in get_object_data(level):
      add_tree_child(layer_parents, prefab_parents, object_data, selected_node_ids, selected_nodes)

    for roof_data in get_roof_data(level):
      add_tree_child(layer_parents, prefab_parents, roof_data, selected_node_ids, selected_nodes)

    for light_data in get_light_data(level):
      add_tree_child(layer_parents, prefab_parents, light_data, selected_node_ids, selected_nodes)

    for portal_data in get_portal_data(level):
      add_tree_child(layer_parents, prefab_parents, portal_data, selected_node_ids, selected_nodes)

    # If we have any nodes that should be selected, select them.
    if selected_nodes.size() > 0:
      for selected_node in selected_nodes:
        selected_node.select()

# Generates a hash for each selectable object in the level. If the hash has changed, we know that
# we need to rerender the tree. Could be more efficient.
func get_tree_hash(level):
  var treehash = ""

  var all_objects = get_object_data(level) + get_pattern_data(level) + get_path_data(level) + get_roof_data(level)

  for object_data in all_objects:
    var layer = String(object_data.z_index)
    var node_id = String(object_data.node_id)
    treehash += "[" + node_id + ":" + layer + "]"

  return treehash

# Actually create a child item from a given node and attach it to the appropriate parent. If the
# node is a part of a prefab, create that and attach it to the tree. Otherwise, attach directly
# to the parent layer.
func add_tree_child(layer_parents, prefab_parents, object_data, selected_node_ids, selected_nodes):
  var parent = layer_parents[object_data.z_index]
  var child

  # We use the filename as the identifier of the object because it's the only easily accessible
  # piece of naming data. If we wanted to, we could look up the human name from the assets list based
  # on filename, but that's a lot of extra work and the filename tends to be relatively
  # human readible and representative.
  var name_tokens = object_data.texture_path.split("/")
  var filename = name_tokens[-1].split(".")[0]

  var name = filename + " - " + object_data.node_id

  # TODO: Add category parent as well

  if tree_filter.length() > 0:
    if name.to_lower().find(tree_filter) == -1:
      return

  # Find or create the prefab parent
  if object_data.prefab_id != null:
    var prefab_parent
    # We might already have a prefab parent for this ID
    if prefab_parents.has(object_data.prefab_id):
      prefab_parent = prefab_parents[object_data.prefab_id]

    # If we don't already have a prefab parent, create it and attach it to the tree.
    else:
      var prefab_name = "prefab " + object_data.prefab_id
      prefab_parent = tree.create_item(parent)
      prefab_parent.set_text(0, prefab_name)
      prefab_parents[object_data.prefab_id] = prefab_parent
      prefab_parent.set_meta("target_prefab_id", object_data.prefab_id)

    # Create our child node
    child = tree.create_item(prefab_parent)
  else:
    child = tree.create_item(parent)


  child.set_text(0, name)
  child.set_meta("target_node_id", object_data.node_id)

  # If the node is selected, flag it and add it to the selected nodes list
  if selected_node_ids.size() > 0 and selected_node_ids.has(object_data.node_id):
    selected_nodes.push_back(child)

  node_dict[object_data.node_id] = child

# Sets up the UI for our tree to live in
func setup_panel():
  # The PanelContainer styling is a bit of a mystery to me - the below is the result of a lot of
  # trial and error.
  panel = PanelContainer.new()

  # Hacky way of doing hidpi scaling. Can't get anchors to work with the current parent node.
  var scale_factor = OS.get_screen_dpi() / 96.0

  panel.set_custom_minimum_size(Vector2(300.0 * scale_factor, 0))

  # Overrides the theme background (which is a light grey) with translucent black.
  var sb = StyleBoxFlat.new()
  sb.set_bg_color(Color(0, 0, 0, 0.4))

  panel.add_stylebox_override("panel", sb)

  # Container that fills the panel
  var box = VBoxContainer.new()
  box.set_h_size_flags(3)
  box.set_v_size_flags(3)

  # Text label. Should probably make it bold or something, but I don't have the will...
  var label = Label.new()
  label.set_text("Layers")
  box.add_child(label)

  # Create our search box - a LineEdit, plus a clear button.
  var search_box = HBoxContainer.new()

  search_input = LineEdit.new()
  search_input.set_h_size_flags(3)
  search_input.connect("text_changed", self, "_filter_tree_items")
  search_input.connect("focus_entered", self, "_focus_entered")
  search_input.connect("focus_exited", self, "_focus_exited")
  search_input.text = tree_filter
  search_box.add_child(search_input)

  var clear_button = Button.new()
  clear_button.set_text("X")
  clear_button.connect("pressed", self, "_clear_button_pressed")
  search_box.add_child(clear_button)

  box.add_child(search_box)

  # Create the tree and tell it to fill the rest of the panel.
  tree = Tree.new()
  tree.hide_root = true
  tree.set_select_mode(2)
  tree.set_column_custom_minimum_width(0, 100.0)

  tree.connect("multi_selected", self, "_on_item_selected")

  tree.set_h_size_flags(3)
  tree.set_v_size_flags(3)

  # Draw the tree for the first time
  refresh_tree()

  box.add_child(tree)
  panel.add_child(box)
  panels_root.add_child(panel)
  print("Layer panel setup done")

func _focus_entered():
  Global.Editor.SuppressTool = true
  Global.Editor.get_node("VPartition/Panels/HSplit/Content").connect("gui_input", self, "_temp_gui_input")

func _focus_exited():
  Global.Editor.SuppressTool = false
  Global.Editor.get_node("VPartition/Panels/HSplit/Content").disconnect("gui_input", self, "_temp_gui_input")

func _temp_gui_input(event):
  if Global.Editor.owner.CanEdit:
    if (event is InputEventMouseButton and event.pressed):
        var focus_owner = Global.Editor.Toolset.get_focus_owner()
        if focus_owner != null:
          focus_owner.release_focus()
    if Global.Editor.ActiveTool != null:
      Global.Editor.ActiveTool._ContentInput(event)

# Clear out our more expensive local variables and detatch the UI from the tree so it can be
# cleaned up.
func teardown_panel():
  treehash = null
  node_dict = {}
  panels_root.remove_child(panel)
  panel.queue_free()
  print("Layer panel teardown complete")

# Whether the user has indicated that the panel should be visible
var is_visible = true
func toggle_panel():
  is_visible = !is_visible

# If you "change" your selection, you will get a deselect and a select event in rapid
# succession. Unfortunately there doesn't seem to be a good way to programatically prevent
# this. So, the solution I have is to set a timer for a fraction of a second before making
# the selection. See the update function for the handler of `pending_selection`
var pending_selection = false
var selection_time_elapsed = 0
func _on_item_selected(item, column, selected):
  pending_selection = true

# Handle our search text input. This will also trigger from _clear_button_pressed
var tree_filter = ""
func _filter_tree_items(text):
  tree_filter = text.to_lower()

  # Clear our previously selected items forcing us to re-sync from the selection
  # select_tool_node_ids = []

  # Force tree to refresh
  refresh_tree(true)

func _clear_button_pressed():
  search_input.clear()

# This is triggered from the pending_selection flag to handle the event order issue. It
# (hackily) selects nodes on the canvas to match the nodes selected in the layer
func handle_selection():
  print("Handled selection")
  var selected_nodes = get_selected_node_ids()

  if selected_nodes.size() > 0:
    select_tool.DeselectAll()

    # This triggers the on-canvas selected state and updates the selected state in the
    # select tool.
    var last_node = null
    for node_id in selected_nodes:
      last_node = Global.World.GetNodeByID(node_id);
      select_tool.SelectThing(last_node, true)
      select_tool.EnableTransformBox(true)

    # Unfortunately it doesn't trigger the additional UI in the select tool panel that allows
    # you to adjust layer, order, and change path texture. So, we make a fake mouse input and
    # target the position of the last node.
    #
    # This _will break_ because there might be multiple nodes at that position, but I don't see
    # any other way to trigger that behavior of the select tool, so it will have to do for now.
    var event = InputEventMouseButton.new()
    event.button_index = BUTTON_LEFT
    event.global_position = last_node.get_position()

    select_tool._ContentInput(event)

    ### VERY USEFUL!!!
    # print(select_tool.Serialize(node))

# Godot tree has a pretty weird way of traversal, treats nodes as a flat list rather than a, y'know, tree.
# There might be some edge cases here w/r/t prefabs but it works well enough for now.
func get_selected_node_ids():
  var selected_nodes = []
  var last_selected = tree.get_next_selected()
  while last_selected != null:
    var node_id = get_meta_safe(last_selected, "target_node_id")
    if node_id:
      selected_nodes.push_back(node_id)
    var prefab_id = get_meta_safe(last_selected, "target_prefab_id")
    if prefab_id:
      var child = last_selected.get_children()
      var prefab_node_child_id = get_meta_safe(child, "target_node_id")
      selected_nodes.push_back(prefab_node_child_id)
    last_selected = tree.get_next_selected(last_selected)

  return selected_nodes

# Store our selected node IDs so we can redraw with new selection if they've changed. This
# triggers every update, we may need to throttle for performance in the future
var select_tool_node_ids = []
func sync_selected_nodes():
  var new_select_tool_node_ids = []
  var selection_changed = false
  var last_selected_node_id = null
  for selected in select_tool.Selected:
    var _nid = get_meta_safe(selected, "node_id")

    if _nid == null:
      continue

    var node_id = String(_nid)

    new_select_tool_node_ids.push_back(node_id)
    if node_dict.has(node_id) and !select_tool_node_ids.has(node_id):
      print(select_tool_node_ids, node_id)
      node_dict[node_id].select()
      last_selected_node_id = node_id
      selection_changed = true

  for previously_selected_id in select_tool_node_ids:
    if !new_select_tool_node_ids.has(previously_selected_id) and node_dict.has(previously_selected_id):
      node_dict[previously_selected_id].deselect()
      selection_changed = true


  # When our selection changes (e.g. from selecting on the canvas) we want to do some side effects to show
  # the last selected node in the sidebar and to clear the search filter
  if selection_changed:
    # TODO: If the click comes from the canvas, we want to clear the filter. We don't want to clear it
    # if the click comes from the sidebar.
    tree.scroll_to_item(node_dict[last_selected_node_id])

  select_tool_node_ids = new_select_tool_node_ids

# The next set of helpers extracts the properties we need from selectable nodes. Patterns are treated
# differently from objects and paths.
func get_object_data(level):
  var objects = level.Objects.get_children()

  var object_data = []
  for object in objects:
    var data = get_standard_data(object)
    # TODO: class instead of dict
    object_data.push_back(data)

  return object_data

func get_path_data(level):
  var paths = level.Pathways.get_children()

  var path_data = []
  for path in paths:
    var data = get_standard_data(path)
    # TODO: class instead of dict
    path_data.push_back(data)

  return path_data

# The standard data for objects and paths.
func get_standard_data(object):
  var z_index = String(object.z_index)
  var texture_path = String(object.Texture.resource_path)
  var node_id = String(get_meta_safe(object, "node_id"))
  var prefab_id = String(get_meta_safe(object, "prefab_id"))

  return { "z_index": z_index, "texture_path": texture_path, "node_id": node_id, "prefab_id": prefab_id }

# The data for patterns is stored slightly differently.
func get_pattern_data(level):
  var pattern_data = [];
  for layer in level.PatternShapes.get_children():
    var z_index = String(layer.z_index)

    for pattern_shape in layer.get_children():
      var texture_path = String(pattern_shape.get__Texture().resource_path)
      var node_id = String( get_meta_safe(pattern_shape, "node_id"))
      var prefab_id = String(get_meta_safe(pattern_shape,"prefab_id"))

      pattern_data.push_back({ "z_index": z_index, "texture_path": texture_path, "node_id": node_id, "prefab_id": prefab_id })

  return pattern_data

# Roof data is also stored differently
func get_roof_data(level):
  var roof_data = [];
  for roof in level.Roofs.get_children():
    # Roofs are hard-coded 800 z-index and cannot be changed.
    var z_index = "800"
    var node_id = String(get_meta_safe(roof, "node_id"))

    # Prefabs don't support roofs through the save file but we do this anyway just in case.
    # They are supported _until_ saving, so that's likely a prefab bug & will be fixed eventually.
    var prefab_id = String(get_meta_safe(roof, "prefab_id"))

    var tile_texture_path = roof.get_TilesTexture().resource_path

    # Tile texture has a bit a different format - it always ends in `tiles.png`. So we manually extract
    # the relevant path segment and just return that.
    var texture_path = tile_texture_path.split("/")[-2]

    roof_data.push_back({ "z_index": z_index, "texture_path": texture_path, "node_id": node_id, "prefab_id": prefab_id})

  return roof_data

# Light data is stored like roofs - hard-coded layer
func get_light_data(level):
  var light_data = []
  for light in level.Lights.get_children():
    var z_index = "9999"
    var node_id = String(get_meta_safe(light, "node_id"))

    # Lights aren't supported in prefabs
    var prefab_id = null
    var texture_path = light.get_texture().resource_path

    light_data.push_back({ "z_index": z_index, "texture_path": texture_path, "node_id": node_id, "prefab_id": prefab_id})

  return light_data

# Ditto with freestanding portals - hardcoded to layer 500
func get_portal_data(level):
  var portal_data = []
  for portal in level.Portals.get_children():
    var data = get_standard_data(portal)
    # All portals on layer 500
    data.z_index = "500"
    portal_data.push_back(data)

  return portal_data


# We don't have a listener for mouse click events on the canvas, so instead we lean on our
# tree_hash checking and do a dirty check every 1 second. If we're dirty we rerender.
func update(delta):
  if Global.Editor.ActiveTool == select_tool and active == false and is_visible == true:
    active = true
    setup_panel()

  if (Global.Editor.ActiveTool != select_tool or is_visible == false) and active == true:
    active = false
    teardown_panel()

  # TODO: Better dirty checking
  if active == true:
    timeout += delta
    # Check dirty here once we figure out a good way to do it
    if timeout > 1.0:
      refresh_tree()
      timeout = 0.0

  # Annoying workaround for multi select bug
  # We call handle_selection 0.1s after we receive a multi select event, which lets us
  # get the state after all the adds and removes.
  if pending_selection == true:
    selection_time_elapsed += delta
    if selection_time_elapsed > 0.1:
      pending_selection = false
      selection_time_elapsed = 0
      handle_selection()

  # We sync selected nodes every update tick. This might become a perf concern in the future.
  sync_selected_nodes()

# IDK why this wasn't working in the utils file. Godot has some annoying behavior with undefined meta
# and it's cumbersome to check has_meta everywhere we want to use get_meta.
func get_meta_safe(object, key, default = null):
  if object.has_meta(key):
    return object.get_meta(key)
  else:
    return default

func get_current_level():
  return Global.World.levels[Global.World.CurrentLevelId]