#===============================================================================
# Debug Utilities
#===============================================================================

#-------------------------------------------------------------------------------
# Override PBDebug to always write to debuglog.txt regardless of $DEBUG.
# Only the latest battle's logs are kept (file cleared at battle start).
# Console output (echoln) still requires $DEBUG.
#-------------------------------------------------------------------------------
module PBDebug
  FLUSH_THRESHOLD = 50   # flush to disk every N buffered lines

  def self.flush
    if @@log.length > 0
      File.open("Data/debuglog.txt", "a+b") { |f| f.write(@@log.join) }
    end
    @@log.clear
  end

  def self.maybe_flush
    PBDebug.flush if @@log.length >= FLUSH_THRESHOLD
  end

  def self.log(msg)
    echoln(msg.gsub("%", "%%")) if $DEBUG
    @@log.push(msg + "\r\n") if $DEBUG
    PBDebug.maybe_flush
  end

  def self.log_header(msg)
    echoln(Console.markup_style(msg.gsub("%", "%%"), text: :light_purple)) if $DEBUG
    @@log.push(msg + "\r\n") if $DEBUG
    PBDebug.maybe_flush
  end

  def self.log_message(msg)
    msg = "\"" + msg + "\""
    echoln(Console.markup_style(msg.gsub("%", "%%"), text: :dark_gray)) if $DEBUG
    @@log.push(msg + "\r\n") if $DEBUG
    PBDebug.maybe_flush
  end

  def self.log_ai(msg)
    msg = "[AI] " + msg
    echoln(msg.gsub("%", "%%")) if $DEBUG
    @@log.push(msg + "\r\n") if $DEBUG
    PBDebug.maybe_flush
  end

  def self.log_score_change(amt, msg)
    sign     = (amt > 0) ? "+" : "-"
    amt_text = sprintf("%3d", amt.abs)
    plain    = "     #{sign}#{amt_text}: #{msg}"
    if $DEBUG
      color = (amt > 0) ? :light_green : :light_red
      echoln Console.markup_style(plain.gsub("%", "%%"), text: color)
    end
    @@log.push(plain + "\r\n") if $DEBUG
    PBDebug.maybe_flush
  end
end

# Clear debuglog.txt at the start of each battle (keeps only latest battle)
class Battle
  alias _clear_debuglog_pbStartBattle pbStartBattle
  def pbStartBattle
    File.open("Data/debuglog.txt", "w") { |f| }
    _clear_debuglog_pbStartBattle
  end
end
