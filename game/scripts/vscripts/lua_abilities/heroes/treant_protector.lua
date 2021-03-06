function CreateTree(keys)
	local caster = keys.caster
	local ability = keys.ability
	local point = ability:GetCursorPosition()
	local duration = ability:GetDuration()
	local vision_range = ability:GetTalentSpecialValueFor("vision_range")
	local trees = 8
	local radius = 150
	local angle = math.pi/4
	local dummy = CreateUnitByName("npc_dummy_unit", point, false, caster, caster, caster:GetTeam())
	ability:ApplyDataDrivenModifier(caster, dummy, "modifier_happy_little_tree_aura_ally", {duration = duration})
    ability:ApplyDataDrivenModifier(caster, dummy, "modifier_happy_little_tree_aura_enemy", {duration = duration})
	CreateTempTree(point, duration)
	ResolveNPCPositions(point, 150)
	Timers:CreateTimer(duration, function() if not dummy:IsNull() then dummy:RemoveSelf() end end)
end

function TreeCheck(keys)
	if not GridNav:IsNearbyTree(keys.target:GetAbsOrigin(), 10, false) then
        keys.target:RemoveSelf()
    end
end

function TreeDamage(keys)
	local ability = keys.ability
	local leechbase = math.abs(ability:GetTalentSpecialValueFor("leech"))
	local leech = keys.target:GetMaxHealth() * math.abs(ability:GetTalentSpecialValueFor("leech_pct") / 100)
	ability.damage_flags = DOTA_DAMAGE_FLAG_HPLOSS
	ApplyDamage({ victim = keys.target, attacker = keys.caster, damage = math.ceil(leechbase + leech) * 0.1, damage_type = DAMAGE_TYPE_PURE, ability = ability, damage_flags = DOTA_DAMAGE_FLAG_HPLOSS })
end

function ApplyLivingArmor(keys)
	local caster = keys.caster
	local ability = keys.ability
	local target = keys.target
	if not target then
		local search = ability:GetCursorPosition()
		local allies = FindUnitsInRadius(caster:GetTeamNumber(), search, nil, FIND_UNITS_EVERYWHERE, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_FLAG_NONE, FIND_CLOSEST, false)
		for _,ally in pairs(allies) do
			if ally then
				target = ally
				break
			end
		end
	end
	ability:ApplyDataDrivenModifier(caster,target, "modifier_living_armor_ebf", {duration = ability:GetTalentSpecialValueFor("duration")})
	ability:ApplyDataDrivenModifier(caster,target, "modifier_living_armor_ebf_stacks", {duration = ability:GetTalentSpecialValueFor("duration")})
	target:SetModifierStackCount("modifier_living_armor_ebf_stacks", caster, ability:GetTalentSpecialValueFor("damage_count"))
	target.oldHealth = target:GetHealth()
end

function HandleLivingArmor(keys)
	-- init --
	local caster = keys.caster
	local ability = keys.ability
	local target = keys.unit

	local damage = keys.damage
	local block = ability:GetTalentSpecialValueFor("damage_block")
	-- heal handling --
	local heal = damage
	if damage > block then heal = block end
	target:SetHealth(target:GetHealth() + heal)
	SendOverheadEventMessage( target, OVERHEAD_ALERT_BLOCK, target, heal, nil )
	target.oldHealth = target:GetHealth()
	
	-- stack handling --
	local stacks = target:GetModifierStackCount("modifier_living_armor_ebf_stacks", caster)
	if stacks - 1 == 0 then 
		target:RemoveModifierByName("modifier_living_armor_ebf")
		target:RemoveModifierByName("modifier_living_armor_ebf_stacks")
	else target:SetModifierStackCount("modifier_living_armor_ebf_stacks", caster, stacks - 1) end
end

function DoubleHeal(keys)
	local target = keys.unit
	target.oldHealth = target.oldHealth or target:GetHealth()
	local newHp = target:GetHealth()
	local ability = keys.ability
	local heal = ( newHp - target.oldHealth ) * ability:GetTalentSpecialValueFor("heal_increase") / 100
	target:SetHealth( newHp + heal )
	target.oldHealth = target:GetHealth()
end

function AddParticle(keys)
	local target = keys.target
	target.LivingArmorParticle = ParticleManager:CreateParticle("particles/units/heroes/hero_treant/treant_livingarmor.vpcf", PATTACH_POINT_FOLLOW, target)
			ParticleManager:SetParticleControlEnt(target.LivingArmorParticle, 0, target, PATTACH_POINT_FOLLOW, "attach_hitloc", target:GetAbsOrigin(), true)
			ParticleManager:SetParticleControlEnt(target.LivingArmorParticle, 1, target, PATTACH_POINT_FOLLOW, "attach_hitloc", target:GetAbsOrigin(), true)
end


function RemoveParticle(keys)
	local target = keys.target
	ParticleManager:DestroyParticle(target.LivingArmorParticle, false)
end



treant_great_protector = class({})

function treant_great_protector:GetCastRange(target, position)
	return self:GetTalentSpecialValueFor("root_aoe")
end

function treant_great_protector:OnAbilityPhaseStart()
	EmitSoundOn( "Hero_Treant.Overgrowth.CastAnim", self:GetCaster() )
	return true
end

function treant_great_protector:OnAbilityPhaseStart()
	StopSoundOn( "Hero_Treant.Overgrowth.CastAnim", self:GetCaster() )
end

--------------------------------------------------------------------------------

function treant_great_protector:OnSpellStart()
	local caster = self:GetCaster()
	
	EmitSoundOn( "Hero_Treant.NaturesGuise.On", self:GetCaster() )
	caster:AddNewModifier( caster, self, "modifier_treant_great_protector", { duration = self:GetTalentSpecialValueFor( "duration" ) } )
	
	EmitSoundOn( "Hero_Treant.Overgrowth.Cast", self:GetCaster() )
	ParticleManager:FireParticle("particles/units/heroes/hero_treant/treant_overgrowth_cast.vpcf", PATTACH_POINT_FOLLOW, caster)
	for _, unit in ipairs(caster:FindEnemyUnitsInRadius(caster:GetAbsOrigin(), self:GetTalentSpecialValueFor("root_aoe") ) ) do
		EmitSoundOn("Hero_Treant.Overgrowth.Target", unit)
		unit:AddNewModifier(caster, self, "modifier_treant_great_protector_root", {duration = self:GetTalentSpecialValueFor("root_duration")})
	end
end

--------------------------------------------------------------------------------

LinkLuaModifier( "modifier_treant_great_protector", "lua_abilities/heroes/treant_protector", LUA_MODIFIER_MOTION_NONE )
modifier_treant_great_protector = class({})

--------------------------------------------------------------------------------

function modifier_treant_great_protector:OnCreated( kv )
	self.move_speed = self:GetAbility():GetSpecialValueFor( "move_speed" )
	self.model_scale = self:GetAbility():GetSpecialValueFor( "model_scale" )
	self.bonus_strength = self:GetAbility():GetSpecialValueFor( "bonus_strength" )
	if IsServer() then
		self.nHealTicks = 0
		self:StartIntervalThink( 0.05 )
	end

end

--------------------------------------------------------------------------------

function modifier_treant_great_protector:OnRemoved()
	if IsServer() then
		local flHealth = self:GetParent():GetHealth() 
		local flMaxHealth = self:GetParent():GetMaxHealth()
		local flHealthPct = flHealth / flMaxHealth

		self:GetParent():CalculateStatBonus()

		local flNewHealth = self:GetParent():GetHealth()  
		local flNewMaxHealth = self:GetParent():GetMaxHealth()

		local flNewDesiredHealth = flNewMaxHealth * flHealthPct
		if flNewHealth ~= flNewDesiredHealth then
			self:GetParent():ModifyHealth( flNewDesiredHealth, self:GetAbility(), false, 0 )
		end	
	end
end

--------------------------------------------------------------------------------

function modifier_treant_great_protector:OnIntervalThink()
	if IsServer() then
		self:GetParent():Heal( ( self.bonus_strength * 20 ) * 0.05, self:GetAbility() )
		self.nHealTicks = self.nHealTicks + 1
		if self.nHealTicks >= 20 then
			self:StartIntervalThink( -1 )
		end
	end
end

--------------------------------------------------------------------------------

function modifier_treant_great_protector:DeclareFunctions()
	local funcs = 
	{
		MODIFIER_EVENT_ON_ATTACK_LANDED,
		MODIFIER_PROPERTY_MODEL_SCALE,
		MODIFIER_PROPERTY_EXTRA_STRENGTH_BONUS,
		MODIFIER_PROPERTY_MOVESPEED_LIMIT,
	}

	return funcs
end

--------------------------------------------------------------------------------


function modifier_treant_great_protector:OnAttackLanded( params )
	if IsServer() then
		local hTarget = params.target

		if hTarget == nil or hTarget ~= self:GetParent() then
			return 0
		end

		--EmitSoundOn( "Hero_Treant.Overgrowth.Target", hTarget )
	end
end

--------------------------------------------------------------------------------

function modifier_treant_great_protector:GetModifierModelScale( params )
	return self.model_scale
end

--------------------------------------------------------------------------------

function modifier_treant_great_protector:GetModifierExtraStrengthBonus( params )
	return self.bonus_strength
end

--------------------------------------------------------------------------------

function modifier_treant_great_protector:GetModifierMoveSpeed_Limit( params )
	return self.move_speed
end

--------------------------------------------------------------------------------

LinkLuaModifier( "modifier_treant_great_protector_root", "lua_abilities/heroes/treant_protector", LUA_MODIFIER_MOTION_NONE )
modifier_treant_great_protector_root = class({})

function modifier_treant_great_protector_root:CheckState()
	return {[MODIFIER_STATE_ROOTED] = true,
			[MODIFIER_STATE_DISARMED] = true,
			[MODIFIER_STATE_SILENCED] = true,}
end

function modifier_treant_great_protector_root:GetEffectName()
	return "particles/units/heroes/hero_lone_druid/lone_druid_bear_entangle.vpcf"
end