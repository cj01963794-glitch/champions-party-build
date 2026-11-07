#===============================================================================
# Battle Simulation: Deep-copy once, restore in-place for subsequent sims.
#
# The first create_battle_copy call per decision cycle deep-copies the real
# Battle and builds a mapping (real object_id → sim object).  Subsequent
# calls restore the cached sim from the real battle by walking the mapping
# and overwriting ivars/contents — no new object allocation.
#===============================================================================

class Battle::AI
  # Symbol used with throw/catch to abort simulation on forced switch attempts.
  SIM_SWITCH_TRIGGERED = :sim_switch_triggered

  # Minimum interval between scene ticks during AI computation (~7 FPS).
  TICK_INTERVAL = 0.01

  #=============================================================================
  # SilentScene: No-op scene for simulation.
  #=============================================================================
  class NullSprite
    attr_accessor :speed, :reversed, :substitute, :visible
    attr_accessor :x, :y, :z, :ox, :oy, :zoom_x, :zoom_y, :opacity

    def initialize
      @speed = 0
      @reversed = false
      @substitute = false
      @visible = false
      @x = @y = @z = @ox = @oy = 0
      @zoom_x = @zoom_y = 1
      @opacity = 0
    end

    def iconBitmap; self; end
    def disposed?; false; end
    def update; nil; end
    def deanimate; nil; end
    def dispose; nil; end
    def method_missing(_method, *_args, &_block); nil; end
    def respond_to_missing?(_method, _include_private = false); true; end
  end

  class SilentScene
    def pbGetBattlerSprites(_idxBattler)
      @_null_sprite ||= NullSprite.new
      return @_null_sprite, @_null_sprite
    end

    def method_missing(_method, *_args, &_block); nil; end
    def respond_to_missing?(_method, _include_private = false); true; end
  end

  #---------------------------------------------------------------------------
  # Tick the battle scene to keep sprites and animations alive during AI.
  # Throttled so Graphics.update overhead doesn't dominate computation.
  #---------------------------------------------------------------------------
  def tick_scene
    now = System.uptime
    # return if @_last_tick && (now - @_last_tick) < TICK_INTERVAL
    @_last_tick = now
    scene = @battle.scene
    return unless scene.is_a?(Battle::Scene)
    scene.pbGraphicsUpdate
    scene.pbFrameUpdate
  end

  #---------------------------------------------------------------------------
  # Show/hide a "..." thinking indicator in the message window.
  #---------------------------------------------------------------------------
  def show_thinking_indicator
    scene = @battle.scene
    return unless scene.is_a?(Battle::Scene)
    scene.pbShowWindow(Battle::Scene::MESSAGE_BOX)
    msgw = scene.sprites["messageWindow"]
    return unless msgw
    msgw.letterbyletter = false
    msgw.setText("...")
    msgw.letterbyletter = true
    @_thinking_shown = true
    tick_scene
  end

  def hide_thinking_indicator
    return unless @_thinking_shown
    scene = @battle.scene
    return unless scene.is_a?(Battle::Scene)
    msgw = scene.sprites["messageWindow"]
    msgw&.text = ""
    @_thinking_shown = false
  end

  #---------------------------------------------------------------------------
  # Return a battle copy for simulation.  First call per decision cycle does
  # a full deep copy and caches the result + object mapping.  Subsequent
  # calls restore the cached copy in-place from the real battle.
  #---------------------------------------------------------------------------
  def create_battle_copy
    tick_scene
    cache_key = [@battle.turnCount, @user&.index]
    if @_sim_template && @_sim_cache_key == cache_key
      restore_sim_from_real
      reset_sim_choices
      @_sim_template.ai_restore_sim_zmove_base_moves if @_sim_template.respond_to?(:ai_restore_sim_zmove_base_moves)
      tick_scene
      return @_sim_template
    end
    # Full deep copy + build real→sim mapping
    @_real_to_sim = {}
    saved_scene = @battle.instance_variable_get(:@scene)
    @battle.instance_variable_set(:@scene, nil)
    begin
      @_sim_template = deep_copy(@battle, @_real_to_sim)
    ensure
      @battle.instance_variable_set(:@scene, saved_scene)
    end
    @_sim_template.instance_variable_set(:@scene, SilentScene.new)
    @_sim_template.instance_variable_set(:@is_simulation, true)
    # Abort simulation on any switch attempt, but preserve whether it was a
    # faint replacement or a live battler leaving mid-turn.
    sim = @_sim_template
    def sim.pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
      pivot_choice = @_sim_pivot_replacement
      if pivot_choice && pivot_choice[0] == idxBattler
        pivot_choice[2] = true
        @_sim_pivot_replacement = nil
        return pivot_choice[1]
      end
      battler = @battlers[idxBattler]
      reason = if @endOfRound || (battler && battler.fainted?)
                 :replacement
               else
                 :live_switch
               end
      throw Battle::AI::SIM_SWITCH_TRIGGERED, { reason: reason, battler_index: idxBattler }
    end
    def sim.pbRecallAndReplace(idxBattler, idxParty, randomReplacement = false, batonPass = false)
      if randomReplacement
        throw Battle::AI::SIM_SWITCH_TRIGGERED,
              { reason: :live_switch, battler_index: idxBattler, party_index: idxParty }
      end
      super
    end
    reset_sim_choices
    @_sim_template.ai_restore_sim_zmove_base_moves if @_sim_template.respond_to?(:ai_restore_sim_zmove_base_moves)
    @_sim_cache_key = cache_key
    @_sim_template
  end

  # Build an independent battle snapshot for move scoring. Unlike
  # create_battle_copy, this snapshot is never cached as a battle simulation
  # template; nested damage simulations may safely make their own copies of it.
  def create_scoring_battle_copy
    tick_scene
    mapping = {}
    saved_scene = @battle.instance_variable_get(:@scene)
    @battle.instance_variable_set(:@scene, nil)
    begin
      scoring_battle = deep_copy(@battle, mapping)
    ensure
      @battle.instance_variable_set(:@scene, saved_scene)
    end
    scoring_battle.instance_variable_set(:@scene, SilentScene.new)
    scoring_battle.instance_variable_set(:@is_simulation, true)
    scoring_battle
  end

  # Temporarily point the existing AI wrappers at a copied battle. Battler
  # wrappers and decision caches are restored after the block.
  def with_scoring_battle(scoring_battle, idxBattler)
    saved_battle  = @battle
    saved_trainer = @trainer
    saved_user    = @user
    saved_target  = @target
    saved_move    = @move
    reset_decision_caches
    @battle = scoring_battle
    @move = AIMove.new(self)
    set_up(idxBattler)
    yield
  ensure
    @battle  = saved_battle if saved_battle
    @trainer = saved_trainer
    @user    = saved_user
    @target  = saved_target
    @move    = saved_move
    @battlers.each { |b| b.refresh_battler if b } if @battlers
    reset_decision_caches
  end

  # Blank every sim choice so an ally AI's already-committed move/switch in
  # the real battle does not carry into sims for the next AI decider. Every
  # simulate_battle / create_switched_sim caller explicitly sets the choices
  # it needs (user_index and target_index), so starting from :None is safe.
  def reset_sim_choices
    return unless @_sim_template
    @_sim_template.battlers.each_with_index do |_b, i|
      @_sim_template.pbClearChoice(i)
    end
  end

  # Invalidate the sim template cache (called on forced switches, etc.)
  def invalidate_sim_cache
    @_sim_template = nil
    @_real_to_sim = nil
    @_sim_cache_key = nil
  end

  # Scope AI-only caches to a single decision so they don't accumulate across
  # the whole battle while still being shared by nested simulations.
  def with_decision_cache
    @_decision_cache_depth ||= 0
    reset_decision_caches(true) if @_decision_cache_depth == 0
    @_decision_cache_depth += 1
    yield
  ensure
    @_decision_cache_depth = [(@_decision_cache_depth || 1) - 1, 0].max
    reset_decision_caches(true) if @_decision_cache_depth == 0
  end

  def reset_decision_caches(clear_tera_actions = false)
    @_ai_dmg_cache = nil
    @_matchup_cache = nil
    @_replacement_score_cache = nil
    @_replacement_1v1_results = nil
    @_tera_foe_actions = nil if clear_tera_actions
    invalidate_sim_cache
  end

  private

  #---------------------------------------------------------------------------
  # Deep copy that builds a mapping from real object_id → sim object.
  # The mapping is used both for cycle detection during copy and for
  # in-place restoration on subsequent simulation calls.
  #---------------------------------------------------------------------------
  def deep_copy(obj, mapping)
    case obj
    when nil, true, false, Numeric, Symbol, Method, Proc
      return obj
    end
    return mapping[obj.object_id] if mapping.key?(obj.object_id)

    case obj
    when String
      copy = obj.dup
      mapping[obj.object_id] = copy
      return copy
    when Array
      copy = []
      mapping[obj.object_id] = copy
      obj.each { |e| copy << deep_copy(e, mapping) }
    when Hash
      copy = {}
      mapping[obj.object_id] = copy
      entries = obj.to_a
      entries.each { |k, v| copy[deep_copy(k, mapping)] = deep_copy(v, mapping) }
    else
      copy = obj.class.allocate
      mapping[obj.object_id] = copy
      obj.instance_variables.each do |ivar|
        tick_scene
        copy.instance_variable_set(ivar, deep_copy(obj.instance_variable_get(ivar), mapping))
      end
    end
    tick_scene
    copy
  end

  #---------------------------------------------------------------------------
  # Restore the cached sim template from the real battle's current state.
  # Walks the real battle's object graph via the mapping and overwrites
  # each sim object's state without allocating new objects.
  #---------------------------------------------------------------------------
  def restore_sim_from_real
    saved_scene = @battle.instance_variable_get(:@scene)
    @battle.instance_variable_set(:@scene, nil)
    begin
      restore_object(@battle, @_real_to_sim, {})
    ensure
      @battle.instance_variable_set(:@scene, saved_scene)
    end
    @_sim_template.instance_variable_set(:@scene, SilentScene.new)
    @_sim_template.instance_variable_set(:@is_simulation, true)
  end

  #---------------------------------------------------------------------------
  # Recursively restore a sim object's state from its real counterpart.
  # - Strings: replace contents
  # - Arrays/Hashes: clear and rebuild with mapped references
  # - Objects: overwrite ivars with mapped values, remove stale ivars
  #---------------------------------------------------------------------------
  def restore_object(real_obj, mapping, visited)
    case real_obj
    when nil, true, false, Numeric, Symbol, Method, Proc
      return
    end
    return if visited.key?(real_obj.object_id)
    sim_obj = mapping[real_obj.object_id]
    return unless sim_obj
    visited[real_obj.object_id] = true

    case real_obj
    when String
      sim_obj.replace(real_obj)
    when Array
      sim_obj.clear
      real_obj.each do |elem|
        sim_obj << (mapping[elem.object_id] || elem)
        restore_object(elem, mapping, visited)
      end
    when Hash
      sim_obj.clear
      real_obj.each do |k, v|
        sim_obj[mapping[k.object_id] || k] = mapping[v.object_id] || v
        restore_object(k, mapping, visited)
        restore_object(v, mapping, visited)
      end
    else
      real_obj.instance_variables.each do |ivar|
        tick_scene
        real_val = real_obj.instance_variable_get(ivar)
        sim_obj.instance_variable_set(ivar, mapping[real_val.object_id] || real_val)
        restore_object(real_val, mapping, visited)
      end
      # Remove ivars that were added during previous simulation
      extra = sim_obj.instance_variables - real_obj.instance_variables
      extra.each { |ivar| sim_obj.remove_instance_variable(ivar) } unless extra.empty?
    end
  end
end

#===============================================================================
# Primal weather constants
#===============================================================================
PRIMAL_WEATHERS = [:HarshSun, :HeavyRain, :StrongWinds].freeze

#===============================================================================
# Simulation support: expose is_simulation flag on Battle.
#===============================================================================
class Battle
  attr_accessor :is_simulation

  alias ai_sim_pbMegaEvolve pbMegaEvolve
  def pbMegaEvolve(idxBattler)
    return ai_sim_pbMegaEvolve(idxBattler) if !@is_simulation
    battler = @battlers[idxBattler]
    return if !battler&.pokemon || !battler.hasMega? || battler.mega?
    old_ability = battler.ability_id
    battler.pokemon.makeMega
    battler.form_update(true)
    side = battler.idxOwnSide
    owner = pbGetOwnerIndexFromBattlerIndex(idxBattler)
    @megaEvolution[side][owner] = -2
    battler.pbOnLosingAbility(old_ability)
    battler.pbTriggerAbilityOnGainingIt
    pbCalculatePriority(false, [idxBattler]) if Settings::RECALCULATE_TURN_ORDER_AFTER_MEGA_EVOLUTION
  end

  def ai_restore_sim_zmove_base_moves
    return if !@is_simulation
    allBattlers.each do |battler|
      next if !battler.respond_to?(:baseMoves) || battler.baseMoves.empty?
      restored = false
      battler.moves.each_with_index do |move, i|
        next if !move&.respond_to?(:zMove?) || !move.zMove?
        base_move = battler.baseMoves[i]
        next if !base_move
        battler.moves[i] = base_move
        restored = true
      end
      next if !restored
      battler.baseMoves.clear
      battler.selectedMoveIsZMove = false if battler.respond_to?(:selectedMoveIsZMove=)
    end
  end

  alias ai_sim_pbShowAbilitySplash pbShowAbilitySplash
  def pbShowAbilitySplash(battler, delay = false, logTrigger = true)
    if @is_simulation
      PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}") if logTrigger
      return
    end
    ai_sim_pbShowAbilitySplash(battler, delay, logTrigger)
  end

  alias ai_sim_pbHideAbilitySplash pbHideAbilitySplash
  def pbHideAbilitySplash(battler)
    return if @is_simulation
    ai_sim_pbHideAbilitySplash(battler)
  end
end

#===============================================================================
# Suppress low-chance crits during AI simulations.
# Only allow crit checks when the crit rate is >= 50% (ratio <= 2, i.e. stage 2+),
# while preserving normal randomness for those allowed crit stages.
# This prevents lucky RNG from skewing AI damage predictions.
#===============================================================================
class Battle::Move
  alias _orig_pbIsCritical pbIsCritical?
  def pbIsCritical?(user, target)
    if @battle.is_simulation
      return false if target.pokemon.immunities.include?(:CRITICALHIT)
      return false if target.pbOwnSide.effects[PBEffects::LuckyChant] > 0
      c = 0
      if c >= 0 && user.abilityActive?
        c = Battle::AbilityEffects.triggerCriticalCalcFromUser(user.ability, user, target, c)
      end
      if c >= 0 && target.abilityActive? && !@battle.moldBreaker
        c = Battle::AbilityEffects.triggerCriticalCalcFromTarget(target.ability, user, target, c)
      end
      if c >= 0 && user.itemActive?
        c = Battle::ItemEffects.triggerCriticalCalcFromUser(user.item, user, target, c)
      end
      if c >= 0 && target.itemActive?
        c = Battle::ItemEffects.triggerCriticalCalcFromTarget(target.item, user, target, c)
      end
      return false if c < 0
      # Move-specific overrides (always/never crit)
      case pbCritialOverride(user, target)
      when 1  then return true
      when -1 then return false
      end
      # Guaranteed-crit effects
      return true if c > 50   # Merciless
      return true if user.effects[PBEffects::LaserFocus] > 0
      # Compute final crit stage (DBK uses crit_stage_bonuses)
      c += crit_stage_bonuses(user)
      ratios = CRITICAL_HIT_RATIOS
      c = ratios.length - 1 if c >= ratios.length
      return false if ratios[c] > 2
      return true if ratios[c] == 1
      r = @battle.pbRandom(ratios[c])
      return true if r == 0
    end
    _orig_pbIsCritical(user, target)
  end
end

#===============================================================================
# Suppress misses for moves with >= 70% accuracy during AI simulations.
#===============================================================================
class Battle::Move
  alias _orig_pbBaseAccuracy pbBaseAccuracy
  def pbBaseAccuracy(user, target)
    acc = _orig_pbBaseAccuracy(user, target)
    if @battle && @battle.is_simulation && acc >= 70
      # 0 = always hits for some reason
      return 0
    end
    return acc
  end
end

#===============================================================================
# Suppress low-chance additional effects during AI simulations.
# Secondary effects below 50% are treated as never occurring, while effects with
# 50%+ odds keep their normal randomness.
#===============================================================================
class Battle::Move
  alias _orig_pbAdditionalEffectChance pbAdditionalEffectChance
  def pbAdditionalEffectChance(user, target, effectChance = 0)
    chance = _orig_pbAdditionalEffectChance(user, target, effectChance)
    if @battle && @battle.is_simulation && chance > 0 && chance < 50
      return 0
    end
    return chance
  end
end

#===============================================================================
# Suppress random damage variance during AI simulations.
# Uses a fixed midpoint (92/100) instead of random 85-100 for consistent
# damage estimates in pbCalcDamage calls.
#===============================================================================
class Battle::Move
  alias _orig_pbCalcDamageMults_Random pbCalcDamageMults_Random
  def pbCalcDamageMults_Random(user, target, numTargets, type, baseDmg, multipliers)
    if @battle && @battle.is_simulation
      # Critical hits (reuse existing sim crit logic via pbIsCritical?)
      if target.damageState.critical
        if Settings::NEW_CRITICAL_HIT_RATE_MECHANICS
          multipliers[:final_damage_multiplier] *= 1.5
        else
          multipliers[:final_damage_multiplier] *= 2
        end
      end
      # Fixed variance instead of random
      if !self.is_a?(Battle::Move::Confusion)
        multipliers[:final_damage_multiplier] *= 92 / 100.0
      end
      return
    end
    _orig_pbCalcDamageMults_Random(user, target, numTargets, type, baseDmg, multipliers)
  end
end

#===============================================================================
# Allow Sucker Punch (FailsIfTargetActed) to succeed during pure damage checks
# where the opponent's action is forced to [:None] in the simulation.
#===============================================================================
class Battle::Move::FailsIfTargetActed < Battle::Move
  if !method_defined?(:_orig_pbFailsAgainstTarget?)
    alias _orig_pbFailsAgainstTarget? pbFailsAgainstTarget?
    def pbFailsAgainstTarget?(user, target, show_message)
      if @battle && @battle.is_simulation && @battle.choices[target.index][0] == :None
        return false
      end
      return _orig_pbFailsAgainstTarget?(user, target, show_message)
    end
  end
end
