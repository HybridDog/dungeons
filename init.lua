local np_density = {
	offset = 0.9,
	scale = 0.5,
	spread = {x=500, y=500, z=500},
	seed = 0,
	octaves = 2,
	persist = 0.8,
	lacunarity = 2,
}

local np_alt_wall = {
	offset = -0.4,
	scale = 1,
	spread = {x=40, y=40, z=40},
	seed = 32474,
	octaves = 6,
	persist = 1.1,
	lacunarity = 2,
}

local c = {
	air = minetest.get_content_id"air",
	ignore = minetest.get_content_id"ignore",
	water = minetest.get_content_id"default:water_source",
	river_water = minetest.get_content_id"default:river_water_source"
}

local c_desert_stone = minetest.get_content_id"default:desert_stone"

local c_cobble = minetest.get_content_id"default:cobble"
local c_mossycobble = minetest.get_content_id"default:mossycobble"
local c_stair_cobble = minetest.get_content_id"stairs:stair_cobble"


-- get the content ids for walls and stairs
local used_default = {c_cobble, c_mossycobble, c_stair_cobble, c_stair_cobble}
local used_desert = {c_desert_stone, c_desert_stone, c_desert_stone, c_desert_stone}
local used_cache = {}
setmetatable(used_cache, {__mode = "kv"})
local function get_used(id)
	if used_cache[id] ~= nil then
		return used_cache[id]
	end
	local name = minetest.get_name_from_content_id(id)
	local def = minetest.registered_nodes[name]
	if not def
	or not def.groups
	or not def.groups.cracky then
		used_cache[id] = false
		return false
	end
	if name:find"desert" then
		used_cache[id] = used_desert
		return used_desert
	end
	used_cache[id] = used_default
	return used_default
end


local dp = {
	seed = seed;
	rooms_min = 2;
	rooms_max = 16;
}

local was_desert
local pr
local function init(bseed, is_desert, minp, maxp)
	local nval_density = minetest.get_perlin(np_density):get3d(minp)

	-- when is this supposed to be > 1?
	if nval_density < 1 then
nval_density = 1
		--return
	end

	pr = PseudoRandom(bseed + 2)

	if is_desert
	and not was_desert then
		dp.holesize = {x=2, y=3, z=2}
		dp.roomsize = {x=2, y=5, z=2}
		dp.diagonal_dirs = true

		was_desert = true
	elseif was_desert ~= false then
		dp.holesize = {x=1, y=2, z=1}
		dp.roomsize = {x=0, y=0, z=0}
		dp.diagonal_dirs = false

		was_desert = false
	end
	return nval_density
end

local mapblock_vec = {x=16, y=16, z=16}
local make_dungeon
local area, data, param2s, toset_data
minetest.register_on_generated(function(minp, maxp, bseed)
local is_desert = false
	local nval_density = init(bseed, is_desert, minp, maxp)
	if not nval_density then
		return
	end

	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	data = vm:get_data()
	param2s = vm:get_param2_data()
	area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}

	-- Add them
	toset_data = {}
	for _ = 1, math.floor(nval_density) do
		make_dungeon(mapblock_vec, minp, maxp)
	end

	-- put nodes
	local ni = 0
	local nmap = minetest.get_perlin_map(np_alt_wall, vector.add(vector.subtract(maxp, minp), 1)):get3dMap_flat(minp)
	for i in area:iterp(minp, maxp) do
		ni = ni+1
		local typ = toset_data[i]
		if typ then
			-- dungeon node to add
			local toset = get_used(data[i])
			if toset then
				-- adding allowed
				if typ == 0 then
					data[i] = c.air
				else
					-- choose wall or stair, usual or mossy
					local ti = typ * 2 - 1
					if nmap[ni] > 0 then
						-- select the mossy one
						ti = ti + 1
					end
					data[i] = toset[ti]
				end
			end
		end
	end

	vm:set_data(data)
	vm:set_param2_data(param2s)
	vm:set_lighting({day=0, night=0})
	vm:calc_lighting()
	vm:write_to_map()

	-- set stuff to nil to feed the garbage collector
	area = nil
	data = nil
	param2s = nil
	pr = nil
end)

local find_place_for_door, find_place_for_room_door, room, door, m_pos, m_dir, make_corridor
function make_dungeon(start_padding, minp, maxp)
	local sidelen = maxp.x - minp.x + 1

	--	Set place for first room
	local roomsize
	if pr:next(0, 3) == 1 then
		roomsize = {
			z = pr:next(8, 16),
			y = pr:next(8, 16),
			x = pr:next(8, 16)
		}
	else
		roomsize = {
			z = pr:next(4, 8),
			y = pr:next(4, 6),
			x = pr:next(4, 8)
		}
	end
	roomsize = vector.add(roomsize, dp.roomsize)

	local roomplace = vector.add(minp, {
		x = pr:next(0, sidelen - roomsize.x),
		y = pr:next(0, sidelen - roomsize.y),
		z = pr:next(0, sidelen - roomsize.z),
	})

	--[[
		Stores the center position of the last room made, so that
		a new corridor can be started from the last room instead of
		the new room, if chosen so.
	]]
	local last_room_center = vector.add(roomplace, {x = math.floor(roomsize.x * .5), y = 1, z = math.floor(roomsize.z * .5)})

	local room_count = pr:next(dp.rooms_min, dp.rooms_max)
	for i = 1, room_count do
		-- Make a room to the determined place
		room(roomsize, roomplace)

		-- Quit if last room
		if i == room_count then
			break
		end

		local room_center = vector.add(roomplace, {x = math.floor(roomsize.x * .5), y = 1, z = math.floor(roomsize.z * .5)})

		-- Determine walker start position
		local walker_start_place
		if pr:next(0, 2) ~= 0 then
			-- start_in_last_room
			walker_start_place = last_room_center
		else
			walker_start_place = room_center
			-- Store center of current room as the last one
			last_room_center = room_center
		end

		-- Create walker and find a place for a door
		m_pos = walker_start_place
		local doorplace, doordir = find_place_for_door()
		if not doorplace then
			return
		end

		if pr:next(0, 1) == 0 then
			-- Make the door
			door(doorplace, doordir)
		else
			-- Don't actually make a door
			doorplace = vector.subtract(doorplace, doordir)
		end

		-- Make a random corridor starting from the door
		local corridor_end, corridor_end_dir = make_corridor(doorplace, doordir, minp, maxp)

		-- Find a place for a random sized room
		roomsize.z = pr:next(4, 8)
		roomsize.y = pr:next(4, 6)
		roomsize.x = pr:next(4, 8)
		roomsize = vector.add(dp.roomsize, roomsize)

		m_pos = corridor_end
		m_dir = corridor_end_dir

		doorplace, doordir, roomplace = find_place_for_room_door(roomsize)
		if not doorplace then
			return
		end

		if pr:next(0, 1) == 0 then
			-- Make the door
			door(doorplace, doordir)
		else
			-- Don't actually make a door
			roomplace = vector.subtract(roomplace, doordir)
		end
	end
end


local iterp_hollowcuboid
function room(roomsize, roomplace)
	-- Make walls
	for vi in iterp_hollowcuboid(area, roomplace, vector.add(roomplace, vector.subtract(roomsize, 1))) do
		if not toset_data[vi] then
			toset_data[vi] = 1
		end
	end

	-- Fill with air
	for vi in area:iterp(vector.add(roomplace, 1), vector.add(roomplace, vector.subtract(roomsize, 2))) do
		toset_data[vi] = 0
	end
end


local function fill(place, size)
	for vi in area:iterp(place, vector.add(place, vector.subtract(size, 1))) do
		if not toset_data[vi] then
			toset_data[vi] = 1
		end
	end
end


local function hole(place)
	for vi in area:iterp(place, vector.add(place, vector.subtract(dp.holesize, 1))) do
		toset_data[vi] = 0
	end
end


function door(doorplace, doordir)
	hole(doorplace)
end

local random_turn, turn_xz, dir_to_facedir, vector_inside
function make_corridor(doorplace, doordir, minp, maxp)
	hole(doorplace)
	local p0 = doorplace
	local dir = doordir
	--[[
	local length
	if (pr:next() % 2)
		length = pr:next(1, 13)
	else
		length = pr:next(1, 6);
	]]
	local length = pr:next(1, 13)
	local partlength = pr:next(1, 13)
	local partcount = 0
	local make_stairs = 0

	if pr:next(0, 1) == 0
	and partlength >= 3 then
		make_stairs = pr:next(0, 1) * 2 - 1
	end

	for i = 0, length-1 do
		local p = vector.add(p0, dir)
		if partcount ~= 0 then
			p.y = p.y + make_stairs
		end

		if vector_inside({x=p.x, y=p.y+1, z=p.z}, minp, maxp)
		and vector_inside({x=p.x - dir.x, y=p.y-1, z=p.z - dir.z}, minp, maxp) then
			if make_stairs ~= 0 then
				fill(vector.subtract(p, 1),
					vector.add(dp.holesize, {x=2, y=3, z=2})
				)
				hole(p)
				hole(vector.subtract(p, dir))

				-- TODO: fix stairs code so it works 100%
				-- (quite difficult)

				-- exclude stairs from the bottom step
				-- exclude stairs from diagonal steps
				if (dir.x + dir.z)%2 == 1
				and (
					(make_stairs == 1 and i ~= 0)
					or (make_stairs == -1 and i ~= length - 1)
				) then
					-- rotate face 180 deg if
					-- making stairs backwards
					local facedir = dir_to_facedir(vector.multiply(dir, make_stairs))

					local vi = area:index(p.x - dir.x, p.y - 1, p.z - dir.z)
					if toset_data[vi] == 1 then
						toset_data[vi] = 2
						param2s[vi] = facedir
					end

					vi = area:indexp(p)
					if toset_data[vi] == 1 then
						toset_data[vi] = 2
						param2s[vi] = facedir
					end
				end
			else
				fill(vector.subtract(p, 1),
					vector.add(dp.holesize, {x=2, y=2, z=2})
				)
				hole(p)
			end

			p0 = p


			partcount = partcount+1
			if partcount >= partlength then
				partcount = 0

				dir = random_turn(dir)

				partlength = pr:next(1, length)

				make_stairs = 0
				if pr:next(0, 1) == 0
				and partlength >= 3 then
					make_stairs = pr:next(0, 1) * 2 - 1
				end
			end

		else
			-- Can't go here, turn away
			dir = turn_xz(dir, pr:next(0, 1))
			make_stairs = -make_stairs
			partcount = 0
			partlength = pr:next(1, length)
		end
	end
	return p0, dir
end


local randomize_dir
function find_place_for_door()
	for i = 0, 99 do
		if i % 4 == 0 then
			randomize_dir()
		else
			local p = vector.add(m_pos, m_dir)
			local p1 = vector.add(p, {x=0, y=1, z=0})
			if not area:containsp(p)
			or not area:containsp(p1) then
				randomize_dir()
			else
				if toset_data[area:indexp(p)] == 1
				and toset_data[area:indexp(p1)] == 1 then
					-- Found wall, this is a good place!
					-- Randomize next direction
					randomize_dir()
					return p, m_dir
				end
				--[[
					Determine where to move next
				]]
				-- Jump one up if the actual space is there
				if toset_data[area:indexp(p)] == 1
				and toset_data[area:indexp(vector.add(p, {x=0, y=1, z=0}))] == 0
				and toset_data[area:index(p.x, p.y+2, p.z)] == 0 then
					p.y = p.y+1
				end
				-- Jump one down if the actual space is there
				if toset_data[area:indexp(vector.add(p, {x=0, y=1, z=0}))] == 1
				and toset_data[area:indexp(p)] == 0
				and toset_data[area:indexp(vector.add(p, {x=0, y=-1, z=0}))] == 0 then
					p.y = p.y-1
				end
				-- Check if walking is now possible
				if toset_data[area:indexp(p)] ~= 0
				or toset_data[area:indexp(vector.add(p, {x=0, y=1, z=0}))] ~= 0 then
					-- Cannot continue walking here
					randomize_dir()
				else
					-- Move there
					m_pos = p
				end
			end
		end
	end
end


function find_place_for_room_door(roomsize)
	for trycount = 0, 29 do
		local doorplace, doordir = find_place_for_door()
		if doorplace then
			local roomplace
			-- X east, Z north, Y up

			local toadd = {x=0, y=-1, z=0}
			if doordir.x == 1 then
				toadd.z = pr:next(-roomsize.z + 2, -2)
			elseif doordir.x == -1 then
				toadd.x = -roomsize.x + 1
				toadd.z = pr:next(-roomsize.z + 2, -2)
			elseif doordir.z == 1 then
				toadd.x = pr:next(-roomsize.x + 2, -2)
			elseif doordir.z == -1 then
				toadd.x = pr:next(-roomsize.x + 2, -2)
				toadd.z = -roomsize.z + 1
			end
			roomplace = vector.add(doorplace, toadd)

		--[[
			if (doordir == {x=1, 0, 0)) -- X+ roomplace = doorplace + {x=0, -1, -roomsize.z / 2)
			if (doordir == {x=-1, 0, 0)) -- X-
				roomplace = doorplace + {x=-roomsize.x+1,-1,-roomsize.z / 2)
			if (doordir == {x=0, 0, 1)) -- Z+ roomplace = doorplace + {x=-roomsize.x / 2, -1, 0)
			if (doordir == {x=0, 0, -1)) -- Z-
				roomplace = doorplace + {x=-roomsize.x / 2, -1, -roomsize.z + 1)
		--]]

			-- Check fit
			local fits = true
			for vi in area:iterp(vector.add(roomplace, 1), vector.add(roomplace, vector.subtract(roomsize, 2))) do
				if toset_data[vi] == 0 then
					fits = false
					break
				end
			end
			if fits then
				return doorplace, doordir, roomplace
			end
		end
	end
end


local function rand_ortho_dir(diagonal_dirs)
	-- Make diagonal directions somewhat rare
	if diagonal_dirs
	and pr:next(0, 3) == 0 then
		local dir
		local trycount = 0

		while trycount <= 10
		and dir.x == 0
		and dir.z == 0 do
			trycount = trycount+1
			dir.z = pr:next(-1, 1)
			dir.y = 0
			dir.x = pr:next(-1, 1)
		end

		return dir
	end
	if pr:next(0, 1) == 0 then
		local p = {y=0, z=0}
		p.x = pr:next(0, 1) * 2 - 1
		return p
	end
	local p = {x=0, y=0}
	p.z = pr:next(0, 1) * 2 - 1
	return p
end


function randomize_dir()
	m_dir = rand_ortho_dir(dp.diagonal_dirs)
end


function turn_xz(olddir, t)
	if t == 0 then
		-- Turn right
		return {x=olddir.z, y=olddir.y, z=-olddir.x}
	end
	-- Turn left
	return {x=-olddir.z, y=olddir.y, z=olddir.x}
end


function random_turn(olddir)
	local turn = pr:next(0, 2)
	if turn == 0 then
		-- Go straight
		return vector.new(olddir)
	end
	if turn == 1 then
		-- Turn right
		return turn_xz(olddir, 0)
	end
	-- Turn left
	return turn_xz(olddir, 1)
end


function dir_to_facedir(d)
	if math.abs(d.x) > math.abs(d.z) then
		return d.x < 0 and 3 or 1
	end
	return d.z < 0 and 2 or 0
end


local function iter_hollowcuboid(self, minx, miny, minz, maxx, maxy, maxz)
	local i = self:index(minx, miny, minz) - 1
	local xrange = maxx - minx + 1
	local nextaction = i + 1 + xrange
	local do_hole = false

	local y = 0
	local ydiff = maxy - miny
	local ystride = self.ystride
	local ymultistride = ydiff * ystride

	local z = 0
	local zdiff = maxz - minz
	local zstride = self.zstride
	local zcorner = true

	return function()
		-- continue i until it needs to jump ystride
		i = i + 1
		if i ~= nextaction then
			return i
		end

		-- add the x offset if y (and z) are not 0 or maxy (or maxz)
		if do_hole then
			do_hole = false
			i = i + xrange - 2
			nextaction = i + 1
			return i
		end

		-- continue y until maxy is exceeded
		y = y+1
		if y ~= ydiff + 1 then
			i = i + ystride - xrange
			if zcorner
			or y == ydiff then
				nextaction = i + xrange
			else
				nextaction = i + 1
				do_hole = true
			end
			return i
		end

		-- continue z until maxz is exceeded
		z = z+1
		if z == zdiff + 1 then
			-- hollowcuboid finished, return nil
			return
		end

		-- set i to index(minx, miny, minz + z) - 1
		i = i + zstride - (ymultistride + xrange)
		zcorner = z == zdiff

		-- y is 0, so traverse the xs
		y = 0
		nextaction = i + xrange
		return i
	end
end

function iterp_hollowcuboid(self, minp, maxp)
	return iter_hollowcuboid(self, minp.x, minp.y, minp.z, maxp.x, maxp.y, maxp.z)
end

function vector_inside(pos, minp, maxp)
	for _,i in pairs{"x", "y", "z"} do
		if pos[i] < minp[i]
		or pos[i] > maxp[i] then
			return false
		end
	end
	return true
end

print"lua dungeons…"
