#===============================================================================
# 5. ShouldSwitch / ShouldNotSwitch Handlers
#===============================================================================

Battle::AI::Handlers::ShouldSwitch.add(:high_damage_from_foe,
  proc { |user, reserves, ai, battle|
    next false
  }
)

# Override: EOR damage is now handled by simulate_battle.
# Keep switching to remove harmful effects (Leech Seed, Nightmare, Curse, Toxic).
Battle::AI::Handlers::ShouldSwitch.add(:significant_eor_damage,
  proc { |battler, reserves, ai, battle|
    next false unless ai.trainer.high_skill?
    if battler.effects[PBEffects::LeechSeed] >= 0 && ai.pbAIRandom(100) < 50
      PBDebug.log_ai("#{battler.name} wants to switch to get rid of its Leech Seed")
      next true
    end
    if battler.effects[PBEffects::Nightmare]
      PBDebug.log_ai("#{battler.name} wants to switch to get rid of its Nightmare")
      next true
    end
    if battler.effects[PBEffects::Curse]
      PBDebug.log_ai("#{battler.name} wants to switch to get rid of its Curse")
      next true
    end
    if battler.status == :POISON && battler.statusCount > 0 && !battler.has_active_ability?(:POISONHEAL)
      poison_damage = battler.totalhp / 8
      next_toxic_damage = battler.totalhp * (battler.effects[PBEffects::Toxic] + 1) / 16
      if (battler.hp <= next_toxic_damage && battler.hp > poison_damage) ||
         next_toxic_damage > poison_damage * 2
        PBDebug.log_ai("#{battler.name} wants to switch to reduce toxic to regular poisoning")
        next true
      end
    end
    next false
  }
)

# Disable the base engine's :battler_has_super_effective_move handler
# — blocking switches just because the battler has a super-effective move
#   causes the switch decision for :escape_boosted_foe to be ignored
Battle::AI::Handlers::ShouldNotSwitch.add(:battler_has_super_effective_move,
  proc { |battler, reserves, ai, battle|
    next false
  }
)

Battle::AI::Handlers::ShouldNotSwitch.add(:keep_substitute_on_mediocre_moves,
  proc { |battler, reserves, ai, battle, switch_branch|
    next false unless switch_branch == :mediocre_moves
    next false unless battler.effects[PBEffects::Substitute] > 0
    PBDebug.log_ai("#{battler.name} is behind a Substitute; will not switch just for mediocre moves.")
    next true
  }
)

#===============================================================================
# [NEW] Trigger a switch when a foe has >= 2 positive stat stages,
# but only if at least one reserve has a meaningful answer to the threat.
#===============================================================================
Battle::AI::Handlers::ShouldSwitch.add(:escape_boosted_foe,
  proc { |user, reserves, ai, battle|
    next false unless ai.trainer.high_skill?

    # Find a threatening foe with >= 2 cumulative positive stat stages
    threatening_foe  = nil
    foe_total_boosts = 0
    ai.each_foe_battler(user.side) do |b, _i|
      boosts = ai.total_positive_boosts(b)
      if boosts >= 2
        threatening_foe  = b
        foe_total_boosts = boosts
        break
      end
    end
    next false unless threatening_foe

    if user.has_active_item?(:REDCARD)
      PBDebug.log_ai(
        "#{user.name}: foe has #{foe_total_boosts} positive boosts, but Red Card can punish an incoming attack."
      )
      next false
    end

    PBDebug.log_ai(
      "#{user.name}: foe has #{foe_total_boosts} positive boosts — should switch."
    )
    next true
  }
)
