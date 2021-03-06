--[[
	CHoldoutGameSpawner - A single unit spawner for Holdout.
]]
if CHoldoutGameSpawner == nil then
	CHoldoutGameSpawner = class({})
end


function CHoldoutGameSpawner:ReadConfiguration( name, kv, gameRound )
	self._gameRound = gameRound
	self._dependentSpawners = {}
	
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CHoldoutGameSpawner, "OnEntityKilled" ), self )
	
	self._szChampionNPCClassName = kv.ChampionNPCName or ""
	self._szGroupWithUnit = kv.GroupWithUnit or ""
	self._szName = name
	self._szNPCClassName = kv.NPCName or ""
	self._RenderColour = kv.SetRenderColor or nil
	self._DoNotIncrease = kv.DoNotIncrease or nil
	if self._RenderColour then
		local colourTable = {}
		for token in string.gmatch(self._RenderColour, "[^%s]+") do
		   table.insert(colourTable, tonumber(token))
		end
		self._RenderColour = Vector(colourTable[1], colourTable[2], colourTable[3])
	end
	self._szSpawnerName = kv.SpawnerName or ""
	self._szWaitForUnit = kv.WaitForUnit or ""
	self._szWaypointName = kv.Waypoint or ""
	self._waypointEntity = nil
	self._nUnitsCurrentlyAlive = 0
	
	self._bDifficultyChecked = false

	self._nChampionLevel = tonumber( kv.ChampionLevel or 1 )
	self._nChampionMax = tonumber( kv.ChampionMax or 1 )
	self._nCreatureLevel = tonumber( kv.CreatureLevel or 1 )
	self._nTotalUnitsToSpawn = tonumber( kv.TotalUnitsToSpawn or 0 )
	self._nUnitsPerSpawn = tonumber( kv.UnitsPerSpawn or 0 )
	self._nUnitsPerSpawn = tonumber( kv.UnitsPerSpawn or 1 )

	self._flChampionChance = tonumber( kv.ChampionChance or 0 )
	self._flInitialWait = tonumber( kv.WaitForTime or 0 )
	self._flSpawnInterval = tonumber( kv.SpawnInterval or 5 )
	self._flReducedSpawnInterval = tonumber( kv.ReducedSpawnInterval or 5 )

	self._bDontGiveGoal = ( tonumber( kv.DontGiveGoal or 0 ) ~= 0 )
	self._bDontOffsetSpawn = ( tonumber( kv.DontOffsetSpawn or 0 ) ~= 0 )
end


function CHoldoutGameSpawner:PostLoad( spawnerList )
	self._waitForUnit = spawnerList[ self._szWaitForUnit ]
	if self._szWaitForUnit ~= "" and not self._waitForUnit then
		print( "%s has a wait for unit %s that is missing from the round data.", self._szName, self._szWaitForUnit )
	elseif self._waitForUnit then
		table.insert( self._waitForUnit._dependentSpawners, self )
	end

	self._groupWithUnit = spawnerList[ self._szGroupWithUnit ]
	if self._szGroupWithUnit ~= "" and not self._groupWithUnit then
		print ("%s has a group with unit %s that is missing from the round data.", self._szName, self._szGroupWithUnit )
	elseif self._groupWithUnit then
		table.insert( self._groupWithUnit._dependentSpawners, self )
	end
end


function CHoldoutGameSpawner:Precache()
	PrecacheUnitByNameAsync( self._szNPCClassName, function( sg ) self._sg = sg end )
	if self._szChampionNPCClassName ~= "" then
		PrecacheUnitByNameAsync( self._szChampionNPCClassName, function( sg ) self._sgChampion = sg end )
	end
end


function CHoldoutGameSpawner:Begin()
	self._nUnitsSpawnedThisRound = 0
	self._nChampionsSpawnedThisRound = 0
	self._nUnitsCurrentlyAlive = 0
	
	-- if GameRules.gameDifficulty > 3 and not self._bDifficultyChecked and not self._DoNotIncrease then
		-- local preIncrease = self._nTotalUnitsToSpawn
		-- self._nTotalUnitsToSpawn = math.ceil(self._nTotalUnitsToSpawn * 1.4)
		-- print("Units spawned increased from "..preIncrease.." to "..self._nTotalUnitsToSpawn)
		-- self._bDifficultyChecked = true
	-- end
	self._vecSpawnLocation = nil
	if self._szSpawnerName ~= "" then
		local entSpawner = Entities:FindByName( nil, self._szSpawnerName )
		if not entSpawner then
			print( string.format( "Failed to find spawner named %s for %s\n", self._szSpawnerName, self._szName ) )
		end
		self._vecSpawnLocation = entSpawner:GetAbsOrigin()
	end
	self._entWaypoint = nil
	if self._szWaypointName ~= "" and not self._bDontGiveGoal then
		self._entWaypoint = Entities:FindByName( nil, self._szWaypointName )
		if not self._entWaypoint then
			print( string.format( "Failed to find waypoint named %s for %s", self._szWaypointName, self._szName ) )
		end
	end

	if self._waitForUnit ~= nil or self._groupWithUnit ~= nil then
		self._flNextSpawnTime = nil
	else
		self._flNextSpawnTime = GameRules:GetGameTime() + self._flInitialWait
	end
end


function CHoldoutGameSpawner:End()
	if self._sg ~= nil then
		UnloadSpawnGroupByHandle( self._sg )
		self._sg = nil
	end
	if self._sgChampion ~= nil then
		UnloadSpawnGroupByHandle( self._sgChampion )
		self._sgChampion = nil
	end
end


function CHoldoutGameSpawner:ParentSpawned( parentSpawner )
	if parentSpawner == self._groupWithUnit then
		-- Make sure we use the same spawn location as parentSpawner.
		self:_DoSpawn()
	elseif parentSpawner == self._waitForUnit then
		if parentSpawner:IsFinishedSpawning() and self._flNextSpawnTime == nil then
			self._flNextSpawnTime = parentSpawner._flNextSpawnTime + self._flInitialWait
		end
	end
end


function CHoldoutGameSpawner:Think()
	if not self._flNextSpawnTime then
		return
	end
	if GameRules:GetGameTime() >= self._flNextSpawnTime and not self.loopPrevention then
		self:_DoSpawn()
		self.recheck = true
		self.loopPrevention = true
		for _,s in pairs( self._dependentSpawners ) do
			s:ParentSpawned( self )
		end

		if self:IsFinishedSpawning() then
			self._flNextSpawnTime = nil
		else
			self._flNextSpawnTime = self._flNextSpawnTime + math.max(self._flSpawnInterval, 5)
		end
	elseif self._nUnitsCurrentlyAlive == 0 and self.recheck and self._nUnitsSpawnedThisRound > 0 then -- skip initial spawn being pushed too fasr
		self._flNextSpawnTime = GameRules:GetGameTime() + self._flReducedSpawnInterval
		self.recheck = false
	elseif self.loopPrevention then
		self.loopPrevention = false
	end
end


function CHoldoutGameSpawner:GetTotalUnitsToSpawn()
	return self._nTotalUnitsToSpawn
end


function CHoldoutGameSpawner:IsFinishedSpawning()
	return ( self._nTotalUnitsToSpawn <= self._nUnitsSpawnedThisRound ) or ( self._groupWithUnit ~= nil )
end


function CHoldoutGameSpawner:_GetSpawnLocation()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetSpawnLocation()
	else
		return self._vecSpawnLocation
	end
end


function CHoldoutGameSpawner:_GetSpawnWaypoint()
	if self._groupWithUnit then
		return self._groupWithUnit:_GetSpawnWaypoint()
	else
		return self._entWaypoint
	end
end


function CHoldoutGameSpawner:_UpdateRandomSpawn()
	self._vecSpawnLocation = Vector( 0, 0, 0 )
	self._entWaypoint = nil

	local spawnInfo = self._gameRound:ChooseRandomSpawnInfo()
	if spawnInfo == nil then
		print( string.format( "Failed to get random spawn info for spawner %s.", self._szName ) )
		return
	end
	
	local entSpawner = Entities:FindByName( nil, spawnInfo.szSpawnerName )
	if not entSpawner then
		print( string.format( "Failed to find spawner named %s for %s.", spawnInfo.szSpawnerName, self._szName ) )
		return
	end
	self._vecSpawnLocation = entSpawner:GetAbsOrigin()

	if not self._bDontGiveGoal then
		self._entWaypoint = Entities:FindByName( nil, spawnInfo.szFirstWaypoint )
		if not self._entWaypoint then
			print( string.format( "Failed to find a waypoint named %s for %s.", spawnInfo.szFirstWaypoint, self._szName ) )
			return
		end
	end
end


function CHoldoutGameSpawner:_DoSpawn()
	local nUnitsToSpawn = math.min( self._nUnitsPerSpawn, self._nTotalUnitsToSpawn - self._nUnitsSpawnedThisRound )

	if nUnitsToSpawn <= 0 then
		return
	elseif self._nUnitsSpawnedThisRound == 0 then
		print( string.format( "Started spawning %s at %.2f", self._szName, GameRules:GetGameTime() ) )
	end

	if self._szSpawnerName == "" then
		self:_UpdateRandomSpawn()
	end

	local vBaseSpawnLocation = self:_GetSpawnLocation()
	if not vBaseSpawnLocation then return end
	for iUnit = 1, nUnitsToSpawn do
		local bIsChampion = RollPercentage( self._flChampionChance )
		if self._nChampionsSpawnedThisRound >= self._nChampionMax then
			bIsChampion = false
		end

		local szNPCClassToSpawn = self._szNPCClassName
		if bIsChampion and self._szChampionNPCClassName ~= "" then
			szNPCClassToSpawn = self._szChampionNPCClassName
		end

		local vSpawnLocation = vBaseSpawnLocation
		if not self._bDontOffsetSpawn then
			vSpawnLocation = vSpawnLocation + RandomVector( RandomFloat( 0, 200 ) )
		end
		local entUnit = CreateUnitByName( szNPCClassToSpawn, vSpawnLocation, true, nil, nil, DOTA_TEAM_BADGUYS )
		Timers:CreateTimer(0, function() 
			for i = 0, 20 do
				local ability = entUnit:GetAbilityByIndex(i)
				if ability then
					PrecacheItemByNameAsync( ability:GetName(), function() end )
				end
			end
		end)
		AddFOWViewer(DOTA_TEAM_GOODGUYS, vSpawnLocation, 516, 3, false) -- show spawns
		if entUnit then
			if entUnit:IsCreature() then
				if bIsChampion then
					self._nChampionsSpawnedThisRound = self._nChampionsSpawnedThisRound + 1
					entUnit:CreatureLevelUp( ( self._nChampionLevel - 1 ) )
					entUnit:SetChampion( true )
					local nParticle = ParticleManager:CreateParticle( "heavens_halberd", PATTACH_ABSORIGIN_FOLLOW, entUnit )
					ParticleManager:ReleaseParticleIndex( nParticle )
					entUnit:SetModelScale( 1.1, 0 )
				else
					entUnit:CreatureLevelUp( self._nCreatureLevel - 1 )
					if self._RenderColour then
						entUnit:SetRenderColor(self._RenderColour.x, self._RenderColour.y, self._RenderColour.z)
					end
				end
			end

			local entWp = self:_GetSpawnWaypoint()
			if entWp ~= nil and not GetMapName() == "epic_boss_fight_boss_master" then
				entUnit:SetInitialGoalEntity( entWp )
			end
			self._nUnitsSpawnedThisRound = self._nUnitsSpawnedThisRound + 1
			self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive + 1
			entUnit.Holdout_IsCore = true
			entUnit:SetDeathXP( 0 )
		end
	end
end

function CHoldoutGameSpawner:OnEntityKilled( event )
	local killedUnit = EntIndexToHScript( event.entindex_killed )
	self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive or 0
	if not killedUnit and not killedUnit.Holdout_IsCore then
		return
	elseif killedUnit.Holdout_IsCore and self._nUnitsCurrentlyAlive > 0 then
		self._nUnitsCurrentlyAlive = self._nUnitsCurrentlyAlive - 1
	end
end


function CHoldoutGameSpawner:StatusReport()
	print( string.format( "** Spawner %s", self._szNPCClassName ) )
	print( string.format( "%d of %d spawned", self._nUnitsSpawnedThisRound, self._nTotalUnitsToSpawn ) )
end