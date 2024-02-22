@tool
extends Node3D


@onready var gridMap : GridMap = $GridMap


@export var start : bool = false : set = setStart
func setStart(val : bool) -> void:
	if Engine.is_editor_hint():
		generate()

@export_range(0, 1) var survivalChance : float = 0.25

@export var borderSize : int = 20 : set = setBorderSize
func setBorderSize(val : int) -> void:
	borderSize = val
	
	if Engine.is_editor_hint():
		visualizeBorder()


@export var roomRecursion : int = 10
@export var minRoomSize : int = 2
@export var maxRoomSize : int = 6
@export var roomMargin : int = 1
@export var roomNumber : int = 3

@export_multiline var customSeed : String = "" : set = setSeed
func setSeed(val : String) -> void:
	customSeed = val
	seed(val.hash())

var roomTiles : Array[PackedVector3Array] = []
var roomPositions : PackedVector3Array = [] #Array[PackedVector3Array] = []


func visualizeBorder():
	gridMap.clear()
	
	for i in range(-1, borderSize +1):
		gridMap.set_cell_item(Vector3i(i, 0, -1), 3)
		gridMap.set_cell_item(Vector3i(i, 0, borderSize), 3)
		gridMap.set_cell_item(Vector3i(borderSize, 0, i), 3)
		gridMap.set_cell_item(Vector3i(-1, 0, i), 3)


func generate():
	roomPositions.clear()
	roomTiles.clear()
	
	if customSeed : setSeed(customSeed)
	
	visualizeBorder()
	
	for i in roomNumber:
		makeRoom(roomRecursion)
	
	var rpv2 : PackedVector2Array = []
	var delGraph : AStar2D = AStar2D.new()
	var mstGraph : AStar2D = AStar2D.new()
	
	for roomPos in roomPositions:
		rpv2.append(Vector2(roomPos.x, roomPos.z))
		delGraph.add_point(delGraph.get_available_point_id(), Vector2(roomPos.x, roomPos.z))
		mstGraph.add_point(mstGraph.get_available_point_id(), Vector2(roomPos.x, roomPos.z))
	
	var delaunay : Array = Array(Geometry2D.triangulate_delaunay(rpv2))
	for i in delaunay.size()/3:
		var p1 : int = delaunay.pop_front()
		var p2 : int = delaunay.pop_front()
		var p3 : int = delaunay.pop_front()
		delGraph.connect_points(p1, p2)
		delGraph.connect_points(p2, p3)
		delGraph.connect_points(p1, p3)
	
	var visitedPoints : PackedInt32Array = []
	visitedPoints.append(randi() % roomPositions.size())
	
	while visitedPoints.size() != mstGraph.get_point_count():
		var possibleConnections : Array[PackedInt32Array] = []
		for vp in visitedPoints:
			for c in delGraph.get_point_connections(vp):
				if !visitedPoints.has(c):
					var con : PackedInt32Array = [vp, c]
					possibleConnections.append(con)
		
		var connection : PackedInt32Array = possibleConnections.pick_random()
		for pc in possibleConnections:
			if rpv2[pc[0]].distance_squared_to(rpv2[pc[1]]) <\
			rpv2[connection[0]].distance_squared_to(rpv2[connection[1]]):
				connection = pc
		
		visitedPoints.append(connection[1])
		mstGraph.connect_points(connection[0], connection[1])
		delGraph.disconnect_points(connection[0], connection[1])
	
	var hallwayGraph : AStar2D = mstGraph
	for p in delGraph.get_point_ids():
		for c in delGraph.get_point_connections(p):
			if c > p:
				var kill : float = randf()
				if survivalChance > kill:
					hallwayGraph.connect_points(p, c)
	
	createHallways(hallwayGraph)


func createHallways(hallwayGraph : AStar2D):
	var hallways : Array[PackedVector3Array] = []
	for p in hallwayGraph.get_point_ids():
		for c in hallwayGraph.get_point_connections(p):
			if c > p:
				var roomFrom : PackedVector3Array = roomTiles[p]
				var roomTo : PackedVector3Array = roomTiles[c]
				var tileFrom : Vector3 = roomFrom[0]
				var tileTo : Vector3 = roomTo[0]
				
				for t in roomFrom:
					if t.distance_squared_to(roomPositions[c]) <\
					tileFrom.distance_squared_to(roomPositions[c]):
						tileFrom = t
				
				for t in roomTo:
					if t.distance_squared_to(roomPositions[p]) <\
					tileTo.distance_squared_to(roomPositions[p]):
						tileTo = t
				
				var hallway : PackedVector3Array = [tileFrom, tileTo]
				hallways.append(hallway)
				gridMap.set_cell_item(tileFrom, 2)
				gridMap.set_cell_item(tileTo, 2)
	
	var astar : AStarGrid2D = AStarGrid2D.new()
	astar.size = Vector2i.ONE * borderSize
	astar.update()
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	
	for t in gridMap.get_used_cells_by_item(0):
		astar.set_point_solid(Vector2i(t.x, t.z))
	
	for h in hallways:
		var posFrom : Vector2i = Vector2i(h[0].x, h[0].z)
		var posTo : Vector2i = Vector2i(h[1].x, h[1].z)
		var hall : PackedVector2Array = astar.get_point_path(posFrom, posTo)
		
		for t in hall:
			var pos : Vector3i = Vector3i(t.x, 0, t.y)
			
			if gridMap.get_cell_item(pos) < 0:
				gridMap.set_cell_item(pos, 1)


func makeRoom(rec : int):
	if !rec > 0:
		return
	
	var width : int = (randi() % (maxRoomSize - minRoomSize)) + minRoomSize
	var height : int = (randi() % (maxRoomSize - minRoomSize)) + minRoomSize
	
	var startPos : Vector3i
	startPos.x = randi() % (borderSize - width + 1)
	startPos.z = randi() % (borderSize - height + 1)
	
	for r in range(-roomMargin, height + roomMargin):
		for c in range(-roomMargin, width + roomMargin):
			var pos : Vector3i = startPos + Vector3i(c, 0, r)
			if gridMap.get_cell_item(pos) == 0:
				makeRoom(rec - 1)
				return
	
	var room : PackedVector3Array = []
	for r in height:
		for c in width:
			var pos : Vector3i = startPos + Vector3i(c, 0, r)
			gridMap.set_cell_item(pos, 0)
			room.append(pos)
	
	roomTiles.append(room)
	var avgX : float = startPos.x + (float(width)/2)
	var avgZ : float = startPos.z + (float(height)/2)
	var pos : Vector3 = Vector3(avgX, 0, avgZ)
	roomPositions.append(pos)
	
