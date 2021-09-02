extends WindowDialog

func _ready():
	pass # Replace with function body.

func set_achievements(achievements, unlocked):
	var container = $VBoxContainer/MarginContainer/ScrollContainer/VBoxContainer
	var total : int = 0
	var total_unlocked : int = 0
	for s in achievements:
		var label = load("res://material_maker/tools/achievements/achievement_section.tscn").instance()
		label.text = s.name
		container.add_child(label)
		var section : VBoxContainer = VBoxContainer.new()
		container.add_child(section)
		var locked_count : int = 0
		for a in s.achievements:
			var achievement = load("res://material_maker/tools/achievements/achievement.tscn").instance()
			section.add_child(achievement)
			if unlocked.find(a.id) != -1:
				achievement.set_texts(a.name, a.description, true)
				total_unlocked += 1
			else:
				achievement.set_texts("? ? ? ? ? ?", a.hint)
				section.move_child(achievement, locked_count)
				locked_count += 1
			total += 1
	$VBoxContainer/Label.text = "Total achievements completed: %d/%d" % [ total_unlocked, total ]
