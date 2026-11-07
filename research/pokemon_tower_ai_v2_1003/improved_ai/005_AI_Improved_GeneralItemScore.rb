#===============================================================================
# 4. GeneralItemScore Handlers
#===============================================================================

#===============================================================================
# ITEM AI SUPPORT – Ace-focused & Switch-aware Item Usage
#  - Does not modify DBK Improved Item AI directly
#  - Adjusts item usage scores to guide behavior
#===============================================================================

class Battle::AI
  def pbChooseToUseItem(target_filter = nil)
    item = nil
    idxTarget = nil
    idxMove = nil
    item, idxTarget, idxMove = choose_item_to_use(target_filter)
    return false if !item
    @battle.pbRegisterItem(@user.index, item, idxTarget, idxMove)
    PBDebug.log_ai("#{@user.name} will use item #{GameData::Item.get(item).name}")
    return true
  end

  def choose_item_to_use(target_filter = nil)
    return nil if !@battle.internalBattle || @battle.noBag
    items = @battle.pbGetOwnerItems(@user.index)
    return nil if !items || items.length == 0
    if @battle.launcherBattle?
      return nil if !@battle.pbCanUseLauncher?(@user.index)
      return nil if @battle.allOwnedByTrainer(@user.index).any? { |b| @battle.choices[b.index][0] == :UseItem }
    end
    predicted_to_faint = @user.rough_end_of_round_damage >= @user.hp
    choices = []
    items.each do |item|
      item_data = GameData::Item.get(item)
      use_type = (@battle.launcherBattle?) ? item_data.launcher_use : item_data.battle_use
      case use_type
      when 1, 2
        next if use_type == 2 && predicted_to_faint
        @battle.eachInTeamFromBattlerIndex(@user.index) do |p, idx_party|
          next unless item_target_matches_filter?(target_filter, use_type, idx_party)
          battler = @battle.pbFindBattler(idx_party, @user.side)
          ai_battler = (battler) ? @battlers[battler.index] : @user
          if use_type == 2
            p.moves.length.times do |idx_move|
              next if !item_usable_on_pokemon?(item, use_type, @user, idx_party, idx_move)
              score = ITEM_BASE_SCORE
              move_name = p.moves[idx_move].name
              PBDebug.log_ai("#{@user.name} is considering using item #{item_data.name} on party #{p.name} (party index #{idx_party}) [#{move_name}]...")
              score = Battle::AI::Handlers.pokemon_item_score(item, score, p, ai_battler, idx_move, self, @battle)
              score = Battle::AI::Handlers.apply_general_item_score_modifiers(score, item, idx_party, idx_move, self, @battle)
              choices.push([score, item, idx_party, idx_move])
            end
          else
            next if !item_usable_on_pokemon?(item, use_type, @user, idx_party)
            score = ITEM_BASE_SCORE
            PBDebug.log_ai("#{@user.name} is considering using item #{item_data.name} on party #{p.name} (party index #{idx_party})...")
            score = Battle::AI::Handlers.pokemon_item_score(item, score, p, ai_battler, nil, self, @battle)
            score = Battle::AI::Handlers.apply_general_item_score_modifiers(score, item, idx_party, nil, self, @battle)
            choices.push([score, item, idx_party])
          end
        end
      when 3, 6
        next if predicted_to_faint
        next unless item_target_matches_filter?(target_filter, use_type)
        @battle.allBattlers.each do |b|
          if use_type == 3
            next if @user.side != b.idxOwnSide
            next if @trainer.trainer_index != @battle.pbGetOwnerIndexFromBattlerIndex(b.index)
          end
          next if !item_usable_on_pokemon?(item, use_type, @user, b.pokemonIndex)
          score = ITEM_BASE_SCORE
          PBDebug.log_ai("#{@user.name} is considering using item #{item_data.name} on battler #{@battlers[b.index].name}...")
          idx_target = (use_type == 3) ? b.pokemonIndex : b.index
          score = Battle::AI::Handlers.battler_item_score(item, score, @battlers[b.index], self, @battle)
          score = Battle::AI::Handlers.apply_general_item_score_modifiers(score, item, idx_target, nil, self, @battle)
          choices.push([score, item, idx_target])
        end
      when 4, 5
        next if predicted_to_faint
        next unless item_target_matches_filter?(target_filter, use_type)
        next if !item_usable_on_pokemon?(item, use_type, @user, @user.party_index)
        score = ITEM_BASE_SCORE
        PBDebug.log_ai("#{@user.name} is considering using item #{item_data.name}...")
        score = Battle::AI::Handlers.item_score(item, score, @user, self, @battle, @battle.pbIsFirstAction?(@user.index))
        score = Battle::AI::Handlers.apply_general_item_score_modifiers(score, item, nil, nil, self, @battle)
        choices.push([score, item, -1])
      end
    end
    @battle.lastUsedItems[@user.side][@trainer.trainer_index] = nil
    if choices.empty? || !choices.any? { |c| c[0] > ITEM_FAIL_SCORE }
      PBDebug.log_ai("#{@user.name} couldn't find any usable items")
      return nil
    end
    max_score = 0
    choices.each { |c| max_score = c[0] if max_score < c[0] }
    if @trainer.high_skill?
      bad_items = false
      if max_score <= ITEM_USELESS_SCORE
        bad_items = true
      elsif max_score < ITEM_BASE_SCORE * move_score_threshold
        bad_items = true if pbAIRandom(100) < 80
      end
      if bad_items
        PBDebug.log_ai("#{@user.name} doesn't want to use any items")
        return nil
      end
    end
    threshold = (max_score * move_score_threshold.to_f).floor
    choices.each { |c| c[4] = [c[0] - threshold, 0].max }
    total_score = choices.sum { |c| c[4] }
    if $INTERNAL
      PBDebug.log_ai("Item choices for #{@user.name}:")
      choices.each do |c|
        item_data = GameData::Item.get(c[1])
        chance = sprintf("%5.1f", (c[4] > 0) ? 100.0 * c[4] / total_score : 0)
        log_msg = "   * #{chance}% to use #{item_data.name}"
        case item_data.battle_use
        when 1 then log_msg += " (party index #{c[2]})"
        when 2 then log_msg += " (party index #{c[2]}, move index #{c[3]})"
        else        log_msg += " (battler index #{c[2]})" if c[2] >= 0
        end
        log_msg += ": score #{c[0]}"
        PBDebug.log(log_msg)
      end
    end
    rand_num = pbAIRandom(total_score)
    choices.each do |c|
      rand_num -= c[4]
      next if rand_num >= 0
      item_data = GameData::Item.get(c[1])
      log_msg = "   => will use #{item_data.name}"
      case item_data.battle_use
      when 1 then log_msg += " (party index #{c[2]})"
      when 2 then log_msg += " (party index #{c[2]}, move index #{c[3]})"
      else        log_msg += " (battler index #{c[2]})" if c[2] >= 0
      end
      PBDebug.log(log_msg)
      @battle.lastUsedItems[@user.side][@trainer.trainer_index] = c[1..3]
      return c[1], c[2], c[3]
    end
    return nil
  end

  def item_target_matches_filter?(target_filter, use_type, idx_party = nil)
    return true if target_filter.nil?
    case target_filter
    when :current
      return true if [3, 4, 5, 6].include?(use_type)
      return idx_party == @user.party_index if [1, 2].include?(use_type)
    when :reserve
      return idx_party != @user.party_index if [1, 2].include?(use_type)
      return false
    end
    return true
  end

  def item_healed_hp_after_use(item, pkmn)
    return nil unless item && pkmn
    return pkmn.totalhp if Battle::AI::FULL_RESTORE_ITEMS.include?(item)

    heal_amt = Battle::AI::HP_HEAL_ITEMS[item] || 0
    heal_amt = pkmn.totalhp / 4 if heal_amt == 1
    heal_amt = pkmn.totalhp - pkmn.hp if heal_amt >= 999
    [[pkmn.hp + heal_amt, pkmn.totalhp].min, 0].max
  end

  def item_use_simulation_context(attacker, defender, healed_hp = nil)
    return nil unless attacker && defender

    attacker = @battlers[attacker.index] unless attacker.respond_to?(:side)
    defender = @battlers[defender.index] unless defender.respond_to?(:side)
    return nil unless attacker && defender

    opening_move_data = best_damage_move(attacker, defender)
    sim = create_battle_copy
    sim_attacker = sim.battlers[attacker.index]
    sim_defender = sim.battlers[defender.index]
    return nil unless sim_attacker && sim_defender

    sim_defender.hp = healed_hp || sim_defender.totalhp

    opening_action = simulation_action_for_move_data(opening_move_data)
    opening_move = opening_action ? resolve_sim_action_move(sim_attacker, opening_action) : nil
    switch_event = false
    if opening_move
      sim.choices[attacker.index] = [:UseMove, sim_attacker.moves.index(opening_move) || 0, opening_move, defender.index, 0]
    else
      sim.choices[attacker.index] = [:None]
    end
    sim.choices[defender.index] = [:None]

    sim.instance_variable_set(:@turnCount, @battle.turnCount)
    switch_event = catch(SIM_SWITCH_TRIGGERED) do
      sim.pbAttackPhase
      sim.pbEndOfRoundPhase
      sim.instance_variable_set(:@turnCount, sim.turnCount + 1)
      false
    end

    sim_attacker = sim.battlers[attacker.index]
    sim_defender = sim.battlers[defender.index]
    sim_result = item_use_opening_simulation_result(
      sim_attacker, sim_defender, switch_event
    )

    {
      sim: sim,
      move_data: switch_event ? nil : best_damage_move(attacker, defender),
      switch_event: switch_event,
      sim_result: sim_result
    }
  end

  def item_use_opening_simulation_result(attacker, defender, switch_event = nil)
    result = Battle::AI::SimulationResult.new
    result.turns = 1
    result.user_fainted = defender&.fainted? || false
    result.target_fainted = attacker&.fainted? || false
    result.user_hp = defender&.hp || 0
    result.target_hp = attacker&.hp || 0
    result.user_ko_turn = 1 if result.user_fainted
    result.target_ko_turn = 1 if result.target_fainted
    result.user_got_action = false
    result.target_got_action = switch_event ? true : (attacker&.instance_variable_get(:@_sim_action_turn) ? true : false)
    result.target_succeeded = switch_event ? true : (attacker&.instance_variable_get(:@_sim_action_succeeded) || false)
    if switch_event
      result.terminated_by_switch = true
      result.switch_type = switch_event[:reason]
      result.switch_battler_index = switch_event[:battler_index]
    end
    result
  end
end

Battle::AI::Handlers::GeneralItemScore.add(
  :ai_improved_item_general_use,
  proc { |score, item, idxPkmn, idxMove, ai, battle|
    user_ai = ai.user
    battler = user_ai&.battler
    next score unless battler
    next score unless item

    party = battle.pbParty(battler.index)
    pkmn = party[idxPkmn]
    next score unless pkmn

    hp_ratio = pkmn.hp.to_f / pkmn.totalhp
    is_healing_item = battle.pbItemHealsHP?(item)

    if hp_ratio > 0.6 && is_healing_item
      score -= 100
      PBDebug.log_score_change(
        -100,
        "ITEM AI: HP is healthy (>60%), healing discouraged."
      )
    end

    next score
  }
)

Battle::AI::Handlers::GeneralItemScore.add(
  :ai_improved_item_current_only,
  proc { |score, item, idxPkmn, idxMove, ai, battle|
    user_ai = ai.user
    battler = user_ai&.battler
    next score unless battler
    next score unless item
    next score unless idxPkmn == battler.pokemonIndex

    party = battle.pbParty(battler.index)
    party_size = party.length
    pkmn = party[idxPkmn]
    next score unless pkmn

    is_healing_item = battle.pbItemHealsHP?(item)
    healed_hp = is_healing_item ? ai.item_healed_hp_after_use(item, pkmn) : nil
    if is_healing_item && (!healed_hp || healed_hp <= pkmn.hp)
      PBDebug.log_score_change(
        Battle::AI::ITEM_FAIL_SCORE - score,
        "ITEM AI: Healing rejected; item does not improve current HP."
      )
      next Battle::AI::ITEM_FAIL_SCORE
    end

    # Simulate one spent healing turn, then require the healed battler to survive.
    PBDebug.log_ai("[item_ai] idxPkmn=#{idxPkmn.inspect}, battler.pokemonIndex=#{battler.pokemonIndex}")
    summary = ai.matchup_summary
    worst_penalty = 0
    worst_reason = nil
    healing_can_survive_after_turn = true
    healing_fail_reason = nil

    summary[:foes].each do |foe_idx, foe|
      foe_battler = ai.battlers[foe_idx]
      heal_context = ai.item_use_simulation_context(foe_battler, user_ai, healed_hp)
      if !heal_context
        if is_healing_item
          healing_can_survive_after_turn = false
          healing_fail_reason = "ITEM AI: Healing rejected; no safe post-heal simulation."
          break
        end
        next
      end

      sim_result = heal_context[:sim_result]
      unless heal_context[:switch_event]
        user_move_data = ai.best_damage_move(user_ai, foe_battler)
        user_action = ai.simulation_action_for_move_data(user_move_data)
        if !user_action
          if is_healing_item
            healing_can_survive_after_turn = false
            healing_fail_reason = "ITEM AI: Healing rejected; no safe post-heal action simulation."
            break
          end
          next
        end
        foe_action = ai.simulation_action_for_move_data(heal_context[:move_data])
        sim_result = ai.simulate_battle(
          battler.index, foe_idx,
          [user_action], foe_action ? [foe_action] : [],
          sim: heal_context[:sim], max_turns: 5
        )
      end

      foe_outspeeds = foe[:effectively_outspeeds]
      PBDebug.log_ai("[item_ai] sim vs foe #{foe_idx}: user_fainted=#{sim_result.user_fainted}, target_fainted=#{sim_result.target_fainted}, foe_ohko=#{sim_result.target_can_ohko?}, foe_outspeeds=#{foe_outspeeds}")

      penalty = 0
      reason = nil

      if sim_result.target_can_ohko?
        penalty = -200
        reason = "ITEM AI: Healing futile [OHKO from full] — foe KOs in 1 hit even at full HP."
      elsif sim_result.target_wins?
        if foe_outspeeds
          penalty = -150
          reason = "ITEM AI: Healing futile [foe wins 1v1 + outspeeds] — foe wins from full HP and acts first."
        elsif is_healing_item
          penalty = -50
          reason = "ITEM AI: Healing questionable [foe wins 1v1 + slower] — foe wins from full HP but AI acts first."
        end
      end

      if penalty < worst_penalty
        worst_penalty = penalty
        worst_reason = reason
      end
    end

    if is_healing_item && !healing_can_survive_after_turn
      PBDebug.log_score_change(
        Battle::AI::ITEM_FAIL_SCORE - score,
        healing_fail_reason
      )
      next Battle::AI::ITEM_FAIL_SCORE
    end

    if worst_penalty != 0
      score += worst_penalty
      PBDebug.log_score_change(worst_penalty, worst_reason)
      next score if worst_penalty <= -150
    end

    can_switch = battle.pbCanChooseNonActive?(battler.index)
    ace_candidate = false

    is_late_party = (idxPkmn >= (party_size * 0.6).floor)
    has_attacks = false
    if pkmn.moves
      damaging_moves = pkmn.moves.count do |m|
        m && GameData::Move.get(m.id).category != 2
      end
      has_attacks = (damaging_moves >= 2)
    end
    ace_candidate = is_late_party && has_attacks

    unless ace_candidate
      score -= 50
      PBDebug.log_score_change(
        -50,
        "ITEM AI: Non-ace Pokemon, item discouraged."
      )
    end

    if ace_candidate
      score += 30
      PBDebug.log_score_change(
        30,
        "ITEM AI: Ace Pokemon preservation priority."
      )
    end

    if !can_switch && battler.hp < battler.totalhp * 0.25
      score += 30
      PBDebug.log_score_change(
        30,
        "ITEM AI: Forced item (cannot switch, low HP)."
      )
    end

    next score
  }
)
