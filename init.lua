
--NoiseParams nparams_dungeon_density(0.9, 0.5, v3f(500.0, 500.0, 500.0), 0, 2, 0.8, 2.0)
--NoiseParams nparams_dungeon_alt_wall(-0.4, 1.0, v3f(40.0, 40.0, 40.0), 32474, 6, 1.1, 2.0)


local c = {}
c.water       = minetest.get_content_id("default:water_source")
c.river_water = minetest.get_content_id("default:river_water_source")
c.wall        = minetest.get_content_id("default:cobble")
c.alt_wall    = minetest.get_content_id("default:mossycobble")
c.stair       = minetest.get_content_id("mapgen_stair_cobble")

DungeonGen(ndef, gennotify, *dparams)

	if (dparams) {
		memcpy(&dp, dparams, sizeof(dp))
	} else {
		dp.seed = 0


		dp.diagonal_dirs = false
		dp.holesize      = {x=1, 2, 1)
		dp.roomsize      = {x=0, 0, 0)
		dp.rooms_min     = 2
		dp.rooms_max     = 16
		dp.y_min         = -MAX_MAP_GENERATION_LIMIT
		dp.y_max         = MAX_MAP_GENERATION_LIMIT
		dp.notifytype    = GENNOTIFY_DUNGEON

		dp.np_density  = nparams_dungeon_density
		dp.np_alt_wall = nparams_dungeon_alt_wall
	}
}

local pr
local function generate(vm, bseed, nmin, nmax)
	if nmin.y < dp.y_min
	or nmax.y > dp.y_max then
		return
	end

	local nval_density = NoisePerlin3D(&dp.np_density, nmin.x, nmin.y, nmin.z, dp.seed)
	if nval_density < 1.0f then
		return
	end

	pr = PseudoRandom(bseed + 2)

	-- Set all air and water to be untouchable
	-- to make dungeons open to caves and open air
	local flags = {}
	for i in area:iterp(nmin, nmax) do
		local id = data[i]
		if id == c.air
		or id == c.water
		or id == c.river_water then
			flags[i] = false
		end
	end

	-- Add them
	for _ = 1, math.floor(nval_density) do
		makeDungeon(vector.new(MAP_BLOCKSIZE))
	end

	-- Optionally convert some structure to alternative structure
	if c.alt_wall == CONTENT_IGNORE
		return
	end

	for i in area:iterp(nmin, nmax) do
		if data[i] == c.wall
		and NoisePerlin3D(&dp.np_alt_wall, x, y, z, blockseed) > 0 then
			data[i] = c.alt_wall
		end
	end
end


local function makeDungeon(start_padding)
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
				for x = 0, roomsize.x-1 do{
					local p = roomplace + {x=x, y, z)
					local vi = area:index(roomplace.x + x, roomplace.y + y, roomplace.z + z)
					if flags[vi] == false
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
		makeRoom(roomsize, roomplace)

		local room_center = vector.add(roomplace, {x = math.floor(roomsize.x * .5), y = 1, z = math.floor(roomsize.z * .5))

		if DGEN_USE_TORCHES then
			-- Place torch at room center (for testing)
			data[area:indexp(room_center)] = c.torch
		end

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
		if not findPlaceForDoor(doorplace, doordir) then
			return
		end

		if pr:next(0, 1) == 0 then
			-- Make the door
			makeDoor(doorplace, doordir)
		else
			-- Don't actually make a door
			doorplace = vector.subtract(doorplace, doordir)
		end

		-- Make a random corridor starting from the door
		local corridor_end
		local corridor_end_dir
		makeCorridor(doorplace, doordir, corridor_end, corridor_end_dir)

		-- Find a place for a random sized room
		roomsize.z = pr:next(4, 8)
		roomsize.y = pr:next(4, 6)
		roomsize.x = pr:next(4, 8)
		roomsize = vector.add(dp.roomsize, roomsize)

		m_pos = corridor_end
		m_dir = corridor_end_dir
		if not findPlaceForRoomDoor(roomsize, doorplace, doordir, roomplace) then
			return
		end

		if pr:next(0, 1) == 0 then
			-- Make the door
			makeDoor(doorplace, doordir)
		else
			-- Don't actually make a door
			roomplace = vector.subtract(roomplace, doordir)
		end
	end
end


local function makeRoom(roomsize, roomplace)
	-- Make walls
	for vi in area:iterp_hollowcuboid(roomplace, vector.add(roomplace, vector.subtract(roomsize, 1))) do
		if flags[vi] ~= false then
			data[vi] = c.wall
		end
	end

	-- Fill with air
	for vi in area:iterp(vector.add(roomplace, 1), vector.add(roomplace, vector.subtract(roomsize, 2))) do
		flags[vi] = false
		data[vi] = n_air
	end
end


local function makeFill(place, size, u8 avoid_flags, id, u8 or_flags)
	for vi in area:iterp(place, vector.add(place, vector.subtract(size, 1))) do
		if flags[vi] ~= false then
			flags[vi] = or_flags
			data[vi] = id
		end
	end
end


local function makeHole(place)
	makeFill(place, dp.holesize, 0, c.air,
		VMANIP_FLAG_DUNGEON_INSIDE)
end


local function makeDoor(doorplace, doordir)
	makeHole(doorplace)
end


local function makeCorridor(doorplace, doordir, &result_place, &result_dir)
	makeHole(doorplace)
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

		if (area:contains(p) && area:contains(p + {x=0, 1, 0)) &&
				area:contains({x=p.x - dir.x, p.y - 1, p.z - dir.z))) {
			if make_stairs ~= 0 then
				makeFill(vector.subtract(p, 1),
					vector.add(dp.holesize, {x=2, y=3, z=2}),
					VMANIP_FLAG_DUNGEON_UNTOUCHABLE,
					c.wall
				)
				makeHole(p)
				makeHole(vector.subtract(p, dir))

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
				makeFill(vector.subtract(p, 1),
					vector.add(dp.holesize, {x=2, y=2, z=2}),
					VMANIP_FLAG_DUNGEON_UNTOUCHABLE,
					c.wall
				)
				makeHole(p)
			end

			p0 = p


			partcount = partcount+1
			if partcount >= partlength then
				partcount = 0

				dir = random_turn(random, dir)

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
	result_place = p0
	result_dir = dir
end


local function findPlaceForDoor(&result_place, &result_dir)
	for i = 0, 99 do
		local p = vector.add(m_pos, m_dir)
		local p1 = vector.add(p, {x=0, y=1, z=0})
		if not area:contains(p)
		or not area:contains(p1)
		or i % 4 == 0 then
			randomizeDir()
		else
			if data[area:indexp(p)] == c.wall
			and data[area:indexp(p1)] == c.wall then
				-- Found wall, this is a good place!
				result_place = p
				result_dir = m_dir
				-- Randomize next direction
				randomizeDir()
				return true
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
	return false
end


local function findPlaceForRoomDoor(roomsize, &result_doorplace, &result_doordir, &result_roomplace)
	for trycount = 0, 29 do
		local doorplace
		local doordir
		local r = findPlaceForDoor(doorplace, doordir)
		if r ~= false then
			local roomplace
			-- X east, Z north, Y up
	#if 1
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
	#endif
	#if 0
			if (doordir == {x=1, 0, 0)) -- X+ roomplace = doorplace + {x=0, -1, -roomsize.z / 2)
			if (doordir == {x=-1, 0, 0)) -- X-
				roomplace = doorplace + {x=-roomsize.x+1,-1,-roomsize.z / 2)
			if (doordir == {x=0, 0, 1)) -- Z+ roomplace = doorplace + {x=-roomsize.x / 2, -1, 0)
			if (doordir == {x=0, 0, -1)) -- Z-
				roomplace = doorplace + {x=-roomsize.x / 2, -1, -roomsize.z + 1)
	#endif

			-- Check fit
			local fits = true
			for vi in area:iterp(vector.add(roomplace, 1), vector.add(roomplace, vector.subtract(roomsize, 2))) do
				if flags[vi] == false then
					fits = false
					break
				end
			end
			if fits then
				result_doorplace = doorplace
				result_doordir   = doordir
				result_roomplace = roomplace
				return true
			end
		end
	end
	return false
end


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


local function turn_xz(olddir, t)
	if t == 0 then
		-- Turn right
		return {x=olddir.z, y=olddir.y, z=-olddir.x}
	end
	-- Turn left
	return {x=-olddir.z, y=olddir.y, z=olddir.x}
end


local function random_turn(&random, olddir)
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
