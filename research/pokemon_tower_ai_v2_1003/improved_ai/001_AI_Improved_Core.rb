#===============================================================================
# [AI_Improved.rb] - Safe Move-Scoring AI for Pokémon Essentials v21.1
# - DBK / Doubles / Raid compatible
#===============================================================================

#===============================================================================
# Override: AI chooses actions BEFORE the player, not after.
#===============================================================================
class Battle
  def pbCommandPhase
    @command_phase = true
    @scene.pbBeginCommandPhase
    @battlers.each_with_index do |b, i|
      next if !b
      pbClearChoice(i) if pbCanShowCommands?(i)
      pbDeluxeTriggers(i, nil, "RoundStartCommand", 1 + @turnCount) if !b.fainted?
    end
    2.times { |side| pbActionCommands(side) }
    pbCommandPhaseLoop(false)   # AI chooses their actions
    if @decision != 0   # Battle ended, stop choosing actions
      @command_phase = false
      return
    end
    pbCommandPhaseLoop(true)    # Player chooses their actions
    @command_phase = false
  end
end


class Battle::Battler
  alias _tower_fog_pbProcessTurn pbProcessTurn
  def pbProcessTurn(choice, tryFlee = true)
    ret = _tower_fog_pbProcessTurn(choice, tryFlee)
    if @battle.is_simulation
      acted_this_turn = @lastRoundMoved == @battle.turnCount
      @_sim_action_turn = (acted_this_turn ? @battle.turnCount : nil)
      @_sim_action_succeeded = (acted_this_turn && !@lastMoveFailed)
    end
    ret
  end

  # Fix: Struggle is blocked by Choice lock during the attack phase because
  # pbTryUseMove calls pbCanChooseMove?, which rejects any move that isn't the
  # Choice-locked move. Struggle should always be usable.
  alias _tower_struggle_pbCanChooseMove pbCanChooseMove?
  def pbCanChooseMove?(move, commandPhase, showMessages = true, specialUsage = false)
    return true if move.is_a?(Battle::Move::Struggle)
    return _tower_struggle_pbCanChooseMove(move, commandPhase, showMessages, specialUsage)
  end
end

#-------------------------------------------------------------------------------
# Delegate missing AIBattler methods to real battler
#-------------------------------------------------------------------------------
class Battle::AI::AIBattler
  def method_missing(method, *args, &block)
    @battler.send(method, *args, &block)
  end

  def respond_to_missing?(method, include_private = false)
    @battler.respond_to?(method, include_private)
  end
end

class Battle::AI
  MOVE_FAIL_SCORE = -999

  INTIMIDATE_IMMUNE = [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY,
                       :HYPERCUTTER, :INNERFOCUS, :OBLIVIOUS,
                       :OWNTEMPO, :SCRAPPY, :GUARDDOG].freeze

  MOVE_SCORE_THRESHOLD_TERRIBLE_MOVES = 80
  REPLACEMENT_THRESHOLD_TERRIBLE_MOVES = 95
  REPLACEMENT_THRESHOLD_SHOULD_SWITCH = 70
  DYNAMAX_REPLACEMENT_THRESHOLD_BONUS = 20
  FOE_IDLE_RESCORE_CHANCE = 50

  #---------------------------------------------------------------------------
  # Apply registered transforms (ultra/mega/tera/dynamax) and assumed foe Mega
  # Evolutions to a disposable scoring copy. Ability gain hooks are run on the
  # copy so weather, terrain and other field effects match the transformed form.
  #---------------------------------------------------------------------------
  def apply_registered_transforms_to_scoring_copy(idxBattler)
    sim = { transforms: [] }
    battler = @battle.battlers[idxBattler]
    # AI's own Ultra Burst
    if @battle.pbRegisteredUltraBurst?(idxBattler) && !battler.ultra?
      prev_form = battler.form
      old_ability = battler.ability_id
      battler.pokemon.makeUltra
      battler.form = battler.pokemon.form
      battler.pbUpdate(true)
      trigger_simulated_form_ability_change(battler, old_ability)
      sim[:transforms] << { battler: battler, type: :ultra, prev_form: prev_form }
      PBDebug.log_ai("[scoring_copy] Ultra Burst applied: #{battler.name}")
    end
    # Apply all predicted Mega Evolutions in the same fixed priority order used
    # by the real attack phase. This makes the last weather ability deterministic.
    apply_megas_to_scoring_copy(idxBattler, sim)
    # AI's own tera
    if !battler.mega? &&
       @battle.pbRegisteredTerastallize?(idxBattler) && !battler.tera?
      prev_form = battler.form
      old_ability = battler.ability_id
      battler.pokemon.terastallized = true
      battler.form = battler.pokemon.form if battler.form != battler.pokemon.form
      battler.pbUpdate(true)
      if battler.respond_to?(:tera_form?) && battler.tera_form?
        trigger_simulated_form_ability_change(battler, old_ability)
      end
      sim[:transforms] << { battler: battler, type: :tera, prev_form: prev_form }
      PBDebug.log_ai("[scoring_copy] Tera applied: #{battler.name} (#{battler.pokemon.tera_type})")
    end
    # AI's own dynamax
    if @battle.pbRegisteredDynamax?(idxBattler) && !battler.dynamax?
      prev_form = battler.form
      battler.pokemon.makeDynamaxForm
      battler.form = battler.pokemon.form
      battler.pokemon.makeDynamax
      # Keep nested battle sims from immediately ending the copied Dynamax state.
      battler.effects[PBEffects::Dynamax] = Settings::DYNAMAX_TURNS
      battler.pbUpdate(true)
      sim[:transforms] << { battler: battler, type: :dynamax, prev_form: prev_form }
      PBDebug.log_ai("[scoring_copy] Dynamax applied: #{battler.name}")
    end

    sim
  end

  # Return at most one predicted Mega per trainer, ordered exactly as the
  # copied battle's attack-phase priority array. Registered Megas win over an
  # assumption; otherwise the first Mega-capable opposing battler is assumed.
  def predicted_scoring_copy_megas(idxBattler, battle = @battle)
    battle.pbCalculatePriority(true)
    priority = battle.pbPriority
    candidates_by_owner = {}
    priority.each do |b|
      next unless b && !b.fainted? && !b.mega?
      registered = battle.pbRegisteredMegaEvolution?(b.index)
      next unless registered || (b.opposes?(idxBattler) && b.pokemon&.hasMegaForm?)
      owner = battle.pbGetOwnerIndexFromBattlerIndex(b.index)
      key = [b.idxOwnSide, owner]
      candidates_by_owner[key] ||= []
      candidates_by_owner[key] << [b, registered]
    end
    selected = candidates_by_owner.values.map do |entries|
      registered_entry = entries.find { |entry| entry[1] }
      (registered_entry || entries.first)[0]
    end
    priority.select { |b| selected.include?(b) }
  end

  def apply_megas_to_scoring_copy(idxBattler, sim)
    mega_order = predicted_scoring_copy_megas(idxBattler)
    if !mega_order.empty?
      labels = mega_order.map { |b| "#{b.name} (#{b.index})" }
      PBDebug.log_ai("[scoring_copy] Mega order: #{labels.join(' -> ')}")
    end
    mega_order.each do |b|
      prev_form = b.form
      old_ability = b.ability_id
      b.pokemon.makeMega
      b.form = b.pokemon.form
      b.pbUpdate(true)
      trigger_simulated_form_ability_change(b, old_ability)
      sim[:transforms] << { battler: b, type: :mega, prev_form: prev_form }
      PBDebug.log_ai("[scoring_copy] Mega applied: #{b.name}")
    end
  end

  def trigger_simulated_form_ability_change(battler, old_ability)
    battler.pbOnLosingAbility(old_ability)
    battler.pbTriggerAbilityOnGainingIt
    PBDebug.log_ai("[scoring_copy] #{battler.name}: ability #{old_ability.inspect} -> #{battler.ability_id.inspect}, weather=#{@battle.field.weather.inspect}")
  end

  def score_moves_on_transform_copy(idxBattler)
    scoring_battle = create_scoring_battle_copy
    with_scoring_battle(scoring_battle, idxBattler) do
      begin
        preview = apply_registered_transforms_to_scoring_copy(idxBattler)
        @_registered_transform_preview = preview
        transformed_user = @battle.battlers[idxBattler]
        @_scored_user_dynamax = transformed_user.respond_to?(:dynamax?) && transformed_user.dynamax?
        pbGetMoveScores
      ensure
        @_registered_transform_preview = nil
      end
    end
  end

  def unregister_terapagos_tera_for_passive_move(idxBattler)
    battler = @battle.battlers[idxBattler]
    return false unless battler
    return false unless battler.isSpecies?(:TERAPAGOS)
    return false unless @battle.pbRegisteredTerastallize?(idxBattler)
    return false unless battler.hasActiveAbility?(:TERASHELL) && battler.hp == battler.totalhp

    @battle.pbUnregisterTerastallize(idxBattler)
    PBDebug.log_ai("[tera rollback] #{battler.name} canceled Terastallization after choosing a non-damaging move with Tera Shell active")
    true
  end

  #---------------------------------------------------------------------------
  # Override pbPredictMoveFailureAgainstTarget to accept explicit arguments.
  # Replaces both the base Essentials and Gen 9 Pack versions.
  # Existing callers pass no args and get the same behavior as before.
  #---------------------------------------------------------------------------
  def pbPredictMoveFailureAgainstTarget(move = @move, user = @user, target = @target)
    # Move effect-specific checks
    return true if Battle::AI::Handlers.move_will_fail_against_target?(move.function_code, move, user, target, self, @battle)
    # Psychic Terrain blocks priority moves against grounded targets
    return true if @battle.field.terrain == :Psychic && target.affectedByTerrain? &&
                   target.opposes?(user) && move.rough_priority(user) > 0
    # Ability immunity (Volt Absorb, Flash Fire, Levitate, Good as Gold, etc.)
    return true if move.move.pbImmunityByAbility(user, target, false)
    # Dazzling / Queenly Majesty / Armor Tail — ally-side priority block
    if move.rough_priority(user) > 0 && target.opposes?(user)
      each_same_side_battler(target.side) do |b, _i|
        return true if b.has_active_ability?([:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL])
      end
    end
    # Commander immunity (conditional on form state)
    return true if target.has_active_ability?(:COMMANDER) && target.isCommander?
    # Type immunity
    calc_type = move.rough_type
    typeMod = move.move.pbCalcTypeMod(calc_type, user, target)
    return true if move.move.pbDamagingMove? && Effectiveness.ineffective?(typeMod)
    # Dark-type immunity to Prankster-boosted status moves
    return true if Settings::MECHANICS_GENERATION >= 7 && move.statusMove? &&
                   user.has_active_ability?(:PRANKSTER) && target.has_type?(:DARK) && target.opposes?(user)
    # Airborne immunity to Ground moves
    return true if move.damagingMove? && calc_type == :GROUND &&
                   target.airborne? && !move.move.hitsFlyingTargets?
    # Powder move immunity
    return true if move.move.powderMove? && !target.affectedByPowder?
    # Substitute blocks non-ignoring status moves
    return true if target.effects[PBEffects::Substitute] > 0 && move.statusMove? &&
                   !move.move.ignoresSubstitute?(user) && user.index != target.index
    return false
  end

  # Override: replace -1 sentinel with MOVE_FAIL_SCORE for failed moves,
  # so negative penalty scores aren't confused with move failures.
  def pbGetMoveScoreAgainstTarget
    if @trainer.has_skill_flag?("PredictMoveFailure") && pbPredictMoveFailureAgainstTarget
      PBDebug.log("     move will not affect #{@target.name}")
      PBDebug.log_score_change(MOVE_FAIL_SCORE - MOVE_BASE_SCORE, "move will fail")
      return MOVE_FAIL_SCORE
    end
    score = MOVE_BASE_SCORE
    if @trainer.has_skill_flag?("ScoreMoves")
      old_score = score
      score = Battle::AI::Handlers.apply_move_effect_against_target_score(@move.function_code,
         MOVE_BASE_SCORE, @move, @user, @target, self, @battle)
      PBDebug.log_score_change(score - old_score, "function code modifier (against target)")
      score = Battle::AI::Handlers.apply_general_move_against_target_score_modifiers(
        score, @move, @user, @target, self, @battle)
    end
    target_data = @move.pbTarget(@user)
    if pbShouldInvertScore?(target_data)
      if score == MOVE_USELESS_SCORE
        PBDebug.log("     move is useless against #{@target.name}")
        return MOVE_FAIL_SCORE
      end
      old_score = score
      score = ((1.85 * MOVE_BASE_SCORE) - score).to_i
      PBDebug.log_score_change(score - old_score, "score inverted (move targets ally but can target foe)")
    end
    return score
  end

  # Override: Returns whether the move will definitely fail (assuming no battle conditions
  # change between now and using the move).
  def pbPredictMoveFailure
    # User is awake and can't use moves that are only usable when asleep
    return true if !@user.asleep? && @move.move.usableWhenAsleep?

    # Primal weather
    return true if @battle.pbWeather == :HeavyRain && @move.rough_type == :FIRE
    return true if @battle.pbWeather == :HarshSun && @move.rough_type == :WATER
    # Move effect-specific checks
    return true if Battle::AI::Handlers.move_will_fail?(@move.function_code, @move, @user, self, @battle)
    return false
  end

  # Override: remove the core engine's score = 0 clamp (line 284) so negative
  # scores from penalties are preserved, letting the AI pick the least-bad move.
  def pbGetMoveScore(targets = nil)
    score = MOVE_BASE_SCORE
    if targets
      score = 0
      affected_targets = 0
      orig_move = @move.move
      targets.each do |target|
        set_up_move_check(orig_move)
        set_up_move_check_target(target)
        t_score = pbGetMoveScoreAgainstTarget
        next if t_score <= MOVE_FAIL_SCORE
        score += t_score
        affected_targets += 1
      end
      if affected_targets == 0
        score = (@trainer.has_skill_flag?("PredictMoveFailure")) ? MOVE_USELESS_SCORE : MOVE_BASE_SCORE
      end
      if affected_targets == 0 && @trainer.has_skill_flag?("PredictMoveFailure")
        if !@move.move.worksWithNoTargets?
          PBDebug.log_score_change(MOVE_FAIL_SCORE, "move will fail")
          return MOVE_FAIL_SCORE
        end
      else
        score /= affected_targets if affected_targets > 1
        if @trainer.has_skill_flag?("PreferMultiTargetMoves") && affected_targets > 1
          old_score = score
          score += (affected_targets - 1) * 10
          PBDebug.log_score_change(score - old_score, "affects multiple battlers")
        end
      end
    end
    if @trainer.has_skill_flag?("ScoreMoves")
      old_score = score
      score = Battle::AI::Handlers.apply_move_effect_score(@move.function_code,
         score, @move, @user, self, @battle)
      PBDebug.log_score_change(score - old_score, "function code modifier (generic)")
      score = Battle::AI::Handlers.apply_general_move_score_modifiers(
        score, @move, @user, self, @battle)
    end
    return score.to_i
  end

  def maybe_rescore_with_idle_foe(choices)
    return choices if !choices || choices.empty?
    return choices if @_foe_idle_rescore_for_scoring

    roll = pbAIRandom(100)
    PBDebug.log_ai("[foe_idle_rescore] roll=#{roll} (need <#{FOE_IDLE_RESCORE_CHANCE})")
    return choices unless roll < FOE_IDLE_RESCORE_CHANCE

    begin
      @_foe_idle_rescore_for_scoring = true
      @_matchup_cache = nil
      PBDebug.log_ai("[foe_idle_rescore] rescoring moves assuming foes do nothing")
      rescored = score_moves_on_transform_copy(@user.index)
      rescored.empty? ? choices : rescored
    ensure
      @_foe_idle_rescore_for_scoring = nil
      @_matchup_cache = nil
    end
  end

  def move_score_switch_threshold(threshold)
    return threshold
  end

  def replacement_switch_threshold(threshold)
    battler = @user && @user.battler
    user_is_dynamaxed = @_scored_user_dynamax ||
                        (battler && battler.respond_to?(:dynamax?) && battler.dynamax?)
    return threshold unless user_is_dynamaxed
    threshold + DYNAMAX_REPLACEMENT_THRESHOLD_BONUS
  end

  def pbDefaultChooseEnemyCommand(idxBattler)
    with_decision_cache do
      set_up(idxBattler)
      # 1. Special commands (Mega, Dynamax, etc.)
      ret = false
      PBDebug.logonerr { ret = pbChooseToUseSpecialCommand }
      if ret
        PBDebug.log("")
        return
      end
      if @battle.pbAutoFightMenu(idxBattler)
        PBDebug.log("")
        return
      end
      pbRegisterEnemySpecialAction(idxBattler)
      ensure_registered_tera_foe_actions
      begin
        # 2. Score moves against a transformed copy of the live battle.
        choices = score_moves_on_transform_copy(idxBattler)
        # chance to not care about score
        roll = pbAIRandom(100)
        max_move_score = choices.map { |c| c[1] }.max || 0
        max_move_score -= 10 if @battle.battlers[idxBattler].effects[PBEffects::Yawn] == 1 && @battle.battlers[idxBattler].pbCanSleepYawn?
        PBDebug.log_ai("Best move score: #{max_move_score},  dont care roll: #{roll}")
        mediocre_move_threshold = move_score_switch_threshold(MOVE_BASE_SCORE)
        terrible_move_threshold = move_score_switch_threshold(MOVE_SCORE_THRESHOLD_TERRIBLE_MOVES)
        checked_reserves = false
        # 3. Try switching before items if moves are mediocre.
        if max_move_score < mediocre_move_threshold && roll > 10
          ret = false
          checked_reserves = true
          PBDebug.logonerr { ret = pbChooseToSwitchOut(true, threshold: 120) }
          if ret
            PBDebug.log("")
            return
          end
          PBDebug.logonerr { ret = pbChooseToUseItem(:current) }
          if ret
            PBDebug.log("")
            return
          end
        end
        # 4. Terrible moves: try switching
        if max_move_score < terrible_move_threshold && roll > 20
          ret = false
          checked_reserves = true
          PBDebug.logonerr { ret = pbChooseToSwitchOut(true, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES) }
          if ret
            PBDebug.log("")
            return
          end
          PBDebug.logonerr { ret = pbChooseToUseItem(:reserve) }
          # 5. Reserve-targeted items are a last resort.
          if ret
            PBDebug.log("")
            return
          end
        end
        if checked_reserves
          ret = false
          PBDebug.logonerr { ret = pbChooseSackReplacement }
          if ret
            PBDebug.log("")
            return
          end
        end
        choices = maybe_rescore_with_idle_foe(choices) if checked_reserves
        # 6. Choose move as normal
        pbChooseMove(choices)
        chosen_move = @battle.choices[idxBattler][2]
        # unregister tera for terapagos when terashell active
        if chosen_move && !chosen_move.damagingMove?
          unregister_terapagos_tera_for_passive_move(idxBattler)
        end
        PBDebug.log("")
        pbRegisterEnemySpecialAction2(idxBattler)
      ensure
        @_scored_user_dynamax = nil
      end
    ensure
    end
  end

  def pbDefaultChooseNewEnemy(idxBattler)
    result = with_decision_cache do
      set_up(idxBattler)
      choose_best_replacement_pokemon(idxBattler, true)
    end
    register_fresh_switch_score(idxBattler, result) if result >= 0
    result
  end

  # The scoring copy already has Max Moves, but the live battler does not.
  # Convert the live move slot before Battle stores the selected move object.
  def register_scored_move_choice(user_battler, choice)
    scored_move = choice[4]
    if scored_move&.dynamaxMove? &&
       @battle.pbRegisteredDynamax?(user_battler.index)
      user_battler.display_dynamax_moves
    end
    @battle.pbRegisterMove(user_battler.index, choice[0], false)
  end

  # Sucker Punch mind games: 30% chance to swap to a OHKO damaging move
  # instead, punishing players who predict priority and use status moves.
  def try_sucker_punch_mindgame(choices, user_battler)
    chosen_move = @battle.choices[user_battler.index][2]
    return unless chosen_move
    PBDebug.log_ai("[Sucker Punch mind game] chosen=#{chosen_move.class} (#{chosen_move.name})")
    return unless chosen_move.is_a?(Battle::Move::FailsIfTargetActed)
    roll = pbAIRandom(100)
    PBDebug.log_ai("[Sucker Punch mind game] roll=#{roll} (need <30)")
    return unless roll < 30
    target_idx = @battle.choices[user_battler.index][3]
    return unless target_idx >= 0
    foe = @battlers[target_idx]
    return unless foe
    best_alt = nil
    choices.each do |c|
      next if c[4].is_a?(Battle::Move::FailsIfTargetActed)
      next unless c[4].damagingMove?
      next unless c[2] == target_idx
      best_alt = c if best_alt.nil? || c[1] > best_alt[1]
    end
    return unless best_alt
    register_scored_move_choice(user_battler, best_alt)
    @battle.pbRegisterTarget(user_battler.index, best_alt[2]) if best_alt[2] && best_alt[2] >= 0
    PBDebug.log_ai("=> Sucker Punch mind game: swapped to #{best_alt[4].name}")
  end

  #override choose move - remove turn count limit
  def pbChooseMove(choices)
    user_battler = @user.battler
    max_score = choices.map { |c| c[1] }.max || 0
    if choices.length == 0
      @battle.pbAutoChooseMove(user_battler.index)
      PBDebug.log_ai("#{@user.name} will auto-use a move or Struggle")
      return
    end

    deterministic_best = max_score < 50
    selected_choice = deterministic_best ? choices.max_by { |c| c[1] } : nil
    if deterministic_best
      choices.each { |c| c[3] = c.equal?(selected_choice) ? 1 : 0 }
      total_score = 1
      PBDebug.log_ai("Move choices for #{@user.name}: top score below 50, choosing highest score")
    else
      threshold = [max_score - 20, 120].min
      threshold = -20 if threshold > -20 && threshold < 50
      choices.each { |c| c[3] = [c[1] - threshold, 0].max }
      total_score = choices.sum { |c| c[3] }
      PBDebug.log_ai("Move choices for #{@user.name} with threshold: #{threshold}: ")
    end
    choices.each_with_index do |c, i|
      chance = sprintf("%5.1f", 100.0 * c[3] / total_score)
      log_msg = "   * #{chance}% to use #{c[4].name}"
      log_msg += " (target #{c[2]})" if c[2] >= 0
      log_msg += ": score #{c[1]}"
      PBDebug.log_ai(log_msg)
    end
    if !selected_choice
      randNum = pbAIRandom(total_score)
      choices.each do |c|
        randNum -= c[3]
        next if randNum >= 0
        selected_choice = c
        break
      end
    end
    pbRegisterEnemySpecialActionFromMove(user_battler, selected_choice[4])
    register_scored_move_choice(user_battler, selected_choice)
    @battle.pbRegisterTarget(user_battler.index, selected_choice[2]) if selected_choice[2] && selected_choice[2] >= 0
    try_sucker_punch_mindgame(choices, user_battler) if !deterministic_best
    chosen_move = @battle.choices[user_battler.index][2]
    if chosen_move
      if @battle.choices[user_battler.index][3] >= 0
        PBDebug.log_ai("=> will use #{chosen_move.name} (target #{@battle.choices[user_battler.index][3]})")
      else
        PBDebug.log_ai("=> will use #{chosen_move.name}")
      end
    end
    # PBDebug.flush
  end

  # Voluntary switch check, including the lower ShouldSwitch fallback threshold.
  def pbChooseToSwitchOut(terrible_moves = true, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES)
    return false if !@battle.canSwitch   # Battle rule
    return false if @user.wild?
    return false if !@battle.pbCanSwitchOut?(@user.index)
    switch_branch = (threshold > REPLACEMENT_THRESHOLD_TERRIBLE_MOVES) ? :mediocre_moves : :terrible_moves
    replacement_threshold = replacement_switch_threshold(threshold)
    # 1) Try replacement at this branch's direct replacement threshold.
    idxParty = choose_best_replacement_pokemon(@user.index, false, threshold: replacement_threshold)
    if idxParty < 0
      # 2) ShouldSwitch handlers only gate the terrible-move lower threshold.
      if switch_branch == :terrible_moves && @trainer.has_skill_flag?("ConsiderSwitching")
        PBDebug.log_ai("   => no replacement at threshold #{replacement_threshold}, trying ShouldSwitch handlers")
        reserves = get_non_active_party_pokemon(@user.index)
        if !reserves.empty?
          should_switch = Battle::AI::Handlers.should_switch?(@user, reserves, self, @battle)
          if should_switch && @trainer.medium_skill?
            should_switch = false if Battle::AI::Handlers.should_not_switch?(@user, reserves, self, @battle, switch_branch)
          end
          if should_switch
            fallback_threshold = replacement_switch_threshold(REPLACEMENT_THRESHOLD_SHOULD_SWITCH)
            idxParty = choose_best_replacement_pokemon(@user.index, false, threshold: fallback_threshold)
          end
        end
      else
        PBDebug.log_ai("   => no replacement at threshold #{replacement_threshold}")
      end
    end
    if idxParty < 0
      PBDebug.log_ai("   => no good replacement Pokémon, will not switch after all")
      return false
    end
    if @battle.pbRegisterSwitch(@user.index, idxParty)
      PBDebug.log_ai("=> will switch with #{@battle.pbParty(@user.index)[idxParty].name}")
      register_fresh_switch_score(@user.index, idxParty)
      return true
    end
    return false
  end

  def register_fresh_switch_score(idxBattler, idxParty, score: nil)
    @_fresh_switch_scores ||= {}
    pkmn = @battle.pbParty(idxBattler)[idxParty]
    @_fresh_switch_scores[idxBattler] = {
      score:       score || @_last_replacement_score || 100,
      personal_id: pkmn.personalID,
      foe_ids:     current_foe_personal_ids(idxBattler)
    }
    PBDebug.log_ai("  [fresh_switch] stored score #{@_fresh_switch_scores[idxBattler][:score]} for #{pkmn.name}")
  end

  def current_foe_personal_ids(idxBattler)
    @battle.allOtherSideBattlers(idxBattler).map { |b| b.pokemon&.personalID }.compact.sort
  end

  def throw_if_simulating_replacement_rating(idxBattler)
    return if !@battle.respond_to?(:is_simulation) || !@battle.is_simulation
    PBDebug.log_ai("[AI SIM] Aborting simulation: replacement rating requested for battler #{idxBattler}")
    throw SIM_SWITCH_TRIGGERED, { reason: :replacement_rating, battler_index: idxBattler }
  end

  def choose_best_replacement_pokemon(idxBattler, forced_switch = false, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES)
    throw_if_simulating_replacement_rating(idxBattler)
    # Clear caches only on forced switches (faints/pivots) where a different
    # Pokémon now occupies the battler index, invalidating cached results.
    if forced_switch
      @_ai_dmg_cache = {}
      @_matchup_cache = {}
      invalidate_sim_cache
    end

    # Get all possible replacement Pokémon
    party = @battle.pbParty(idxBattler)
    reserves = []
    party.each_with_index do |_pkmn, i|
      next if !@battle.pbCanSwitchIn?(idxBattler, i)
      unless forced_switch   # Choosing an action for the round
        ally_will_switch_with_i = false
        @battle.allSameSideBattlers(idxBattler).each do |b|
          next if @battle.choices[b.index][0] != :SwitchOut || @battle.choices[b.index][1] != i
          ally_will_switch_with_i = true
          break
        end
        next if ally_will_switch_with_i
      end

      reserves.push([i, 100])
      break if @trainer.has_skill_flag?("UsePokemonInOrder") && reserves.length > 0
    end
    return -1 if reserves.length == 0
    # Double KO: both sides fainted and are sending in fresh replacements,
    # meaning we don't know what the player chose — pick randomly.
    if forced_switch && @battle.battlers[idxBattler].fainted?
      # Check if our battler's underlying Pokémon still has HP (i.e. was
      # recalled alive, not truly KO'd). 
      truly_fainted = @battle.pbParty(idxBattler).none? { |pkmn|
        pkmn && pkmn == @battle.battlers[idxBattler].pokemon && pkmn.hp > 0
      }
      if truly_fainted
        foe_is_unknown = true
        @battle.allOtherSideBattlers(idxBattler).each do |b|
          if !b.fainted? && b.turnCount > 0
            foe_is_unknown = false
            break
          end
        end
        if foe_is_unknown
          chosen = reserves.sample
          PBDebug.log_ai("=> double KO: randomly choosing #{party[chosen[0]].name}")
          return chosen[0]
        end
      end
    end
    reserves = scored_replacement_candidates(idxBattler, forced_switch, party, reserves)
    @_last_replacement_score = reserves[0][1]
    # Fresh switch-in protection: if the current battler just switched in
    # (turnCount == 0) and hasn't acted yet, require the replacement to beat its
    # original replacement score — prevents flip-flopping.
    battler = @battle.battlers[idxBattler]
    fresh = (@_fresh_switch_scores || {})[idxBattler]
    if fresh && battler.turnCount == 0 && !battler.fainted? &&
        battler.pokemon&.personalID == fresh[:personal_id]
      current_foes = current_foe_personal_ids(idxBattler)
      if fresh[:foe_ids] && fresh[:foe_ids] != current_foes
        PBDebug.log_ai("=> fresh switch-in protection skipped for #{battler.name}: foe changed from #{fresh[:foe_ids].inspect} to #{current_foes.inspect}")
      elsif reserves[0][1] <= fresh[:score]
        PBDebug.log_ai("=> fresh switch-in #{battler.name} (entry score #{fresh[:score]}) >= best replacement #{party[reserves[0][0]].name} (#{reserves[0][1]}), not switching")
        return -1
      else
        PBDebug.log_ai("=> fresh switch-in #{battler.name} (entry score #{fresh[:score]}) beaten by #{party[reserves[0][0]].name} (#{reserves[0][1]})")
      end
    end
    if reserves[0][1] < threshold
      if forced_switch
        # Must switch (faint/pivot) — just pick the highest-scored reserve
        PBDebug.log_ai("=> forced switch: #{party[reserves[0][0]].name} (best score #{reserves[0][1]})")
        return reserves[0][0]
      end
      PBDebug.log_ai("=> staying in: all reserves scored < #{threshold} (best: #{reserves[0][1]}), not switching")
      return -1
    end
    poll = reserves.select { |_idxParty, score| score > 120 }
    if poll.length > 1
      total_weight = poll.sum { |_idxParty, score| score - 120 }
      if total_weight > 0
        PBDebug.log_ai("Replacement poll for reserves over 120:")
        poll.each do |idxParty, score|
          weight = score - 120
          chance = sprintf("%5.1f", 100.0 * weight / total_weight)
          PBDebug.log_ai("   * #{chance}% #{party[idxParty].name}: score #{score}")
        end
        roll = pbAIRandom(total_weight)
        poll.each do |idxParty, score|
          roll -= score - 120
          next if roll >= 0
          @_last_replacement_score = score
          PBDebug.log_ai("=> replacement poll chose #{party[idxParty].name} (score #{score})")
          return idxParty
        end
      end
    end
    # Return the party index of the best rated replacement Pokémon
    return reserves[0][0]
  end

  def scored_replacement_candidates(idxBattler, forced_switch, party, reserves)
    throw_if_simulating_replacement_rating(idxBattler)
    battler = @battle.battlers[idxBattler]
    cache_key = [
      idxBattler,
      forced_switch,
      @battle.command_phase,
      battler.pokemon&.personalID,
      battler.pokemonIndex,
      reserves.map { |reserve| reserve[0] }
    ]
    @_replacement_score_cache ||= {}
    cached = @_replacement_score_cache[cache_key]
    return cached.map(&:dup) if cached

    scored = reserves.map do |reserve|
      pkmn = party[reserve[0]]
      replacement_1v1_results(idxBattler, pkmn)
      score = rate_replacement_pokemon(idxBattler, pkmn, reserve[1])
      PBDebug.log_ai("pokemon #{party[reserve[0]].name} has switch score #{score}")
      [reserve[0], score]
    end
    scored.sort! { |a, b| b[1] <=> a[1] }
    @_replacement_score_cache[cache_key] = scored.map(&:dup)
    return scored
  end

  #override
  def rate_replacement_pokemon(idxBattler, pkmn, score)
    throw_if_simulating_replacement_rating(idxBattler)
    # The actual calculations are deferred to handlers
    score = Battle::AI::Handlers.score_replacement(idxBattler, pkmn, score, @battle, self)
    return score.to_i
  end
end

module Battle::AI::Handlers
  ScoreReplacement = HandlerHash.new

  def self.score_replacement(idxBattler, pkmn, score, battle, user_ai)
    ScoreReplacement.each do |id, score_proc|
      new_score = score_proc.call(idxBattler, pkmn, score, battle, user_ai)
      score = new_score if new_score
    end
    return score
  end
end
