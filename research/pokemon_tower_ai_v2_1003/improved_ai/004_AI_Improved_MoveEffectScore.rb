#===============================================================================
# 3. move effect handlers (many overrides)
#===============================================================================

module AIEffectScoreHelper
  def self.get_inherent_preference(move, multiplier)
    chance = move.move.addlEffect
    chance = move.move.accuracy if chance == 0
    return (multiplier * (chance / 100.0)).round
  end

  # Returns true if the target will instantly cure a status via Hydration in rain.
  def self.hydration_cures_immediately?(target, user)
    target.faster_than?(user) &&
      target.has_active_ability?(:HYDRATION) &&
      [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
  end

  def self.get_target_heal_penalty(target, ai)
    penalty = 0
    if target.has_active_ability?(:SHEDSKIN)
      penalty -= 8
    elsif target.has_active_ability?(:HYDRATION) &&
          [:Rain, :HeavyRain].include?(target.battler.effectiveWeather)
      penalty -= 15
    end
    ai.each_same_side_battler(target.side) do |b, i|
      penalty -= 8 if i != target.index && b.has_active_ability?(:HEALER)
    end
    return penalty
  end
end

#===============================================================================
# FlinchTarget
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("FlinchTarget",
  proc { |score, move, user, target, ai, battle|
    next score if target.faster_than?(user) || target.effects[PBEffects::Substitute] > 0
    next score if target.has_active_ability?(:INNERFOCUS) && !battle.moldBreaker
    add_effect = move.get_score_change_for_additional_effect(user, target)
    next score if add_effect == -999   # Additional effect will be negated
    score += add_effect

    # Inherent preference scaled by effect chance
    score += AIEffectScoreHelper.get_inherent_preference(move, 30)

    # Prefer if the target is paralysed, confused or infatuated, to compound the
    # turn skipping
    score += 8 if target.status == :PARALYSIS ||
                  target.effects[PBEffects::Confusion] > 1 ||
                  target.effects[PBEffects::Attract] >= 0
    next score
  }
)

#===============================================================================
# SleepTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("SleepTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    next useless_score if target.effects[PBEffects::Yawn] > 0   # Target is going to fall asleep anyway
    # No score modifier if the sleep will be removed immediately
    next useless_score if target.has_active_item?([:CHESTOBERRY, :LUMBERRY])
    next useless_score if AIEffectScoreHelper.hydration_cures_immediately?(target, user)
    if target.battler.pbCanSleep?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 30)

      bonus = 0

      # Prefer if the user or an ally has a move/ability that is better if the target is asleep
      ai.each_same_side_battler(user.side) do |b, i|
        bonus += 5 if b.has_move_with_function?("DoublePowerIfTargetAsleepCureTarget",
                                                "DoublePowerIfTargetStatusProblem",
                                                "HealUserByHalfOfDamageDoneIfTargetAsleep",
                                                "StartDamageTargetEachTurnIfTargetAsleep")
        bonus += 10 if b.has_active_ability?(:BADDREAMS)
      end
      # Don't prefer if target benefits from having the sleep status problem
      # NOTE: The target's Guts/Quick Feet will benefit from the target being
      #       asleep, but the target won't (usually) be able to make use of
      #       them, so they're not worth considering.
      bonus -= 10 if target.has_active_ability?(:EARLYBIRD)
      bonus -= 8 if target.has_active_ability?(:MARVELSCALE)
      # Don't prefer if target has a move it can use while asleep
      bonus -= 8 if target.check_for_move { |m| m.usableWhenAsleep? }
      # Don't prefer if the target can heal itself (or be healed by an ally)
      bonus += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

      score += AIEffectScoreHelper.get_inherent_preference(move, bonus)
    end
    next score
  }
)

#===============================================================================
# PoisonTarget
#===============================================================================
# Add score modifier for Barb Barrage and Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("PoisonTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    next useless_score if target.has_active_ability?(:POISONHEAL)
    # No score modifier if the poisoning will be removed immediately
    next useless_score if target.has_active_item?([:PECHABERRY, :LUMBERRY])
    next useless_score if AIEffectScoreHelper.hydration_cures_immediately?(target, user)
    if target.battler.pbCanPoison?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect

      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 30)

      bonus = 0
      # Prefer if the target is at high HP
      if ai.trainer.has_skill_flag?("HPAware")
        bonus += 15 * target.hp / target.totalhp
      end
      # Prefer if the user or an ally has a move/ability that is better if the target is poisoned
      ai.each_same_side_battler(user.side) do |b, i|
        bonus += 5 if b.has_move_with_function?("DoublePowerIfTargetPoisoned",
                                                "DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetPoisonedPoisonTarget",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
        bonus += 10 if b.has_active_ability?(:MERCILESS)
      end
      # Don't prefer if target benefits from having the poison status problem
      bonus -= 8 if target.has_active_ability?([:GUTS, :MARVELSCALE, :QUICKFEET, :TOXICBOOST])
      bonus -= 25 if target.has_active_ability?(:POISONHEAL)
      bonus -= 20 if target.has_active_ability?(:SYNCHRONIZE) &&
                     user.battler.pbCanPoisonSynchronize?(target.battler)
      bonus -= 5 if target.has_move_with_function?("DoublePowerIfUserPoisonedBurnedParalyzed",
                                                   "CureUserBurnPoisonParalysis")
      bonus -= 15 if target.check_for_move { |m|
        m.function_code == "GiveUserStatusToTarget" && user.battler.pbCanPoison?(target.battler, false, m)
      }
      # Don't prefer if the target won't take damage from the poison
      bonus -= 20 if !target.battler.takesIndirectDamage?
      # Don't prefer if the target can heal itself (or be healed by an ally)
      bonus += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

      score += AIEffectScoreHelper.get_inherent_preference(move, bonus)
    end
    next score
  }
)

#===============================================================================
# ParalyzeTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ParalyzeTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    # No score modifier if the paralysis will be removed immediately
    next useless_score if target.has_active_item?([:CHERIBERRY, :LUMBERRY])
    next useless_score if AIEffectScoreHelper.hydration_cures_immediately?(target, user)
    if target.battler.pbCanParalyze?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 10)

      bonus = 0

      # Prefer if the target is faster than the user but will become slower if
      # paralysed
      if target.faster_than?(user)
        user_speed = user.rough_stat(:SPEED)
        target_speed = target.rough_stat(:SPEED)
        bonus += 30 if target_speed < user_speed * ((Settings::MECHANICS_GENERATION >= 7) ? 2 : 4)
      end
      # Prefer if the user or an ally has a move/ability that is better if the target is paralysed
      ai.each_same_side_battler(user.side) do |b, i|
        bonus += 5 if b.has_move_with_function?("DoublePowerIfTargetParalyzedCureTarget",
                                                "DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
      end
      # Don't prefer if target benefits from having the paralysis status problem
      bonus -= 8 if target.has_active_ability?([:GUTS, :MARVELSCALE, :QUICKFEET])
      bonus -= 20 if target.has_active_ability?(:SYNCHRONIZE) &&
                     user.battler.pbCanParalyzeSynchronize?(target.battler)
      bonus -= 5 if target.has_move_with_function?("DoublePowerIfUserPoisonedBurnedParalyzed",
                                                   "CureUserBurnPoisonParalysis")
      bonus -= 15 if target.check_for_move { |m|
        m.function_code == "GiveUserStatusToTarget" && user.battler.pbCanParalyze?(target.battler, false, m)
      }
      # Don't prefer if the target can heal itself (or be healed by an ally)
      bonus += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

      score += AIEffectScoreHelper.get_inherent_preference(move, bonus)
    end
    next score
  }
)

#===============================================================================
# BurnTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("BurnTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    # No score modifier if the burn will be removed immediately
    next useless_score if target.has_active_item?([:RAWSTBERRY, :LUMBERRY])
    next useless_score if AIEffectScoreHelper.hydration_cures_immediately?(target, user)
    if target.battler.pbCanBurn?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 20)

      bonus = 0

      # Prefer if the target knows any physical moves that will be weakened by a burn
      has_physical = target.check_for_move { |m| m.physicalMove? }
      has_special = target.check_for_move { |m| m.specialMove? }
      if !target.has_active_ability?(:GUTS)
        if has_physical
          bonus += 8
          bonus += 8 if !has_special  # Only physical moves
        elsif has_special
          # Penalize if target is a pure special attacker (burn's attack drop is wasted)
          bonus -= move.statusMove? ? 60 : 15
        end
      end
      # Prefer if the user or an ally has a move/ability that is better if the target is burned
      ai.each_same_side_battler(user.side) do |b, i|
        bonus += 5 if b.has_move_with_function?("DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
      end
      # Don't prefer if target benefits from having the burn status problem
      bonus -= 8 if target.has_active_ability?([:FLAREBOOST, :GUTS, :MARVELSCALE, :QUICKFEET])
      bonus -= 5 if target.has_active_ability?(:HEATPROOF)
      bonus -= 20 if target.has_active_ability?(:SYNCHRONIZE) &&
                     user.battler.pbCanBurnSynchronize?(target.battler)
      bonus -= 5 if target.has_move_with_function?("DoublePowerIfUserPoisonedBurnedParalyzed",
                                                   "CureUserBurnPoisonParalysis")
      bonus -= 15 if target.check_for_move { |m|
        m.function_code == "GiveUserStatusToTarget" && user.battler.pbCanBurn?(target.battler, false, m)
      }
      # Don't prefer if the target won't take damage from the burn
      bonus -= 20 if !target.battler.takesIndirectDamage?
      # Don't prefer if the target can heal itself (or be healed by an ally)
      bonus += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

      score += AIEffectScoreHelper.get_inherent_preference(move, bonus)
    end
    next score
  }
)

#===============================================================================
# FreezeTarget
#===============================================================================
# Add score modifier for Infernal Parade
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("FreezeTarget",
  proc { |score, move, user, target, ai, battle|
    useless_score = (move.statusMove?) ? Battle::AI::MOVE_USELESS_SCORE : score
    # No score modifier if the freeze will be removed immediately
    next useless_score if target.has_active_item?([:ASPEARBERRY, :LUMBERRY])
    next useless_score if AIEffectScoreHelper.hydration_cures_immediately?(target, user)
    if target.battler.pbCanFreeze?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next useless_score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      
      # Inherent preference scaled by effect chance
      score += AIEffectScoreHelper.get_inherent_preference(move, 30)

      bonus = 0 

      # Prefer if the user or an ally has a move/ability that is better if the target is frozen
      ai.each_same_side_battler(user.side) do |b, i|
        bonus += 5 if b.has_move_with_function?("DoublePowerIfTargetStatusProblem",
                                                "DoublePowerIfTargetStatusProblemBurnTarget")
      end
      # Don't prefer if target benefits from having the frozen status problem
      # NOTE: The target's Guts/Quick Feet will benefit from the target being
      #       frozen, but the target won't be able to make use of them, so
      #       they're not worth considering.
      bonus -= 8 if target.has_active_ability?(:MARVELSCALE)
      # Don't prefer if the target knows a move that can thaw it
      bonus -= 15 if target.check_for_move { |m| m.thawsUser? }
      # Don't prefer if the target can heal itself (or be healed by an ally)
      bonus += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

      score += AIEffectScoreHelper.get_inherent_preference(move, bonus)
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ConfuseTarget",
  proc { |score, move, user, target, ai, battle|
    # No score modifier if the status problem will be removed immediately
    next score if target.has_active_item?(:PERSIMBERRY)
    if target.battler.pbCanConfuse?(user.battler, false, move.move)
      add_effect = move.get_score_change_for_additional_effect(user, target)
      next score if add_effect == -999   # Additional effect will be negated
      score += add_effect
      # Inherent preference
      score += AIEffectScoreHelper.get_inherent_preference(move, 10)

      bonus = 0
      # Prefer if the target is at high HP
      if ai.trainer.has_skill_flag?("HPAware")
        bonus += 20 * target.hp / target.totalhp
      end

      # Don't prefer if target benefits from being confused
      bonus -= 15 if target.has_active_ability?(:TANGLEDFEET)

      score += AIEffectScoreHelper.get_inherent_preference(move, bonus)
    end
    next score
  }
)

# Re-copy handlers that inherited from base/plugin versions before these
# overrides loaded. SleepTargetNextTurn is intentionally omitted because this
# plugin defines its own dedicated handler below.
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("BurnTarget",
                                                        "StarmobileBurnTarget")
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("ConfuseTarget",
                                                        "ConfuseTargetAlwaysHitsInRainHitsTargetInSky",
                                                        "StarmobileConfuseTarget")
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("FlinchTarget",
                                                        "FlinchTargetDoublePowerIfTargetInSky",
                                                        "FlinchTargetFailsIfNotUserFirstTurn",
                                                        "FlinchTargetFailsIfUserNotAsleep")
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("FreezeTarget",
                                                        "FreezeTargetAlwaysHitsInHail",
                                                        "FreezeTargetSuperEffectiveAgainstWater")
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("ParalyzeTarget",
                                                        "ParalyzeTargetAlwaysHitsInRainHitsTargetInSky",
                                                        "ParalyzeTargetIfNotTypeImmune",
                                                        "StarmobileParalyzeTarget")
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("PoisonTarget",
                                                        "BadPoisonTarget",
                                                        "CategoryDependsOnHigherDamagePoisonTarget",
                                                        "StarmobilePoisonTarget")
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("SleepTarget",
                                                        "SleepTargetChangeUserMeloettaForm",
                                                        "SleepTargetIfUserDarkrai",
                                                        "StarmobileSleepTarget")

#===============================================================================
# Choice item preference
#===============================================================================
# A Choice item is only a good fit for an attack-heavy moveset. Two or more
# status moves make the lock actively harmful; mixed attacking sets which don't
# meet the threshold are treated as neutral.
choice_item_preference = proc { |item, score, battler, ai|
  moves = battler.moves.compact
  status_move_count = moves.count { |m| m.statusMove? }
  next -9 if status_move_count >= 2

  matching_attack_count = case item
                          when :CHOICEBAND
                            moves.count { |m| m.physicalMove?(m.type) }
                          when :CHOICESPECS
                            moves.count { |m| m.specialMove?(m.type) }
                          when :CHOICESCARF
                            moves.count { |m| m.damagingMove? }
                          else
                            0
                          end
  next score if matching_attack_count >= 3
  next 0
}

Battle::AI::Handlers::ItemRanking.add(:CHOICEBAND, choice_item_preference)
Battle::AI::Handlers::ItemRanking.add(:CHOICESPECS, choice_item_preference)
Battle::AI::Handlers::ItemRanking.add(:CHOICESCARF, choice_item_preference)

#===============================================================================
# Trick/Switcheroo
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("UserTargetSwapItems",
  proc { |score, move, user, target, ai, battle|
    choice_items = [:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]
    user_new_item_preference = user.wants_item?(target.item_id)
    user_old_item_preference = user.wants_item?(user.item_id)
    user_diff = user_new_item_preference - user_old_item_preference
    user_diff = 0 if !user.item_active?
    target_new_item_preference = target.wants_item?(user.item_id)
    target_old_item_preference = target.wants_item?(target.item_id)
    target_diff = target_new_item_preference - target_old_item_preference
    target_diff = 0 if !target.item_active?
    score += user_diff * 4
    score -= target_diff * 4
    # Don't prefer if user used this move in the last round
    score -= 15 if user.battler.lastMoveUsed &&
                   GameData::Move.exists?(user.battler.lastMoveUsed) &&
                   GameData::Move.get(user.battler.lastMoveUsed).function_code == move.function_code
    if choice_items.include?(target.item_id)
      score -= 100
      PBDebug.log_score_change(-100, "Trick/Switcheroo: target already has a Choice item.")
    end
    next score
  }
)

#===============================================================================
# FreezeFlinchTarget  (Ice Fang)
# BurnFlinchTarget    (Fire Fang)
# ParalyzeFlinchTarget (Thunder Fang)
#
# The base game stores EffectChance = 101 as a magic number meaning
# "10% for each of two effects".  The base AI scoring reads addlEffect
# raw (101%) and massively over-scores these moves.  These overrides
# replace the base handlers with correct 10%-scaled scoring for both
# the flinch and the status component.
#===============================================================================

# Helper: flinch component (10% chance, mirrors FlinchTarget handler logic)
module AIEffectScoreHelper
  FANG_FLINCH_CHANCE = 10
  FANG_STATUS_CHANCE = 10

  def self.fang_flinch_score(score, move, user, target, ai, battle)
    return 0 if target.faster_than?(user) || target.effects[PBEffects::Substitute] > 0
    return 0 if target.has_active_ability?(:INNERFOCUS) && !battle.moldBreaker
    add_effect = move.get_score_change_for_additional_effect(user, target)
    return 0 if add_effect == -999
    bonus = add_effect
    bonus += (30 * (FANG_FLINCH_CHANCE / 100.0)).round   # 3
    bonus += 8 if target.status == :PARALYSIS ||
                  target.effects[PBEffects::Confusion] > 1 ||
                  target.effects[PBEffects::Attract] >= 0
    bonus
  end
end

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("FreezeFlinchTarget",
  proc { |score, move, user, target, ai, battle|
    # Flinch component
    score += AIEffectScoreHelper.fang_flinch_score(score, move, user, target, ai, battle)
    # Freeze component (10% chance)
    if target.battler.pbCanFreeze?(user.battler, false, move.move)
      if !target.has_active_item?([:ASPEARBERRY, :LUMBERRY])
        can_heal = AIEffectScoreHelper.hydration_cures_immediately?(target, user)
        unless can_heal
          bonus = (30 * (AIEffectScoreHelper::FANG_STATUS_CHANCE / 100.0)).round  # 3
          bonus -= 2 if target.has_active_ability?(:MARVELSCALE)
          bonus -= 3 if target.check_for_move { |m| m.thawsUser? }
          score += [bonus, 0].max
        end
      end
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("BurnFlinchTarget",
  proc { |score, move, user, target, ai, battle|
    # Flinch component
    score += AIEffectScoreHelper.fang_flinch_score(score, move, user, target, ai, battle)
    # Burn component (10% chance)
    if target.battler.pbCanBurn?(user.battler, false, move.move)
      if !target.has_active_item?([:RAWSTBERRY, :LUMBERRY])
        can_heal = AIEffectScoreHelper.hydration_cures_immediately?(target, user)
        unless can_heal
          bonus = (20 * (AIEffectScoreHelper::FANG_STATUS_CHANCE / 100.0)).round  # 2
          if !target.has_active_ability?(:GUTS) && target.check_for_move { |m| m.physicalMove? }
            bonus += 2
          end
          bonus -= 2 if target.has_active_ability?([:FLAREBOOST, :GUTS, :MARVELSCALE, :QUICKFEET])
          score += [bonus, 0].max
        end
      end
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ParalyzeFlinchTarget",
  proc { |score, move, user, target, ai, battle|
    # Flinch component
    score += AIEffectScoreHelper.fang_flinch_score(score, move, user, target, ai, battle)
    # Paralysis component (10% chance)
    if target.battler.pbCanParalyze?(user.battler, false, move.move)
      if !target.has_active_item?([:CHERIBERRY, :LUMBERRY])
        can_heal = AIEffectScoreHelper.hydration_cures_immediately?(target, user)
        unless can_heal
          bonus = (20 * (AIEffectScoreHelper::FANG_STATUS_CHANCE / 100.0)).round  # 2
          if target.faster_than?(user)
            user_speed = user.rough_stat(:SPEED)
            target_speed = target.rough_stat(:SPEED)
            bonus += 3 if target_speed < user_speed * ((Settings::MECHANICS_GENERATION >= 7) ? 2 : 4)
          end
          bonus -= 2 if target.has_active_ability?([:GUTS, :MARVELSCALE, :QUICKFEET])
          score += [bonus, 0].max
        end
      end
    end
    next score
  }
)

#===============================================================================
# [NEW] Taunt Override — Tactical Taunt
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("DisableTargetStatusMoves",
  proc { |score, move, user, target, ai, battle|
    # Not worth on Choice-locked targets
    if !target.effects[PBEffects::ChoiceBand]
      if target.has_active_item?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) ||
         target.has_active_ability?(:GORILLATACTICS)
        next Battle::AI::MOVE_FAIL_SCORE
      end
    end

    # Count status moves the target has
    status_count = 0
    has_setup = false
    has_recovery = false
    has_new_field_setup = false
    has_protection = false
    sim_move = Battle::AI::AIMove.new(ai)
    old_mold_breaker = battle.moldBreaker
    target.battler.eachMove do |m|
      if m.statusMove? && (m.pp > 0 || m.total_pp == 0)
        next if !target.battler.pbCanChooseMove?(m, false, false)
        next if target.status == :SLEEP && target.statusCount > 1 && !m.usableWhenAsleep?
        next if target.status != :SLEEP && m.usableWhenAsleep?
        battle.moldBreaker = target.has_mold_breaker?
        sim_move.set_up(m)
        next if Battle::AI::Handlers.move_will_fail?(m.function_code, sim_move, target, ai, battle)
        target_data = sim_move.pbTarget(target)
        if target_data.num_targets > 0 && target_data.targets_foe
          next if ai.pbPredictMoveFailureAgainstTarget(sim_move, target, user)
        end
        status_count += 1
        has_setup = true if ai.move_is_setup?(m, target)
        healing_codes = [
          "HealUserHalfOfTotalHP",
          "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",
          "HealUserDependingOnWeather"
        ]
        has_recovery = true if healing_codes.include?(m.function_code)
        case m.function_code
        when "AddStealthRocksToFoeSide"
          has_new_field_setup = true if !target.pbOpposingSide.effects[PBEffects::StealthRock]
        when "AddSpikesToFoeSide"
          has_new_field_setup = true if target.pbOpposingSide.effects[PBEffects::Spikes] == 0
        when "AddToxicSpikesToFoeSide"
          has_new_field_setup = true if target.pbOpposingSide.effects[PBEffects::ToxicSpikes] == 0
        when "AddStickyWebToFoeSide"
          has_new_field_setup = true if !target.pbOpposingSide.effects[PBEffects::StickyWeb]
        when "StartWeakenPhysicalDamageAgainstUserSide"
          has_new_field_setup = true if target.pbOwnSide.effects[PBEffects::Reflect] == 0
        when "StartWeakenSpecialDamageAgainstUserSide"
          has_new_field_setup = true if target.pbOwnSide.effects[PBEffects::LightScreen] == 0
        when "StartWeakenDamageAgainstUserSideIfHail"
          has_new_field_setup = true if target.pbOwnSide.effects[PBEffects::AuroraVeil] == 0
        end
        has_protection = true if m.function_code.start_with?("Protect")
      end
    end
    battle.moldBreaker = old_mold_breaker
    next Battle::AI::MOVE_FAIL_SCORE if status_count == 0

    score += status_count * 3

    score += 3 if has_recovery

    if has_protection
      score += 5
    end

    user_speed = user.battler.pbSpeed
    target_speed = target.battler.pbSpeed
    user_is_faster = user_speed > target_speed

    if user_is_faster && (has_setup || has_new_field_setup)
      score += 20

      if has_new_field_setup
        remaining_foes = battle.pbAbleNonActiveCount(target.index)
        field_setup_bonus = 3 * remaining_foes
        score += field_setup_bonus
        PBDebug.log_score_change(field_setup_bonus,
          "Taunt: prevents new field setup for #{remaining_foes} remaining foe party members")
      end
      PBDebug.log_score_change(20, "Taunt: user is faster so prevents setup or field setup")
    end

    PBDebug.log_score_change(score - 100, "Taunt: #{status_count} status moves#{has_setup ? ', has setup' : ''}#{has_recovery ? ', has recovery' : ''}.")
    next score
  }
)

#===============================================================================
# [NEW] Yawn Override — Tactical Yawn
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("SleepTargetNextTurn",
  proc { |score, move, user, target, ai, battle|
    useless_score = Battle::AI::MOVE_USELESS_SCORE

    # Already drowsy or asleep
    next useless_score if target.effects[PBEffects::Yawn] > 0
    next useless_score if target.status == :SLEEP

    # Can't sleep
    next useless_score if !target.battler.pbCanSleep?(user.battler, false, move.move)

    # Immediate cure
    next useless_score if target.has_active_item?([:CHESTOBERRY, :LUMBERRY])
    next useless_score if AIEffectScoreHelper.hydration_cures_immediately?(target, user)

    # Electric Terrain blocks sleep on grounded
    if ai.trainer.high_skill?
      next useless_score if user.battler.battle.field.terrain == :Electric &&
                            target.battler.affectedByTerrain?
    end

    # Base preference — Yawn forces switches, which is inherently useful
    score += 15
    PBDebug.log_score_change(15, "Yawn: forces switch or sleeps target.")

    # Prefer as pseudo-phaze when hazards are up
    foe_side = target.pbOwnSide
    hazard_value = 0
    hazard_value += 8 if foe_side.effects[PBEffects::StealthRock]
    hazard_value += 4 if foe_side.effects[PBEffects::Spikes] > 0
    hazard_value += 4 if foe_side.effects[PBEffects::ToxicSpikes] > 0

    if hazard_value > 0
      score += hazard_value
      PBDebug.log_score_change(hazard_value, "Yawn + hazard synergy.")
    end

    # Prefer against setup mons — forces them to switch or sleep
    target_boosts = ai.total_positive_boosts(target)
    if target_boosts >= 2
      score += 10
      PBDebug.log_score_change(10, "Yawn vs boosted foe (+#{target_boosts}).")
    end

    # Don't prefer if target can heal
    score += AIEffectScoreHelper.get_target_heal_penalty(target, ai)

    next score
  }
)

#===============================================================================
# Defog - final score override after DBK Dynamax
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("LowerTargetEvasion1RemoveSideEffects",
  proc { |score, move, user, target, ai, battle|
    next Battle::AI::MOVE_USELESS_SCORE if !target.opposes?(user)

    target_side = target.pbOwnSide
    user_side = target.pbOpposingSide
    foe_has_screens = target_side.effects[PBEffects::AuroraVeil] > 1 ||
                      target_side.effects[PBEffects::Reflect] > 1 ||
                      target_side.effects[PBEffects::LightScreen] > 1
    foe_has_hazards = target_side.effects[PBEffects::Spikes] > 0 ||
                      target_side.effects[PBEffects::ToxicSpikes] > 0 ||
                      target_side.effects[PBEffects::StealthRock] ||
                      target_side.effects[PBEffects::Steelsurge] ||
                      target_side.effects[PBEffects::StickyWeb]
    user_has_hazards = Settings::MECHANICS_GENERATION >= 6 &&
                       (user_side.effects[PBEffects::Spikes] > 0 ||
                        user_side.effects[PBEffects::ToxicSpikes] > 0 ||
                        user_side.effects[PBEffects::StealthRock] ||
                        user_side.effects[PBEffects::Steelsurge] ||
                        user_side.effects[PBEffects::StickyWeb])

    score = ai.get_score_for_target_stat_drop(score, target, move.move.statDown)

    if !foe_has_screens && !foe_has_hazards && !user_has_hazards
      score -= 30
      PBDebug.log_score_change(-30, "Defog: no hazards or screens to remove.")
    end

    if foe_has_screens
      score += 15
      PBDebug.log_score_change(15, "Defog: removes foe screens.")
    end

    if target.can_switch_lax? && foe_has_hazards
      score -= 15
      PBDebug.log_score_change(-15, "Defog: would remove foe hazards.")
    end

    if user.can_switch_lax? && user_has_hazards
      score += 15
      PBDebug.log_score_change(15, "Defog: removes own hazards.")
    end

    if Settings::MECHANICS_GENERATION >= 8 && battle.field.terrain != :None
      score -= ai.get_score_for_terrain(battle.field.terrain, user)
    end

    next score
  }
)

#===============================================================================
# [NEW] Haze / Clear Smog / Spectral Thief — Counter foe stat boosts
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ResetTargetStatStages",
  proc { |score, move, user, target, ai, battle|
    target_boosts = ai.total_positive_boosts(target)
    target_drops = 0
    GameData::Stat.each_battle { |s| target_drops += target.stages[s.id].abs if target.stages[s.id] < 0 }

    if target_boosts >= 2
      bonus = 8 + (target_boosts * 5)
      score += bonus
      PBDebug.log_score_change(bonus, "Clear Smog vs boosted foe (+#{target_boosts}).")
    end

    # Penalize if target has more drops than boosts (we'd be helping them)
    if target_drops > target_boosts
      score -= 10
      PBDebug.log_score_change(-10, "Clear Smog would reset target's negative stages.")
    end

    next score
  }
)

Battle::AI::Handlers::MoveEffectScore.add("ResetAllBattlersStatStages",
  proc { |score, move, user, ai, battle|
    foe_boosts = 0
    ally_drops = 0
    ai.each_foe_battler(user.side) { |b, _i| foe_boosts += ai.total_positive_boosts(b) }
    ai.each_same_side_battler(user.side) do |b, _i|
      GameData::Stat.each_battle { |s| ally_drops -= b.stages[s.id] if b.stages[s.id] < 0 }
    end
    if foe_boosts == 0 && ally_drops <= 2
      score -= 50
      PBDebug.log_score_change(-50, "Haze has no meaningful stat changes to clear.")
    end

    net_value = foe_boosts
    net_value -= ai.total_positive_boosts(user)

    if net_value >= 2
      bonus = 5 + (net_value * 8)
      score += bonus
      PBDebug.log_score_change(bonus, "Haze: foe has +#{net_value} net boosts to clear.")
    elsif net_value < 0
      penalty = net_value * 5
      score += penalty
      PBDebug.log_score_change(penalty, "Haze would erase user's own boosts.")
    end

    next score
  }
)

#===============================================================================
# [NEW] Encore — score based on target's last used move
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("DisableTargetUsingDifferentMove",
  proc { |score, move, user, target, ai, battle|
    # Already encored
    next Battle::AI::MOVE_USELESS_SCORE if target.effects[PBEffects::Encore] > 0

    # Mental Herb cures Encore immediately
    next Battle::AI::MOVE_USELESS_SCORE if target.has_active_item?(:MENTALHERB)

    # Target hasn't moved yet — Encore will fail
    last_move_id = target.battler.lastMoveUsed
    next Battle::AI::MOVE_USELESS_SCORE unless last_move_id

    last_move_data = GameData::Move.try_get(last_move_id)
    next score unless last_move_data

    last_move_category = last_move_data.category   # 0=Physical, 1=Special, 2=Status
    last_move_power    = last_move_data.power
    last_move_type     = last_move_data.type

    # Locking target into a status/setup move is very valuable
    if last_move_category == 2
      score += 20
      PBDebug.log_score_change(20, "Encore: target's last move was a status move.")
    else
      # Check STAB
      is_stab = target.has_type?(last_move_type)

      if !is_stab && last_move_power <= 60
        # Weak non-STAB attack — worth locking
        score += 15
        PBDebug.log_score_change(15, "Encore: target's last move is a weak non-STAB attack.")
      elsif is_stab && last_move_power >= 80
        # Strong STAB attack — don't lock target into this
        score -= 10
        PBDebug.log_score_change(-10, "Encore: target's last move is a strong STAB attack.")
      end
    end

    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("UserStealTargetPositiveStatStages",
  proc { |score, move, user, target, ai, battle|
    target_boosts = ai.total_positive_boosts(target)

    if target_boosts >= 2
      bonus = 10 + (target_boosts * 5)
      score += bonus
      PBDebug.log_score_change(bonus, "Spectral Thief vs boosted foe (+#{target_boosts}).")
    end

    next score
  }
)

#===============================================================================
# FailsIfTargetActed (Sucker Punch, Upper Hand)
# Overrides base handler which incorrectly gates on speed instead of priority.
#===============================================================================
Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("FailsIfTargetActed",
  proc { |score, move, user, target, ai, battle|
    # Fail if target has no damaging moves
    next Battle::AI::MOVE_FAIL_SCORE if !target.check_for_move { |m| m.damagingMove? }
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("CurseTargetOrLowerUserSpd1RaiseUserAtkDef1",
  proc { |score, move, user, target, ai, battle|
    next score if !user.has_type?(:GHOST) &&
                  !(move.rough_type == :GHOST && user.has_active_ability?([:LIBERO, :PROTEAN]))
    if ai.trainer.medium_skill?
      # Prefer if the user has no damaging moves
      score += 15 if !user.check_for_move { |m| m.damagingMove? }
      # Prefer if the target can't switch out to remove its curse
      score += 10 if !battle.pbCanChooseNonActive?(target.index)
    end
    if ai.trainer.high_skill?
      # Prefer if user can stall while damage is dealt
      if user.check_for_move { |m| m.is_a?(Battle::Move::ProtectMove) }
        score += 5
      end
    end
    trick_room_bonus = ai.trick_room_ace_reserve_bonus(user, battle)
    if trick_room_bonus > 0
      score += trick_room_bonus
      PBDebug.log_score_change(trick_room_bonus, "Trick Room ace reserve follow-up.")
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectScore.add("HealUserPositionNextTurn",
  proc { |score, move, user, ai, battle|
    battler = user.battler
    next score unless battler

    # Block if Wish is already active on this position
    position = battle.positions[battler.index]
    if position && position.effects[PBEffects::Wish] > 0
      next Battle::AI::MOVE_FAIL_SCORE
    end

    # Consider how much HP will be restored
    if user.hp <= user.totalhp * 0.5
      score -= 10
    end

    # Wish + pivot synergy
    if user.check_for_move { |m| ai.safe_function_code(m)&.start_with?("SwitchOutUser") }
      score += 20
      PBDebug.log_score_change(20, "Wish: pivot move synergy.")
    end

    next score
  }
)

Battle::AI::Handlers::MoveEffectScore.add("SwitchOutUserDamagingMove",
  proc { |score, move, user, ai, battle|
    next score if !battle.pbCanChooseNonActive?(user.index)
    # Don't want to switch in ace
    score -= 20 if ai.trainer.has_skill_flag?("ReserveLastPokemon") &&
                   battle.pbTeamAbleNonActiveCount(user.index) == 1
    # Prefer if the user switching out will lose a negative effect
    score += 20 if user.effects[PBEffects::PerishSong] > 0
    score += 10 if user.effects[PBEffects::Confusion] > 1
    score += 10 if user.effects[PBEffects::Attract] >= 0
    # Prefer if the user switching out will change its form
    score += 20 if user.has_active_ability?(:ZEROTOHERO) && user.battler.form == 0
    score += 10 if user.has_active_ability?(:REGENERATOR) && user.hp <= user.totalhp * 0.75
    # Consider the user's stat stages
    if user.stages.any? { |key, val| val >= 2 }
      score -= 15
    elsif user.stages.any? { |key, val| val < 0 }
      score += 10
    end
    # Don't prefer if the user's side has entry hazards on it
    score -= 5 if user.pbOwnSide.effects[PBEffects::Spikes] > 0
    score -= 5 if user.pbOwnSide.effects[PBEffects::ToxicSpikes] > 0
    score -= 5 if user.pbOwnSide.effects[PBEffects::StealthRock]
    next score
  }
)

# geomancy
Battle::AI::Handlers::MoveEffectScore.add("TwoTurnAttackRaiseUserSpAtkSpDefSpd2",
  proc { |score, move, user, ai, battle|
    # Score for raising user's stats
    score = ai.get_score_for_target_stat_raise(score, user, move.move.statUp)
    # Power Herb makes this a 1 turn move, the same as a move with no effect
    next score if user.has_active_item?(:POWERHERB)
    score -= 20
    # Treat as a failure if user has Truant (the charging turn has no effect)
    next Battle::AI::MOVE_FAIL_SCORE if user.has_active_ability?(:TRUANT)
    # Useless if user will faint from EoR damage before finishing this attack
    next Battle::AI::MOVE_FAIL_SCORE if user.rough_end_of_round_damage >= user.hp
    next score
  }
)

# chillyreception
Battle::AI::Handlers::MoveEffectScore.add("SwitchOutUserStartHailWeather",
  proc { |score, move, user, ai, battle|
    score = Battle::AI::Handlers.apply_move_effect_score("SwitchOutUserStatusMove",
      score, move, user, ai, battle)
    score += ai.get_score_for_weather(:Hail, user, true)
    next score
  }
)



#===============================================================================
# Dynamax move-effect score overrides
#===============================================================================
Battle::AI::Handlers::MoveEffectScore.add("DamageTargetStartSunWeather",
  proc { |score, move, user, ai, battle|
    next score
  }
)
Battle::AI::Handlers::MoveEffectScore.copy("DamageTargetStartSunWeather",
                                           "DamageTargetStartRainWeather",
                                           "DamageTargetStartSandstormWeather",
                                           "DamageTargetStartHailWeather")

Battle::AI::Handlers::MoveEffectScore.add("ProtectUserEvenFromDynamaxMoves",
  proc { |score, move, user, ai, battle|
    next Battle::AI::MOVE_USELESS_SCORE if !battle.allOtherSideBattlers(user.battler).any?(&:dynamax?)
    next Battle::AI::MOVE_USELESS_SCORE if user.effects[PBEffects::ProtectRate] >= 4
    useless = true
    ai.each_foe_battler(user.side) do |b, i|
      next if !b.can_attack?
      next if b.check_for_move { |m| m.damagingMove? && m.ignoresMaxGuard? }
      useless = false
      score += 7 if b.battler.dynamax?
      score += 15 if b.effects[PBEffects::TwoTurnAttack] &&
                     GameData::Move.get(b.effects[PBEffects::TwoTurnAttack]).category != 2
    end
    next Battle::AI::MOVE_USELESS_SCORE if useless
    user_eor_damage = user.rough_end_of_round_damage
    if user_eor_damage >= user.hp
      next Battle::AI::MOVE_USELESS_SCORE
    elsif user_eor_damage > 0
      score -= 8
    elsif user_eor_damage < 0
      score += 8
    end
    score -= (user.effects[PBEffects::ProtectRate] - 1) * ((Settings::MECHANICS_GENERATION >= 6) ? 15 : 10)
    next score
  }
)

Battle::AI::Handlers::MoveEffectScore.add("RaiseUserSideAtk1",
  proc { |score, move, user, ai, battle|
    old_score = score
    battle.allSameSideBattlers(user.battler).each do |b|
      check_score = ai.get_score_for_target_stat_raise(old_score, ai.battlers[b.index], move.move.statUp)
      score += (check_score - old_score) / battle.pbSideBattlerCount(user.battler)
    end
    next score 
  }
)
Battle::AI::Handlers::MoveEffectScore.copy("RaiseUserSideAtk1",
                                           "RaiseUserSideDef1",
                                           "RaiseUserSideSpAtk1",
                                           "RaiseUserSideSpDef1",
                                           "RaiseUserSideSpeed1")

Battle::AI::Handlers::MoveEffectScore.add("LowerTargetSideAtk1",
  proc { |score, move, user, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      check_score = ai.get_score_for_target_stat_drop(old_score, ai.battlers[b.index], move.move.statDown)
      score += (check_score - old_score) / battle.pbOpposingBattlerCount(user.battler)
    end
    next score 
  }
)
Battle::AI::Handlers::MoveEffectScore.copy("LowerTargetSideAtk1",
                                           "LowerTargetSideDef1",
                                           "LowerTargetSideSpAtk1",
                                           "LowerTargetSideSpDef1",
                                           "LowerTargetSideSpeed1",
                                           "LowerTargetSideSpeed2",
                                           "LowerTargetSideEva1")

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("PoisonTargetSide",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      check_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("PoisonTarget",
                      old_score, move, user, ai.battlers[b.index], ai, battle)
      score += (check_score - old_score) / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ParalyzeTargetSide",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      check_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("ParalyzeTarget",
                      old_score, move, user, ai.battlers[b.index], ai, battle)
      score += (check_score - old_score) / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("PoisonOrParalyzeTargetSide",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      poison_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("PoisonTarget",
                       old_score, move, user, ai.battlers[b.index], ai, battle)
      paralyze_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("ParalyzeTarget",
                         old_score, move, user, ai.battlers[b.index], ai, battle)
      delta = (poison_score - old_score) + (paralyze_score - old_score)
      score += delta / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("PoisonParalyzeOrSleepTargetSide",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      poison_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("PoisonTarget",
                       old_score, move, user, ai.battlers[b.index], ai, battle)
      paralyze_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("ParalyzeTarget",
                         old_score, move, user, ai.battlers[b.index], ai, battle)
      sleep_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("SleepTarget",
                      old_score, move, user, ai.battlers[b.index], ai, battle)
      delta = (poison_score - old_score) + (paralyze_score - old_score) + (sleep_score - old_score)
      score += delta / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("InfatuateTargetSide",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      check_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("AttractTarget",
                      old_score, move, user, ai.battlers[b.index], ai, battle)
      score += (check_score - old_score) / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("ConfuseTargetSide",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      check_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("ConfuseTarget",
                      old_score, move, user, ai.battlers[b.index], ai, battle)
      score += (check_score - old_score) / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)
Battle::AI::Handlers::MoveEffectAgainstTargetScore.copy("ConfuseTargetSide",
                                                        "ConfuseTargetSideAddMoney")

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("DamageTargetStartGravity",
  proc { |score, move, user, target, ai, battle|
    next score if battle.field.effects[PBEffects::Gravity] > 0
    gravity_score = Battle::AI::Handlers::MoveEffectScore.trigger("StartGravity",
                      score, move, user, ai, battle)
    score += (gravity_score || score) - score
    next score
  }
)

Battle::AI::Handlers::MoveEffectAgainstTargetScore.add("BindTargetSideUserCanSwitch",
  proc { |score, move, user, target, ai, battle|
    old_score = score
    battle.allOtherSideBattlers(user.battler).each do |b|
      check_score = Battle::AI::Handlers::MoveEffectAgainstTargetScore.trigger("BindTarget",
                      old_score, move, user, ai.battlers[b.index], ai, battle)
      score += (check_score - old_score) / battle.pbOpposingBattlerCount(user.battler)
    end
    next score
  }
)

#-------------------------------------------------------------------------------
# G-Max Resonance override
#-------------------------------------------------------------------------------
Battle::AI::Handlers::MoveEffectScore.add("DamageTargetStartWeakenDamageAgainstUserSide",
  proc { |score, move, user, ai, battle|
    next score if user.pbOwnSide.effects[PBEffects::Reflect] > 0 &&
                  user.pbOwnSide.effects[PBEffects::LightScreen] > 0
    score += 5 if user.has_active_item?(:LIGHTCLAY)

    score += 15 if user.battler.effects[PBEffects::Dynamax] == 1
    next score + 20
  }
)
