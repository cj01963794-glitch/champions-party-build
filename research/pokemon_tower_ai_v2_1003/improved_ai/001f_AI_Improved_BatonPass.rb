#===============================================================================
# [AI_Improved_BatonPass.rb] - Baton Pass switch replacement logic
#===============================================================================

class Battle::AI
  BATON_PASS_FUNCTION_CODE = "SwitchOutUserPassOnEffects"
  BATON_PASS_SWITCH_SCORE_THRESHOLD = 100

  alias tower_baton_pass_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand
  def pbDefaultChooseEnemyCommand(idxBattler)
    clear_baton_pass_replacement(idxBattler)
    tower_baton_pass_pbDefaultChooseEnemyCommand(idxBattler)
  end

  def baton_pass_switch_choice(idxBattler, idxParty)
    return nil if !idxParty || idxParty < 0
    return nil if !@battle.pbCanSwitchIn?(idxBattler, idxParty)

    best_choice = nil
    @user.battler.eachMoveWithIndex do |orig_move, idxMove|
      next if safe_function_code(orig_move) != BATON_PASS_FUNCTION_CODE
      next if !@battle.pbCanChooseMove?(idxBattler, idxMove, false)

      score = MOVE_FAIL_SCORE
      set_up_move_check(orig_move)
      PBDebug.log_ai("#{@user.name} is considering using #{orig_move.name} after choosing #{@battle.pbParty(idxBattler)[idxParty].name}...")
      if @trainer.has_skill_flag?("PredictMoveFailure") && pbPredictMoveFailure
        PBDebug.log_score_change(MOVE_FAIL_SCORE - MOVE_BASE_SCORE, "move will fail")
        score = MOVE_FAIL_SCORE
      else
        PBDebug.logonerr { score = pbGetMoveScore }
      end

      PBDebug.log_ai("   Baton Pass switch score: #{score}")
      if !best_choice || score > best_choice[:score]
        best_choice = { idx_move: idxMove, move: orig_move, score: score, idx_party: idxParty }
      end
    end
    best_choice
  end

  def remember_baton_pass_replacement(idxBattler, idxParty)
    pkmn = @battle.pbParty(idxBattler)[idxParty]
    return if !pkmn

    @_baton_pass_replacements ||= {}
    @_baton_pass_replacements[idxBattler] = {
      idx_party:   idxParty,
      personal_id: pkmn.personalID
    }
  end

  def clear_baton_pass_replacement(idxBattler)
    @_baton_pass_replacements&.delete(idxBattler)
  end

  def consume_baton_pass_replacement(idxBattler)
    entry = @_baton_pass_replacements&.delete(idxBattler)
    return nil if !entry
    return nil if @battle.battlers[idxBattler]&.fainted?

    idxParty = entry[:idx_party]
    pkmn = @battle.pbParty(idxBattler)[idxParty]
    return nil if !pkmn || pkmn.personalID != entry[:personal_id]
    return nil if !@battle.pbCanSwitchIn?(idxBattler, idxParty)

    idxParty
  end

  alias tower_baton_pass_pbDefaultChooseNewEnemy pbDefaultChooseNewEnemy
  def pbDefaultChooseNewEnemy(idxBattler)
    replacement = consume_baton_pass_replacement(idxBattler)
    return tower_baton_pass_pbDefaultChooseNewEnemy(idxBattler) if !replacement

    result = with_decision_cache do
      set_up(idxBattler)
      @_ai_dmg_cache = {}
      @_matchup_cache = {}
      invalidate_sim_cache
      PBDebug.log_ai("   => Baton Pass will switch with #{@battle.pbParty(idxBattler)[replacement].name}")
      replacement
    end
    register_fresh_switch_score(idxBattler, result) if result >= 0
    result
  end

  alias tower_baton_pass_pbChooseToSwitchOut pbChooseToSwitchOut
  def pbChooseToSwitchOut(terrible_moves = true, threshold: REPLACEMENT_THRESHOLD_TERRIBLE_MOVES)
    switched = tower_baton_pass_pbChooseToSwitchOut(terrible_moves, threshold: threshold)
    return false if !switched

    choice = @battle.choices[@user.index]
    return true if choice[0] != :SwitchOut

    idxParty = choice[1]
    baton_pass = baton_pass_switch_choice(@user.index, idxParty)
    if baton_pass && baton_pass[:score] > BATON_PASS_SWITCH_SCORE_THRESHOLD
      pbRegisterEnemySpecialActionFromMove(@user.battler, baton_pass[:move])
      if @battle.pbRegisterMove(@user.index, baton_pass[:idx_move], false)
        @_fresh_switch_scores&.delete(@user.index)
        remember_baton_pass_replacement(@user.index, idxParty)
        PBDebug.log_ai("=> will use #{baton_pass[:move].name} to switch with #{@battle.pbParty(@user.index)[idxParty].name} (score #{baton_pass[:score]})")
        return true
      end
    elsif baton_pass
      PBDebug.log_ai("   => Baton Pass score #{baton_pass[:score]} is not above #{BATON_PASS_SWITCH_SCORE_THRESHOLD}; direct switch instead")
    end

    true
  end
end
