class_name EconomyConfig
extends Resource
## Root economy resource: one generation entry per map.

@export var generations: Array[EconomyGeneration] = []
@export var default_generation: StringName = &""


func find_generation(generation_id: StringName) -> EconomyGeneration:
	for generation: EconomyGeneration in generations:
		if generation != null and generation.id == generation_id:
			return generation
	return null
