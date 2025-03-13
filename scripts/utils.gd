# In the future we'll have a better way of setting up util scripts. This will do until
# then, but has some downsides - it doesn't get reloaded on mod reload.
class_name Utils
var script_class = "tool"

func start():
  # no-op
  pass

# Helpful utils
func get_method_names(node):
  var names = []
  for method in node.get_method_list():
      if method.name:
          names.append(method.name)
  return names

func print_method_names(node):
  print(String(get_method_names(node)))

# Not used but I'm going to hang onto it for testing
var chars = 'abcdefghijklmnopqrstuvwxyz'
func generate_word(length):
  var word: String
  var n_char = len(chars)
  for i in range(length):
      word += chars[randi()% n_char]
  return word

# Dict of all standard layer names to whether the layer is user editable.
var layers = {
  -500: false,
  -400: true,
  -300: false,
  -200: false,
  -100: true,
  0: false,
  100: true,
  200: true,
  300:true,
  400: true,
  # 500 is portals. Not user editable, but assets are selectable.
  500: true,
  600: false,
  700: true,
  # 800 is roofs. Not user editable, but assets are selectable.
  800: true,
  900: true,
  # 9999 is lights. Not user editable, but assets are selectable.
  9999: true
}

var layer_names = {
  -500: "Terrain",
  -400: "Below Ground",
  -300: "Caves",
  -200: "Floor",
  -100: "Below Water",
  0: "Water",
  100: "User Layer 1",
  200: "User Layer 2",
  300: "User Layer 3",
  400: "User Layer 4",
  500: "Portals",
  600: "Walls",
  700: "Above Walls",
  800: "Roofs",
  900: "Above Roofs",
  9999: "Lights"
}