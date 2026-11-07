#===============================================================================
# [AI_Improved_UltraBurst.rb] - Ultra Burst decision
#===============================================================================

class Battle::AI
  # Ultra Burst when it creates an immediate OHKO or reduces the expected hit.
  def pbEnemyShouldUltraBurst?
    return false unless @battle.pbCanUltraBurst?(@user.index)

    foes = []
    each_foe_battler(@user.side) { |foe, _i| foes << foe }
    return false if foes.empty?

    damage_before = {}
    foe_damage_before = {}
    foes.each do |foe|
      profile = damage_moves(@user, foe)
      damage_before[foe.index] = profile.values.map { |entry| entry[:dmg] }.max || 0

      expected_foe_move = best_damage_move(foe, @user)
      foe_damage_before[foe.index] = if expected_foe_move
        { key: expected_foe_move[:key], dmg: expected_foe_move[:dmg] }
      end
    end

    battler = @user.battler
    previous_form = battler.form
    should_ultra_burst = false
    ultra_reason = nil
    begin
      battler.pokemon.makeUltra
      battler.form = battler.pokemon.form
      battler.pbUpdate(true)

      foes.each do |foe|
        profile = damage_moves(@user, foe)
        damage_after = profile.values.map { |entry| entry[:dmg] }.max || 0
        damage_before_burst = damage_before[foe.index]

        expected_foe_move = foe_damage_before[foe.index]
        foe_profile_after = damage_moves(foe, @user)
        foe_entry_after = expected_foe_move ? foe_profile_after[expected_foe_move[:key]] : nil
        foe_damage_after = foe_entry_after&.dig(:dmg)

        new_ohko = damage_before_burst < foe.hp && damage_after >= foe.hp
        lower_foe_damage = foe_damage_after && foe_damage_after < expected_foe_move[:dmg]
        PBDebug.log_ai(
          "[Ultra Burst] vs #{foe.name}: outgoing=#{damage_before_burst}/#{damage_after} " \
          "incoming=#{expected_foe_move&.dig(:dmg) || 0}/#{foe_damage_after || 0} hp=#{foe.hp}"
        )
        next unless new_ohko || lower_foe_damage
        should_ultra_burst = true
        ultra_reason = new_ohko ? :new_ohko : :lower_foe_damage
        break
      end
    ensure
      battler.pokemon.makeUnUltra
      battler.form = previous_form
      battler.pbUpdate(true)
    end

    case ultra_reason
    when :new_ohko
      PBDebug.log_ai("#{@user.name} will Ultra Burst to secure a new OHKO")
    when :lower_foe_damage
      PBDebug.log_ai("#{@user.name} will Ultra Burst to reduce the expected damage")
    else
      PBDebug.log_ai("#{@user.name} will not Ultra Burst: no new OHKO or damage reduction")
    end
    should_ultra_burst
  end
end
