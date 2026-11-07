class_name DrawBox
extends Control
## A Control that draws itself with a callable: painter.call(self). Handy for small icons
## (drops, coins, pips) inside containers. Set `animated` to redraw every frame.

var painter: Callable
var animated := false


func _init(p: Callable = Callable(), min_size := Vector2.ZERO, p_animated := false) -> void:
	painter = p
	custom_minimum_size = min_size
	animated = p_animated
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if animated and is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
