#===============================================================================
# [AI_Improved_Matchup.rb] - Matchup Analysis
#===============================================================================

class Battle::AI
  FIRST_TURN_ONLY_DAMAGE_FUNCTION_CODES = [
    "FailsIfNotUserFirstTurn",            # First Impression
    "FlinchTargetFailsIfNotUserFirstTurn" # Fake Out
  ].freeze

  def status_move_succeeded_in_result?(result, target_index)
    result.user_succeeded ||
      (result.terminated_by_switch &&
       result.switch_type == :live_switch &&
       result.switch_battler_index == target_index &&
       !result.user_fainted)
  end

  def status_move_succeeded_on_first_turn?(result, target_index)
    first_turn = result.turn_log&.first
    target_pivoted_turn_one = result.terminated_by_switch &&
                              result.switch_type == :live_switch &&
                              result.switch_battler_index == target_index &&
                              !result.user_fainted &&
                              result.turns <= 1
    return first_turn[:user_succeeded] || target_pivoted_turn_one if first_turn

    target_pivoted_turn_one
  end

  def status_move_missed_followup_action?(result)
    return false if result.terminated_by_switch

    turns = result.turn_log || []
    return result.user_fainted if turns.length < 2

    !turns[1][:user_acted]
  end

  def eager_current_status_move_success(target_battler, foe_action)
    status_survival = {}
    status_moves = @user.moves.select { |move| move&.statusMove? }
    return status_survival if status_moves.empty?

    foe_actions = foe_action.is_a?(Array) ? foe_action.compact : (foe_action ? [foe_action] : [])
    status_moves.each do |move|
      result = simulate_battle(
        @user.index, target_battler.index,
        [move.id, move.id], foe_actions,
        max_turns: 2,
        lock_user_first_action: true
      )
      success = status_move_succeeded_on_first_turn?(result, target_battler.index)
      status_survival[move.id] = {
        success: success,
        missed_followup_action: success && status_move_missed_followup_action?(result),
        result:  result
      }
    end
    status_survival
  end

  def one_v_one_sim_turn_limit_for_move(move)
    first_turn_only_damage_move?(move) ? 1 : 10
  end

  def first_turn_only_damage_move?(move)
    FIRST_TURN_ONLY_DAMAGE_FUNCTION_CODES.include?(safe_function_code(move))
  end

  def best_repeatable_damage_move(attacker, defender)
    repeatable_moves = damage_moves(attacker, defender).reject do |_key, data|
      first_turn_only_damage_move?(data[:move])
    end
    planned = tera_foe_damage_entry(attacker, defender, repeatable_moves, 1)
    return planned if planned
    _select_best_damage_move(repeatable_moves, attacker, defender)
  end

  def foe_actions_for_scoring(first_action, repeatable_action, foe)
    return [] if @_foe_idle_rescore_for_scoring
    tera_foe_actions(foe)&.dup || (first_action ? [first_action, repeatable_action] : [])
  end

  #---------------------------------------------------------------------------
  # Returns a cached summary of KO/speed data for all current battler pairs.
  #---------------------------------------------------------------------------
  def matchup_summary
    mega = @battle.pbRegisteredMegaEvolution?(@user.index) 
    tera = @battle.pbRegisteredTerastallize?(@user.index) || @user.tera?
    foe_ids = []
    each_foe_battler(@user.side) { |b, _| foe_ids << b.pokemon&.personalID }
    key = [@user.index, @battle.turnCount, mega, tera, @user.pokemon&.personalID, foe_ids, @_foe_idle_rescore_for_scoring]
    (@_matchup_cache ||= {})[key] ||= begin
      summary = { foes: {} }
      summary[:max_foe_dmg] = 0

      each_foe_battler(@user.side) do |b, _i|
        user_best = best_damage_move(@user, b)
        foe_best = best_damage_move(b, @user)
        user_best_repeatable = best_repeatable_damage_move(@user, b)
        foe_best_repeatable = best_repeatable_damage_move(b, @user)

        foe_outspeeds = b.faster_than?(@user)
        foe_best_move = foe_best&.dig(:move)
        foe_has_priority = foe_best_move && foe_best_move.priority > 0
        foe_effectively_outspeeds = foe_outspeeds || foe_has_priority

        # Run per-move sims against the foe's best damage line. First-turn-only
        # moves are capped at one turn so they aren't scored as repeatable.
        move_results = {}
        move_results_by_id = {}
        user_best_followup_action = simulation_action_for_move_data(user_best_repeatable)
        foe_best_action = simulation_action_for_move_data(foe_best)
        foe_followup_action = simulation_action_for_move_data(foe_best_repeatable)
        foe_damage_actions = foe_actions_for_scoring(foe_best_action, foe_followup_action, b)
        if @_foe_idle_rescore_for_scoring || !foe_damage_actions.empty?
          damage_moves(@user, b).each do |move_key, data|
            user_action = simulation_action_for_move_data(data)
            next unless user_action
            max_turns = one_v_one_sim_turn_limit_for_move(data[:move])
            user_actions = [user_action]
            user_actions << user_best_followup_action if max_turns > 1
            result = simulate_battle(
              @user.index, b.index,
              user_actions, foe_damage_actions,
              max_turns: max_turns,
              lock_user_first_action: true
            )
            move_results[move_key] = result
            move_results_by_id[data[:move].id] = result
          end
        end
        sim_result = user_best ? move_results[user_best[:key]] : nil

        foe_best_dmg = foe_best&.dig(:dmg) || 0
        foe_action = nil
        
        if foe_best_dmg >= @user.hp
          lethal_moves = damage_moves(b, @user).values.select { |d| d[:dmg] >= @user.hp }
          foe_lethal_move = lethal_moves.max_by { |d| d[:move].priority }
          foe_action = simulation_action_for_move_data(foe_lethal_move) if foe_lethal_move
        else
          foe_action = simulation_action_for_move_data(foe_best) if foe_best_move
        end
        foe_status_actions = foe_actions_for_scoring(foe_action, foe_followup_action, b)

        foe_entry = {
          best_dmg:      foe_best_dmg,
          best_move:     foe_best_move,
          effectively_outspeeds: foe_effectively_outspeeds,
          can_ohko:      sim_result&.target_can_ohko? || false,
          sim_result:    sim_result,
          damage_actions: foe_damage_actions,
          move_results:  move_results,
          move_results_by_id: move_results_by_id,
          status_survival: eager_current_status_move_success(b, foe_status_actions),
          status_foe_actions: foe_status_actions
        }
        summary[:foes][b.index] = foe_entry
        summary[:max_foe_dmg] = [summary[:max_foe_dmg], foe_best_dmg].max
      end
      summary
    end
  end

  #---------------------------------------------------------------------------
  # Lazy per-move status success check for reserve switch-ins.
  #---------------------------------------------------------------------------
  def reserve_status_move_success(attacker_index, target_index, pre_switch, foe_vs_reserve_action, foe_vs_current_action, move_id)
    if pre_switch[attacker_index]
      pkmn = @battle.pbParty(attacker_index)[pre_switch[attacker_index]]
      return false unless pkmn
      atk_id = pkmn.personalID
    else
      atk_id = @battle.battlers[attacker_index].pokemon&.personalID
    end

    tgt_id = pre_switch[target_index] ? @battle.pbParty(target_index)[pre_switch[target_index]].personalID : @battle.battlers[target_index].pokemon&.personalID

    key = [:status_switch, attacker_index, target_index, @battle.turnCount, atk_id, tgt_id, foe_vs_reserve_action, foe_vs_current_action, move_id]
    (@_ai_dmg_cache ||= {})[key] ||= begin
      voluntary_switch = @battle.command_phase
      party_index = pre_switch[attacker_index]

      scenario = if voluntary_switch && party_index
        SimulationScenario.voluntary_switch(pre_switch, target_index, foe_vs_current_action)
      else
        SimulationScenario.switch(pre_switch)
      end
      sim_foe_actions = foe_vs_reserve_action ? [foe_vs_reserve_action] : []
      res = simulate_battle(
        attacker_index, target_index,
        [move_id], sim_foe_actions,
        scenario: scenario, max_turns: 1
      )
      {
        success: status_move_succeeded_in_result?(res, target_index),
        result:  res
      }
    end
  end

  def current_status_move_cache_entry(target_battler, move)
    summary = matchup_summary
    foe_entry = summary[:foes][target_battler.index]
    return nil unless foe_entry

    real_move = move.respond_to?(:move) ? move.move : move
    move_id = move.respond_to?(:id) ? move.id : real_move&.id
    return nil unless real_move && move_id

    is_status_zmove = real_move.respond_to?(:status_zmove) && real_move.status_zmove
    cache_key = is_status_zmove ? [:status_zmove, move_id] : move_id
    cached = foe_entry[:status_survival][cache_key]
    return cached if cached

    first_action = if is_status_zmove
      move_index = @user.battler.moves.index { |candidate| candidate&.id == move_id }
      {
        move_id: move_id,
        move_index: move_index,
        status_zmove: true
      }
    else
      move_id
    end
    result = simulate_battle(
      @user.index, target_battler.index,
      [first_action, move_id], foe_entry[:status_foe_actions] || [],
      max_turns: 2,
      lock_user_first_action: true
    )
    success = status_move_succeeded_on_first_turn?(result, target_battler.index)
    foe_entry[:status_survival][cache_key] = {
      success: success,
      missed_followup_action: success && status_move_missed_followup_action?(result),
      result: result
    }
  end

  def current_status_move_succeeds?(target_battler, move)
    cached = current_status_move_cache_entry(target_battler, move)
    return false unless cached

    cached.is_a?(Hash) ? cached[:success] == true : cached == true
  end

  def current_status_move_sim_result(target_battler, move)
    cached = current_status_move_cache_entry(target_battler, move)
    cached.is_a?(Hash) ? cached[:result] : nil
  end

  def current_status_move_missed_followup_action?(target_battler, move)
    cached = current_status_move_cache_entry(target_battler, move)
    return false unless cached

    cached.is_a?(Hash) && cached[:missed_followup_action] == true
  end

  #---------------------------------------------------------------------------
  # Exposes whether a specific reserve status move succeeds after its switch-in.
  #---------------------------------------------------------------------------
  def reserve_status_move_succeeds?(idxBattler, pkmn, target_battler, m_id)
    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return true unless party_index

    replacement_1v1_results(idxBattler, pkmn)
    cached_foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, target_battler)
    return true unless cached_foe_results

    cached_entry = cached_foe_results&.dig(:status_move_survival, m_id)
    if cached_entry.is_a?(Hash)
      return cached_entry[:success] == true
    elsif !cached_entry.nil?
      return cached_entry == true
    end

    if cached_foe_results[:entry_user_fainted]
      cached_foe_results[:status_move_survival][m_id] = {
        success: false,
        result: nil
      }
      return false
    end
    if cached_foe_results[:entry_foe_fainted]
      cached_foe_results[:status_move_survival][m_id] = {
        success: true,
        result: nil
      }
      return true
    end

    # Skip sim when foe damage is clearly non-threatening to the reserve
    pre_switch = { idxBattler => party_index }
    foe_vs_reserve_data = cached_foe_results[:foe_vs_reserve]
    foe_vs_reserve_dmg = foe_vs_reserve_data ? foe_vs_reserve_data[:dmg].to_i : 0
    voluntary = cached_foe_results[:voluntary_switch]
    total_threat = foe_vs_reserve_dmg
    if voluntary
      foe_switch_in_data = cached_foe_results[:foe_switch_in] || cached_foe_results[:foe_vs_current]
      if foe_switch_in_data
        # Look up the assumed switch-in move's actual damage against the reserve (cache hit)
        foe_to_reserve = damage_moves_with_switch(target_battler.index, idxBattler, pre_switch)
        switch_in_dmg = foe_to_reserve&.dig(foe_switch_in_data[:key], :dmg).to_i
        total_threat += switch_in_dmg
      else
        total_threat += foe_vs_reserve_dmg
      end
    end
    if total_threat < pkmn.hp * 0.9
      PBDebug.log_ai("[status_skip] #{pkmn.name} clearly survives vs #{target_battler.name} (threat #{total_threat} < #{(pkmn.hp * 0.9).round} HP)")
      cached_foe_results[:status_move_survival][m_id] = { success: true, result: nil }
      return true
    end

    foe_vs_reserve = cached_foe_results[:foe_vs_reserve]
    foe_vs_reserve_action = foe_vs_reserve ? simulation_action_for_move_data(foe_vs_reserve) : nil
    foe_switch_in_action = cached_foe_results[:foe_switch_in_action]
    status_result = reserve_status_move_success(
      idxBattler, target_battler.index, pre_switch, foe_vs_reserve_action, foe_switch_in_action, m_id
    )
    cached_foe_results[:status_move_survival][m_id] = status_result
    status_result.is_a?(Hash) ? status_result[:success] == true : status_result == true
  end

  def reserve_status_move_sim_result(idxBattler, pkmn, target_battler, m_id)
    party_index = @battle.pbParty(idxBattler).index(pkmn)
    return nil unless party_index

    replacement_1v1_results(idxBattler, pkmn)
    cached_foe_results = replacement_1v1_result_for_foe(idxBattler, pkmn, target_battler)
    return nil unless cached_foe_results

    cached_entry = cached_foe_results&.dig(:status_move_survival, m_id)
    if cached_entry.is_a?(Hash)
      return cached_entry[:result]
    end

    # Trigger the sim to populate cache
    reserve_status_move_succeeds?(idxBattler, pkmn, target_battler, m_id)
    cached_entry = cached_foe_results&.dig(:status_move_survival, m_id)
    cached_entry.is_a?(Hash) ? cached_entry[:result] : nil
  end

end
