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

local dp = {
	seed = seed;
	rooms_min = 2;
	rooms_max = 16;
}

local was_desert
local pr
local function init(bseed, is_desert, minp, maxp)
	--np_density.seed = np_density.seed + bseed
	local nval_density = minetest.get_perlin(np_density):get3d(minp)
	--np_density.seed = np_density.seed - bseed
	if nval_density < 1 then
		return false
	end

	pr = PseudoRandom(bseed + 2)

	if is_desert
	and was_desert == false then
		dp.holesize = {x=2, y=3, z=2}
		dp.roomsize = {x=2, y=5, z=2}
		dp.diagonal_dirs = true

		c.wall = c_desert_stone
		c.alt_wall = c_desert_stone
		c.stair = c_desert_stone

		was_desert = true
	elseif was_desert then
		dp.holesize = {x=1, y=2, z=1}
		dp.roomsize = {x=0, y=0, z=0}
		dp.diagonal_dirs = false

		c.wall = c_cobble
		c.alt_wall = c_mossycobble
		c.stair = c_stair_cobble

		was_desert = false
	end
	return true
end

local mapblock_vec = vector.new(16)
local make_dungeon
local area, data, param2s, flags
local function generate(bseed, minp, maxp)
	if not init(bseed, is_desert, minp, maxp) then
		return
	end

	-- Set all air and water to be untouchable
	-- to make dungeons open to caves and open air
	flags = {}
	for vi in area:iterp(minp, maxp) do
		local id = data[vi]
		if id == c.air
		or id == c.water
		or id == c.river_water then
			flags[vi] = true
		end
	end

	-- Add them
	for _ = 1, math.floor(nval_density) do
		make_dungeon(mapblock_vec)
	end

	-- put moss
	local ni = 0
	local nmap = minetest.get_perlin_map(np_alt_wall, vector.add(vector.subtract(maxp, minp), 1)):get3dMap_flat(minp)
	for i in area:iterp(minp, maxp) do
		ni = ni+1
		if data[i] == c.wall
		and nmap[ni] > 0 then
			data[i] = c.alt_wall
		end
	end

	-- set stuff to nil to feed the garbage collector
	area = nil
	data = nil
	param2s = nil
	flags = nil
	pr = nil
end

local find_place_for_door, find_place_for_room_door, room, door
function make_dungeon(start_padding)
	local areasize = area:getExtent()
	local roomsize
	local roomplace

	--	Find place for first room
	local fits = false
	local i = 0
	while i < 100
	and not fits do
		local is_large_room = pr:next(0, 3) == 1
		if is_large_room then
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

		-- start_padding is used to disallow starting the generation of
		-- a dungeon in a neighboring generation chunk
		roomplace = vector.add(vector.add(area.MinEdge, start_padding), {
			x = pr:next(0, areasize.x - roomsize.x - start_padding.x),
			y = pr:next(0, areasize.y - roomsize.y - start_padding.y),
			z = pr:next(0, areasize.z - roomsize.z - start_padding.z),
		})

		--	Check that we're not putting the room to an unknown place,
		--	otherwise it might end up floating in the air
		fits = true
		for z = 0, roomsize.z-1 do
			for y = 0, roomsize.y-1 do
				for x = 0, roomsize.x-1 do
					local vi = area:index(roomplace.x + x, roomplace.y + y, roomplace.z + z)
					if flags[vi]
					or data[vi] == c.ignore then
						fits = false
						break
					end
				end
				if not fits then
					break
				end
			end
			if not fits then
				break
			end
		end
		i = i+1
	end
	-- No place found
	if not fits then
		return
	end

	--[[
		Stores the center position of the last room made, so that
		a new corridor can be started from the last room instead of
		the new room, if chosen so.
	]]
	local last_room_center = vector.add(roomplace, {x = math.floor(roomsize.x * .5), y = 1, z = math.floor(roomsize.z * .5))

	local room_count = pr:next(dp.rooms_min, dp.rooms_max)
	for i = 0, room_count-1 do
		-- Make a room to the determined place
		room(roomsize, roomplace)

		local room_center = vector.add(roomplace, {x = math.floor(roomsize.x * .5), y = 1, z = math.floor(roomsize.z * .5))

		-- Quit if last room
		if i == room_count - 1 then
			break
		end

		-- Determine walker start position

		local start_in_last_room = pr:next(0, 2) ~= 0

		local walker_start_place

		if start_in_last_room then
			walker_start_place = last_room_center
		else
			walker_start_place = room_center
			-- Store center of current room as the last one
			last_room_center = room_center
		end

		-- Create walker and find a place for a door
		local doorplace, doordir

		m_pos = walker_start_place
		if not find_place_for_door(doorplace, doordir) then
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
		local corridor_end, corridor_end_dir = make_corridor(doorplace, doordir, corridor_end, corridor_end_dir)

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
		if not flags[vi] then
			data[vi] = c.wall
		end
	end

	-- Fill with air
	for vi in area:iterp(vector.add(roomplace, 1), vector.add(roomplace, vector.subtract(roomsize, 2))) do
		flags[vi] = true
		data[vi] = n_air
	end
end


local function fill(place, size, id)
	for vi in area:iterp(place, vector.add(place, vector.subtract(size, 1))) do
		if not flags[vi] then
			data[vi] = id
		end
	end
end


local function hole(place)
	for vi in area:iterp(place, vector.add(place, vector.subtract(dp.holesize, 1))) do
		flags[vi] = true
		data[vi] = c.air
	end
end


function door(doorplace, doordir)
	hole(doorplace)
end

local random_turn, turn_xz, dir_to_facedir
local function make_corridor(doorplace, doordir)
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

		if area:containsp(p)
		and area:containsp(vector.add(p, {x=0, y=1, z=0}))
		and area:contains(p.x - dir.x, p.y - 1, p.z - dir.z) then
			if make_stairs ~= 0 then
				fill(vector.subtract(p, 1),
					vector.add(dp.holesize, {x=2, y=3, z=2}),
					c.wall
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
					if data[vi] == c.wall then
						data[vi] = c.stair
						param2s[vi] = facedir
					end

					vi = area:indexp(p)
					if data[vi] == c.wall then
						data[vi] = c.stair
						param2s[vi] = facedir
					end
				end
			else
				fill(vector.subtract(p, 1),
					vector.add(dp.holesize, {x=2, y=2, z=2}),
					c.wall
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


function find_place_for_door()
	for i = 0, 99 do
		local p = vector.add(m_pos, m_dir)
		local p1 = vector.add(p, {x=0, y=1, z=0})
		if not area:containsp(p)
		or not area:containsp(p1)
		or i % 4 == 0 then
			randomizeDir()
		else
			if data[area:indexp(p)] == c.wall
			and data[area:indexp(p1)] == c.wall then
				-- Found wall, this is a good place!
				-- Randomize next direction
				randomizeDir()
				return p, m_dir
			end
			--[[
				Determine where to move next
			]]
			-- Jump one up if the actual space is there
			if data[area:indexp(p)] == c.wall
			and data[area:indexp(vector.add(p, {x=0, y=1, z=0}))] == c.air
			and data[vector.add(p, {x=0, y=2, z=0}))] == c.air then
				p.y = p.y+1
			end
			-- Jump one down if the actual space is there
			if data[area:indexp(vector.add(p, {x=0, y=1, z=0}))] == c.wall
			and data[area:indexp(p)] == c.air
			and data[area:indexp(vector.add(p, {x=0, y=-1, z=0}))] == c.air then
				p.y = p.y-1
			end
			-- Check if walking is now possible
			if data[area:indexp(p)] ~= c.air
			or data[area:indexp(vector.add(p, {x=0, y=1, z=0}))] ~= c.air then
				-- Cannot continue walking here
				randomizeDir()
			else
				-- Move there
				m_pos = p
			end
		end
	end
end


function find_place_for_room_door(roomsize)
	for trycount = 0, 29 do
		local doorplace, doordir = find_place_for_door(doorplace, doordir)
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
				if flags[vi] then
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


--[[
local function rand_ortho_dir(&random, diagonal_dirs)
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
--]]


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


local function dir_to_facedir(d)
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
