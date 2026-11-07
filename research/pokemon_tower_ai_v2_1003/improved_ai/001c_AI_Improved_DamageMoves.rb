#===============================================================================
# [AI_Improved_DamageMoves.rb] - Damage Caching, Damage Move Selection
# Uses actual battle simulation via deep copies.
#===============================================================================

class Battle::AI
  def zmove_available_for_battler_index?(idxBattler)
    battler = @battle.battlers[idxBattler]
    return false unless battler
    return false if @user && battler.idxOwnSide != @user.side
    return false if $game_switches[Settings::NO_ZMOVE]
    return false unless @battle.pbHasZRing?(idxBattler)
    return false if battler.effects[PBEffects::SkyDrop] >= 0
    side  = battler.idxOwnSide
    owner = @battle.pbGetOwnerIndexFromBattlerIndex(idxBattler)
    @battle.zMove[side][owner] == -1
  rescue StandardError
    false
  end

  def _damage_entry_key(base_move, move)
    return base_move.id unless move.respond_to?(:zMove?) && move.zMove?
    [:zmove, base_move.id, move.id]
  end

  def _damage_entry_action(base_move, move, dynamax_base_move_id = nil)
    return { move_id: base_move.id, zmove: true } if move.respond_to?(:zMove?) && move.zMove?
    if dynamax_base_move_id && move.respond_to?(:dynamaxMove?) && move.dynamaxMove?
      return {
        move_id: move.id,
        base_move_id: dynamax_base_move_id,
        dynamax: true
      }
    end
    base_move.id
  end

  def _build_damage_entry(base_move, move, dmg, dynamax_base_move_id = nil)
    {
      key: _damage_entry_key(base_move, move),
      move: move,
      base_move: base_move,
      dmg: dmg,
      zmove: move.respond_to?(:zMove?) && move.zMove?,
      action: _damage_entry_action(base_move, move, dynamax_base_move_id)
    }
  end

  def _dynamax_base_move_id(battler, move)
    return nil unless move&.dynamaxMove?
    return nil unless battler.respond_to?(:baseMoves) && !battler.baseMoves.empty?

    move_index = move.index if move.respond_to?(:index)
    if !move_index.is_a?(Integer) || move_index < 0 ||
       battler.moves[move_index]&.id != move.id
      move_index = nil
    end
    move_index ||= battler.moves.index(move)
    move_index ||= battler.moves.index { |candidate| candidate&.id == move.id }
    battler.baseMoves[move_index]&.id if move_index
  end

  def _compatible_damaging_zmove(base_move, holder, battle, battler_index = nil)
    return nil if !base_move || !holder
    return nil unless base_move.respond_to?(:damagingMove?) && base_move.damagingMove?
    return nil unless battler_index && zmove_available_for_battler_index?(battler_index)

    item_id = holder.respond_to?(:item_id) ? holder.item_id : holder.item
    return nil unless item_id
    item = GameData::Item.try_get(item_id)
    return nil unless item&.is_zcrystal?

    pkmn =
      if holder.is_a?(Battle::Battler)
        holder.effects[PBEffects::TransformPokemon] || holder.pokemon
      elsif holder.respond_to?(:battler) && holder.battler.is_a?(Battle::Battler)
        holder.battler.effects[PBEffects::TransformPokemon] || holder.battler.pokemon
      elsif holder.respond_to?(:pokemon)
        holder.pokemon
      else
        holder
      end
    return nil unless pkmn

    new_id = base_move.get_compatible_zmove(item, pkmn)
    return nil unless new_id

    zmove = base_move.make_zmove(new_id, battle)
    return nil unless zmove&.damagingMove?
    zmove
  rescue StandardError
    nil
  end

  def zmove_cache_allowed_for_battler_index?(idxBattler)
    battler = @battle.battlers[idxBattler]
    return false unless battler
    battler.idxOwnSide == @user.side
  rescue StandardError
    false
  end

  def _each_damage_option(move_source, calc_holder, battle, battler_index: nil, can_choose: nil)
    Array(move_source).compact.each do |base_move|
      next unless base_move&.damagingMove?
      next if can_choose && !can_choose.call(base_move)

      yield base_move, base_move

      next unless battler_index && zmove_cache_allowed_for_battler_index?(battler_index)
      zmove = _compatible_damaging_zmove(base_move, calc_holder, battle, battler_index)
      next unless zmove
      yield base_move, zmove
    end
  end

  def simulation_action_for_move_data(move_data)
    return nil unless move_data
    move_data[:action]
  end

  def damage_entry_for_move(attacker, defender, move, dmg_data = nil)
    return nil unless attacker && defender && move
    dmg_data ||= damage_moves(attacker, defender)
    return nil unless dmg_data

    entry = dmg_data[move.id]
    return entry if entry

    return nil unless move.respond_to?(:zMove?) && move.zMove?
    dmg_data.each_value do |candidate|
      next unless candidate[:zmove]
      return candidate if candidate[:move]&.id == move.id
    end
    nil
  end

  def damage_entry_for_action(dmg_data, action)
    dmg_data&.values&.find { |entry| entry[:action] == action } if action
  end


  #---------------------------------------------------------------------------
  # Direct damage calculation for a single move on sim battlers.
  # Handles failure checks, multi-hit, Parental Bond, and fixed damage.
  # attacker_ai/defender_ai are retained for call-site compatibility.
  #---------------------------------------------------------------------------
  def calc_move_damage(move, sim_user, sim_target, attacker_ai = nil, defender_ai = nil)
    # Find the sim version of the move on the sim battler
    sim_move = sim_user.moves.find { |sm| sm.id == move.id }
    sim_move ||= move  # fallback to the original move object

    # Mirror the real move-use flow closely enough for moves whose damage setup
    # happens in pbOnStartUse (e.g. Tera Blast under simulated Terastallization).
    sim_move.calcType = sim_move.pbCalcType(sim_user)
    return 0 if sim_move.pbMoveFailed?(sim_user, [sim_target])
    sim_move.pbOnStartUse(sim_user, [sim_target])

    calc_type = sim_move.calcType
    return 0 if sim_user.battle.pbWeather == :HeavyRain && calc_type == :FIRE
    return 0 if sim_user.battle.pbWeather == :HarshSun && calc_type == :WATER

    success, type_mod = damage_profile_success_check(sim_move, sim_user, sim_target)
    return 0 unless success

    sim_target.damageState.reset
    sim_move.calcType = calc_type
    sim_target.damageState.typeMod = type_mod
    sim_move.pbCheckDamageAbsorption(sim_user, sim_target)

    sim_move.pbCalcDamage(sim_user, sim_target, 1)
    base_dmg = sim_target.damageState.calcDamage || 0

    hits = calc_multi_hit_count(sim_move, sim_user)
    if hits > 1
      if sim_move.is_a?(Battle::Move::HitThreeTimesPowersUpWithEachHit)
        base_dmg *= 6
      else
        base_dmg *= hits
      end
    end

    if hits <= 1 && sim_user.hasActiveAbility?(:PARENTALBOND) &&
       !(sim_move.respond_to?(:chargingTurnMove?) && sim_move.chargingTurnMove?)
      second_hit = (base_dmg * (Settings::MECHANICS_GENERATION >= 7 ? 0.25 : 0.5)).round
      base_dmg += second_hit
    end

    [base_dmg, 0].max
  end

  def damage_profile_success_check(move, sim_user, sim_target)
    battle = sim_user.battle
    user_snapshot = damage_profile_battler_snapshot(sim_user)
    target_snapshot = damage_profile_battler_snapshot(sim_target)
    success_snapshot = damage_profile_object_snapshot(battle.successStates[sim_user.index])
    choice_snapshot = battle.choices[sim_user.index]&.dup

    move_idx = sim_user.moves.index(move) || 0
    priority = move_priority_for_sim(move, sim_user)
    battle.choices[sim_user.index] = [:UseMove, move_idx, move, sim_target.index, priority]
    sim_target.damageState.reset

    success = sim_user.pbSuccessCheckAgainstTarget(move, sim_user, sim_target, [sim_target])
    type_mod = sim_target.damageState.typeMod
    [success, type_mod]
  ensure
    damage_profile_restore_battler_snapshot(sim_user, user_snapshot) if user_snapshot
    damage_profile_restore_battler_snapshot(sim_target, target_snapshot) if target_snapshot
    damage_profile_restore_object_snapshot(battle.successStates[sim_user.index], success_snapshot) if success_snapshot
    battle.choices[sim_user.index] = choice_snapshot if battle && sim_user
  end

  def damage_profile_battler_snapshot(battler)
    {
      hp: battler.hp,
      status: battler.status,
      status_count: battler.statusCount,
      stages: battler.stages.dup,
      effects: damage_profile_object_snapshot(battler.effects),
      last_move_failed: battler.lastMoveFailed,
      damage_state: damage_profile_object_snapshot(battler.damageState)
    }
  end

  def damage_profile_restore_battler_snapshot(battler, snapshot)
    battler.hp = snapshot[:hp]
    battler.status = snapshot[:status]
    battler.statusCount = snapshot[:status_count]
    battler.stages.clear
    snapshot[:stages].each { |stat, stage| battler.stages[stat] = stage }
    damage_profile_restore_object_snapshot(battler.effects, snapshot[:effects])
    battler.lastMoveFailed = snapshot[:last_move_failed]
    damage_profile_restore_object_snapshot(battler.damageState, snapshot[:damage_state])
  end

  def damage_profile_object_snapshot(obj)
    obj.instance_variables.each_with_object({}) do |ivar, snapshot|
      value = obj.instance_variable_get(ivar)
      snapshot[ivar] = value.is_a?(Array) || value.is_a?(Hash) ? value.dup : value
    end
  end

  def damage_profile_restore_object_snapshot(obj, snapshot)
    obj.instance_variables.each do |ivar|
      obj.remove_instance_variable(ivar) unless snapshot.key?(ivar)
    end
    snapshot.each do |ivar, value|
      obj.instance_variable_set(ivar, value.is_a?(Array) || value.is_a?(Hash) ? value.dup : value)
    end
  end

  #---------------------------------------------------------------------------
  # Returns the expected number of hits for a multi-hit move.
  #---------------------------------------------------------------------------
  def calc_multi_hit_count(move, sim_user)
    return 1 unless move.multiHitMove?
    case move
    when Battle::Move::HitTwoTimes,
         Battle::Move::HitTwoTimesPoisonTarget,
         Battle::Move::HitTwoTimesFlinchTarget
      return 2
    when Battle::Move::HitThreeTimesPowersUpWithEachHit,
         Battle::Move::HitThreeTimesAlwaysCriticalHit
      return 3
    when Battle::Move::HitTwoToFiveTimes,
         Battle::Move::HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1
      return 5 if sim_user.hasActiveAbility?(:SKILLLINK)
      return 5 if sim_user.hasActiveItem?(:LOADEDDICE)
      return 3
    when Battle::Move::HitTwoToFiveTimesOrThreeForAshGreninja
      return 3 if sim_user.isSpecies?(:GRENINJA) && sim_user.form == 2
      return 5 if sim_user.hasActiveAbility?(:SKILLLINK)
      return 5 if sim_user.hasActiveItem?(:LOADEDDICE)
      return 3
    when Battle::Move::HitOncePerUserTeamMember
      count = 0
      sim_user.battle.eachInTeamFromBattlerIndex(sim_user.index) do |pkmn, _i|
        count += 1 if pkmn.able? && pkmn.status == :NONE
      end
      return [count, 1].max
    end
    return 1
  end

  #---------------------------------------------------------------------------
  # Returns the best move data {move:, dmg:} from damage_moves.
  #---------------------------------------------------------------------------
  def best_damage_move(attacker, defender, include_zmove = true)
    dmg_data = damage_moves(attacker, defender)
    dmg_data = dmg_data.reject { |_key, data| data[:zmove] } unless include_zmove
    planned = tera_foe_damage_entry(attacker, defender, dmg_data, 0)
    return planned if planned
    _select_best_damage_move(dmg_data, attacker, defender)
  end

  #---------------------------------------------------------------------------
  # Selects the best damage option.
  # If any move is lethal against the current target HP, selection is restricted
  # to lethal options. Tied lethal options are chosen with weighted probability
  # once, then cached so later lookups for the same entry stay consistent.
  #---------------------------------------------------------------------------
  def _select_best_damage_move(dmg_data, attacker, target = nil)
    return nil if !dmg_data || dmg_data.empty?
    max_dmg = dmg_data.values.max_by { |md| md[:dmg] }[:dmg]
    lethal_moves = dmg_data.values.select { |md| md[:dmg] == max_dmg }
    lethal_threshold = nil
    if target && target.respond_to?(:hp)
      lethal_threshold = target.hp
      lethal_candidates = dmg_data.values.select { |md| md[:dmg] >= lethal_threshold }
      lethal_moves = lethal_candidates if lethal_candidates.any?
    end
    cached_selection = _cached_best_damage_move(dmg_data, lethal_threshold)
    return cached_selection if cached_selection

    if lethal_moves.length > 1
      lethal_moves.each do |md|
        md[:lethal_score] = _lethal_move_score(md, attacker, target)
        md[:lethal_weight] = _lethal_move_weight(md[:lethal_score])
      end
      selected = _pick_weighted_lethal_move(lethal_moves)
      _cache_best_damage_move(dmg_data, lethal_threshold, selected)
      return selected
    end

    best = lethal_moves.max_by { |md| md[:dmg] }
    best[:lethal_score] = _lethal_move_score(best, attacker, target) if best
    _cache_best_damage_move(dmg_data, lethal_threshold, best)
    best
  end

  def _lethal_move_score(move_data, attacker, target = nil)
    move = move_data.is_a?(Hash) ? move_data[:move] : move_data
    dmg  = move_data.is_a?(Hash) ? move_data[:dmg].to_i : 0
    scored_move = _move_for_lethal_scoring(move, attacker)
    score = _move_priority(scored_move, attacker) * 100
    score -= 50 if scored_move.function_code == "AttackAndSkipNextTurn"
    # players dont really use charging moves if they cant use it on one turn
    # score -= 70 if scored_move.respond_to?(:chargingTurnMove?) && scored_move.chargingTurnMove?
    score -= 10 if scored_move.respond_to?(:recoilMove?) && scored_move.recoilMove?
    score += 15 if scored_move.respond_to?(:healingMove?) && scored_move.healingMove? && scored_move.damagingMove?

    contrary = attacker && attacker.respond_to?(:hasActiveAbility?) && attacker.hasActiveAbility?(:CONTRARY)
    score += _lethal_stat_stage_score(scored_move, contrary)
    score += _lethal_overkill_score(dmg, target)
    score
  end

  def _lethal_overkill_score(dmg, target)
    return 0 if dmg <= 0 || !target || !target.respond_to?(:hp) || !target.respond_to?(:totalhp)

    hp_floor = [target.hp.to_i, 1].max
    capped_damage = [dmg.to_i, (target.totalhp * 1.5).floor].min
    return 0 if capped_damage <= hp_floor

    # Let overkill matter for lethal move prediction, but taper it by capping
    # the rewarded damage at 150% of the target's total HP.
    overkill = capped_damage - hp_floor
    [(overkill.to_f / [target.totalhp, 1].max * 40).round, 40].min
  end

  def _move_for_lethal_scoring(move, attacker)
    return move if move.is_a?(Battle::Move)
    battle = (attacker && attacker.respond_to?(:battle)) ? attacker.battle : @battle
    Battle::Move.from_pokemon_move(battle, move)
  rescue StandardError
    move
  end

  def _move_priority(move, attacker)
    # grassy terrain grassy glide etc
    return move.pbPriority(attacker) if attacker && move.respond_to?(:pbPriority)
    return move.priority if move.respond_to?(:priority)
    0
  end

  def _lethal_stat_stage_score(move, contrary)
    score = 0
    score += _sum_stat_stages(move.statUp) * (contrary ? -12 : 12) if move.respond_to?(:statUp) && move.statUp
    score += _sum_stat_stages(move.statDown) * (contrary ? 40 : -40) if move.respond_to?(:statDown) && move.statDown
    score
  end

  def _sum_stat_stages(stat_changes)
    total = 0
    stat_changes.each_with_index do |_stat, idx|
      next if idx.even?
      total += stat_changes[idx].to_i
    end
    total
  end

  def _lethal_move_weight(score)
    [1, 100 + score].max
  end

  def _pick_weighted_lethal_move(lethal_moves)
    total_weight = lethal_moves.sum { |md| md[:lethal_weight] || 1 }
    roll = @battle.pbRandom(total_weight)
    lethal_moves.each do |md|
      weight = md[:lethal_weight] || 1
      return md if roll < weight
      roll -= weight
    end
    lethal_moves.max_by do |md|
      move = md[:move]
      base_move = md[:base_move] || move
      [
        md[:lethal_weight] || 1,
        md[:dmg].to_i,
        md[:zmove] ? 0 : 1,
        (base_move&.id || move&.id).to_s,
        (move&.id || "").to_s
      ]
    end
  end

  def _cached_best_damage_move(dmg_data, lethal_threshold)
    cache = dmg_data.instance_variable_get(:@_selected_best_moves)
    return nil unless cache
    cache[lethal_threshold]
  end

  def _cache_best_damage_move(dmg_data, lethal_threshold, selected)
    cache = dmg_data.instance_variable_get(:@_selected_best_moves)
    unless cache
      cache = {}
      dmg_data.instance_variable_set(:@_selected_best_moves, cache)
    end
    cache[lethal_threshold] = selected
  end

  # Unified damage calculation for current and scenario-prepared battlers.
  def damage_moves(attacker, defender)
    return {} if attacker.fainted? || defender.fainted?
    damage_profile(attacker.index, defender.index, SimulationScenario.current)
  end

  def damage_moves_with_switch(attacker_index, target_index, pre_switch, options = {})
    damage_profile(attacker_index, target_index, scenario_from_switch_options(pre_switch, options))
  end

  def best_damage_move_with_switch(attacker_index, target_index, pre_switch, options = {})
    dmg_data = damage_moves_with_switch(attacker_index, target_index, pre_switch, options)
    return nil unless dmg_data
    target = target_for_damage_selection(target_index, scenario_from_switch_options(pre_switch, options))
    _select_best_damage_move(dmg_data, @battle.battlers[attacker_index], target)
  end

  def damage_profile(attacker_index, target_index, scenario = SimulationScenario.current)
    scenario ||= SimulationScenario.current
    fwd_transform = previous_form_damage_profile_transform(attacker_index, target_index, scenario)
    fwd_key = damage_profile_cache_key(attacker_index, target_index, scenario)
    fwd_key += [previous_form_damage_profile_cache_key(fwd_transform)] if fwd_key && fwd_transform
    return nil unless fwd_key
    cache = (@_ai_dmg_cache ||= {})
    return cache[fwd_key] if cache.key?(fwd_key)

    sim = prepare_sim_for_scenario(scenario)
    sim_a = sim.battlers[attacker_index]
    sim_b = sim.battlers[target_index]
    return {} unless sim_a && sim_b
    return {} if sim_a.fainted? || sim_b.fainted?

    PBDebug.log_ai("[damage_profile] computing #{sim_a.name} -> #{sim_b.name} (turn #{@battle.turnCount})")
    fwd = build_damage_profile_entries_for_form(
      attacker_index, sim_a, sim_b, sim, scenario, fwd_transform
    )
    cache[fwd_key] = fwd

    rev_transform = previous_form_damage_profile_transform(target_index, attacker_index, scenario)
    rev_key = damage_profile_cache_key(target_index, attacker_index, scenario)
    rev_key += [previous_form_damage_profile_cache_key(rev_transform)] if rev_key && rev_transform
    if rev_key && !cache.key?(rev_key)
      cache[rev_key] = build_damage_profile_entries_for_form(
        target_index, sim_b, sim_a, sim, scenario, rev_transform
      )
    end
    fwd
  end

  def previous_form_damage_profile_transform(attacker_index, target_index, scenario)
    return nil unless scenario.current?
    return nil unless @_registered_transform_preview && @user
    return nil unless target_index == @user.index

    attacker = @battlers[attacker_index]
    return nil unless attacker && attacker.side != @user.side

    @_registered_transform_preview[:transforms].find do |transform|
      transform[:battler].index == target_index && transform[:type] == :ultra
    end
  end

  def previous_form_damage_profile_cache_key(transform)
    [:previous_form, transform[:type], transform[:prev_form]]
  end

  def build_damage_profile_entries_for_form(attacker_index, sim_attacker, sim_target,
                                            sim, scenario, transform)
    return build_damage_profile_entries(
      attacker_index, sim_attacker, sim_target, sim, scenario
    ) unless transform

    pokemon = sim_target.pokemon
    current_form = sim_target.form
    current_pokemon_form = pokemon.form
    begin
      pokemon.form = transform[:prev_form]
      sim_target.form = transform[:prev_form]
      sim_target.pbUpdate(true)
      PBDebug.log_ai(
        "[damage_profile] #{sim_attacker.name} chooses against #{sim_target.name}'s previous form"
      )
      build_damage_profile_entries(attacker_index, sim_attacker, sim_target, sim, scenario)
    ensure
      pokemon.form = current_pokemon_form
      sim_target.form = current_form
      sim_target.pbUpdate(true)
    end
  end

  def build_damage_profile_entries(attacker_index, sim_attacker, sim_target, sim, scenario)
    entries = {}
    move_source = damage_profile_move_source(attacker_index, sim_attacker, scenario)
    holder = damage_profile_calc_holder(attacker_index, sim_attacker, scenario)
    can_choose = damage_profile_can_choose(attacker_index, sim_attacker, scenario)
    _each_damage_option(move_source, holder, sim, battler_index: attacker_index,
                        can_choose: can_choose) do |base_move, move|
      dmg = calc_move_damage(move, sim_attacker, sim_target)
      dynamax_base_move_id = _dynamax_base_move_id(sim_attacker, move)
      entry = _build_damage_entry(base_move, move, dmg, dynamax_base_move_id)
      entries[entry[:key]] = entry
    end
    entries
  end

  def damage_profile_move_source(battler_index, sim_battler, scenario)
    return sim_battler.moves if scenario.pre_switch.key?(battler_index)

    ai = @battlers[battler_index]
    if ai && ai.side != @user.side
      return known_foe_moves(ai).map do |move|
        next move if !move&.respond_to?(:zMove?) || !move.zMove?
        idx = ai.battler.moves.index(move)
        idx ||= ai.battler.moves.index { |m| m&.id == move.id }
        base_move = idx ? ai.battler.baseMoves[idx] : nil
        base_move || move
      end
    end
    sim_battler.moves
  end

  def damage_profile_calc_holder(battler_index, sim_battler, scenario)
    return sim_battler.pokemon if scenario.pre_switch.key?(battler_index)
    @battlers[battler_index] || sim_battler
  end

  def damage_profile_can_choose(battler_index, sim_battler, scenario)
    return nil if scenario.pre_switch.key?(battler_index)
    battler = @battle.battlers[battler_index]
    return nil unless battler

    lambda do |move|
      move_index = battler.moves.index(move)
      move_index ||= battler.moves.index { |candidate| candidate&.id == move.id }
      next false unless move_index

      @battle.pbCanChooseMove?(battler_index, move_index, false)
    end
  end

  def target_for_damage_selection(target_index, scenario)
    if scenario.pre_switch[target_index]
      @battle.pbParty(target_index)[scenario.pre_switch[target_index]]
    else
      @battle.battlers[target_index]
    end
  end

  def damage_profile_cache_key(attacker_index, target_index, scenario)
    attacker_state = damage_profile_cache_subject(attacker_index, scenario)
    target_state = damage_profile_cache_subject(target_index, scenario)
    return nil unless attacker_state && target_state

    [
      :dmg_profile,
      attacker_index,
      target_index,
      @battle.turnCount,
      scenario.cache_key,
      attacker_state,
      target_state,
      zmove_available_for_battler_index?(attacker_index),
      zmove_available_for_battler_index?(target_index)
    ]
  end

  def damage_profile_cache_subject(battler_index, scenario)
    if scenario.pre_switch[battler_index]
      pkmn = @battle.pbParty(battler_index)[scenario.pre_switch[battler_index]]
      return nil unless pkmn
      return [
        pkmn.personalID,
        pkmn.form,
        pkmn.instance_variable_get(:@terastallized) == true
      ]
    end

    battler = @battle.battlers[battler_index]
    return nil unless battler&.pokemon
    [
      battler.pokemon&.personalID,
      battler.form,
      battler.pokemon.instance_variable_get(:@terastallized) == true,
      battler.effects[PBEffects::Dynamax]
    ]
  end
end
